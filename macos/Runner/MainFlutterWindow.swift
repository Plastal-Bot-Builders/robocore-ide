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

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    MenuBar.shared.attach(to: messenger)
    Notifications.shared.attach(to: messenger)
    SerialPorts.shared.attach(to: messenger)
    Sketchbook.shared.attach(to: messenger)

    super.awakeFromNib()
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
