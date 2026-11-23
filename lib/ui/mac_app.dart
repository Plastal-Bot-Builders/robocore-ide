// The macOS app's menu bar and notifications (macos/Runner/MenuBar.swift and Notifications.swift). Elsewhere
// (web, the other native apps, tests) none of this runs.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get isMacApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

const _menu = MethodChannel('robocore/menu');
const _notify = MethodChannel('robocore/notify');
const _window = MethodChannel('robocore/window');

// The window's title bar is the app's own top bar (MainFlutterWindow.swift): macOS's close, minimise and zoom buttons
// sit at the left of the yellow bar, as in Figma or ChatGPT.

/// The top bar's height in the Mac app: AppKit's unified toolbar height, which the window's buttons are centred on.
const kMacBarHeight = 52.0;

/// Where the top bar's content starts in the Mac app: right of the window's buttons (they end 79 pt in), plus a gap.
const kMacButtonsInset = 92.0;

/// True while the window is full screen, where macOS hides its buttons (the bar's content goes back to the left edge).
final macFullScreen = ValueNotifier<bool>(false);

/// Listens for the window going full screen and back.
void attachWindowChrome() {
  if (!isMacApp) return;
  _window.setMethodCallHandler((call) async {
    if (call.method == 'fullScreen') macFullScreen.value = call.arguments == true;
  });
  _window.invokeMapMethod<String, Object?>('state').then((m) {
    macFullScreen.value = m?['fullScreen'] == true;
  }, onError: (Object _) {});
}

bool _overEmptyBar = false;

/// Tells the window whether the pointer is over an empty part of the top bar, where a press moves the window and a
/// double-click zooms it, as on a title bar.
void setMacDragArea(bool on) {
  if (!isMacApp || on == _overEmptyBar) return;
  _overEmptyBar = on;
  _window.invokeMethod<void>('dragArea', on).catchError((Object _) {});
}

/// The editor's part of the menu bar (Undo, Find, Zoom …), set while the editor is built.
void Function(String id)? editorMenuCommand;

/// [onCommand] gets the id of every menu command the user picks (see MenuBar.swift).
void attachMenuBar(void Function(String id) onCommand) {
  if (!isMacApp) return;
  _menu.setMethodCallHandler((call) async {
    if (call.method == 'command') onCommand(call.arguments as String);
  });
}

String? _sent;

/// Which commands can run now and which toggles are on; the menu greys out and ticks its items from this.
void updateMenuBar({required Set<String> enabled, required Set<String> checked}) {
  if (!isMacApp) return;
  final e = enabled.toList()..sort();
  final c = checked.toList()..sort();
  final key = '$e$c';
  if (key == _sent) return;
  _sent = key;
  _menu.invokeMethod<void>('update', {'enabled': e, 'checked': c}).catchError((Object _) {});
}

/// Shows a message as a macOS notification. False when macOS won't show it (the user said no), so the
/// app shows its own toast instead.
Future<bool> showMacNotification(String title, String? body, bool error) async {
  try {
    return await _notify.invokeMethod<bool>('show', {'title': title, 'body': body ?? '', 'error': error}) ?? false;
  } catch (_) {
    return false;
  }
}
