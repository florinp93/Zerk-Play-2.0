import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../l10n/l10n.dart';
import '../../playback/sync/watch_together.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'net_image.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.url, required this.name, this.size = 48, this.ring});

  final Uri? url;
  final String name;
  final double size;

  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final hue = (name.hashCode % 360).abs().toDouble();
    final fallback = Container(
      color: HSLColor.fromAHSL(1, hue, 0.45, 0.35).toColor(),
      alignment: Alignment.center,
      child: Text(letter, style: Zt.label.copyWith(fontSize: size * 0.45, fontWeight: FontWeight.w700)),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring == null ? null : Border.all(color: ring!, width: size * 0.06),
      ),
      child: ClipOval(child: NetImage(url: url, width: size, height: size, fallback: fallback)),
    );
  }
}

Uri? memberAvatar(AppServices s, RoomMember member) {
  final mine = s.profiles.profile;
  if (mine != null && member.userId == mine.id) return mine.avatarUrl;
  return s.profiles.avatarOf(member.userId);
}

class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.members, this.size = 36, this.max = 4, this.ring = Zc.surfaceHigh});

  final List<RoomMember> members;
  final double size;
  final int max;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final s = AppServicesScope.of(context);
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    final step = size * 0.62;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      width: count == 0 ? 0 : step * (count - 1) + size,
      height: size,
      child: Stack(children: [
        for (final (i, m) in shown.indexed)
          Positioned(left: i * step, child: UserAvatar(url: memberAvatar(s, m), name: m.name, size: size, ring: ring)),
        if (extra > 0)
          Positioned(
            left: shown.length * step,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Zc.surfaceTop, shape: BoxShape.circle, border: Border.all(color: ring, width: size * 0.06)),
              child: Text('+$extra', style: Zt.caption.copyWith(color: Colors.white, fontSize: size * 0.36)),
            ),
          ),
      ]),
    );
  }
}

class MyListButton extends StatelessWidget {
  const MyListButton({super.key, required this.item, this.collapsed = false});

  final Object item;

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final profiles = AppServicesScope.of(context).profiles;
    return ListenableBuilder(
      listenable: profiles,
      builder: (context, _) {
        if (!profiles.canList(item) || profiles.profile == null) return const SizedBox.shrink();
        final listed = profiles.inList(item);
        return TvButton(
          label: context.l10n.myList,
          icon: listed ? Icons.check_rounded : Icons.add_rounded,
          collapsed: collapsed,
          onSelect: () async {
            final l10n = context.l10n;
            try {
              await profiles.toggle(item);
              if (context.mounted) showToast(context, listed ? l10n.myListRemoved : l10n.myListAdded);
            } catch (e) {
              debugPrint('[my list] $e');
              UiSounds.play(UiSound.error);
              if (context.mounted) showToast(context, l10n.profileSaveFailed);
            }
          },
        );
      },
    );
  }
}

class TogetherButton extends StatefulWidget {
  const TogetherButton({super.key, this.collapsed = false});

  final bool collapsed;

  @override
  State<TogetherButton> createState() => _TogetherButtonState();
}

class _TogetherButtonState extends State<TogetherButton> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  void _focusChanged(bool focused) => focused ? _portal.show() : _portal.hide();

  Future<void> _select(WatchTogether together) async {
    if (together.room == null && !together.busy) unawaited(together.create());
    await showRoomDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final together = AppServicesScope.of(context).together;
    if (!together.available) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: together,
      builder: (context, _) {
        final room = together.room;
        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (context) => room == null
                ? const SizedBox.shrink()
                : CompositedTransformFollower(
                    link: _link,
                    targetAnchor: Alignment.topLeft,
                    followerAnchor: Alignment.bottomLeft,
                    offset: const Offset(0, -14),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: IgnorePointer(child: _MembersPopover(together: together, room: room)),
                    ),
                  ),
            child: TvFocusable(
              onSelect: () => _select(together),
              onFocusChange: _focusChanged,
              builder: (context, focused) {
                final bg = focused ? Colors.white : Colors.white.withValues(alpha: 0.12);
                final fg = focused ? Zc.background : Colors.white;
                if (widget.collapsed) {
                  return ExpandingPill(
                    focused: focused,
                    pad: room == null ? 17 : 12,
                    leading: room == null
                        ? Icon(Icons.groups_rounded, color: fg, size: 30)
                        : AvatarStack(members: room.members, size: 40, ring: focused ? Colors.white : const Color(0xFF34343F)),
                    label: Text(room == null ? context.l10n.togetherWatchWith : room.code,
                        style: Zt.label.copyWith(color: fg, fontSize: 22, letterSpacing: room == null ? null : 3)),
                  );
                }
                return AnimatedScale(
                  scale: focused ? 1.06 : 1,
                  duration: Zm.fast,
                  curve: Zm.curve,
                  child: AnimatedContainer(
                    duration: Zm.fast,
                    height: 64,
                    padding: EdgeInsets.only(left: room == null ? 30 : 14, right: 30),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: focused ? [BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 24)] : null,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (room == null)
                        Icon(Icons.groups_rounded, color: fg, size: 30)
                      else
                        AvatarStack(members: room.members, size: 40, ring: focused ? Colors.white : const Color(0xFF34343F)),
                      const SizedBox(width: 12),
                      Text(room == null ? context.l10n.togetherWatchWith : room.code,
                          style: Zt.label.copyWith(color: fg, fontSize: 22, letterSpacing: room == null ? null : 3)),
                    ]),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _MembersPopover extends StatelessWidget {
  const _MembersPopover({required this.together, required this.room});

  final WatchTogether together;
  final RoomState room;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Zc.surfaceTop,
      elevation: 16,
      borderRadius: BorderRadius.circular(Zs.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 28, 18),
        child: IntrinsicWidth(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.togetherPeople.toUpperCase(), style: Zt.caption.copyWith(letterSpacing: 2)),
            const SizedBox(height: 12),
            RoomMembers(together: together, room: room, size: 40, showStatus: false),
          ]),
        ),
      ),
    );
  }
}

class RoomMembers extends StatelessWidget {
  const RoomMembers({super.key, required this.together, required this.room, this.size = 52, this.showStatus = true});

  final WatchTogether together;
  final RoomState room;
  final double size;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final s = AppServicesScope.of(context);
    final l10n = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final m in room.members)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            UserAvatar(url: memberAvatar(s, m), name: m.name, size: size),
            const SizedBox(width: 16),
            Text(m.id == together.me ? l10n.togetherYou(m.name) : m.name,
                style: Zt.label.copyWith(fontSize: size > 44 ? 23 : 20)),
            if (m.device.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(m.device, style: Zt.caption),
            ],
            if (showStatus) ...[
              const SizedBox(width: 18),
              memberStatus(l10n, room, m),
            ],
          ]),
        ),
    ]);
  }
}

Widget memberStatus(L10n l10n, RoomState room, RoomMember m) {
  if (m.watching == null || m.watching != room.itemId) return Pill(l10n.togetherBrowsing);
  if (!m.ready) return Pill(l10n.togetherLoading, color: Zc.requestDeep);
  return Pill(l10n.togetherWatching, color: Zc.accent);
}

Future<void> showRoomDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _RoomDialog());

class _RoomDialog extends StatelessWidget {
  const _RoomDialog();

  @override
  Widget build(BuildContext context) {
    final together = AppServicesScope.of(context).together;
    final l10n = context.l10n;
    return Dialog(
      backgroundColor: Zc.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Zs.radiusLarge)),
      child: SizedBox(
        width: 820,
        child: Padding(
          padding: const EdgeInsets.all(44),
          child: ListenableBuilder(
            listenable: together,
            builder: (context, _) {
              final room = together.room;
              return FocusZone(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(room == null ? l10n.watchTogether : l10n.togetherRoomReady(room.code), style: Zt.headline),
                  const SizedBox(height: 18),
                  if (room == null) ...[
                    if (together.problem != null)
                      Text(l10n.togetherUnreachable, style: Zt.meta.copyWith(color: Zc.danger))
                    else
                      Text(l10n.togetherConnecting, style: Zt.meta),
                  ] else ...[
                    Text(l10n.togetherRoomHint, style: Zt.body),
                    const SizedBox(height: 22),
                    Text(room.code, style: Zt.display.copyWith(fontSize: 88, letterSpacing: 18, color: Zc.accentSoft)),
                    const SizedBox(height: 22),
                    Text(l10n.togetherMembersCount(room.members.length), style: Zt.rowTitle),
                    const SizedBox(height: 14),
                    RoomMembers(together: together, room: room),
                  ],
                  const SizedBox(height: 26),
                  Row(children: [
                    TvButton(
                        label: l10n.close, icon: Icons.check_rounded, primary: true, autofocus: true,
                        onSelect: () => Navigator.of(context).pop()),
                    if (room != null) ...[
                      const SizedBox(width: 16),
                      TvButton(
                        label: l10n.togetherLeave,
                        icon: Icons.logout_rounded,
                        onSelect: () {
                          together.leave();
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ]),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }
}
