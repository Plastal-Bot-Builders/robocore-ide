import Cocoa
import FlutterMacOS
import UserNotifications

/// The app's messages ("Saved", "Upload complete", errors) as macOS notifications instead of toasts inside the
/// window ("robocore/notify" channel, lib/ui/mac_app.dart). macOS asks the user once (at the first message);
/// until they allow it, "show" answers false and the app shows its own toast.
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
  static let shared = Notifications()

  func attach(to messenger: FlutterBinaryMessenger) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    let channel = FlutterMethodChannel(name: "robocore/notify", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "show", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      let content = UNMutableNotificationContent()
      content.title = args["title"] as? String ?? ""
      content.body = args["body"] as? String ?? ""
      content.threadIdentifier = "robocore"
      if args["error"] as? Bool == true { content.sound = .default }
      center.getNotificationSettings { settings in
        switch settings.authorizationStatus {
        case .authorized, .provisional:
          let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
          center.add(request) { error in
            DispatchQueue.main.async { result(error == nil) }
          }
        case .notDetermined:
          // The first message: macOS asks the user now, and this one shows in the window meanwhile.
          center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
          DispatchQueue.main.async { result(false) }
        default:
          DispatchQueue.main.async { result(false) }
        }
      }
    }
  }

  /// Shown while RoboCore is the app in front too (macOS hides them then unless asked).
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  /// A click on a notification brings the window forward.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first?.makeKeyAndOrderFront(nil)
    completionHandler()
  }
}
