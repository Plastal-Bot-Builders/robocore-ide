// RoboCore IDE: the USB-C link to a real board, from the browser.
//
//  - Serial Monitor over Web Serial (Chrome / Edge on a computer, or Chrome on Android with USB OTG).
//  - Plug-in / unplug notices and automatic reconnect to a board the user has already allowed.
//  - Flashing with esptool-js (vendor/esptool-js/bundle.js), loaded only when an upload starts.
//  - Flashing an Arduino Uno (ATmega328P) through its Optiboot bootloader (STK500v1), below.
//
// The Flutter app loads this file as a module and talks to window.robocoreUsb.
// Every call resolves with a JSON string { ok, ... } and never rejects, so errors reach Dart as data.
// Events go to the onEvent(type, message) handler:
//   unplugged, reconnected, plugged, error, log (flash output), progress (JSON), stage (flash step)
// identify() asks the chip its name (Test connection); cancelFlash() stops an upload.
// identify() and reset() take the board's arch: 'esp32' (default) or 'avr'.

const ESPRESSIF_VID = 0x303a;
const ESPTOOL_URL = new URL('./vendor/esptool-js/bundle.js', import.meta.url).href;

const state = {
  port: null, // the open SerialPort
  reader: null,
  readLoop: null,
  baud: 115200,
  want: false, // the user asked to stay connected (drives auto-reconnect)
  last: null, // { vid, pid } of the last board, to find it again after a reset or re-plug
  busy: false, // flashing, or asking the chip its name
  cancel: false, // Stop pressed during an upload
  opening: false,
  quietUntil: 0, // a reset we asked for: the board drops off USB for a moment, so no unplug notice
  onText: null,
  onEvent: null,
};

const decoder = new TextDecoder();
const encoder = new TextEncoder();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function emit(type, message) {
  try {
    if (state.onEvent) state.onEvent(String(type), message == null ? '' : String(message));
  } catch (e) {
    console.error('robocoreUsb handler', e);
  }
}

function result(obj) {
  return JSON.stringify(obj);
}

function fail(code, message) {
  return result({ ok: false, code, message: String(message || code) });
}

function errText(e) {
  if (!e) return 'Unknown error';
  return e.message ? String(e.message) : String(e);
}

function infoOf(port) {
  const i = port && port.getInfo ? port.getInfo() : {};
  return { vid: i.usbVendorId ?? null, pid: i.usbProductId ?? null };
}

function hex4(n) {
  return n == null ? '????' : n.toString(16).toUpperCase().padStart(4, '0');
}

function labelOf(info) {
  if (!info) return 'USB board';
  if (info.vid === ESPRESSIF_VID && info.pid === 0x1001) return 'ESP32-S3 USB (303A:1001)';
  if (info.vid === ESPRESSIF_VID) return `Espressif USB (303A:${hex4(info.pid)})`;
  if (info.vid === 0x10c4) return `CP210x USB-UART (10C4:${hex4(info.pid)})`;
  if (info.vid === 0x1a86) return `CH340 USB-UART (1A86:${hex4(info.pid)})`;
  if ((info.vid === 0x2341 || info.vid === 0x2a03) && [0x0001, 0x0043, 0x0243].includes(info.pid)) return `Arduino Uno (${hex4(info.vid)}:${hex4(info.pid)})`;
  if (info.vid === 0x2341) return `Arduino (2341:${hex4(info.pid)})`;
  return `USB serial (${hex4(info.vid)}:${hex4(info.pid)})`;
}

function same(a, b) {
  return !!a && !!b && a.vid === b.vid && a.pid === b.pid;
}

function supported() {
  return typeof navigator !== 'undefined' && !!navigator.serial;
}

// ---------------------------------------------------------------- reading

function startReading(port) {
  state.readLoop = (async () => {
    while (state.port === port && port.readable) {
      let reader;
      try {
        reader = port.readable.getReader();
      } catch (e) {
        break;
      }
      state.reader = reader;
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          if (value && value.length && state.onText) {
            const text = decoder.decode(value, { stream: true });
            if (text) state.onText(text);
          }
        }
      } catch (e) {
        // A framing or buffer error keeps the port usable: the loop gets a new reader.
        // A lost device makes port.readable null and the loop ends; 'disconnect' reports it.
        if (state.port === port && e && e.name !== 'NetworkError') emit('error', `Serial read: ${errText(e)}`);
      } finally {
        try {
          reader.releaseLock();
        } catch (e) {
          /* already released */
        }
        if (state.reader === reader) state.reader = null;
      }
    }
  })();
}

async function openPort(port, baud) {
  await port.open({ baudRate: baud, bufferSize: 16384 });
  // DTR and RTS low = the chip runs normally (on the ESP32-S3 USB Serial/JTAG these lines drive reset and BOOT).
  try {
    await port.setSignals({ dataTerminalReady: false, requestToSend: false });
  } catch (e) {
    /* not every adapter supports it */
  }
  state.port = port;
  state.baud = baud;
  state.last = infoOf(port);
  startReading(port);
}

async function closePort() {
  const port = state.port;
  if (!port) return;
  state.port = null;
  try {
    if (state.reader) await state.reader.cancel();
  } catch (e) {
    /* ignore */
  }
  try {
    await state.readLoop;
  } catch (e) {
    /* ignore */
  }
  state.readLoop = null;
  try {
    await port.close();
  } catch (e) {
    /* already closed or unplugged */
  }
}

// Finds a board the user has already allowed (no permission prompt).
async function grantedPort(prefer) {
  if (!supported()) return null;
  const ports = await navigator.serial.getPorts();
  if (prefer) {
    const m = ports.find((p) => same(infoOf(p), prefer));
    if (m) return m;
  }
  const esp = ports.filter((p) => infoOf(p).vid === ESPRESSIF_VID);
  if (esp.length === 1) return esp[0];
  return ports.length === 1 ? ports[0] : null;
}

// After a reset the ESP32-S3 drops off USB and comes back: wait for it and reopen.
async function waitAndOpen(info, baud, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (state.port) return true;
    try {
      const port = await grantedPort(info);
      if (port) {
        await openPort(port, baud);
        return true;
      }
    } catch (e) {
      /* not back yet */
    }
    await sleep(300);
  }
  return false;
}

// ---------------------------------------------------------------- plug and unplug

if (supported()) {
  navigator.serial.addEventListener('disconnect', (e) => {
    const port = e.target;
    if (port && port === state.port) {
      const info = infoOf(port);
      state.port = null;
      state.reader = null;
      if (!state.busy && Date.now() > state.quietUntil) emit('unplugged', labelOf(info));
    }
  });
  navigator.serial.addEventListener('connect', async (e) => {
    if (state.busy || state.port || state.opening) return;
    const info = infoOf(e.target);
    if (state.want && (!state.last || same(info, state.last))) {
      state.opening = true;
      try {
        if (await waitAndOpen(info, state.baud, 4000)) emit(Date.now() > state.quietUntil ? 'reconnected' : 'restarted', labelOf(info));
      } finally {
        state.opening = false;
      }
    } else {
      emit('plugged', labelOf(info));
    }
  });
}

// ---------------------------------------------------------------- flashing

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function chipKey(name) {
  return String(name || '').toLowerCase().replace(/[^a-z0-9]/g, '');
}

// Stop pressed during an upload (E-07): the flasher gives up at its next step.
class Cancelled extends Error {}

function checkCancel() {
  if (state.cancel) throw new Cancelled('Upload cancelled.');
}

async function loadEsptool() {
  try {
    return await import(ESPTOOL_URL);
  } catch (e) {
    throw Object.assign(new Error(`Could not load the flasher (esptool-js): ${errText(e)}`), { code: 'esptool' });
  }
}

// After flashing or asking the chip its name: let go of the bootloader and give the Serial Monitor back.
async function release(transport, monitorBaud, ms) {
  if (transport) {
    try {
      await transport.disconnect();
    } catch (e) {
      /* the chip may already have dropped off USB */
    }
  }
  if (state.busy) {
    state.busy = false;
    state.cancel = false;
    // In the background, so the answer is not held up while the board restarts.
    if (state.want && !state.port && state.last) waitAndOpen(state.last, monitorBaud, ms);
  }
}

async function flash(jobJson) {
  if (!supported()) return fail('unsupported', 'This browser has no Web Serial. Use Chrome or Edge on a computer.');
  if (state.busy) return fail('busy', 'An upload is already running.');
  let job;
  try {
    job = JSON.parse(jobJson);
  } catch (e) {
    return fail('bad-job', 'The program image is damaged.');
  }
  if (job.format === 'hex') return flashAvr(job);
  const parts = Array.isArray(job.parts) ? job.parts : [];
  if (!parts.length) return fail('bad-job', 'The compile server sent no program image.');

  state.busy = true;
  state.cancel = false;
  const monitorBaud = job.monitorBaud || state.baud || 115200;
  let port = state.port;
  let transport = null;
  let loader = null;
  let writing = false;
  let reopenMs = 3000;
  try {
    if (!port) port = await grantedPort(state.last);
    if (!port) return fail('no-port', 'No board connected. Press Connect and pick the RoboCore.');
    const info = infoOf(port);
    state.last = info;

    // 1. Free the port: stop the Serial Monitor reader and close it.
    emit('stage', 'connecting');
    await closePort();
    checkCancel();

    // 2. Load esptool-js and put the chip into its bootloader.
    const { ESPLoader, Transport } = await loadEsptool();
    checkCancel();
    transport = new Transport(port, false);
    const terminal = {
      clean() {},
      writeLine(s) {
        emit('log', s);
      },
      write(s) {
        emit('log', s);
      },
    };
    loader = new ESPLoader({ transport, baudrate: job.baud || 921600, terminal, debugLogging: false });
    let chipName;
    try {
      await loader.main('default_reset');
      chipName = loader.chip && loader.chip.CHIP_NAME ? loader.chip.CHIP_NAME : '';
    } catch (e) {
      loader = null;
      return fail('bootloader', errText(e));
    }
    if (job.chip && chipKey(chipName) && chipKey(chipName) !== chipKey(job.chip)) {
      try {
        await loader.after('hard_reset');
      } catch (e) {
        /* ignore */
      }
      return fail('wrong-chip', `This board has an ${chipName}, but the project is set to ${job.boardName || job.chip}. Pick the right board and upload again.`);
    }
    checkCancel();

    // 3. Write every part (bootloader, partition table, boot_app0, app) at its offset.
    emit('stage', 'writing');
    writing = true;
    const fileArray = parts.map((p) => ({ address: Number(p.offset), data: b64ToBytes(p.data) }));
    const sizes = fileArray.map((f) => f.data.length);
    const total = sizes.reduce((a, b) => a + b, 0);
    const before = sizes.map((_, i) => sizes.slice(0, i).reduce((a, b) => a + b, 0));
    await loader.writeFlash({
      fileArray,
      flashMode: 'keep',
      flashFreq: 'keep',
      flashSize: 'keep',
      eraseAll: false,
      compress: true,
      reportProgress: (i, written, size) => {
        checkCancel();
        const done = before[i] + Math.round((sizes[i] * written) / Math.max(1, size));
        emit('progress', JSON.stringify({ part: i, parts: fileArray.length, name: parts[i].name || '', address: fileArray[i].address, done, total }));
      },
    });
    writing = false;

    // 4. Restart the board so the new sketch runs.
    emit('stage', 'resetting');
    await loader.after('hard_reset');
    try {
      await transport.disconnect();
    } catch (e) {
      /* the chip may already have dropped off USB */
    }
    transport = null;

    // 5. Reopen the Serial Monitor (the ESP32-S3 re-enumerates after the reset).
    emit('stage', 'reopening');
    state.want = true;
    state.busy = false;
    state.cancel = false;
    state.opening = true;
    let reopened = false;
    try {
      reopened = await waitAndOpen(info, monitorBaud, 9000);
    } finally {
      state.opening = false;
    }
    return result({ ok: true, chip: chipName, bytes: total, reopened, label: labelOf(info) });
  } catch (e) {
    if (e instanceof Cancelled) {
      // Restart the board out of its bootloader. Stopped while writing, its program is now incomplete.
      if (loader) {
        try {
          state.quietUntil = Date.now() + 9000;
          await loader.after('hard_reset');
        } catch (err) {
          /* ignore */
        }
      }
      reopenMs = 9000;
      return result({ ok: false, code: 'cancelled', message: 'Upload cancelled.', partial: writing });
    }
    return fail(e && e.code === 'esptool' ? 'esptool' : 'flash', errText(e));
  } finally {
    await release(transport, monitorBaud, reopenMs);
  }
}

// Test connection (B-04): asks the chip its name through the bootloader, then restarts it.
async function identify(baud, arch) {
  if (arch === 'avr') return identifyAvr(baud);
  if (!supported()) return fail('unsupported', 'This browser has no Web Serial. Use Chrome or Edge on a computer.');
  if (state.busy) return fail('busy', 'An upload is running. Wait for it to finish.');
  state.busy = true;
  state.cancel = false;
  const monitorBaud = baud || state.baud || 115200;
  let port = state.port;
  let transport = null;
  try {
    if (!port) port = await grantedPort(state.last);
    if (!port) return fail('no-port', 'No board connected. Press Connect and pick the RoboCore.');
    const info = infoOf(port);
    state.last = info;
    await closePort();
    const { ESPLoader, Transport } = await loadEsptool();
    transport = new Transport(port, false);
    const quiet = { clean() {}, writeLine() {}, write() {} };
    const loader = new ESPLoader({ transport, baudrate: 115200, terminal: quiet, debugLogging: false });
    let chip;
    try {
      await loader.main('default_reset');
      const c = loader.chip || {};
      chip = c.getChipDescription ? await c.getChipDescription(loader) : c.CHIP_NAME || 'an unknown chip';
    } catch (e) {
      return fail('bootloader', errText(e));
    }
    state.quietUntil = Date.now() + 9000;
    try {
      await loader.after('hard_reset');
    } catch (e) {
      /* it answered; the restart is best effort */
    }
    try {
      await transport.disconnect();
    } catch (e) {
      /* the chip may already have dropped off USB */
    }
    transport = null;
    state.want = true;
    state.busy = false;
    state.opening = true;
    let reopened = false;
    try {
      reopened = await waitAndOpen(info, monitorBaud, 9000);
    } finally {
      state.opening = false;
    }
    return result({ ok: true, chip, label: labelOf(info), reopened });
  } catch (e) {
    return fail(e && e.code === 'esptool' ? 'esptool' : 'identify', errText(e));
  } finally {
    await release(transport, monitorBaud, 3000);
  }
}

// ---------------------------------------------------------------- Arduino Uno (Optiboot, STK500v1)
//
// The Uno's bootloader runs for about a second after a reset. Opening the port and pulsing DTR resets it (the board's
// auto-reset capacitor), then the bootloader takes the same few STK500v1 commands avrdude sends: get in sync, read the
// signature, enter programming mode, load an address and write a page (128 bytes on the ATmega328P), read pages back
// to check them, and leave programming mode, which starts the sketch.

const STK = { OK: 0x10, INSYNC: 0x14, EOP: 0x20, SYNC: 0x30, ENTER: 0x50, LEAVE: 0x51, ADDR: 0x55, PROG: 0x64, READ: 0x74, SIGN: 0x75 };

const AVR_CHIPS = {
  '1e950f': 'ATmega328P',
  '1e9514': 'ATmega328',
  '1e9516': 'ATmega328PB',
  '1e940b': 'ATmega168P',
  '1e9406': 'ATmega168',
  '1e9587': 'ATmega32U4',
};

// Intel HEX (what avr-gcc makes) to one block of bytes from address 0. Gaps are 0xFF, like erased flash.
function parseHex(text) {
  const records = [];
  let base = 0;
  let end = 0;
  for (const raw of String(text).split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    if (line[0] !== ':' || line.length < 11 || line.length % 2 === 0) throw new Error(`bad line "${line.slice(0, 16)}"`);
    const b = [];
    for (let i = 1; i < line.length; i += 2) b.push(parseInt(line.slice(i, i + 2), 16));
    if (b.some(Number.isNaN) || b.length !== b[0] + 5) throw new Error(`bad line "${line.slice(0, 16)}"`);
    if ((b.reduce((s, x) => s + x, 0) & 0xff) !== 0) throw new Error(`checksum error in "${line.slice(0, 16)}"`);
    const type = b[3];
    if (type === 0) {
      const at = base + ((b[1] << 8) | b[2]);
      records.push([at, b.slice(4, 4 + b[0])]);
      end = Math.max(end, at + b[0]);
    } else if (type === 1) {
      break;
    } else if (type === 2) {
      base = ((b[4] << 8) | b[5]) << 4;
    } else if (type === 4) {
      base = ((b[4] << 8) | b[5]) << 16;
    }
  }
  const out = new Uint8Array(end).fill(0xff);
  for (const [at, data] of records) out.set(data, at);
  return out;
}

// The bootloader's bytes, read in the background so a reply can be waited for with a timeout.
function byteLink(port) {
  const buf = [];
  let wake = null;
  let closed = false;
  let got = 0;
  const reader = port.readable.getReader();
  const writer = port.writable.getWriter();
  const poke = () => {
    if (wake) wake();
    wake = null;
  };
  const pump = (async () => {
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        if (value) {
          for (const x of value) buf.push(x);
          got += value.length;
        }
        poke();
      }
    } catch (e) {
      /* the port closed */
    }
    closed = true;
    poke();
  })();
  return {
    async send(bytes) {
      await writer.write(Uint8Array.from(bytes));
    },
    drain() {
      buf.length = 0;
    },
    // Whether the board has sent anything since the link opened (a bootloader that lost sync, not a silent board).
    heard() {
      return got > 0;
    },
    async take(n, ms) {
      const end = Date.now() + ms;
      while (buf.length < n) {
        const left = end - Date.now();
        if (left <= 0 || closed) throw Object.assign(new Error('The board stopped answering.'), { code: 'timeout' });
        await new Promise((r) => {
          wake = r;
          setTimeout(r, left);
        });
      }
      return buf.splice(0, n);
    },
    async close() {
      try {
        await reader.cancel();
      } catch (e) {
        /* already closed */
      }
      await pump;
      for (const l of [reader, writer]) {
        try {
          l.releaseLock();
        } catch (e) {
          /* already released */
        }
      }
    },
  };
}

// One command: the bytes, then EOP; the answer is INSYNC, `reply` bytes, OK.
async function stk(io, bytes, reply = 0, ms = 1000) {
  await io.send([...bytes, STK.EOP]);
  const [sync] = await io.take(1, ms);
  if (sync !== STK.INSYNC) throw Object.assign(new Error('The bootloader lost sync.'), { code: 'sync' });
  const data = reply ? await io.take(reply, ms) : [];
  const [ok] = await io.take(1, ms);
  if (ok !== STK.OK) throw Object.assign(new Error('The bootloader refused a command.'), { code: 'sync' });
  return data;
}

// Opens the port, resets the board into its bootloader and gets in sync. The Uno's Optiboot talks at 115200 baud;
// older bootloaders (Duemilanove, old Nano) at 57600, so that is tried next. Resolves the link, or null.
//
// Pacing matters: after a reset Optiboot flashes the LED for about 0.4 s before it reads the serial line, and bytes
// sent meanwhile overflow its 2-byte receive buffer. Sync requests sent every 150 ms (as this did first) got one
// answer and left a broken command behind; Optiboot then gives up, starts the old sketch, and the next command gets
// no answer ("The board stopped answering", seen on a real Uno R3). So, like avrdude: one request, and the first
// wait covers the LED flash (600 ms); later ones are short, since a listening bootloader answers at once. Sync is
// checked once more on a clean line. A board that answered something but lost sync is reset once more; a silent one
// is not, so a board without a bootloader still fails within a few seconds.
async function avrStart(port, bauds) {
  for (const baud of bauds) {
    checkCancel();
    try {
      await port.open({ baudRate: baud, bufferSize: 4096 });
    } catch (e) {
      throw Object.assign(new Error(`Could not open the port: ${errText(e)}. Close the Arduino IDE or any other app using it, then try again.`), { code: 'open' });
    }
    const io = byteLink(port);
    try {
      for (let reset = 0; reset < 2 && (reset === 0 || io.heard()); reset++) {
        await port.setSignals({ dataTerminalReady: false, requestToSend: false });
        await sleep(250);
        await port.setSignals({ dataTerminalReady: true, requestToSend: true });
        await sleep(50);
        for (let i = 0; i < 4; i++) {
          checkCancel();
          io.drain();
          await io.send([STK.SYNC, STK.EOP]);
          try {
            const r = await io.take(2, i === 0 ? 600 : 250);
            if (r[0] !== STK.INSYNC || r[1] !== STK.OK) continue;
            await sleep(30);
            io.drain();
            await io.send([STK.SYNC, STK.EOP]);
            const again = await io.take(2, 250);
            if (again[0] === STK.INSYNC && again[1] === STK.OK) return io;
          } catch (e) {
            /* no answer yet: the bootloader may still be starting */
          }
        }
      }
    } catch (e) {
      // Stop, or the adapter refused the reset lines: let go of the port before giving up.
      await io.close();
      await port.close().catch(() => {});
      throw e;
    }
    await io.close();
    await port.close();
  }
  return null;
}

async function avrChip(io) {
  const s = await stk(io, [STK.SIGN], 3);
  const key = s.map((x) => x.toString(16).padStart(2, '0')).join('');
  return AVR_CHIPS[key] || `an unknown chip (signature ${key.toUpperCase()})`;
}

// The app adds what to check (the board picked in Board Setup, another program holding the port).
const AVR_NO_ANSWER = 'The board did not answer its bootloader.';

// Closes the bootloader link and the port, then reopens the Serial Monitor on the same port.
async function avrFinish(port, io, info, monitorBaud) {
  if (io) await io.close();
  try {
    await port.close();
  } catch (e) {
    /* already closed */
  }
  state.want = true;
  state.busy = false;
  state.cancel = false;
  state.opening = true;
  try {
    return await waitAndOpen(info, monitorBaud, 4000);
  } finally {
    state.opening = false;
  }
}

async function flashAvr(job) {
  let image;
  try {
    image = parseHex(job.hex || '');
  } catch (e) {
    return fail('bad-job', `The program image is damaged: ${errText(e)}.`);
  }
  if (!image.length) return fail('bad-job', 'The compile server sent no program image.');
  if (job.max && image.length > job.max) return fail('too-big', `The sketch is ${image.length} bytes; the board has room for ${job.max}.`);
  const pageSize = job.pageSize || 128;
  const monitorBaud = job.monitorBaud || state.baud || 115200;

  state.busy = true;
  state.cancel = false;
  let port = state.port;
  let io = null;
  let programming = false;
  let writing = false;
  try {
    if (!port) port = await grantedPort(state.last);
    if (!port) return fail('no-port', 'No board connected. Press Connect and pick the board.');
    const info = infoOf(port);
    state.last = info;

    // 1. Free the port, reset the board into its bootloader and get in sync.
    emit('stage', 'connecting');
    await closePort();
    io = await avrStart(port, [job.baud || 115200, 57600]);
    if (!io) return fail('avr-sync', AVR_NO_ANSWER);

    // 2. The right chip?
    const chip = await avrChip(io);
    if (job.chip && chipKey(chip) !== chipKey(job.chip)) {
      await stk(io, [STK.LEAVE]).catch(() => {});
      await avrFinish(port, io, info, monitorBaud);
      io = null;
      return fail('wrong-chip', `This board has an ${chip}, but the project is set to ${job.boardName || job.chip}. Pick the right board and upload again.`);
    }
    checkCancel();

    // 3. Write the pages, then read them back.
    await stk(io, [STK.ENTER]);
    programming = true;
    emit('stage', 'writing');
    writing = true;
    const pages = Math.ceil(image.length / pageSize);
    const total = image.length;
    for (let i = 0; i < pages; i++) {
      checkCancel();
      const at = i * pageSize;
      const page = new Uint8Array(pageSize).fill(0xff);
      page.set(image.subarray(at, at + pageSize));
      await stk(io, [STK.ADDR, (at >> 1) & 0xff, (at >> 9) & 0xff]);
      await stk(io, [STK.PROG, pageSize >> 8, pageSize & 0xff, 0x46, ...page]);
      emit('progress', JSON.stringify({ part: 0, parts: 1, name: 'sketch', address: at, done: Math.min(total, at + pageSize), total }));
    }
    writing = false;
    emit('stage', 'verifying');
    for (let i = 0; i < pages; i++) {
      checkCancel();
      const at = i * pageSize;
      await stk(io, [STK.ADDR, (at >> 1) & 0xff, (at >> 9) & 0xff]);
      const back = await stk(io, [STK.READ, pageSize >> 8, pageSize & 0xff, 0x46], pageSize);
      for (let j = 0; j < pageSize && at + j < total; j++) {
        if (back[j] !== image[at + j]) {
          const where = (at + j).toString(16).toUpperCase().padStart(4, '0');
          throw Object.assign(new Error(`The board did not keep what was written (first difference at 0x${where}). Upload again.`), { code: 'verify' });
        }
      }
    }

    // 4. Leave programming mode: the bootloader starts the new sketch. Then the Serial Monitor comes back.
    emit('stage', 'resetting');
    await stk(io, [STK.LEAVE]);
    programming = false;
    emit('stage', 'reopening');
    const reopened = await avrFinish(port, io, info, monitorBaud);
    io = null;
    return result({ ok: true, chip, bytes: total, reopened, label: labelOf(info) });
  } catch (e) {
    if (io && programming) await stk(io, [STK.LEAVE], 0, 300).catch(() => {});
    if (e instanceof Cancelled) return result({ ok: false, code: 'cancelled', message: 'Upload cancelled.', partial: writing });
    const code = e && e.code;
    if (code === 'verify' || code === 'open') return fail(code, errText(e));
    if (code === 'sync' || code === 'timeout') return fail('avr-sync', errText(e));
    return fail('flash', errText(e));
  } finally {
    if (io) {
      await io.close();
      try {
        await port.close();
      } catch (e) {
        /* already closed */
      }
    }
    await release(null, monitorBaud, 3000);
  }
}

// Test connection on an Uno: the bootloader's signature names the chip; leaving it starts the sketch again.
async function identifyAvr(baud) {
  if (!supported()) return fail('unsupported', 'This browser has no Web Serial. Use Chrome or Edge on a computer.');
  if (state.busy) return fail('busy', 'An upload is running. Wait for it to finish.');
  state.busy = true;
  state.cancel = false;
  const monitorBaud = baud || state.baud || 115200;
  let port = state.port;
  let io = null;
  try {
    if (!port) port = await grantedPort(state.last);
    if (!port) return fail('no-port', 'No board connected. Press Connect and pick the board.');
    const info = infoOf(port);
    state.last = info;
    await closePort();
    io = await avrStart(port, [115200, 57600]);
    if (!io) return fail('avr-sync', AVR_NO_ANSWER);
    const chip = await avrChip(io);
    await stk(io, [STK.LEAVE]).catch(() => {});
    const reopened = await avrFinish(port, io, info, monitorBaud);
    io = null;
    return result({ ok: true, chip, label: labelOf(info), reopened });
  } catch (e) {
    return fail(e && e.code === 'open' ? 'open' : 'identify', errText(e));
  } finally {
    if (io) {
      await io.close();
      try {
        await port.close();
      } catch (e) {
        /* already closed */
      }
    }
    await release(null, monitorBaud, 3000);
  }
}

// ---------------------------------------------------------------- API for the app

window.robocoreUsb = {
  version: 1,

  supported,

  isOpen() {
    return !!state.port;
  },

  setHandlers(onText, onEvent) {
    state.onText = onText;
    state.onEvent = onEvent;
  },

  // Shows the browser's port chooser (needs a click). espressifOnly limits it to ESP32-S3 USB boards.
  async connect(baud, espressifOnly) {
    if (!supported()) return fail('unsupported', 'This browser has no Web Serial. Use Chrome or Edge on a computer.');
    if (state.busy) return fail('busy', 'An upload is running. Wait for it to finish.');
    let port;
    try {
      port = await navigator.serial.requestPort(espressifOnly ? { filters: [{ usbVendorId: ESPRESSIF_VID }] } : {});
    } catch (e) {
      if (e && e.name === 'NotFoundError') return fail('cancelled', 'No port was chosen.');
      if (e && e.name === 'SecurityError') return fail('blocked', 'The browser blocked the port chooser. Click Connect again.');
      return fail('request', errText(e));
    }
    try {
      if (state.port && state.port !== port) await closePort();
      if (state.port !== port) await openPort(port, baud);
      state.want = true;
      return result({ ok: true, label: labelOf(infoOf(port)) });
    } catch (e) {
      if (e && e.name === 'InvalidStateError' && port.readable) {
        // Already open (for example by this tab after a reload).
        state.port = port;
        state.want = true;
        startReading(port);
        return result({ ok: true, label: labelOf(infoOf(port)) });
      }
      return fail('open', `Could not open the port: ${errText(e)}. Close the Arduino IDE or any other app using it, then try again.`);
    }
  },

  // Opens a board the user allowed before, without a prompt. Resolves ok:false if there is none.
  async reconnect(baud) {
    if (!supported()) return fail('unsupported', 'No Web Serial.');
    if (state.port) return result({ ok: true, label: labelOf(infoOf(state.port)) });
    try {
      const port = await grantedPort(state.last);
      if (!port) return fail('none', 'No board plugged in.');
      await openPort(port, baud);
      state.want = true;
      return result({ ok: true, label: labelOf(infoOf(port)) });
    } catch (e) {
      return fail('open', errText(e));
    }
  },

  async disconnect() {
    state.want = false;
    await closePort();
    return result({ ok: true });
  },

  async setBaud(baud) {
    state.baud = baud;
    const port = state.port;
    if (!port) return result({ ok: true });
    try {
      await closePort();
      await openPort(port, baud);
      return result({ ok: true });
    } catch (e) {
      return fail('open', errText(e));
    }
  },

  async write(text) {
    const port = state.port;
    if (!port || !port.writable) return fail('closed', 'The board is not connected.');
    let writer;
    try {
      writer = port.writable.getWriter();
      await writer.write(encoder.encode(text));
      return result({ ok: true });
    } catch (e) {
      return fail('write', errText(e));
    } finally {
      if (writer) {
        try {
          writer.releaseLock();
        } catch (e) {
          /* ignore */
        }
      }
    }
  },

  // Restarts the sketch (EN pulse through RTS). The ESP32-S3 drops off USB for a moment and comes back.
  // An Uno resets on a DTR pulse instead (its auto-reset capacitor) and stays on USB.
  async reset(arch) {
    const port = state.port;
    if (!port) return fail('closed', 'The board is not connected.');
    try {
      if (arch === 'avr') {
        await port.setSignals({ dataTerminalReady: true, requestToSend: true });
        await sleep(100);
        await port.setSignals({ dataTerminalReady: false, requestToSend: false });
        return result({ ok: true });
      }
      state.quietUntil = Date.now() + 6000;
      await port.setSignals({ dataTerminalReady: false, requestToSend: true });
      await sleep(120);
      await port.setSignals({ dataTerminalReady: false, requestToSend: false });
      return result({ ok: true });
    } catch (e) {
      return fail('reset', errText(e));
    }
  },

  flash,

  // Stop during an upload. Resolves at once; flash() then resolves with code 'cancelled'.
  cancelFlash() {
    if (state.busy) state.cancel = true;
    return Promise.resolve(result({ ok: true, cancelling: state.busy }));
  },

  identify,
};
