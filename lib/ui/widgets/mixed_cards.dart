import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/release_info.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../focus/tv_focusable.dart';
import '../core/playback_launcher.dart';
import '../pages/routes.dart';
import '../theme/tokens.dart';
import 'cards.dart';
import 'common.dart';
import 'net_image.dart';

enum CardStyle {
  poster,

  landscape,

  ranked,

  spotlight,
}

const double spotlightWidth = 640;
const double _rankWidth = 118;

double cardAreaHeight(CardStyle style) => switch (style) {
      CardStyle.poster || CardStyle.ranked => Zs.posterWidth * 1.5 + 100,
      CardStyle.landscape => Zs.landscapeWidth * 9 / 16 + 100,
      CardStyle.spotlight => spotlightWidth * 9 / 16 + 44,
    };

double cardWidth(CardStyle style) => switch (style) {
      CardStyle.poster => Zs.posterWidth,
      CardStyle.ranked => Zs.posterWidth + _rankWidth,
      CardStyle.landscape => Zs.landscapeWidth,
      CardStyle.spotlight => spotlightWidth,
    };

Widget mixedCard(
  BuildContext context,
  Object data, {
  required CardStyle style,
  int rank = 0,
  bool autofocus = false,
  VoidCallback? onFocus,
}) {
  if (data is SeerrMedia) {
    void open() => openRequest(context, data);
    return switch (style) {
      CardStyle.poster => RequestPosterCard(media: data, autofocus: autofocus, onFocus: onFocus, onSelect: open),
      CardStyle.ranked => RankedCard(
          rank: rank,
          child: RequestPosterCard(media: data, autofocus: autofocus, onFocus: onFocus, onSelect: open)),
      CardStyle.landscape => RequestLandscapeCard(media: data, autofocus: autofocus, onFocus: onFocus, onSelect: open),
      CardStyle.spotlight => SpotlightCard.request(data, autofocus: autofocus, onFocus: onFocus, onSelect: open),
    };
  }
  final item = data as EmbyItem;
  void open() => openItem(context, item);
  return switch (style) {
    CardStyle.poster => PosterCard(item: item, autofocus: autofocus, onFocus: onFocus, onSelect: open),
    CardStyle.ranked =>
      RankedCard(rank: rank, child: PosterCard(item: item, autofocus: autofocus, onFocus: onFocus, onSelect: open)),
    CardStyle.landscape => LandscapeCard(
        item: item,
        autofocus: autofocus,
        title: item.name,
        subtitle: [item.productionYear?.toString(), item.genres.firstOrNull].nonNulls.join('  ·  '),
        preferEpisodeStill: false,
        onFocus: onFocus,
        onSelect: open,
        onPlay: () => playItem(context, item),
      ),
    CardStyle.spotlight => SpotlightCard.item(context, item, autofocus: autofocus, onFocus: onFocus, onSelect: open),
  };
}

class RankedCard extends StatelessWidget {
  const RankedCard({super.key, required this.rank, required this.child});

  final int rank;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const h = Zs.posterWidth * 1.5;
    final numeral = TextStyle(fontSize: 230, fontWeight: FontWeight.w900, height: 1, letterSpacing: -18);
    return SizedBox(
      width: Zs.posterWidth + _rankWidth,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          top: h - 196,
          width: _rankWidth + 70,
          height: 230,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomRight,
            child: Stack(children: [
              Text('$rank',
                  maxLines: 1,
                  softWrap: false,
                  style: numeral.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 5
                        ..color = Colors.white.withValues(alpha: 0.55))),
              Text('$rank', maxLines: 1, softWrap: false, style: numeral.copyWith(color: Zc.background)),
            ]),
          ),
        ),
        Padding(padding: const EdgeInsets.only(left: _rankWidth), child: child),
      ]),
    );
  }
}

class RequestLandscapeCard extends StatelessWidget {
  const RequestLandscapeCard({
    super.key,
    required this.media,
    this.onSelect,
    this.onFocus,
    this.autofocus = false,
    this.width = Zs.landscapeWidth,
  });

  final SeerrMedia media;
  final VoidCallback? onSelect;
  final VoidCallback? onFocus;
  final bool autofocus;
  final double width;

  @override
  Widget build(BuildContext context) => RequestStateBuilder(media: media, builder: _build);

  Widget _build(BuildContext context, Availability availability, ReleaseInfo? release) {
    final (label, color) = requestStatusLabel(context.l10n, availability, release: release);
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      onFocusChange: (f) => f ? onFocus?.call() : null,
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FocusFrame(
            focused: focused,
            scale: 1.06,
            ringColor: Zc.request,
            glowColor: Zc.request,
            child: SizedBox(
              width: width,
              height: width * 9 / 16,
              child: Stack(fit: StackFit.expand, children: [
                ColorFiltered(
                  colorFilter: focused ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : requestTint,
                  child: Opacity(
                    opacity: focused ? 1 : 0.6,
                    child: NetImage(
                      url: media.backdrop(width: 780) ?? media.poster(),
                      width: width,
                      fallback: TitleArt(title: media.title, subtitle: media.year?.toString()),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    Pill(label, color: color, textColor: Zc.background),
                    if (release?.notOut ?? false) ReleasePill(release),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Text(media.title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.label.copyWith(color: focused ? Zc.text : Zc.textMuted)),
          Text(media.year?.toString() ?? '', maxLines: 1, style: Zt.caption),
        ]),
      ),
    );
  }
}

class SpotlightCard extends StatelessWidget {
  const SpotlightCard({
    super.key,
    required this.title,
    required this.backdrop,
    this.logo,
    this.meta = const [],
    this.overview,
    this.media,
    this.onSelect,
    this.onFocus,
    this.autofocus = false,
  });

  factory SpotlightCard.item(BuildContext context, EmbyItem item,
      {bool autofocus = false, VoidCallback? onFocus, VoidCallback? onSelect}) {
    final c = AppServicesScope.read(context).catalog;
    return SpotlightCard(
      title: item.name,
      backdrop: c.backdrop(item, width: 1280) ?? c.landscape(item, width: 1280),
      logo: c.logo(item, width: 500),
      meta: [item.productionYear?.toString(), item.genres.take(2).join(', ')],
      overview: item.overview,
      autofocus: autofocus,
      onFocus: onFocus,
      onSelect: onSelect,
    );
  }

  factory SpotlightCard.request(SeerrMedia m, {bool autofocus = false, VoidCallback? onFocus, VoidCallback? onSelect}) =>
      SpotlightCard(
        title: m.title,
        backdrop: m.backdrop() ?? m.poster(width: 780),
        meta: [m.year?.toString(), m.genres.take(2).join(', ')],
        overview: m.overview,
        media: m,
        autofocus: autofocus,
        onFocus: onFocus,
        onSelect: onSelect,
      );

  final String title;
  final Uri? backdrop;
  final Uri? logo;
  final List<String?> meta;
  final String? overview;

  final SeerrMedia? media;
  final VoidCallback? onSelect;
  final VoidCallback? onFocus;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => media == null
      ? _build(context, null, null)
      : RequestStateBuilder(media: media!, builder: _build);

  Widget _build(BuildContext context, Availability? req, ReleaseInfo? release) {
    const w = spotlightWidth, h = spotlightWidth * 9 / 16;
    final titleText = Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.title);
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      onFocusChange: (f) => f ? onFocus?.call() : null,
      builder: (context, focused) => FocusFrame(
        focused: focused,
        scale: 1.04,
        radius: Zs.radiusLarge,
        ringColor: req != null ? Zc.request : Colors.white,
        glowColor: req != null ? Zc.request : Zc.accent,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(fit: StackFit.expand, children: [
            NetImage(url: backdrop, width: w, fallback: TitleArt(title: '', icon: Icons.movie_outlined)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xF0000000), Color(0x99000000), Color(0x00000000)],
                  stops: [0, 0.45, 0.85],
                ),
              ),
            ),
            if (req != null)
              Positioned(
                top: 16,
                left: 16,
                child: Row(children: [
                  Pill(requestStatusLabel(context.l10n, req, release: release).$1,
                      color: requestStatusLabel(context.l10n, req, release: release).$2, textColor: Zc.background),
                  if (release?.notOut ?? false) ...[const SizedBox(width: 8), ReleasePill(release)],
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                if (logo != null)
                  SizedBox(
                    height: 76,
                    width: w * 0.55,
                    child: NetImage(url: logo, width: w * 0.55, fit: BoxFit.contain, alignment: Alignment.bottomLeft,
                        fallback: titleText),
                  )
                else
                  titleText,
                const SizedBox(height: 10),
                MetaLine(meta, style: Zt.caption.copyWith(color: Zc.textMuted)),
                if (overview != null) ...[
                  const SizedBox(height: 8),
                  Text(overview!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Zt.caption.copyWith(color: Zc.textMuted, height: 1.35)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
