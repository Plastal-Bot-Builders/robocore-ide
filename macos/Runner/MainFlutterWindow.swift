import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    MainFlutterWindow.moveSettingsOutOfSandbox()
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Small enough for macOS's half- and quarter-screen tiling (Window > Move & Resize) on a 13-inch
    // MacBook; below 760 px wide the app takes its compact layout (the sidebar becomes a drawer).
    self.contentMinSize = NSSize(width: 640, height: 420)
    // The window comes back where it was and as big as it was. The first time: a comfortable IDE
    // size that fits the screen, centred.
    if !self.setFrameUsingName("RoboCoreMain") {
      let screen = (self.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
      self.setContentSize(NSSize(width: min(1280, screen.width * 0.9), height: min(800, screen.height * 0.9)))
      self.center()
    }
    self.setFrameAutosaveName("RoboCoreMain")
    self.drawTitleBarInTheApp()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    MenuBar.shared.attach(to: messenger)
    Notifications.shared.attach(to: messenger)
    SerialPorts.shared.attach(to: messenger)
    Sketchbook.shared.attach(to: messenger)
    self.attachTitleBar(to: messenger)

    super.awakeFromNib()
  }

  // MARK: The title bar is the app's own top bar

  /// The height of the app's top bar here (kMacBarHeight in lib/ui/mac_app.dart): AppKit's unified toolbar height,
  /// which the window's buttons are centred on.
  private static let barHeight: CGFloat = 52

  /// As in Figma or ChatGPT: no title bar of its own. The app is drawn up to the window's top edge, and macOS's close,
  /// minimise and zoom buttons sit at the left of the app's yellow top bar. The empty toolbar is only there to make the
  /// title bar 52 pt tall, so the buttons are centred on the bar; clicks anywhere else in it still reach the app.
  private func drawTitleBarInTheApp() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    titlebarSeparatorStyle = .none
    styleMask.insert(.fullSizeContentView)
    let bar = NSToolbar(identifier: "RoboCoreTitleBar")
    bar.allowsUserCustomization = false
    bar.displayMode = .iconOnly
    toolbar = bar
    toolbarStyle = .unified
  }

  private var titleBarChannel: FlutterMethodChannel?
  /// The pointer is over an empty part of the app's top bar (the app says so as the pointer moves): a press there
  /// moves the window and a double-click zooms it, as on a title bar. Flutter's view never moves the window by itself.
  private var overEmptyBar = false

  private func attachTitleBar(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "robocore/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "dragArea":
        self?.overEmptyBar = (call.arguments as? Bool) ?? false
        result(nil)
      case "state":
        let full = self?.styleMask.contains(.fullScreen) ?? false
        if full { self?.toolbar?.isVisible = false }  // macOS reopened the window in full screen
        result(["fullScreen": full])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    titleBarChannel = channel
    // Full screen hides the window's buttons, so the top bar's content moves back to the left edge. The empty toolbar
    // goes too: in full screen macOS shows a toolbar as a solid strip across the top, which covered the app's top bar.
    // Without it the title bar slides in over the app only when the pointer reaches the top of the screen.
    let center = NotificationCenter.default
    center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: self, queue: .main) { [weak self] _ in
      self?.toolbar?.isVisible = false
      self?.titleBarChannel?.invokeMethod("fullScreen", arguments: true)
    }
    center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: self, queue: .main) { [weak self] _ in
      self?.titleBarChannel?.invokeMethod("fullScreen", arguments: false)
    }
    center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: self, queue: .main) { [weak self] _ in
      self?.toolbar?.isVisible = true
    }
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown, overEmptyBar, !styleMask.contains(.fullScreen),
       frame.height - event.locationInWindow.y <= MainFlutterWindow.barHeight, !onWindowButton(event.locationInWindow) {
      if event.clickCount == 2 {
        doubleClickTitleBar()
      } else {
        if !isKeyWindow {
          if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
          makeKeyAndOrderFront(nil)
        }
        performDrag(with: event)
      }
      return
    }
    super.sendEvent(event)
  }

  /// Close, minimise and zoom keep their own clicks (the app can't see them, so it may think the pointer is over an
  /// empty part of the bar).
  private func onWindowButton(_ point: NSPoint) -> Bool {
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      if let b = standardWindowButton(kind), !b.isHidden, b.convert(b.bounds, to: nil).insetBy(dx: -4, dy: -4).contains(point) {
        return true
      }
    }
    return false
  }

  /// What System Settings › Desktop & Dock says a double-click on a title bar does: zoom (also for "Fill"), minimise,
  /// or nothing.
  private func doubleClickTitleBar() {
    let defaults = UserDefaults.standard
    switch defaults.string(forKey: "AppleActionOnDoubleClick") {
    case "Minimize": performMiniaturize(nil)
    case "None": break
    case nil where defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick"): performMiniaturize(nil)
    default: performZoom(nil)
    }
  }

  /// Until October 2026 the app ran in Apple's sandbox, which kept its settings (profile, the projects folder, the
  /// boards allowed on USB) in its container. Copied once to where they are now, before Flutter reads them.
  private static func moveSettingsOutOfSandbox() {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: "flutter.robocore-ide-v1") == nil, let id = Bundle.main.bundleIdentifier else { return }
    let old = "\(NSHomeDirectory())/Library/Containers/\(id)/Data/Library/Preferences/\(id).plist"
    guard let saved = NSDictionary(contentsOfFile: old) as? [String: Any] else { return }
    for (key, value) in saved { defaults.set(value, forKey: key) }
  }
}
