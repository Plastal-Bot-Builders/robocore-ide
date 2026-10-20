// Tests web/robocore_usb.js (the Web Serial + esptool-js bridge) in Node with a fake
// navigator.serial and a fake esptool-js. Run: node --test test/js/robocore_usb.test.mjs
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class FakePort {
  constructor(vid, pid) {
    this.info = { usbVendorId: vid, usbProductId: pid };
    this.opened = false;
    this.readable = null;
    this.writable = null;
    this.signals = [];
    this.written = [];
    this.opens = [];
  }
  getInfo() {
    return this.info;
  }
  async open({ baudRate }) {
    if (this.gone) throw Object.assign(new Error('device gone'), { name: 'NetworkError' });
    if (this.opened) throw Object.assign(new Error('already open'), { name: 'InvalidStateError' });
    this.opened = true;
    this.opens.push(baudRate);
    this.readable = new ReadableStream({ start: (c) => (this.ctrl = c) });
    this.writable = new WritableStream({ write: (chunk) => this.written.push(new TextDecoder().decode(chunk)) });
  }
  async close() {
    if (this.readable && this.readable.locked) throw Object.assign(new Error('locked'), { name: 'InvalidStateError' });
    this.opened = false;
    this.readable = null;
    this.writable = null;
  }
  async setSignals(s) {
    this.signals.push(s);
  }
  push(text) {
    this.ctrl.enqueue(new TextEncoder().encode(text));
  }
}

class FakeSerial {
  constructor() {
    this.ports = [];
    this.handlers = { connect: [], disconnect: [] };
    this.pick = null;
  }
  addEventListener(type, f) {
    this.handlers[type].push(f);
  }
  async getPorts() {
    return this.ports.filter((p) => p.granted && !p.gone);
  }
  async requestPort(opts) {
    this.lastFilter = opts;
    if (!this.pick) throw Object.assign(new Error('No port selected'), { name: 'NotFoundError' });
    const p = this.pick;
    p.granted = true;
    if (!this.ports.includes(p)) this.ports.push(p);
    return p;
  }
  unplug(p) {
    p.gone = true;
    p.opened = false;
    try {
      p.ctrl.error(Object.assign(new Error('The device has been lost.'), { name: 'NetworkError' }));
    } catch (e) {
      /* already closed */
    }
    p.readable = null;
    p.writable = null;
    for (const f of this.handlers.disconnect) f({ target: p });
  }
  plug(p) {
    p.gone = false;
    for (const f of this.handlers.connect) f({ target: p });
  }
}

const serial = new FakeSerial();
const events = [];
const text = [];
let usb;
let esp;

before(async () => {
  // A copy of the bridge next to a fake esptool-js bundle.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rcusb-'));
  fs.copyFileSync(path.join(here, '../../web/robocore_usb.js'), path.join(dir, 'robocore_usb.mjs'));
  fs.mkdirSync(path.join(dir, 'vendor/esptool-js'), { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'vendor/esptool-js/bundle.js'),
    `const esp = (globalThis.__esp ??= { log: [] });
export class Transport {
  constructor(port) { this.port = port; esp.transport = this; }
  async disconnect() { esp.log.push('disconnect'); await this.port.close(); }
}
export class ESPLoader {
  constructor(o) { this.o = o; this.chip = null; esp.loader = this; esp.baud = o.baudrate; }
  async main(mode) {
    esp.log.push('main:' + mode);
    await this.o.transport.port.open({ baudRate: 115200 });
    if (esp.onMain) await esp.onMain();
    if (esp.failMain) throw new Error('Failed to connect with the device');
    this.chip = { CHIP_NAME: esp.chipName || 'ESP32-S3', async getChipDescription() { return (esp.chipName || 'ESP32-S3') + ' (QFN56) (revision v0.2)'; } };
    this.o.terminal.writeLine('Chip is ' + this.chip.CHIP_NAME);
    return this.chip.CHIP_NAME;
  }
  async writeFlash(opts) {
    esp.flash = opts;
    if (esp.onWrite) await esp.onWrite();
    opts.fileArray.forEach((f, i) => { opts.reportProgress(i, f.data.length / 2, f.data.length); opts.reportProgress(i, f.data.length, f.data.length); });
  }
  async after(mode) { esp.log.push('after:' + mode); }
}
`,
  );
  Object.defineProperty(globalThis, 'navigator', { value: { serial }, configurable: true, writable: true });
  globalThis.window = globalThis;
  await import(pathToFileURL(path.join(dir, 'robocore_usb.mjs')).href);
  usb = globalThis.robocoreUsb;
  esp = globalThis.__esp ??= { log: [] };
  usb.setHandlers(
    (t) => text.push(t),
    (type, msg) => events.push([type, msg]),
  );
});

const call = async (p) => JSON.parse(await p);
const b64 = (n, fill) => Buffer.alloc(n, fill).toString('base64');

test('cancelling the port chooser is reported, not thrown', async () => {
  const r = await call(usb.connect(115200, false));
  assert.equal(r.ok, false);
  assert.equal(r.code, 'cancelled');
});

const board = new FakePort(0x303a, 0x1001);

test('connect opens the ESP32-S3 with DTR/RTS low and streams text', async () => {
  serial.pick = board;
  const r = await call(usb.connect(115200, true));
  assert.equal(r.ok, true);
  assert.equal(r.label, 'ESP32-S3 USB (303A:1001)');
  assert.deepEqual(serial.lastFilter, { filters: [{ usbVendorId: 0x303a }] });
  assert.deepEqual(board.opens, [115200]);
  assert.deepEqual(board.signals.at(-1), { dataTerminalReady: false, requestToSend: false });
  assert.equal(usb.isOpen(), true);
  board.push('RoboCore V2 ready\r\n');
  await sleep(20);
  assert.equal(text.join(''), 'RoboCore V2 ready\r\n');
});

test('write sends text to the board', async () => {
  const r = await call(usb.write('led on\n'));
  assert.equal(r.ok, true);
  assert.deepEqual(board.written, ['led on\n']);
});

test('unplugging is reported and plugging back in reconnects by itself', async () => {
  events.length = 0;
  serial.unplug(board);
  await sleep(20);
  assert.deepEqual(events[0], ['unplugged', 'ESP32-S3 USB (303A:1001)']);
  assert.equal(usb.isOpen(), false);
  serial.plug(board);
  await sleep(50);
  assert.ok(events.some(([t]) => t === 'reconnected'), JSON.stringify(events));
  assert.equal(usb.isOpen(), true);
  assert.equal(board.opens.length, 2);
});

test('a board plugged in while disconnected only raises a notice', async () => {
  const other = new FakePort(0x10c4, 0xea60);
  other.granted = true;
  serial.ports.push(other);
  events.length = 0;
  serial.plug(other); // connected to the RoboCore: nothing to say
  await sleep(20);
  assert.deepEqual(events, []);
  await call(usb.disconnect());
  serial.plug(other); // not connected: announce it, but don't open it
  await sleep(20);
  assert.deepEqual(events, [['plugged', 'CP210x USB-UART (10C4:EA60)']]);
  assert.equal(other.opened, false);
  serial.ports.splice(serial.ports.indexOf(other), 1);
  const r = await call(usb.reconnect(115200));
  assert.equal(r.ok, true);
  assert.equal(r.label, 'ESP32-S3 USB (303A:1001)');
});

test('flash closes the monitor, writes every part, resets and reopens the monitor', async () => {
  events.length = 0;
  esp.log.length = 0;
  const job = {
    chip: 'esp32s3',
    boardName: 'RoboCore V2',
    baud: 921600,
    monitorBaud: 115200,
    parts: [
      { name: 'bootloader', offset: 0x0, data: b64(100, 1) },
      { name: 'partitions', offset: 0x8000, data: b64(30, 2) },
      { name: 'boot_app0', offset: 0xe000, data: b64(20, 3) },
      { name: 'app', offset: 0x10000, data: b64(250, 4) },
    ],
  };
  const r = await call(usb.flash(JSON.stringify(job)));
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(r.bytes, 400);
  assert.equal(r.reopened, true);
  assert.equal(esp.baud, 921600);
  assert.deepEqual(esp.log, ['main:default_reset', 'after:hard_reset', 'disconnect']);
  assert.deepEqual(esp.flash.fileArray.map((f) => [f.address, f.data.length, f.data[0]]), [
    [0x0, 100, 1],
    [0x8000, 30, 2],
    [0xe000, 20, 3],
    [0x10000, 250, 4],
  ]);
  assert.equal(esp.flash.flashSize, 'keep');
  const progress = events.filter(([t]) => t === 'progress').map(([, m]) => JSON.parse(m));
  assert.equal(progress.at(-1).done, 400);
  assert.equal(progress.at(-1).total, 400);
  assert.deepEqual(
    events.filter(([t]) => t === 'stage').map(([, m]) => m),
    ['connecting', 'writing', 'resetting', 'reopening'],
  );
  assert.ok(events.some(([t, m]) => t === 'log' && m.includes('ESP32-S3')));
  assert.equal(usb.isOpen(), true);
  board.push('after upload\n');
  await sleep(20);
  assert.ok(text.join('').endsWith('after upload\n'));
});

test('no bootloader answer gives the bootloader code (BOOT + RESET tip)', async () => {
  esp.failMain = true;
  const r = await call(usb.flash(JSON.stringify({ chip: 'esp32s3', parts: [{ offset: 0, data: b64(4, 0) }] })));
  esp.failMain = false;
  assert.equal(r.ok, false);
  assert.equal(r.code, 'bootloader');
  await sleep(400);
  assert.equal(usb.isOpen(), true, 'the Serial Monitor comes back after a failed upload');
});

test('a different chip is refused before writing', async () => {
  esp.chipName = 'ESP32';
  esp.flash = null;
  const r = await call(usb.flash(JSON.stringify({ chip: 'esp32s3', boardName: 'RoboCore V2', parts: [{ offset: 0, data: b64(4, 0) }] })));
  esp.chipName = undefined;
  assert.equal(r.ok, false);
  assert.equal(r.code, 'wrong-chip');
  assert.equal(esp.flash, null);
  await sleep(400);
});

test('Stop while writing cancels the upload, restarts the board and gives the monitor back', async () => {
  esp.log.length = 0;
  esp.onWrite = () => usb.cancelFlash();
  const r = await call(usb.flash(JSON.stringify({ chip: 'esp32s3', parts: [{ offset: 0x10000, data: b64(64, 4) }] })));
  esp.onWrite = null;
  assert.equal(r.ok, false);
  assert.equal(r.code, 'cancelled');
  assert.equal(r.partial, true, 'stopped while writing: the program is incomplete');
  assert.deepEqual(esp.log, ['main:default_reset', 'after:hard_reset', 'disconnect']);
  await sleep(400);
  assert.equal(usb.isOpen(), true);
});

test('Stop before writing leaves the program alone', async () => {
  esp.flash = null;
  esp.onMain = () => usb.cancelFlash();
  const r = await call(usb.flash(JSON.stringify({ chip: 'esp32s3', parts: [{ offset: 0x10000, data: b64(64, 4) }] })));
  esp.onMain = null;
  assert.equal(r.code, 'cancelled');
  assert.equal(r.partial, false);
  assert.equal(esp.flash, null, 'nothing written');
  await sleep(400);
  assert.equal(usb.isOpen(), true);
  // The next upload is not cancelled by the old Stop.
  const again = await call(usb.flash(JSON.stringify({ chip: 'esp32s3', parts: [{ offset: 0x10000, data: b64(64, 4) }] })));
  assert.equal(again.ok, true, JSON.stringify(again));
});

test('cancelFlash with no upload running does nothing', async () => {
  const r = await call(usb.cancelFlash());
  assert.equal(r.ok, true);
  assert.equal(r.cancelling, false);
});

test('identify asks the chip its name, restarts it and reopens the monitor', async () => {
  esp.log.length = 0;
  const r = await call(usb.identify(115200));
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(r.chip, 'ESP32-S3 (QFN56) (revision v0.2)');
  assert.equal(r.label, 'ESP32-S3 USB (303A:1001)');
  assert.equal(r.reopened, true);
  assert.deepEqual(esp.log, ['main:default_reset', 'after:hard_reset', 'disconnect']);
  assert.equal(usb.isOpen(), true);
});

test('identify reports a board that does not answer', async () => {
  esp.failMain = true;
  const r = await call(usb.identify(115200));
  esp.failMain = false;
  assert.equal(r.ok, false);
  assert.equal(r.code, 'bootloader');
  await sleep(400);
  assert.equal(usb.isOpen(), true);
});

test('reconnect opens an already-allowed board without a prompt', async () => {
  await call(usb.disconnect());
  assert.equal(usb.isOpen(), false);
  serial.pick = null; // a prompt would fail
  const r = await call(usb.reconnect(115200));
  assert.equal(r.ok, true);
  assert.equal(usb.isOpen(), true);
});

test('reset pulses RTS and the restart is not reported as an unplug', async () => {
  events.length = 0;
  const r = await call(usb.reset());
  assert.equal(r.ok, true);
  assert.deepEqual(board.signals.slice(-2), [
    { dataTerminalReady: false, requestToSend: true },
    { dataTerminalReady: false, requestToSend: false },
  ]);
  serial.unplug(board);
  serial.plug(board);
  await sleep(50);
  assert.ok(!events.some(([t]) => t === 'unplugged'), JSON.stringify(events));
  assert.ok(events.some(([t]) => t === 'restarted'), JSON.stringify(events));
  await call(usb.disconnect());
});
