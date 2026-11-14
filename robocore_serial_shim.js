// RoboCore IDE, macOS app only: Web Serial (navigator.serial) for the USB helper (robocore_usb.js and esptool-js),
// on top of the Mac's serial ports. The page runs in a hidden WebView (robocore_usb_host.html); the ports are
// opened by the app (lib/hw/usb_link_native.dart → macos/Runner/SerialPorts.swift).
//
// To the app, on the RoboCoreHost channel: ['serial', requestId, op, ...args] with op request (filters: show the
// port chooser), granted, open (path, baud), write (handle, base64), signals (handle, dtr, rts), close (handle).
// From the app: rcSerialHost.reply(requestId, ok, value), .data(handle, base64), .closed(handle, reason) and
// .devices(ports) whenever a serial port comes or goes.
'use strict';

(function () {
  const host = window.RoboCoreHost;
  if (!host || navigator.serial) return;

  let nextRequest = 1;
  const pending = new Map();
  const byPath = new Map(); // one SerialPort per path, so the same board is the same object (state.port === port)
  const byHandle = new Map();
  let present = null; // paths plugged in at the last devices() call; null until the first one

  function call(op, ...args) {
    return new Promise((resolve, reject) => {
      const id = nextRequest++;
      pending.set(id, { resolve, reject });
      host.postMessage(JSON.stringify(['serial', id, op, ...args]));
    });
  }

  function domError(name, message) {
    return new DOMException(message || name, name);
  }

  function toBase64(bytes) {
    let s = '';
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(s);
  }

  function fromBase64(b64) {
    const s = atob(b64);
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  }

  class SerialPort extends EventTarget {
    constructor(info) {
      super();
      this._info = info;
      this._handle = null;
      this._readable = null;
      this._writable = null;
      this._readCtrl = null;
      this._waiting = []; // bytes that arrived while no stream was reading (kept for the next reader, as the OS would)
    }

    getInfo() {
      return { usbVendorId: this._info.vid ?? undefined, usbProductId: this._info.pid ?? undefined };
    }

    // Like Web Serial: a new stream whenever the last one was cancelled or closed, while the port is open.
    get readable() {
      if (this._handle == null) return null;
      if (!this._readable) {
        this._readable = new ReadableStream({
          start: (c) => {
            this._readCtrl = c;
            for (const b of this._waiting.splice(0)) c.enqueue(b);
          },
          cancel: () => {
            this._readCtrl = null;
            this._readable = null;
          },
        });
      }
      return this._readable;
    }

    get writable() {
      if (this._handle == null) return null;
      if (!this._writable) {
        this._writable = new WritableStream({
          write: (chunk) => call('write', this._handle, toBase64(chunk instanceof Uint8Array ? chunk : new Uint8Array(chunk))),
          close: () => {
            this._writable = null;
          },
          abort: () => {
            this._writable = null;
          },
        });
      }
      return this._writable;
    }

    async open(options) {
      if (this._handle != null) throw domError('InvalidStateError', 'The port is already open.');
      try {
        this._handle = await call('open', this._info.path, options.baudRate);
      } catch (e) {
        throw domError('NetworkError', e.message);
      }
      this._waiting = [];
      byHandle.set(this._handle, this);
    }

    async setSignals(s) {
      if (this._handle == null) throw domError('InvalidStateError', 'The port is closed.');
      await call('signals', this._handle, s.dataTerminalReady ?? null, s.requestToSend ?? null);
    }

    async close() {
      const h = this._handle;
      if (h == null) return;
      this._ended(null);
      await call('close', h).catch(() => {});
    }

    async forget() {}

    // Closed by us, or lost (reason): readers see the end, or a NetworkError when the board was unplugged.
    _ended(reason) {
      byHandle.delete(this._handle);
      this._handle = null;
      const c = this._readCtrl;
      this._readCtrl = null;
      this._readable = null;
      this._writable = null;
      try {
        if (c) reason ? c.error(domError('NetworkError', reason)) : c.close();
      } catch (e) {
        /* the stream was already done */
      }
    }

    _data(bytes) {
      if (this._readCtrl) this._readCtrl.enqueue(bytes);
      else this._waiting.push(bytes);
    }
  }

  function portFor(info) {
    let p = byPath.get(info.path);
    if (!p) {
      p = new SerialPort(info);
      byPath.set(info.path, p);
    } else {
      p._info = info;
    }
    return p;
  }

  // Like Chrome, the events fire with the port as their target.
  function fire(type, port) {
    const e = new Event(type);
    Object.defineProperty(e, 'target', { value: port });
    serial.dispatchEvent(e);
  }

  class Serial extends EventTarget {
    async requestPort(options) {
      const info = await call('request', (options && options.filters) || []).catch((e) => {
        throw domError('NotFoundError', e.message || 'No port selected by the user.');
      });
      if (!info) throw domError('NotFoundError', 'No port selected by the user.');
      return portFor(info);
    }

    async getPorts() {
      const list = await call('granted');
      return list.map(portFor);
    }
  }

  const serial = new Serial();
  Object.defineProperty(navigator, 'serial', { value: serial, configurable: true });

  window.rcSerialHost = {
    reply(id, ok, value) {
      const p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      if (ok) p.resolve(value);
      else p.reject(new Error(String(value)));
    },
    data(handle, b64) {
      const port = byHandle.get(handle);
      if (port) port._data(fromBase64(b64));
    },
    closed(handle, reason) {
      const port = byHandle.get(handle);
      if (port) port._ended(reason || 'The board was unplugged.');
    },
    // The granted ports that are plugged in now: 'connect' and 'disconnect' for the ones that came or went.
    devices(list) {
      const now = new Set(list.map((i) => i.path));
      if (present == null) {
        present = now; // what is plugged in when the app starts is not news
        return;
      }
      for (const path of present) if (!now.has(path) && byPath.has(path)) fire('disconnect', byPath.get(path));
      for (const info of list) if (!present.has(info.path)) fire('connect', portFor(info));
      present = now;
    },
  };
})();
