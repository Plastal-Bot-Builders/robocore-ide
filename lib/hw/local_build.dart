// Real compiles without a compile server: arduino-cli on this computer in the Windows app (local_build_io.dart).
export 'local_build_stub.dart' if (dart.library.io) 'local_build_io.dart';
