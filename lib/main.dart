import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'hw/local_compiler.dart';
import 'hw/sketchbook.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/app_scope.dart';
import 'ui/editor/web_editors.dart' show EditorFramesObserver;
import 'ui/mac_app.dart';
import 'ui/shell.dart';
import 'ui/widgets/logo_intro.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The Mac app compiles on this Mac when it can (arduino-cli inside the app).
  final state = AppState()
    ..local = localBuilder()
    ..loading = true;
  // The window first, so it never stays blank while the projects are read.
  runApp(RoboCoreApp(state: state));
  if (projectsFolderSupported) {
    // The Mac app keeps the projects as files in a folder the user picks (Settings → Projects folder).
    state.chooseFolder = chooseProjectsFolder;
    state.folderAt = projectsFolderAt;
    state.folder = await restoreProjectsFolder();
  }
  await state.load();
  // The Mac app's messages go to Notification Centre.
  if (isMacApp) state.systemToast = showMacNotification;
}

final _paperTheme = buildTheme(RC.paper);
final _navyTheme = buildTheme(RC.navy);
// One for the app's life: the app rebuilds MaterialApp on every change.
final _framesObserver = EditorFramesObserver();
// The Mac app opens with the logo animation (ui/widgets/logo_intro.dart); this turns true when it has played.
final _introDone = ValueNotifier<bool>(!isMacApp);

class RoboCoreApp extends StatelessWidget {
  const RoboCoreApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: Listenable.merge([state, _introDone]),
        builder: (context, _) {
          return MaterialApp(
            title: 'RoboCore',
            debugShowCheckedModeBanner: false,
            theme: state.settings.theme == 'navy' ? _navyTheme : _paperTheme,
            navigatorObservers: [_framesObserver],
            home: isMacApp
                ? _MacHome(opening: state.loading || !_introDone.value)
                : state.loading
                    ? const _Opening()
                    : const Shell(),
          );
        },
      ),
    );
  }
}

/// The Mac app: the opening screen (logo animation) until it has played and the projects are read, then the
/// app fades in.
class _MacHome extends StatelessWidget {
  const _MacHome({required this.opening});
  final bool opening;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
        child: opening ? const _Opening(key: ValueKey('opening'), intro: true) : const Shell(key: ValueKey('shell')),
      );
}

/// While the saved state is read at start-up. With [intro] (the Mac app) the logo animation plays first.
class _Opening extends StatelessWidget {
  const _Opening({super.key, this.intro = false});
  final bool intro;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final caption = Text('Opening your projects…', style: tLabel(c, color: c.muted));
    if (intro) {
      return Scaffold(
        backgroundColor: c.bg,
        body: LogoIntro(size: 96, caption: caption, onDone: () => _introDone.value = true),
      );
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SvgPicture.asset('assets/images/app_icon.svg', width: 72, height: 72),
          const SizedBox(height: 16),
          caption,
        ]),
      ),
    );
  }
}
