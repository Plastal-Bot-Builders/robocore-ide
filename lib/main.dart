import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;

import 'hw/local_compiler.dart';
import 'hw/sketchbook.dart';
import 'licences.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/app_scope.dart';
import 'ui/editor/web_editors.dart' show EditorFramesObserver, initWebEditors;
import 'ui/mac_app.dart';
import 'ui/shell.dart';
import 'ui/splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // In a browser Flutter builds its tree for screen readers only after a hidden "Enable accessibility" button is
  // found and pressed; build it from the start instead.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  // The desktop apps compile on this computer when they can (arduino-cli).
  final state = AppState()..local = localBuilder();
  registerLicences(state.local);
  // The window opens on the launch animation straight away; projects and settings load behind it.
  Future<void> load() async {
    if (projectsFolderSupported) {
      // The Mac app keeps the projects as files in a folder the user picks (Settings → Projects folder).
      state.chooseFolder = chooseProjectsFolder;
      state.folderAt = projectsFolderAt;
      state.folder = await restoreProjectsFolder();
    }
    await state.load();
    await initWebEditors();
    // The Mac app's messages go to Notification Centre.
    if (isMacApp) state.systemToast = showMacNotification;
  }

  runApp(LaunchApp(state: state, ready: load()));
}

/// The launch animation over the app: the app appears under it once [ready] completes, and the animation
/// fades out to show it.
class LaunchApp extends StatefulWidget {
  const LaunchApp({super.key, required this.state, required this.ready});
  final AppState state;
  final Future<void> ready;

  @override
  State<LaunchApp> createState() => _LaunchAppState();
}

class _LaunchAppState extends State<LaunchApp> {
  bool _loaded = false, _splash = true;

  @override
  void initState() {
    super.initState();
    // A failed load still opens the app (AppState starts from defaults), rather than leaving the splash up.
    widget.ready.catchError((Object e) => debugPrint('RoboCore did not load everything: $e')).whenComplete(() {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(fit: StackFit.expand, children: [
          if (_loaded) RoboCoreApp(key: const ValueKey('app'), state: widget.state),
          if (_splash) Splash(key: const ValueKey('splash'), ready: _loaded, onDone: () => setState(() => _splash = false)),
        ]),
      );
}

final _paperTheme = buildTheme(RC.paper);
final _navyTheme = buildTheme(RC.navy);
// One for the app's life: the app rebuilds MaterialApp on every change.
final _framesObserver = EditorFramesObserver();

class RoboCoreApp extends StatelessWidget {
  const RoboCoreApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return MaterialApp(
            title: 'RoboCore',
            debugShowCheckedModeBanner: false,
            theme: state.settings.theme == 'navy' ? _navyTheme : _paperTheme,
            navigatorObservers: [_framesObserver],
            // The launch animation covers the start-up, so the app opens straight on Home (or Welcome).
            home: const Shell(),
          );
        },
      ),
    );
  }
}
