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

// ---------------------------------------------------------------- Arduino Uno (Optiboot, STK500v1)

// An Arduino Uno: after a DTR reset its Optiboot answers STK500v1 for a second (longer while it gets commands);
// leaving programming mode starts the sketch.
class FakeUno extends FakePort {
  constructor({ signature = [0x1e, 0x95, 0x0f], bootBaud = 115200, bootloader = true } = {}) {
    super(0x2341, 0x0043);
    Object.assign(this, { signature, bootBaud, bootloader });
    this.flash = new Uint8Array(32768).fill(0xff);
    this.pages = 0;
    this.resets = 0;
    this.inBoot = false;
    this.running = false;
    this.dtr = false;
  }
  async open(o) {
    await super.open(o);
    this.baud = o.baudRate;
    this.rx = [];
    this.writable = new WritableStream({ write: (chunk) => this.receive(chunk) });
  }
  async setSignals(s) {
    await super.setSignals(s);
    if (s.dataTerminalReady && !this.dtr) {
      this.resets++;
      this.inBoot = this.bootloader;
      this.bootUntil = Date.now() + 1000;
      this.running = false;
    }
    this.dtr = !!s.dataTerminalReady;
  }
  answer(bytes) {
    this.ctrl.enqueue(Uint8Array.from(bytes));
  }
  receive(chunk) {
    if (!this.inBoot || this.baud !== this.bootBaud || Date.now() > this.bootUntil) return;
    this.rx.push(...chunk);
    for (;;) {
      const b = this.rx;
      if (!b.length) return;
      const len = { 0x30: 2, 0x50: 2, 0x51: 2, 0x75: 2, 0x55: 4, 0x74: 5 }[b[0]] ?? (b[0] === 0x64 ? (b.length >= 3 ? 5 + ((b[1] << 8) | b[2]) : Infinity) : 1);
      if (b.length < len) return;
      const cmd = b.splice(0, len);
      this.bootUntil = Date.now() + 1000;
      if (cmd.at(-1) !== 0x20) {
        this.answer([0x15]); // STK_NOSYNC
        continue;
      }
      const n = (cmd[1] << 8) | cmd[2];
      switch (cmd[0]) {
        case 0x30:
        case 0x50:
          this.answer([0x14, 0x10]);
          break;
        case 0x51:
          this.answer([0x14, 0x10]);
          this.inBoot = false;
          this.running = true;
          break;
        case 0x75:
          this.answer([0x14, ...this.signature, 0x10]);
          break;
        case 0x55:
          this.addr = (cmd[1] | (cmd[2] << 8)) * 2;
          this.answer([0x14, 0x10]);
          break;
        case 0x64:
          this.flash.set(cmd.slice(4, 4 + n), this.addr);
          this.pages++;
          this.answer([0x14, 0x10]);
          break;
        case 0x74:
          this.answer([0x14, ...this.flash.slice(this.addr, this.addr + n), 0x10]);
          break;
      }
    }
  }
}

// Intel HEX of `bytes` from address 0, 16 bytes a line, as avr-objcopy writes it.
function toHex(bytes) {
  const lines = [];
  for (let at = 0; at < bytes.length; at += 16) {
    const rec = [Math.min(16, bytes.length - at), (at >> 8) & 0xff, at & 0xff, 0, ...bytes.subarray(at, at + 16)];
    rec.push(-rec.reduce((s, x) => s + x, 0) & 0xff);
    lines.push(':' + rec.map((x) => x.toString(16).toUpperCase().padStart(2, '0')).join(''));
  }
  return lines.join('\n') + '\n:00000001FF\n';
}

const sketch = Uint8Array.from({ length: 300 }, (_, i) => (i * 7 + 3) & 0xff);
const unoJob = (o = {}) =>
  JSON.stringify({ format: 'hex', hex: toHex(sketch), chip: 'ATmega328P', boardName: 'Arduino Uno R3', pageSize: 128, max: 32256, monitorBaud: 9600, ...o });
const stagesOf = () => events.filter(([t]) => t === 'stage').map(([, m]) => m);
let uno;

async function plugUno(o) {
  if (usb.isOpen()) await call(usb.disconnect());
  serial.ports.length = 0;
  uno = new FakeUno(o);
  serial.pick = uno;
  const r = await call(usb.connect(115200, false));
  assert.equal(r.ok, true, JSON.stringify(r));
  events.length = 0;
  return r;
}

test('an Uno is named as one in the port label', async () => {
  const r = await plugUno();
  assert.equal(r.label, 'Arduino Uno (2341:0043)');
});

test('Upload to an Uno: syncs with Optiboot, checks the chip, writes and checks every page, starts the sketch', async () => {
  await plugUno();
  const r = await call(usb.flash(unoJob()));
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(r.chip, 'ATmega328P');
  assert.equal(r.bytes, 300);
  assert.equal(r.reopened, true);
  assert.deepEqual([...uno.flash.subarray(0, 300)], [...sketch]);
  assert.ok(uno.flash.subarray(300, 384).every((x) => x === 0xff), 'the last page is padded with 0xFF');
  assert.equal(uno.pages, 3);
  assert.equal(uno.running, true, 'leaving programming mode starts the sketch');
  assert.deepEqual(stagesOf(), ['connecting', 'writing', 'verifying', 'resetting', 'reopening']);
  const progress = events.filter(([t]) => t === 'progress').map(([, m]) => JSON.parse(m));
  assert.deepEqual(progress.map((p) => p.done), [128, 256, 300]);
  assert.equal(progress.at(-1).total, 300);
  assert.deepEqual(uno.opens, [115200, 115200, 9600], 'monitor, bootloader, then the monitor at the sketch’s baud');
  assert.equal(usb.isOpen(), true);
  uno.push('hello from the Uno\n');
  await sleep(20);
  assert.ok(text.join('').endsWith('hello from the Uno\n'));
});

test('an older bootloader at 57600 baud is found too', async () => {
  await plugUno({ bootBaud: 57600 });
  const r = await call(usb.flash(unoJob()));
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.deepEqual(uno.opens, [115200, 115200, 57600, 9600]);
  assert.deepEqual([...uno.flash.subarray(0, 300)], [...sketch]);
});

test('a board with another chip is not written', async () => {
  await plugUno({ signature: [0x1e, 0x94, 0x06] });
  const r = await call(usb.flash(unoJob()));
  assert.equal(r.ok, false);
  assert.equal(r.code, 'wrong-chip');
  assert.match(r.message, /ATmega168, but the project is set to Arduino Uno R3/);
  assert.equal(uno.pages, 0);
  assert.equal(uno.running, true, 'its old sketch runs again');
  assert.equal(usb.isOpen(), true);
});

test('no answer from the bootloader is reported, and the Serial Monitor comes back', async () => {
  await plugUno({ bootloader: false });
  const t0 = Date.now();
  const r = await call(usb.flash(unoJob()));
  assert.equal(r.ok, false);
  assert.equal(r.code, 'avr-sync');
  assert.match(r.message, /did not answer its bootloader/);
  assert.ok(Date.now() - t0 < 5000, 'gives up within a few seconds');
  await sleep(400);
  assert.equal(usb.isOpen(), true);
});

test('a damaged or too big image is refused before touching the board', async () => {
  await plugUno();
  const bad = await call(usb.flash(unoJob({ hex: ':0300000001020305\n' })));
  assert.equal(bad.code, 'bad-job');
  assert.match(bad.message, /checksum/);
  const big = await call(usb.flash(unoJob({ max: 256 })));
  assert.equal(big.code, 'too-big');
  assert.equal(uno.resets, 0);
  assert.equal(usb.isOpen(), true);
});

test('Stop while writing an Uno: cancelled, the bootloader is left so the board restarts', async () => {
  await plugUno();
  usb.setHandlers(
    (t) => text.push(t),
    (type, msg) => {
      events.push([type, msg]);
      if (type === 'progress') usb.cancelFlash();
    },
  );
  const r = await call(usb.flash(unoJob()));
  usb.setHandlers(
    (t) => text.push(t),
    (type, msg) => events.push([type, msg]),
  );
  assert.equal(r.code, 'cancelled');
  assert.equal(r.partial, true);
  assert.equal(uno.pages, 1);
  assert.equal(uno.running, true);
  await sleep(400);
  assert.equal(usb.isOpen(), true);
});

test('Stop while still trying to reach the bootloader lets go of the port', async () => {
  await plugUno({ bootloader: false });
  setTimeout(() => usb.cancelFlash(), 450);
  const t0 = Date.now();
  const r = await call(usb.flash(unoJob()));
  assert.equal(r.code, 'cancelled');
  assert.equal(r.partial, false);
  assert.ok(Date.now() - t0 < 1500, 'stops at the next sync attempt');
  await sleep(400);
  assert.equal(usb.isOpen(), true, 'the port was closed, so the Serial Monitor could reopen it');
});

test('Test connection on an Uno reads the chip from the bootloader and restarts the sketch', async () => {
  await plugUno();
  const r = await call(usb.identify(9600, 'avr'));
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(r.chip, 'ATmega328P');
  assert.equal(r.label, 'Arduino Uno (2341:0043)');
  assert.equal(r.reopened, true);
  assert.equal(uno.pages, 0);
  assert.equal(uno.running, true);
  assert.deepEqual(uno.opens.at(-1), 9600);
});

test('reset on an Uno pulses DTR', async () => {
  await plugUno();
  const r = await call(usb.reset('avr'));
  assert.equal(r.ok, true);
  assert.deepEqual(uno.signals.slice(-2), [
    { dataTerminalReady: true, requestToSend: true },
    { dataTerminalReady: false, requestToSend: false },
  ]);
  assert.equal(uno.resets, 1);
  await call(usb.disconnect());
});
