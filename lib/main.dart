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
import 'ui/widgets/ui_scale.dart';
import 'ui/splash.dart';
import 'ui/widgets/logo_intro.dart';

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

  void _splashDone() => setState(() => _splash = false);

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(fit: StackFit.expand, children: [
          if (_loaded) RoboCoreApp(key: const ValueKey('app'), state: widget.state),
          // The Mac app opens with its icon's gear ring spinning round the planet; the others with the splash.
          if (_splash)
            isMacApp
                ? MacIntro(key: const ValueKey('splash'), state: widget.state, ready: _loaded, onDone: _splashDone)
                : Splash(key: const ValueKey('splash'), ready: _loaded, onDone: _splashDone),
        ]),
      );
}

/// The Mac app's launch: the app icon's gear ring spins round the planet and settles (ui/widgets/logo_intro.dart)
/// while the app loads behind it, then fades into the app as the splash does. If the projects take longer,
/// "Opening your projects…" shows under the still icon until they are read.
class MacIntro extends StatefulWidget {
  const MacIntro({super.key, required this.state, required this.ready, required this.onDone});
  final AppState state;

  /// True once the app has loaded; the intro leaves after its animation and this.
  final bool ready;

  /// Called when the intro has faded out.
  final VoidCallback onDone;

  @override
  State<MacIntro> createState() => _MacIntroState();
}

class _MacIntroState extends State<MacIntro> with SingleTickerProviderStateMixin {
  late final _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  bool _played = false;

  /// Fades out once the animation has played and the app is ready.
  void _next() {
    if (_played && widget.ready && !_exit.isAnimating && !_exit.isCompleted) _exit.forward();
  }

  @override
  void didUpdateWidget(MacIntro oldWidget) {
    super.didUpdateWidget(oldWidget);
    _next();
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        // The settings are read during the intro: from then on it is on the user's theme (Paper or Navy).
        animation: Listenable.merge([widget.state, _exit]),
        builder: (context, _) {
          final c = widget.state.settings.theme == 'navy' ? RC.navy : RC.paper;
          return IgnorePointer(
            ignoring: _exit.isAnimating,
            child: Opacity(
              opacity: 1 - Curves.easeIn.transform(_exit.value),
              child: ColoredBox(
                color: c.bg,
                child: LogoIntro(
                  size: 96,
                  // Kept in the layout so the icon never moves; seen only while the projects are still being read.
                  caption: Opacity(
                    opacity: widget.ready ? 0 : 1,
                    child: Text('Opening your projects…', style: tLabel(c, color: c.muted)),
                  ),
                  onDone: () {
                    _played = true;
                    _next();
                  },
                ),
              ),
            ),
          );
        },
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
            // The display size (Settings → Appearance): dialogs, menus and tooltips grow with the rest.
            builder: (context, child) => UiScale(setting: state.settings.uiScale, child: child!),
            // The launch animation covers the start-up, so the app opens straight on Home (or Welcome).
            home: const Shell(),
          );
        },
      ),
    );
  }
}
