import 'package:flutter/material.dart';

import '../../playback/versions.dart';
import '../theme/tokens.dart';

class MediaBadges extends StatelessWidget {
  const MediaBadges(this.info, {super.key, this.trailing = const []});

  final VersionInfo info;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final hdr = info.hdr;
    final audio = info.bestAudio;
    return Wrap(spacing: 22, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Icon(
        switch (info.resolution) {
          '2160p' => Icons.four_k_rounded,
          '1080p' || '720p' => Icons.hd_rounded,
          _ => Icons.sd_rounded,
        },
        size: 38,
        color: Zc.text,
      ),
      if (hdr != null) _Badge(icon: hdr == 'HDR10+' ? Icons.hdr_plus_rounded : Icons.hdr_on_rounded, label: hdr),
      if (audio != null)
        _Badge(
          icon: audio.contains('Atmos') || audio.contains('DTS:X')
              ? Icons.spatial_audio_rounded
              : audio.contains('5.1') || audio.contains('7.1')
                  ? Icons.surround_sound_rounded
                  : Icons.speaker_rounded,
          label: audio,
        ),
      ...trailing,
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 30, color: Zc.text),
        const SizedBox(width: 8),
        Text(label, style: Zt.meta.copyWith(color: Zc.text, fontWeight: FontWeight.w600)),
      ]);
}
