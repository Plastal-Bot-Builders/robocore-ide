// The Windows app's WebView for the Blockly and Monaco page: WebView2 (package:webview_windows) in place of the
// macOS app's WKWebView, speaking the same protocol (web_editors_native.dart): the app runs JavaScript in the page,
// and the page answers with JSON arrays on window.RoboCoreHost, which here posts them through chrome.webview.
//
// The WebView is drawn by Flutter (a texture), so menus, dialogs and dividers over it need none of the web app's
// iframe guards. A PC without the WebView2 runtime keeps the Flutter BlocksView and CodeView.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart';

/// Defines the channel robocore_editors.js looks for before the page's own scripts run.
const _host = 'window.RoboCoreHost = { postMessage: (m) => window.chrome.webview.postMessage(m) };';

/// True when the WebView2 runtime is installed (it comes with Windows 11 and Edge).
Future<bool> webView2Installed() async {
  try {
    return await WebviewController.getWebViewVersion() != null;
  } catch (_) {
    return false;
  }
}

class WindowsEditorPage {
  WindowsEditorPage(Future<Uri> url, this.onMessage) {
    unawaited(_start(url));
  }

  /// Every message from the page: a JSON array, [event, ...args].
  final void Function(String json) onMessage;
  final controller = WebviewController();

  Future<void> _start(Future<Uri> url) async {
    try {
      await controller.initialize();
      await controller.setBackgroundColor(const Color(0x00000000));
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.addScriptToExecuteOnDocumentCreated(_host);
      controller.webMessage.listen((m) {
        if (m is String) onMessage(m);
      });
      await controller.loadUrl((await url).toString());
    } catch (e) {
      debugPrint('RoboCore editor did not start: $e');
    }
  }

  void run(String js) {
    if (!controller.value.isInitialized) return;
    unawaited(controller.executeScript(js).catchError((Object e) {
      debugPrint('RoboCore editor: $e');
    }));
  }

  /// The WebView once it is up (it sizes the page, so it is in the window as soon as it can be).
  Widget view() => ValueListenableBuilder<WebviewValue>(
        valueListenable: controller,
        builder: (context, v, _) => v.isInitialized ? Webview(controller) : const SizedBox.expand(),
      );
}
