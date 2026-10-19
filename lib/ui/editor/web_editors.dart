// Blockly and Monaco editors. In the web app they run in web/robocore_editors.html; the native
// apps keep the Flutter BlocksView and CodeView for now (kWebEditors is false there).
export 'web_editors_stub.dart' if (dart.library.js_interop) 'web_editors_web.dart';
