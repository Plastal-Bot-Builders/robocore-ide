import Cocoa
import FlutterMacOS

/// The menu bar: RoboCore, File, Edit, Sketch, Tools, View, Window and Help, like other Mac IDEs. The app's own
/// commands go to Flutter on the "robocore/menu" channel (lib/ui/mac_app.dart), which also says which ones can
/// run now and which toggles are on. Cut, Copy, Paste and Select All go to whatever has the keyboard (a Flutter
/// text field, Blockly or Monaco), as in any Mac app.
final class MenuBar: NSObject, NSMenuItemValidation {
  static let shared = MenuBar()

  private var channel: FlutterMethodChannel?
  private var enabled: Set<String> = []
  private var checked: Set<String> = []

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "robocore/menu", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.enabled = Set(args["enabled"] as? [String] ?? [])
      self?.checked = Set(args["checked"] as? [String] ?? [])
      result(nil)
    }
    self.channel = channel
  }

  func install() {
    let main = NSMenu()
    main.addItem(submenu(appMenu()))
    main.addItem(submenu(fileMenu()))
    main.addItem(submenu(editMenu()))
    main.addItem(submenu(sketchMenu()))
    main.addItem(submenu(toolsMenu()))
    main.addItem(submenu(viewMenu()))
    let window = windowMenu()
    main.addItem(submenu(window))
    let help = helpMenu()
    main.addItem(submenu(help))
    NSApp.mainMenu = main
    NSApp.windowsMenu = window  // macOS adds its Move & Resize and Fill / Centre items here
    NSApp.helpMenu = help  // and the Help search field here
  }

  // MARK: - Menus

  private func appMenu() -> NSMenu {
    let m = NSMenu(title: "RoboCore")
    m.addItem(command("About RoboCore IDE", "about"))
    m.addItem(.separator())
    m.addItem(command("Settings…", "settings", key: ","))
    m.addItem(.separator())
    let services = NSMenu(title: "Services")
    NSApp.servicesMenu = services
    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    servicesItem.submenu = services
    m.addItem(servicesItem)
    m.addItem(.separator())
    m.addItem(system("Hide RoboCore", #selector(NSApplication.hide(_:)), key: "h"))
    m.addItem(system("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", [.command, .option]))
    m.addItem(system("Show All", #selector(NSApplication.unhideAllApplications(_:))))
    m.addItem(.separator())
    m.addItem(system("Quit RoboCore", #selector(NSApplication.terminate(_:)), key: "q"))
    return m
  }

  private func fileMenu() -> NSMenu {
    let m = NSMenu(title: "File")
    m.addItem(command("New Project…", "newProject", key: "n"))
    m.addItem(command("Open Sketch…", "openSketch", key: "o"))
    m.addItem(command("Projects…", "openProject", key: "o", [.command, .shift]))
    m.addItem(command("Examples", "examples"))
    m.addItem(.separator())
    m.addItem(command("Save", "save", key: "s"))
    m.addItem(command("Show in Finder", "reveal", key: "r", [.command, .option]))
    m.addItem(command("Rename Project…", "rename"))
    m.addItem(command("Duplicate Project", "duplicate"))
    m.addItem(command("Project Settings…", "projectSettings"))
    m.addItem(.separator())
    m.addItem(system("Close Window", #selector(NSWindow.performClose(_:)), key: "w"))
    return m
  }

  private func editMenu() -> NSMenu {
    let m = NSMenu(title: "Edit")
    m.addItem(command("Undo", "undo", key: "z"))
    m.addItem(command("Redo", "redo", key: "z", [.command, .shift]))
    m.addItem(.separator())
    m.addItem(system("Cut", #selector(NSText.cut(_:)), key: "x"))
    m.addItem(system("Copy", #selector(NSText.copy(_:)), key: "c"))
    m.addItem(system("Paste", #selector(NSText.paste(_:)), key: "v"))
    m.addItem(system("Select All", #selector(NSText.selectAll(_:)), key: "a"))
    m.addItem(.separator())
    m.addItem(command("Comment / Uncomment", "comment", key: "/"))
    m.addItem(command("Increase Indent", "indent", key: "]"))
    m.addItem(command("Decrease Indent", "outdent", key: "["))
    m.addItem(.separator())
    m.addItem(command("Find…", "find", key: "f"))
    m.addItem(command("Go to Line…", "goToLine", key: "l"))
    return m
  }

  private func sketchMenu() -> NSMenu {
    let m = NSMenu(title: "Sketch")
    m.addItem(command("Verify", "verify", key: "r"))
    m.addItem(command("Upload", "upload", key: "u"))
    m.addItem(command("Stop", "stop", key: "."))
    m.addItem(.separator())
    m.addItem(command("Ask Cog", "cog", key: "i"))
    m.addItem(.separator())
    m.addItem(command("Include Library…", "libraries"))
    return m
  }

  private func toolsMenu() -> NSMenu {
    let m = NSMenu(title: "Tools")
    m.addItem(command("Board Setup…", "board", key: "b", [.command, .shift]))
    m.addItem(command("Serial Monitor", "serial", key: "m", [.command, .shift]))
    m.addItem(.separator())
    m.addItem(command("Libraries", "libraries", key: "i", [.command, .shift]))
    m.addItem(command("Examples", "examples", key: "e", [.command, .shift]))
    return m
  }

  private func viewMenu() -> NSMenu {
    let m = NSMenu(title: "View")
    m.addItem(command("Blocks", "modeBlocks", key: "1"))
    m.addItem(command("Code", "modeCode", key: "2"))
    m.addItem(.separator())
    m.addItem(command("Sidebar", "sidebar", key: "b"))
    m.addItem(command("Console", "console", key: "j"))
    m.addItem(command("C++ from the Blocks", "cppPane", key: "k"))
    m.addItem(.separator())
    m.addItem(command("Zoom In", "zoomIn", key: "="))
    m.addItem(command("Zoom Out", "zoomOut", key: "-"))
    m.addItem(command("Actual Size", "zoomReset", key: "0"))
    m.addItem(.separator())
    m.addItem(system("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", [.command, .control]))
    return m
  }

  private func windowMenu() -> NSMenu {
    let m = NSMenu(title: "Window")
    m.addItem(system("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
    m.addItem(system("Zoom", #selector(NSWindow.performZoom(_:))))
    m.addItem(.separator())
    m.addItem(system("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
    return m
  }

  private func helpMenu() -> NSMenu {
    let m = NSMenu(title: "Help")
    m.addItem(link("RoboCore IDE Help", "https://www.plastalbotbuilders.com/robocore/ide"))
    m.addItem(command("Keyboard Shortcuts", "shortcuts"))
    m.addItem(.separator())
    m.addItem(link("Arduino Language Reference", "https://docs.arduino.cc/language-reference/"))
    m.addItem(.separator())
    m.addItem(link("Report a Problem…", "https://github.com/Plastal-Bot-Builders/robocore-ide/issues"))
    return m
  }

  // MARK: - Items

  private func submenu(_ menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  /// An app command: sent to Flutter, which knows what it does on the current screen.
  private func command(
    _ title: String, _ id: String, key: String = "", _ mods: NSEvent.ModifierFlags = .command
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: key)
    item.keyEquivalentModifierMask = mods
    item.target = self
    item.representedObject = id
    return item
  }

  /// A standard Mac action, sent to whatever has the keyboard (or the window, or the app).
  private func system(
    _ title: String, _ action: Selector, key: String = "", _ mods: NSEvent.ModifierFlags = .command
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = mods
    return item
  }

  private func link(_ title: String, _ url: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(open(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = url
    return item
  }

  @objc private func run(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    channel?.invokeMethod("command", arguments: id)
  }

  @objc private func open(_ sender: NSMenuItem) {
    if let s = sender.representedObject as? String, let url = URL(string: s) {
      NSWorkspace.shared.open(url)
    }
  }

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard item.action == #selector(run(_:)), let id = item.representedObject as? String else { return true }
    item.state = checked.contains(id) ? .on : .off
    return enabled.contains(id)
  }
}
