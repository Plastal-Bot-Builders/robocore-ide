// Saving a file to the user's Downloads: the browser's download in the web app; native apps can't yet.
export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
