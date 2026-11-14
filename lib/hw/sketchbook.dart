// The desktop apps' projects folder (lib/state/project_folder.dart): picked once, then the projects are files there;
// and Open from computer.
// The web app keeps its projects in the browser; there these all answer null.
export 'sketchbook_stub.dart' if (dart.library.io) 'sketchbook_native.dart';
