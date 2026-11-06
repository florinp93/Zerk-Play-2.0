import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../l10n/l10n.dart';
import '../../playback/sync/watch_together.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/setting_rows.dart';

class TogetherPage extends StatelessWidget {
  const TogetherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final together = AppServicesScope.of(context).together;
    return ListenableBuilder(
      listenable: together,
      builder: (context, _) {
        final l10n = context.l10n;
        final room = together.room;
        return Padding(
          padding: const EdgeInsets.only(left: contentLeft, top: 90, right: 120),
          child: FocusZone(
            debugLabel: 'together',
            child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
              Text(l10n.watchTogether, style: Zt.headline),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Text(room == null ? l10n.togetherIntro : l10n.togetherShare, style: Zt.body),
              ),
              const SizedBox(height: 40),
              if (room == null) ..._lobby(context, together) else ..._room(context, together, room),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _lobby(BuildContext context, WatchTogether together) {
    final l10n = context.l10n;
    final problem = together.problem;
    return [
      Row(children: [
        TvButton(
          label: l10n.togetherStart,
          icon: Icons.add_rounded,
          primary: true,
          onSelect: together.busy ? null : together.create,
        ),
        const SizedBox(width: 16),
        TvButton(
          label: l10n.togetherJoin,
          icon: Icons.login_rounded,
          onSelect: together.busy ? null : () => _join(context, together),
        ),
      ]),
      const SizedBox(height: 28),
      if (together.busy)
        Text(l10n.togetherConnecting, style: Zt.meta)
      else if (problem != null)
        Text(_problemText(l10n, problem), style: Zt.meta.copyWith(color: Zc.danger)),
    ];
  }

  Future<void> _join(BuildContext context, WatchTogether together) async {
    final l10n = context.l10n;
    final code = await showTextInputDialog(context,
        title: l10n.togetherCodeTitle, hint: l10n.togetherCodeHint, action: l10n.togetherJoin);
    if (code != null && code.trim().isNotEmpty) await together.join(code);
  }

  List<Widget> _room(BuildContext context, WatchTogether together, RoomState room) {
    final l10n = context.l10n;
    return [
      Text(l10n.togetherCodeTitle.toUpperCase(), style: Zt.caption.copyWith(letterSpacing: 2)),
      const SizedBox(height: 8),
      Text(room.code, style: Zt.display.copyWith(fontSize: 96, letterSpacing: 18, color: Zc.accentSoft)),
      if (room.itemTitle != null) ...[
        const SizedBox(height: 12),
        Text(l10n.togetherNowPlaying(room.itemTitle!), style: Zt.title),
      ],
      const SizedBox(height: 40),
      Text(l10n.togetherPeople, style: Zt.rowTitle),
      const SizedBox(height: 16),
      RoomMembers(together: together, room: room),
      const SizedBox(height: 32),
      Row(children: [
        TvButton(label: l10n.togetherLeave, icon: Icons.logout_rounded, onSelect: together.leave),
      ]),
    ];
  }

  static String _problemText(L10n l10n, TogetherProblem problem) => switch (problem) {
        TogetherProblem.unreachable => l10n.togetherUnreachable,
        TogetherProblem.signedOut => l10n.togetherSignedOut,
        TogetherProblem.noRoom => l10n.togetherNoRoom,
        TogetherProblem.roomFull => l10n.togetherRoomFull,
      };
}
