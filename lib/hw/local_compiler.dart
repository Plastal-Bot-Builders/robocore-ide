// Compiling on this computer (the macOS and Windows apps); null elsewhere, where the compile server builds.
export 'local_compiler_stub.dart' if (dart.library.io) 'local_compiler_native.dart';
