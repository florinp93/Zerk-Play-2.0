import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/release_info.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/net_image.dart';

@immutable
class HeroInfo {
  const HeroInfo({
    required this.key,
    required this.title,
    this.backdrop,
    this.logo,
    this.meta = const [],
    this.rating,
    this.overview,
    this.request,
    this.media,
    this.progress,
    this.badge,
  });

  final String key;
  final String title;
  final Uri? backdrop;
  final Uri? logo;
  final List<String?> meta;
  final double? rating;
  final String? overview;

  final Availability? request;

  final SeerrMedia? media;
  final double? progress;
  final String? badge;

  static HeroInfo fromItem(L10n l10n, AppServices s, EmbyItem item, {EmbyItem? series}) {
    final c = s.catalog;
    final ep = item.isEpisode;
    return HeroInfo(
      key: item.id,
      title: ep ? (item.seriesName ?? item.name) : item.name,
      backdrop: c.backdrop(item) ?? c.landscape(item, width: 1280),
      logo: c.logo(item),
      meta: [
        if (ep) [item.episodeCode, item.name].whereType<String>().join('  '),
        if (!ep) item.productionYear?.toString(),
        if (item.isSeries && item.childCount != null) l10n.seasonCount(item.childCount!),
        if (!item.isSeries) formatRuntime(l10n, item.runtime),
        item.officialRating,
        if (item.genres.isNotEmpty) item.genres.take(3).join(', '),
      ],
      rating: item.communityRating,
      overview: item.overview,
      progress: item.progress,
      badge: item.resumePosition != null ? l10n.timeLeft(formatRuntime(l10n, (item.runtime ?? Duration.zero) - item.resumePosition!) ?? '') : null,
    );
  }

  static HeroInfo fromRequest(L10n l10n, SeerrMedia m) => HeroInfo(
        key: m.key,
        title: m.title,
        backdrop: m.backdrop(),
        meta: [m.year?.toString(), m.isTv ? l10n.series : l10n.movie, if (m.genres.isNotEmpty) m.genres.take(3).join(', ')],
        rating: m.voteAverage == null || m.voteAverage == 0 ? null : m.voteAverage,
        overview: m.overview,
        request: RequestStatuses.of(m),
        media: m,
      );
}

String? formatRuntime(L10n l10n, Duration? d) {
  if (d == null || d.inMinutes <= 0) return null;
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? (m > 0 ? l10n.runtimeHoursMinutes(h, m) : l10n.runtimeHours(h)) : l10n.runtimeMinutes(m);
}

class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key, required this.info});

  final HeroInfo? info;

  @override
  Widget build(BuildContext context) {
    final i = info;
    return AnimatedSwitcher(
      duration: Zm.normal,
      switchInCurve: Zm.curve,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(position: Tween(begin: const Offset(0.02, 0), end: Offset.zero).animate(anim), child: child),
      ),
      child: i == null
          ? const SizedBox.shrink()
          : SizedBox(
              key: ValueKey(i.key),
              width: 980,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (i.request != null) ...[
                  i.media != null
                      ? RequestStateBuilder(media: i.media!, builder: (_, a, r) => _RequestBanner(a, release: r))
                      : _RequestBanner(i.request!),
                  const SizedBox(height: 16),
                ],
                if (i.logo != null)
                  SizedBox(
                    height: 130,
                    width: 520,
                    child: NetImage(
                      url: i.logo,
                      width: 520,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomLeft,
                      fallback: _Title(i.title),
                    ),
                  )
                else
                  _Title(i.title),
                const SizedBox(height: 18),
                MetaLine(i.meta, leading: [if (i.rating != null) RatingPill(i.rating!)]),
                if (i.badge != null || i.progress != null) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    if (i.progress != null)
                      SizedBox(width: 220, child: ClipRRect(borderRadius: BorderRadius.circular(3), child: ProgressStrip(i.progress!, height: 6))),
                    if (i.badge != null) ...[const SizedBox(width: 14), Text(i.badge!, style: Zt.caption.copyWith(color: Zc.textMuted))],
                  ]),
                ],
                if (i.overview != null) ...[
                  const SizedBox(height: 18),
                  Text(i.overview!, maxLines: 3, overflow: TextOverflow.ellipsis, style: Zt.body),
                ],
              ]),
            ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.display);
}

class _RequestBanner extends StatelessWidget {
  const _RequestBanner(this.a, {this.release});

  final Availability a;
  final ReleaseInfo? release;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, color) = requestStatusLabel(l10n, a, release: release);
    final waiting = release?.notOut ?? false;
    final text = switch (a) {
      Availability.pending || Availability.processing when waiting => l10n.bannerAwaitingRelease,
      Availability.none => l10n.bannerNotInLibrary,
      Availability.pending => l10n.bannerPending,
      Availability.processing => l10n.bannerProcessing,
      Availability.downloading => l10n.bannerDownloading,
      Availability.partial => l10n.bannerPartial,
      Availability.available => l10n.inYourLibrary,
      Availability.blocked => l10n.bannerBlocked,
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Pill(label, color: color, textColor: Zc.background),
      if (waiting) ...[const SizedBox(width: 10), ReleasePill(release)],
      const SizedBox(width: 14),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.meta.copyWith(color: color))),
    ]);
  }
}
