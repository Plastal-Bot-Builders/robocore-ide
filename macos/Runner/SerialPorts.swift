import Cocoa
import FlutterMacOS
import IOKit
import IOKit.serial

/// USB serial ports for the macOS app, which has no Web Serial. Flutter's side (lib/hw/usb_link_native.dart) hands
/// them to the web app's USB helper as a stand-in for Web Serial, so the same Serial Monitor and flashing code runs.
///
/// "robocore/serial" methods: list, open {path, baud} → id, write {id, data}, signals {id, dtr?, rts?},
/// baud {id, baud}, close {id}. "robocore/serial/events": {type: data, id, data}, {type: closed, id, reason}
/// (unplugged or failed), and {type: devices} when a serial port comes or goes.
final class SerialPorts: NSObject, FlutterStreamHandler {
  static let shared = SerialPorts()

  private final class Port {
    let fd: Int32
    let source: DispatchSourceRead
    init(fd: Int32, source: DispatchSourceRead) {
      self.fd = fd
      self.source = source
    }
  }

  // The ioctl requests are function-like C macros, which Swift doesn't import (values for 64-bit macOS).
  private static let tiocexcl: UInt = 0x2000_740D  // _IO('t', 13): no one else may open the port
  private static let tiocmget: UInt = 0x4004_746A  // _IOR('t', 106, int)
  private static let tiocmset: UInt = 0x8004_746D  // _IOW('t', 109, int)
  private static let iossiospeed: UInt = 0x8008_5402  // _IOW('T', 2, speed_t): any baud rate
  private static let dtrBit: Int32 = 0x2  // TIOCM_DTR
  private static let rtsBit: Int32 = 0x4  // TIOCM_RTS

  private let queue = DispatchQueue(label: "robocore.serial")
  private var ports: [Int: Port] = [:]  // only touched on `queue`
  private var nextId = 1
  private var sink: FlutterEventSink?
  private var notifications: IONotificationPortRef?
  private var iterators: [io_iterator_t] = []

  func attach(to messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "robocore/serial", binaryMessenger: messenger).setMethodCallHandler {
      [weak self] call, result in
      self?.handle(call, result)
    }
    FlutterEventChannel(name: "robocore/serial/events", binaryMessenger: messenger).setStreamHandler(self)
    watchDevices()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func send(_ event: [String: Any]) {
    DispatchQueue.main.async { self.sink?(event) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let a = call.arguments as? [String: Any] ?? [:]
    let id = a["id"] as? Int ?? 0
    let reply: (Any?) -> Void = { value in DispatchQueue.main.async { result(value) } }
    switch call.method {
    case "list":
      result(SerialPorts.list())
    case "open":
      guard let path = a["path"] as? String, let baud = a["baud"] as? Int else {
        return result(FlutterError(code: "args", message: "open needs path and baud", details: nil))
      }
      queue.async { reply(self.open(path, baud)) }
    case "write":
      guard let data = a["data"] as? FlutterStandardTypedData else {
        return result(FlutterError(code: "args", message: "write needs data", details: nil))
      }
      queue.async { reply(self.write(id, data.data)) }
    case "signals":
      queue.async { reply(self.signals(id, dtr: a["dtr"] as? Bool, rts: a["rts"] as? Bool)) }
    case "baud":
      queue.async { reply(self.ports[id].map { SerialPorts.setSpeed($0.fd, a["baud"] as? Int ?? 115200) } ?? false) }
    case "close":
      queue.async {
        self.close(id)
        reply(true)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Ports

  /// Every serial port, with the USB device's ids and names where it is a USB device.
  static func list() -> [[String: Any]] {
    var out: [[String: Any]] = []
    let matching = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
    matching[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return out }
    defer { IOObjectRelease(iterator) }
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      guard let path = property(service, kIOCalloutDeviceKey, parents: false) as? String else { continue }
      var port: [String: Any] = ["path": path]
      if let vid = property(service, "idVendor") as? Int { port["vid"] = vid }
      if let pid = property(service, "idProduct") as? Int { port["pid"] = pid }
      if let name = property(service, "USB Product Name") as? String { port["product"] = name }
      if let maker = property(service, "USB Vendor Name") as? String { port["maker"] = maker }
      if let serial = property(service, "USB Serial Number") as? String { port["serial"] = serial }
      out.append(port)
    }
    return out
  }

  private static func property(_ service: io_object_t, _ key: String, parents: Bool = true) -> Any? {
    let options = parents ? IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents) : 0
    return IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
  }

  private func open(_ path: String, _ baud: Int) -> Any {
    let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
    if fd < 0 { return SerialPorts.error("open", path) }
    _ = ioctl(fd, SerialPorts.tiocexcl)
    var t = termios()
    tcgetattr(fd, &t)
    cfmakeraw(&t)
    t.c_cflag |= tcflag_t(CLOCAL | CREAD)
    t.c_cflag &= ~tcflag_t(CRTSCTS)
    tcsetattr(fd, TCSANOW, &t)
    if !SerialPorts.setSpeed(fd, baud) {
      let e = SerialPorts.error("baud", path)
      Darwin.close(fd)
      return e
    }
    let id = nextId
    nextId += 1
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.read(id) }
    source.setCancelHandler { Darwin.close(fd) }
    ports[id] = Port(fd: fd, source: source)
    source.resume()
    return id
  }

  private func read(_ id: Int) {
    guard let port = ports[id] else { return }
    var buffer = [UInt8](repeating: 0, count: 16384)
    let n = Darwin.read(port.fd, &buffer, buffer.count)
    if n > 0 {
      send(["type": "data", "id": id, "data": FlutterStandardTypedData(bytes: Data(buffer[0..<n]))])
    } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
      // Unplugged (or the device went away): the port is gone.
      let reason = n == 0 ? "The board was unplugged." : String(cString: strerror(errno))
      close(id)
      send(["type": "closed", "id": id, "reason": reason])
    }
  }

  private func write(_ id: Int, _ data: Data) -> Any {
    guard let port = ports[id] else { return FlutterError(code: "closed", message: "The port is closed.", details: nil) }
    let bytes = [UInt8](data)
    var off = 0
    while off < bytes.count {
      let n = bytes.withUnsafeBufferPointer { Darwin.write(port.fd, $0.baseAddress! + off, bytes.count - off) }
      if n > 0 {
        off += n
      } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
        usleep(1000)  // the driver's buffer is full: wait for it to drain
      } else {
        return SerialPorts.error("write", "")
      }
    }
    return true
  }

  /// DTR and RTS together (an ESP32's auto-reset needs both changed at once). nil leaves a line as it is.
  private func signals(_ id: Int, dtr: Bool?, rts: Bool?) -> Any {
    guard let port = ports[id] else { return FlutterError(code: "closed", message: "The port is closed.", details: nil) }
    var bits: Int32 = 0
    _ = withUnsafeMutablePointer(to: &bits) { ioctl(port.fd, SerialPorts.tiocmget, $0) }
    if let dtr { bits = dtr ? bits | SerialPorts.dtrBit : bits & ~SerialPorts.dtrBit }
    if let rts { bits = rts ? bits | SerialPorts.rtsBit : bits & ~SerialPorts.rtsBit }
    let r = withUnsafeMutablePointer(to: &bits) { ioctl(port.fd, SerialPorts.tiocmset, $0) }
    return r == 0 ? true : SerialPorts.error("signals", "")
  }

  private static func setSpeed(_ fd: Int32, _ baud: Int) -> Bool {
    var speed = speed_t(baud)
    return withUnsafeMutablePointer(to: &speed) { ioctl(fd, iossiospeed, $0) } == 0
  }

  private func close(_ id: Int) {
    guard let port = ports.removeValue(forKey: id) else { return }
    port.source.cancel()  // closes the file descriptor
  }

  private static func error(_ code: String, _ path: String) -> FlutterError {
    let e = errno
    var message = String(cString: strerror(e))
    if e == EBUSY { message = "\(path) is in use by another app (the Arduino IDE or a serial monitor?)." }
    return FlutterError(code: code, message: message, details: Int(e))
  }

  // MARK: - Plug and unplug

  private func watchDevices() {
    guard let np = IONotificationPortCreate(kIOMainPortDefault) else { return }
    notifications = np
    IONotificationPortSetDispatchQueue(np, DispatchQueue.main)
    let context = Unmanaged.passUnretained(self).toOpaque()
    let callback: IOServiceMatchingCallback = { context, iterator in
      SerialPorts.drain(iterator)
      Unmanaged<SerialPorts>.fromOpaque(context!).takeUnretainedValue().send(["type": "devices"])
    }
    for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
      var iterator: io_iterator_t = 0
      IOServiceAddMatchingNotification(np, kind, IOServiceMatching(kIOSerialBSDServiceValue), callback, context, &iterator)
      SerialPorts.drain(iterator)  // arms the notification
      iterators.append(iterator)
    }
  }

  private static func drain(_ iterator: io_iterator_t) {
    while case let o = IOIteratorNext(iterator), o != 0 { IOObjectRelease(o) }
  }
}
