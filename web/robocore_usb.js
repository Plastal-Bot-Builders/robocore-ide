// RoboCore IDE: the USB-C link to a real board, from the browser.
//
//  - Serial Monitor over Web Serial (Chrome / Edge on a computer, or Chrome on Android with USB OTG).
//  - Plug-in / unplug notices and automatic reconnect to a board the user has already allowed.
//  - Flashing with esptool-js (vendor/esptool-js/bundle.js), loaded only when an upload starts.
//
// The Flutter app loads this file as a module and talks to window.robocoreUsb.
// Every call resolves with a JSON string { ok, ... } and never rejects, so errors reach Dart as data.
// Events go to the onEvent(type, message) handler:
//   unplugged, reconnected, plugged, error, log (flash output), progress (JSON), stage (flash step)

const ESPRESSIF_VID = 0x303a;
const ESPTOOL_URL = new URL('./vendor/esptool-js/bundle.js', import.meta.url).href;

const state = {
  port: null, // the open SerialPort
  reader: null,
  readLoop: null,
  baud: 115200,
  want: false, // the user asked to stay connected (drives auto-reconnect)
  last: null, // { vid, pid } of the last board, to find it again after a reset or re-plug
  busy: false, // flashing
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

async function flash(jobJson) {
  if (!supported()) return fail('unsupported', 'This browser has no Web Serial. Use Chrome or Edge on a computer.');
  if (state.busy) return fail('busy', 'An upload is already running.');
  let job;
  try {
    job = JSON.parse(jobJson);
  } catch (e) {
    return fail('bad-job', 'The program image is damaged.');
  }
  const parts = Array.isArray(job.parts) ? job.parts : [];
  if (!parts.length) return fail('bad-job', 'The compile server sent no program image.');

  state.busy = true;
  const monitorBaud = job.monitorBaud || state.baud || 115200;
  let port = state.port;
  let transport = null;
  try {
    if (!port) port = await grantedPort(state.last);
    if (!port) return fail('no-port', 'No board connected. Press Connect and pick the RoboCore.');
    const info = infoOf(port);
    state.last = info;

    // 1. Free the port: stop the Serial Monitor reader and close it.
    emit('stage', 'connecting');
    await closePort();

    // 2. Load esptool-js and put the chip into its bootloader.
    let mod;
    try {
      mod = await import(ESPTOOL_URL);
    } catch (e) {
      return fail('esptool', `Could not load the flasher (esptool-js): ${errText(e)}`);
    }
    const { ESPLoader, Transport } = mod;
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
    const loader = new ESPLoader({ transport, baudrate: job.baud || 921600, terminal, debugLogging: false });
    let chipName;
    try {
      await loader.main('default_reset');
      chipName = loader.chip && loader.chip.CHIP_NAME ? loader.chip.CHIP_NAME : '';
    } catch (e) {
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

    // 3. Write every part (bootloader, partition table, boot_app0, app) at its offset.
    emit('stage', 'writing');
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
        const done = before[i] + Math.round((sizes[i] * written) / Math.max(1, size));
        emit('progress', JSON.stringify({ part: i, parts: fileArray.length, name: parts[i].name || '', address: fileArray[i].address, done, total }));
      },
    });

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
    state.opening = true;
    let reopened = false;
    try {
      reopened = await waitAndOpen(info, monitorBaud, 9000);
    } finally {
      state.opening = false;
    }
    return result({ ok: true, chip: chipName, bytes: total, reopened, label: labelOf(info) });
  } catch (e) {
    return fail('flash', errText(e));
  } finally {
    if (transport) {
      try {
        await transport.disconnect();
      } catch (e) {
        /* ignore */
      }
    }
    if (state.busy) {
      state.busy = false;
      // A failed upload leaves the port closed: try to give the Serial Monitor back.
      if (state.want && !state.port && state.last) waitAndOpen(state.last, monitorBaud, 3000);
    }
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
  async reset() {
    const port = state.port;
    if (!port) return fail('closed', 'The board is not connected.');
    try {
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
};
