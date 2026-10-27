import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// The macOS app's projects folder: the user chooses it once, and a bookmark finds it again even after it is moved
/// or renamed. Flutter (lib/hw/sketchbook_native.dart) reads and writes the project files itself; it also knows the
/// folder's path, which it uses when there is no bookmark.
///
/// "robocore/sketchbook": restore → path or nil, choose → path or nil (a folder called RoboCore inside the one
/// picked), pickSketch → [path] or nil (File > Open Sketch…), reveal {path}, trash {path} → Bool, forget.
final class Sketchbook {
  static let shared = Sketchbook()

  private let bookmarkKey = "RoboCoreProjectsFolder"
  private var folder: URL?

  func attach(to messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "robocore/sketchbook", binaryMessenger: messenger).setMethodCallHandler {
      [weak self] call, result in
      guard let self else { return result(nil) }
      let path = (call.arguments as? [String: Any])?["path"] as? String
      switch call.method {
      case "restore":
        result(self.restore()?.path)
      case "choose":
        self.choose(result)
      case "pickSketch":
        self.pickSketch(result)
      case "reveal":
        if let path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        result(nil)
      case "trash":
        guard let path else { return result(false) }
        result((try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)) != nil)
      case "forget":
        self.stop()
        UserDefaults.standard.removeObject(forKey: self.bookmarkKey)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The folder chosen before, if it is still there. (A bookmark made while the app was sandboxed still resolves.)
  private func restore() -> URL? {
    if let folder { return folder }
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    else { return nil }
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return nil }
    if stale { remember(url) }  // moved or renamed: keep the new place
    folder = url
    return url
  }

  private func remember(_ url: URL) {
    if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
  }

  private func stop() {
    folder = nil
  }

  /// The user's own Documents folder.
  private var documents: URL {
    let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    return URL(fileURLWithPath: home).appendingPathComponent("Documents")
  }

  private func ask(_ panel: NSOpenPanel, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
    if let window = NSApp.keyWindow ?? NSApp.windows.first {
      panel.beginSheetModal(for: window, completionHandler: done)
    } else {
      done(panel.runModal())
    }
  }

  private func choose(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = documents
    panel.prompt = "Use This Folder"
    panel.message =
      "Where should RoboCore keep your projects? A folder called RoboCore is made inside the one you choose. Documents is a good place."
    ask(panel) { [weak self] response in
      guard let self, response == .OK, let picked = panel.url else { return result(nil) }
      let target = picked.lastPathComponent.lowercased() == "robocore" ? picked : picked.appendingPathComponent("RoboCore")
      do {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      } catch {
        return result(FlutterError(code: "folder", message: error.localizedDescription, details: nil))
      }
      self.stop()
      self.remember(target)
      result(self.restore()?.path ?? target.path)
    }
  }

  private func pickSketch(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType(filenameExtension: "ino") ?? .sourceCode]
    panel.directoryURL = documents
    panel.prompt = "Open"
    panel.message = "Open an Arduino sketch: its .ino file, or its folder to bring the other files too."
    ask(panel) { response in
      result(response == .OK ? panel.urls.map { $0.path } : nil)
    }
  }
}
