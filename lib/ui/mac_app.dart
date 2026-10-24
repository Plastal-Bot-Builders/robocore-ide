// The macOS app's menu bar and notifications (macos/Runner/MenuBar.swift and Notifications.swift). Elsewhere
// (web, the other native apps, tests) none of this runs.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get isMacApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

const _menu = MethodChannel('robocore/menu');
const _notify = MethodChannel('robocore/notify');

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
