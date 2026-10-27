// First start on a device: asks who is using the app, so the IDE greets them by name.
// The name stays on this device (with the projects); it can be changed in Settings → Profile.
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../app_scope.dart';
import '../dialogs.dart' show FieldLabel;
import '../widgets/brand.dart';
import '../widgets/common.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _name = TextEditingController();
  final _school = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    super.dispose();
  }

  void _start() {
    final s = AppScope.read(context);
    final e = s.validateProfileName(_name.text);
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    s.setProfile(name: _name.text, school: _school.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final phone = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: kBrand,
      body: Stack(children: [
        Positioned.fill(child: Image.asset('assets/images/contours.png', fit: BoxFit.cover, excludeFromSemantics: true)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: 440,
              padding: EdgeInsets.all(phone ? 20 : 32),
              decoration: BoxDecoration(
                color: c.raised,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(14),
                boxShadow: modalShadow,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Align(alignment: Alignment.centerLeft, child: AppIconTile()),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: ProductLockup(color: c.ink)),
                const SizedBox(height: 22),
                Text('WELCOME TO ROBOCORE', style: tH1(c)),
                const SizedBox(height: 6),
                Text('Build, code and upload sketches to your robot. First, who is using RoboCore on this computer?',
                    style: tBody(c, size: 14, color: c.muted, height: 20 / 14)),
                const SizedBox(height: 22),
                const FieldLabel('Your name'),
                RcInput(
                  controller: _name,
                  hint: 'Thandi Mokoena',
                  height: 38,
                  fontSize: 14,
                  autofocus: true,
                  error: _error != null,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _start(),
                ),
                if (_error != null) ...[const SizedBox(height: 6), Text(_error!, style: tCaption(c, color: c.err))],
                const SizedBox(height: 16),
                const FieldLabel('School or class (optional)'),
                RcInput(controller: _school, hint: 'Grade 7B', height: 38, fontSize: 14, onSubmitted: (_) => _start()),
                const SizedBox(height: 24),
                Btn('Get started', icon: 'arrow', kind: BtnKind.primary, height: 40, expand: true, onTap: _start),
                const SizedBox(height: 12),
                Text('Saved only on this device, with your projects. You can change it any time in Settings.',
                    style: tCaption(c), textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
