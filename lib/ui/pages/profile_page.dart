import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/host.dart';
import '../../core/pick_image.dart';
import '../../data/user_profile.dart';
import '../../l10n/l10n.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/setting_rows.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _scroll = RevealController(margin: 120);
  Future<List<String>>? _library;
  bool _busy = false;

  static bool get _canUpload => Host.isWindows;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? failure}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('[profile] $e');
      UiSounds.play(UiSound.error);
      if (mounted) showToast(context, failure ?? context.l10n.profileSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(ProfileService profiles, UserProfile profile) async {
    final l10n = context.l10n;
    final name = await showTextInputDialog(context, title: l10n.profileName, initial: profile.name, hint: l10n.profileNameHint);
    if (name == null || name.trim().isEmpty || name.trim() == profile.name) return;
    await _run(() => profiles.rename(name));
  }

  Future<void> _upload(ProfileService profiles) async {
    final l10n = context.l10n;
    final bytes = await pickImage();
    if (bytes == null) return;
    await _run(() => profiles.uploadAvatar(bytes), failure: l10n.profileUploadFailed);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = AppServicesScope.of(context).profiles;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: profiles,
      builder: (context, _) {
        final profile = profiles.profile;
        if (profile == null) return const SizedBox.shrink();
        _library ??= profiles.library();
        return FocusZone(
          debugLabel: 'profile',
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.only(left: contentLeft, top: 90, right: 120, bottom: 140),
            children: [
              Text(l10n.profile, style: Zt.headline),
              const SizedBox(height: 36),
              Row(children: [
                UserAvatar(url: profile.avatarUrl, name: profile.name, size: 168),
                const SizedBox(width: 40),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(profile.name, style: Zt.display.copyWith(fontSize: 56)),
                    const SizedBox(height: 22),
                    Wrap(spacing: 16, runSpacing: 16, children: [
                      TvButton(label: l10n.profileName, icon: Icons.edit_rounded, onSelect: () => _rename(profiles, profile)),
                      if (_canUpload)
                        TvButton(label: l10n.profileUpload, icon: Icons.upload_rounded, onSelect: () => _upload(profiles)),
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 56),
              Text(l10n.profilePicture, style: Zt.rowTitle),
              const SizedBox(height: 10),
              Text(l10n.profilePictureHint, style: Zt.meta),
              const SizedBox(height: 26),
              FutureBuilder(
                future: _library,
                builder: (context, snap) {
                  final ids = snap.data;
                  if (ids == null) return const SizedBox(height: 140);
                  return FocusZone(
                    debugLabel: 'avatar-library',
                    child: Wrap(spacing: 22, runSpacing: 22, children: [
                      for (final id in ids)
                        _AvatarChoice(
                          url: profiles.libraryAvatar(id),
                          label: id,
                          selected: profile.libraryAvatar == id,
                          onSelect: () => _run(() => profiles.pickAvatar(id)),
                        ),
                    ]),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({required this.url, required this.label, required this.selected, required this.onSelect});

  final Uri url;
  final String label;
  final bool selected;
  final VoidCallback onSelect;

  static const _size = 124.0;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onSelect,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.1 : 1,
        duration: Zm.fast,
        curve: Zm.curve,
        child: Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: Zm.fast,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused ? Colors.white : (selected ? Zc.accent : Colors.transparent),
              boxShadow: focused ? [BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 24)] : null,
            ),
            child: UserAvatar(url: url, name: label, size: _size),
          ),
          if (selected)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Zc.accent, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 24, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }
}
