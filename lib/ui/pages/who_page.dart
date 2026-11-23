// "Who's coding today?": on a computer several people share, each has their own name, projects and settings. It
// shows at start when more than one person uses this computer, and from the account menu's Switch person.
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

const _avatarColours = [kNavy, Color(0xFF2F6BBF), Color(0xFFB84A26), Color(0xFF0F7680), Color(0xFF7A4FB5), Color(0xFF2F7A4C)];

class WhoPage extends StatelessWidget {
  const WhoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final phone = MediaQuery.sizeOf(context).width < 760;

    Widget tile({required Widget avatar, required String title, String? sub, required VoidCallback onTap, bool current = false, bool dashed = false}) =>
        Hover(
          onTap: onTap,
          radius: 14,
          builder: (context, h) => Container(
            height: 84,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: dashed ? Colors.transparent : (h ? c.sunk : c.raised),
              border: Border.all(color: current ? c.ink : (dashed ? c.muted : c.line), width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              avatar,
              const SizedBox(width: 14),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: tBody(c, size: 18, w: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  if (sub != null && sub.isNotEmpty) Text(sub, style: tCaption(c), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        );

    Widget circle(Color bg, Widget child) => Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: child,
        );

    String initial(Person p) => p.name.trim().isEmpty ? '?' : String.fromCharCode(p.name.trim().runes.first).toUpperCase();

    final tiles = <Widget>[
      for (final (i, p) in s.people.indexed)
        tile(
          avatar: circle(_avatarColours[i % _avatarColours.length],
              Text(initial(p), style: const TextStyle(fontFamily: fBody, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
          title: p.name.trim().isEmpty ? 'No name' : p.name,
          sub: p.school,
          current: p.id == s.personId && s.welcomed,
          onTap: () => s.switchPerson(p.id),
        ),
      tile(
        avatar: circle(kBrand, const RcIcon('plus', size: 22, color: kNavy)),
        title: 'I’m new here',
        dashed: true,
        onTap: () => s.switchPerson(null),
      ),
    ];

    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(phone ? 20 : 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('WHO’S CODING TODAY?',
                  style: TextStyle(fontFamily: fDisplay, fontSize: phone ? 32 : 46, height: 1, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 22),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: phone ? 1 : 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 84,
                ),
                children: tiles,
              ),
              const SizedBox(height: 18),
              Text('Each person has their own name and projects on this computer.', style: tBody(c, size: 15, color: c.muted)),
              if (s.welcomed) ...[
                const SizedBox(height: 18),
                Align(alignment: Alignment.centerLeft, child: Btn('Back', icon: 'undo', onTap: s.keepPerson)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
