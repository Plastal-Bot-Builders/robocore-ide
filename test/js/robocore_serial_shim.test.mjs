// Tests web/robocore_serial_shim.js (the macOS app's Web Serial stand-in) under the real web/robocore_usb.js, with a
// fake app on the RoboCoreHost channel (the Dart and Swift side, with a few ms per hop) and a fake Arduino Uno on its
// serial port. Run: node --test test/js/robocore_serial_shim.test.mjs
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const HOP = 3; // ms for a message between the page and the serial port, each way

// An Arduino Uno behind a USB serial port: a DTR rising edge resets it into Optiboot, which answers STK500v1 at
// 115200 baud for a second (longer while it gets commands); leaving programming mode starts the sketch.
class Uno {
  constructor() {
    this.flash = new Uint8Array(32768).fill(0xff);
    this.pages = 0;
    this.dtr = false;
    this.inBoot = false;
    this.running = false;
    this.rx = [];
    this.send = () => {};
  }
  signals(dtr) {
    if (dtr === true && !this.dtr) {
      this.inBoot = true;
      this.bootUntil = Date.now() + 1000;
      this.running = false;
      this.rx = [];
    }
    if (dtr != null) this.dtr = dtr;
  }
  receive(bytes) {
    if (!this.inBoot || this.baud !== 115200 || Date.now() > this.bootUntil) return;
    this.rx.push(...bytes);
    for (;;) {
      const b = this.rx;
      if (!b.length) return;
      const len = { 0x30: 2, 0x50: 2, 0x51: 2, 0x75: 2, 0x55: 4, 0x74: 5 }[b[0]] ?? (b[0] === 0x64 ? (b.length >= 3 ? 5 + ((b[1] << 8) | b[2]) : Infinity) : 1);
      if (b.length < len) return;
      const cmd = b.splice(0, len);
      this.bootUntil = Date.now() + 1000;
      if (cmd.at(-1) !== 0x20) {
        this.send([0x15]);
        continue;
      }
      const n = (cmd[1] << 8) | cmd[2];
      switch (cmd[0]) {
        case 0x30:
        case 0x50:
          this.send([0x14, 0x10]);
          break;
        case 0x51:
          this.send([0x14, 0x10]);
          this.inBoot = false;
          this.running = true;
          break;
        case 0x75:
          this.send([0x14, 0x1e, 0x95, 0x0f, 0x10]);
          break;
        case 0x55:
          this.addr = (cmd[1] | (cmd[2] << 8)) * 2;
          this.send([0x14, 0x10]);
          break;
        case 0x64:
          this.flash.set(cmd.slice(4, 4 + n), this.addr);
          this.pages++;
          this.send([0x14, 0x10]);
          break;
        case 0x74:
          this.send([0x14, ...this.flash.slice(this.addr, this.addr + n), 0x10]);
          break;
      }
    }
  }
}

// The app: lib/hw/usb_link_native.dart on top of macos/Runner/SerialPorts.swift, with one Uno plugged in.
const UNO = { path: '/dev/cu.usbmodem21301', vid: 0x2341, pid: 0x0043, product: 'Arduino Uno', serial: '9573' };
const app = { uno: new Uno(), handle: 0, open: null, choose: UNO, opens: [], plugged: [UNO], granted: [] };
const later = (f) => setTimeout(f, HOP);
const reply = (id, ok, value) => later(() => window.rcSerialHost.reply(id, ok, value));

function hostMessage(json) {
  const [kind, id, op, ...a] = JSON.parse(json);
  if (kind !== 'serial') return;
  switch (op) {
    case 'request':
      if (app.choose && !app.granted.includes(app.choose)) app.granted.push(app.choose);
      return reply(id, true, app.choose);
    case 'granted':
      return reply(id, true, app.plugged.filter((p) => app.granted.includes(p)));
    case 'open': {
      if (app.open != null) return reply(id, false, 'Resource busy');
      app.open = ++app.handle;
      app.uno.baud = a[1];
      app.opens.push(a[1]);
      const h = app.open;
      app.uno.send = (bytes) => later(() => app.open === h && window.rcSerialHost.data(h, Buffer.from(bytes).toString('base64')));
      return reply(id, true, h);
    }
    case 'signals':
      app.uno.signals(a[1]);
      return reply(id, true, true);
    case 'write':
      later(() => app.uno.receive([...Buffer.from(a[1], 'base64')]));
      return reply(id, true, true);
    case 'close':
      app.open = null;
      return reply(id, true, true);
  }
}

const events = [];
const text = [];
let usb;

before(async () => {
  globalThis.window = globalThis;
  Object.defineProperty(globalThis, 'navigator', { value: {}, configurable: true, writable: true });
  globalThis.RoboCoreHost = { postMessage: hostMessage };
  vm.runInThisContext(fs.readFileSync(path.join(here, '../../web/robocore_serial_shim.js'), 'utf8'));
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rcshim-'));
  fs.copyFileSync(path.join(here, '../../web/robocore_usb.js'), path.join(dir, 'robocore_usb.mjs'));
  await import(pathToFileURL(path.join(dir, 'robocore_usb.mjs')).href);
  usb = globalThis.robocoreUsb;
  usb.setHandlers(
    (t) => text.push(t),
    (type, msg) => events.push([type, msg]),
  );
  window.rcSerialHost.devices(app.plugged); // what the app sends when the page is ready
});

const call = async (p) => JSON.parse(await p);

function toHex(bytes) {
  const lines = [];
  for (let at = 0; at < bytes.length; at += 16) {
    const rec = [Math.min(16, bytes.length - at), (at >> 8) & 0xff, at & 0xff, 0, ...bytes.subarray(at, at + 16)];
    rec.push(-rec.reduce((s, x) => s + x, 0) & 0xff);
    lines.push(':' + rec.map((x) => x.toString(16).toUpperCase().padStart(2, '0')).join(''));
  }
  return lines.join('\n') + '\n:00000001FF\n';
}

test('navigator.serial is the stand-in, and the chooser picks the Uno', async () => {
  assert.ok(navigator.serial);
  const r = await call(usb.connect(115200, false));
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(r.label, 'Arduino Uno (2341:0043)');
  assert.equal(usb.isOpen(), true);
});

test('text from the board reaches the Serial Monitor', async () => {
  app.uno.send([...Buffer.from('hello from the Uno\n')]);
  await sleep(20);
  assert.ok(text.join('').endsWith('hello from the Uno\n'));
});

test('Upload to the Uno through the stand-in writes and checks every page and starts the sketch', async () => {
  const sketch = Uint8Array.from({ length: 1000 }, (_, i) => (i * 7 + 3) & 0xff);
  events.length = 0;
  const job = { format: 'hex', hex: toHex(sketch), chip: 'ATmega328P', boardName: 'Arduino Uno R3', pageSize: 128, max: 32256, monitorBaud: 9600 };
  const r = await call(usb.flash(JSON.stringify(job)));
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(r.chip, 'ATmega328P');
  assert.deepEqual([...app.uno.flash.subarray(0, 1000)], [...sketch]);
  assert.equal(app.uno.pages, 8);
  assert.equal(app.uno.running, true);
  assert.equal(app.opens.at(-1), 9600, 'the monitor comes back at the sketch’s baud');
  assert.equal(usb.isOpen(), true);
});

test('unplugging the Uno is reported once, and plugging it back in reconnects', async () => {
  events.length = 0;
  const h = app.open;
  app.open = null;
  window.rcSerialHost.closed(h, 'The board was unplugged.');
  app.plugged = [];
  window.rcSerialHost.devices([]);
  await sleep(20);
  assert.deepEqual(events.filter(([t]) => t === 'unplugged').length, 1, JSON.stringify(events));
  assert.equal(usb.isOpen(), false);
  app.plugged = [UNO];
  window.rcSerialHost.devices([UNO]);
  await sleep(100);
  assert.ok(events.some(([t]) => t === 'reconnected'), JSON.stringify(events));
  assert.equal(usb.isOpen(), true);
  await call(usb.disconnect());
  assert.equal(app.open, null, 'disconnect closes the port');
});

test('cancelling the chooser is reported, not thrown', async () => {
  app.choose = null;
  const r = await call(usb.connect(115200, false));
  assert.equal(r.ok, false);
  assert.equal(r.code, 'cancelled');
  app.choose = UNO;
});
