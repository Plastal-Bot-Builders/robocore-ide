import 'dart:convert';
import 'dart:io';

import 'update_check.dart' show kReleasesRepo;

/// The Windows app updates itself (an Inno Setup installer that installs for the current user, so no admin prompt).
/// Not while the tests run.
bool get kCanSelfUpdate => Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST');

/// Downloads RoboCore-Setup-[version].exe from the release into a temporary folder, reporting progress, and checks
/// its SHA-256 against the one GitHub lists for the release's file. Returns its path, or null if it could not be
/// downloaded, was cancelled, or doesn't match.
Future<String?> downloadUpdate(String version, void Function(int got, int total) onProgress, {bool Function()? cancelled}) async {
  if (!kCanSelfUpdate) return null;
  final name = 'RoboCore-Setup-$version.exe';
  final client = HttpClient()..userAgent = 'RoboCore-updater';
  Directory? dir;
  try {
    // The release's file and its checksum.
    final meta = await (await client.getUrl(Uri.parse('https://api.github.com/repos/$kReleasesRepo/releases/tags/v$version'))
          ..headers.set('Accept', 'application/vnd.github+json'))
        .close();
    if (meta.statusCode != 200) return null;
    final j = jsonDecode(await meta.transform(utf8.decoder).join());
    final assets = (j is Map ? j['assets'] : null) as List? ?? const [];
    final asset = assets.whereType<Map>().where((a) => a['name'] == name).firstOrNull;
    if (asset == null) return null;
    final url = '${asset['browser_download_url'] ?? ''}';
    final digest = '${asset['digest'] ?? ''}'.toLowerCase();
    if (!url.startsWith('https://github.com/$kReleasesRepo/releases/download/')) return null;

    final res = await (await client.getUrl(Uri.parse(url))).close(); // follows GitHub's redirect to its file host
    if (res.statusCode != 200) return null;
    dir = await Directory.systemTemp.createTemp('robocore-update-');
    final file = File('${dir.path}\\$name');
    final sink = file.openWrite();
    final total = res.contentLength > 0 ? res.contentLength : ((asset['size'] as num?)?.toInt() ?? -1);
    var got = 0;
    try {
      await for (final chunk in res) {
        if (cancelled?.call() ?? false) return null;
        sink.add(chunk);
        got += chunk.length;
        onProgress(got, total);
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && got != total) return null;
    if (digest.startsWith('sha256:')) {
      final r = await Process.run('certutil', ['-hashfile', file.path, 'SHA256']);
      final m = RegExp(r'^([0-9a-fA-F ]{64,})$', multiLine: true).firstMatch('${r.stdout}');
      final sum = (m?.group(1) ?? '').replaceAll(' ', '').toLowerCase();
      if (sum != digest.substring(7)) return null;
    }
    final path = file.path;
    dir = null; // keep it: the installer runs from there
    return path;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Runs the installer silently for the current user and quits, so it can replace RoboCore.exe. The installer opens
/// the new version when it is done.
Future<void> installUpdate(String installer) async {
  await Process.start(installer, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached);
  exit(0);
}
