// Blockly and Monaco editors. In the web app they run in web/robocore_editors.html inside an iframe; in the
// Windows app the same page runs in a WebView2. Elsewhere the app keeps the Flutter BlocksView and CodeView
// (kWebEditors is false there).
export 'web_editors_stub.dart'
    if (dart.library.js_interop) 'web_editors_web.dart'
    if (dart.library.io) 'web_editors_native.dart';
