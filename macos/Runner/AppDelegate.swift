import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // FlutterAppDelegate has no applicationDidFinishLaunching of its own, so no super call here.
  override func applicationDidFinishLaunching(_ notification: Notification) {
    MenuBar.shared.install()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
