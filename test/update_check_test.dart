// "A new version is out": comparing versions, reading GitHub's latest release, and the notice in the app.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:robocore_ide/hw/update_check.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('versions compare part by part, and anything else is never newer', () {
    expect(isNewerVersion('1.0.2', '1.0.1'), isTrue);
    expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
    expect(isNewerVersion('1.0.10', '1.0.9'), isTrue);
    expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.1', '1.0.1'), isFalse);
    expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    expect(isNewerVersion('1.0.2+5', '1.0.1'), isTrue);
    expect(isNewerVersion('nightly', '1.0.1'), isFalse);
    expect(isNewerVersion('1.0', '1.0.1'), isFalse);
  });

  test('the latest release is read from GitHub without its "v"', () async {
    final client = MockClient((r) async {
      expect(r.url.path, '/repos/$kReleasesRepo/releases/latest');
      return http.Response(
          jsonEncode({'tag_name': 'v1.0.2', 'html_url': 'https://github.com/$kReleasesRepo/releases/tag/v1.0.2', 'draft': false}), 200);
    });
    final r = await fetchLatestRelease(client: client);
    expect(r?.version, '1.0.2');
    expect(r?.url, 'https://github.com/$kReleasesRepo/releases/tag/v1.0.2');
  });

  test('offline, rate-limited or odd answers give no update', () async {
    expect(await fetchLatestRelease(client: MockClient((_) async => http.Response('limit', 403))), isNull);
    expect(await fetchLatestRelease(client: MockClient((_) async => throw http.ClientException('offline'))), isNull);
    expect(await fetchLatestRelease(client: MockClient((_) async => http.Response('not json', 200))), isNull);
    expect(await fetchLatestRelease(client: MockClient((_) async => http.Response(jsonEncode({'tag_name': 'latest'}), 200))), isNull);
    // A link that isn't GitHub's falls back to the releases page.
    final r = await fetchLatestRelease(
        client: MockClient((_) async => http.Response(jsonEncode({'tag_name': 'v9.0.0', 'html_url': 'https://example.com/x'}), 200)));
    expect(r?.url, kReleasesPage);
  });

  test('a newer release shows the update banner and stays in the status bar; the same version shows nothing', () async {
    final s = AppState();
    await s.checkForUpdate('1.0.1', () async => (version: '1.0.1', url: kReleasesPage));
    expect(s.updateVersion, isNull);
    expect(s.toast, isNull);

    await s.checkForUpdate('1.0.1', () async => null);
    expect(s.updateVersion, isNull);

    await s.checkForUpdate('1.0.1', () async => (version: '1.0.2', url: 'https://github.com/$kReleasesRepo/releases/tag/v1.0.2'));
    expect(s.updateVersion, '1.0.2');
    expect(s.updateUrl, endsWith('/v1.0.2'));
    expect(s.updateDismissed, isFalse, reason: 'the banner shows');
    expect(s.appVersion, '1.0.1');

    String? opened;
    s.openUrl = (url) async {
      opened = url;
      return true;
    };
    await s.openUpdate();
    expect(opened, s.updateUrl);
    s.closeToast();
  });

  test('Update now: where the app cannot update itself it opens the release page', () async {
    final s = AppState();
    await s.checkForUpdate('1.0.5', () async => (version: '1.0.6', url: 'https://github.com/$kReleasesRepo/releases/tag/v1.0.6'));
    String? opened;
    s.openUrl = (url) async {
      opened = url;
      return true;
    };
    await s.updateNow();
    expect(opened, endsWith('/v1.0.6'));
    expect(s.updatePhase, '');
  });

  test('Update now downloads, then Restart and update runs the installer; Later hides the banner', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await s.load();
    s.sim.stop();
    await s.checkForUpdate('1.0.5', () async => (version: '1.0.6', url: kReleasesPage));
    s.dismissUpdate();
    expect(s.updateDismissed, isTrue);
    s.showUpdate();
    expect(s.updateDismissed, isFalse);

    final seen = <double?>[];
    s.downloadUpdate = (v, onProgress, {cancelled}) async {
      expect(v, '1.0.6');
      onProgress(5, 10);
      seen.add(s.updateProgress);
      onProgress(10, 10);
      return r'C:\Temp\RoboCore-Setup-1.0.6.exe';
    };
    String? ran;
    s.installUpdate = (path) async => ran = path;
    await s.updateNow();
    expect(seen, [0.5]);
    expect(s.updatePhase, 'ready');
    await s.restartAndUpdate();
    expect(ran, endsWith('RoboCore-Setup-1.0.6.exe'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rc-updating-to'), '1.0.6');

    // The next start, on 1.0.6: "You're up to date" once.
    s.checkJustUpdated('1.0.6');
    expect(s.justUpdated, '1.0.6');
    expect(prefs.getString('rc-updating-to'), isNull);
  });

  test('a failed download says so and can be tried again', () async {
    final s = AppState();
    await s.checkForUpdate('1.0.5', () async => (version: '1.0.6', url: kReleasesPage));
    s.downloadUpdate = (v, onProgress, {cancelled}) async => null;
    await s.updateNow();
    expect(s.updatePhase, 'failed');
  });
}
