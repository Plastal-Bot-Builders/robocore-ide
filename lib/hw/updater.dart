// One-click updates for the Windows app: download the new installer, check it against the release's checksum, then
// run it silently and quit; the installer puts the new version in place and opens RoboCore again
// (windows/installer/robocore.iss). Elsewhere (web, macOS, Android, Linux) there is no in-app updater: the update
// banner opens the release page instead.
export 'updater_stub.dart' if (dart.library.io) 'updater_io.dart';
