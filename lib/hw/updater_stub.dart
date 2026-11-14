/// No in-app updater on this platform.
const bool kCanSelfUpdate = false;

Future<String?> downloadUpdate(String version, void Function(int got, int total) onProgress, {bool Function()? cancelled}) async => null;

Future<void> installUpdate(String installer) async {}
