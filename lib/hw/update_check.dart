// "A new version is out": the desktop and Android apps ask GitHub, once when they start, for the latest release.
// The web app needs no check (it is always the latest), and any failure (offline, school proxy, GitHub's rate
// limit) is silent: the app works the same, it just doesn't mention an update.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The repository whose releases the apps come from.
const kReleasesRepo = 'Plastal-Bot-Builders/robocore-ide';

/// The page people download a release from.
const kReleasesPage = 'https://github.com/$kReleasesRepo/releases/latest';

/// The newest published release: its version without the "v" (1.0.2) and its page, or null when it can't be read.
Future<({String version, String url})?> fetchLatestRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(Uri.parse('https://api.github.com/repos/$kReleasesRepo/releases/latest'),
            headers: const {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    if (j is! Map || j['draft'] == true || j['prerelease'] == true) return null;
    final tag = '${j['tag_name'] ?? ''}'.trim();
    final v = tag.startsWith('v') ? tag.substring(1) : tag;
    if (parseVersion(v) == null) return null;
    final url = '${j['html_url'] ?? ''}';
    return (version: v, url: url.startsWith('https://github.com/') ? url : kReleasesPage);
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// 1.0.2 → [1, 0, 2]; anything else (a build number after "+" is ignored) → null.
List<int>? parseVersion(String v) {
  final parts = v.split('+').first.split('.');
  if (parts.length != 3) return null;
  final n = parts.map(int.tryParse).toList();
  return n.contains(null) ? null : n.cast<int>();
}

/// Whether [latest] is newer than [current] (both like 1.0.2).
bool isNewerVersion(String latest, String current) {
  final a = parseVersion(latest), b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
