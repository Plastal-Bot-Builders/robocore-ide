// Compiling on this computer (the macOS app); null elsewhere, where the compile server builds.
export 'local_compiler_stub.dart' if (dart.library.io) 'local_compiler_native.dart';
