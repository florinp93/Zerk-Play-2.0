import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/release_info.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'net_image.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    this.onSelect,
    this.onFocus,
    this.onMenu,
    this.autofocus = false,
    this.width = Zs.posterWidth,
    this.marked,
    this.focusNode,
  });

  final EmbyItem item;
  final VoidCallback? onSelect;
  final VoidCallback? onFocus;
  final VoidCallback? onMenu;
  final bool autofocus;
  final double width;

  final String? marked;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final catalog = AppServicesScope.read(context).catalog;
    final height = width * 1.5;
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: onSelect,
      onMenu: onMenu,
      onFocusChange: (f) => f ? onFocus?.call() : null,
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FocusFrame(
            focused: focused,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(fit: StackFit.expand, children: [
                NetImage(
                  url: catalog.poster(item, width: width),
                  width: width,
                  fallback: TitleArt(title: item.name, subtitle: item.productionYear?.toString(),
                      icon: item.isSeries ? Icons.tv_rounded : Icons.movie_outlined),
                ),
                _PosterBadges(item: item),
                if (marked != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Zc.accent.withValues(alpha: 0.92),
                      child: Text(marked!, textAlign: TextAlign.center,
                          style: Zt.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 1.5)),
                    ),
                  )
                else if (item.progress != null)
                  Positioned(left: 0, right: 0, bottom: 0, child: ProgressStrip(item.progress!)),
              ]),
            ),
          ),
          _FocusCaption(focused: focused, title: item.name, subtitle: _subtitle(item)),
        ]),
      ),
    );
  }

  static String? _subtitle(EmbyItem i) {
    if (i.isSeries) {
      final y = i.productionYear;
      if (y == null) return null;
      final end = i.endDate?.year;
      return i.status == 'Continuing' ? '$y –' : (end != null && end != y ? '$y – $end' : '$y');
    }
    return i.productionYear?.toString();
  }
}

class _PosterBadges extends StatelessWidget {
  const _PosterBadges({required this.item});

  final EmbyItem item;

  @override
  Widget build(BuildContext context) {
    final unwatched = item.unplayedItemCount ?? 0;
    return Positioned(
      top: 10,
      right: 10,
      child: item.isPlayed
          ? const _Corner(child: Icon(Icons.check_rounded, size: 22, color: Colors.white))
          : (item.isSeries || item.isSeason) && unwatched > 0
              ? _Corner(child: Text('$unwatched', style: Zt.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w800)))
              : const SizedBox.shrink(),
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Zc.accent,
          borderRadius: BorderRadius.circular(17),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
        child: child,
      );
}

class _FocusCaption extends StatelessWidget {
  const _FocusCaption({required this.focused, required this.title, this.subtitle});

  final bool focused;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: focused ? 1 : 0,
      duration: Zm.fast,
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.label),
          if (subtitle != null) Text(subtitle!, maxLines: 1, style: Zt.caption),
        ]),
      ),
    );
  }
}

class LandscapeCard extends StatelessWidget {
  const LandscapeCard({
    super.key,
    required this.item,
    this.title,
    this.subtitle,
    this.onSelect,
    this.onFocus,
    this.onMenu,
    this.autofocus = false,
    this.width = Zs.landscapeWidth,
    this.preferEpisodeStill = true,
    this.focusNode,
    this.onPlay,
  });

  final EmbyItem item;
  final String? title;
  final String? subtitle;
  final VoidCallback? onSelect;

  final VoidCallback? onPlay;
  final VoidCallback? onFocus;
  final VoidCallback? onMenu;
  final bool autofocus;
  final double width;
  final bool preferEpisodeStill;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final catalog = AppServicesScope.read(context).catalog;
    final height = width * 9 / 16;
    final missing = item.isVirtual;
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: missing ? null : onSelect,
      onMenu: onMenu,
      onFocusChange: (f) => f ? onFocus?.call() : null,
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FocusFrame(
            focused: focused,
            scale: 1.06,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(fit: StackFit.expand, children: [
                Opacity(
                  opacity: missing ? 0.35 : 1,
                  child: NetImage(
                    url: catalog.landscape(item, width: width, preferEpisodeStill: preferEpisodeStill),
                    width: width,
                    fallback: TitleArt(title: item.seriesName ?? item.name, subtitle: item.episodeCode, icon: Icons.play_circle_outline),
                  ),
                ),
                if (item.isPlayed)
                  const Positioned(top: 10, right: 10, child: _Corner(child: Icon(Icons.check_rounded, size: 22, color: Colors.white))),
                if (missing)
                  Center(child: Pill(item.premiereDate != null && item.premiereDate!.isAfter(DateTime.now()) ? context.l10n.upcoming : context.l10n.missing)),
                if (focused && !missing && onSelect != null)
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onPlay ?? onSelect,
                      child: _PlayCircle(),
                    ),
                  ),
                if (item.progress != null) Positioned(left: 0, right: 0, bottom: 0, child: ProgressStrip(item.progress!, height: 6)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Text(title ?? item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Zt.label.copyWith(color: focused ? Zc.text : Zc.textMuted)),
          if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.caption),
        ]),
      ),
    );
  }
}

class _PlayCircle extends StatefulWidget {
  @override
  State<_PlayCircle> createState() => _PlayCircleState();
}

class _PlayCircleState extends State<_PlayCircle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: Zm.fast,
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _hover ? Zc.accent : Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow_rounded, size: 48, color: Colors.white),
        ),
      );
}

class RequestPosterCard extends StatelessWidget {
  const RequestPosterCard({
    super.key,
    required this.media,
    this.onSelect,
    this.onFocus,
    this.autofocus = false,
    this.width = Zs.posterWidth,
  });

  final SeerrMedia media;
  final VoidCallback? onSelect;
  final VoidCallback? onFocus;
  final bool autofocus;
  final double width;

  @override
  Widget build(BuildContext context) => RequestStateBuilder(media: media, builder: _build);

  Widget _build(BuildContext context, Availability availability, ReleaseInfo? release) {
    final height = width * 1.5;
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
            ringColor: Zc.request,
            glowColor: Zc.request,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(fit: StackFit.expand, children: [
                ColorFiltered(
                  colorFilter: focused ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : requestTint,
                  child: Opacity(
                    opacity: focused ? 1 : 0.6,
                    child: NetImage(
                      url: media.poster(width: width > 200 ? 500 : 342),
                      width: width,
                      fallback: TitleArt(title: media.title, subtitle: media.year?.toString()),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.8)]),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(
                          availability.canRequest
                              ? Icons.add_circle_outline_rounded
                              : release?.notOut ?? false
                                  ? Icons.hourglass_top_rounded
                                  : Icons.schedule_rounded,
                          size: 20,
                          color: Zc.background),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Zt.caption.copyWith(color: Zc.background, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ]),
                  ),
                ),
                if (release?.notOut ?? false)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FittedBox(fit: BoxFit.scaleDown, child: ReleasePill(release)),
                    ),
                  ),
              ]),
            ),
          ),
          _FocusCaption(focused: focused, title: media.title, subtitle: media.year?.toString()),
        ]),
      ),
    );
  }
}

(String, Color) requestStatusLabel(L10n l10n, Availability a, {ReleaseInfo? release}) => switch (a) {
      Availability.pending || Availability.processing when release?.notOut ?? false =>
        (l10n.statusAwaitingRelease, Zc.cinema),
      Availability.none => (l10n.statusRequest, Zc.request),
      Availability.pending => (l10n.statusRequested, const Color(0xFFB9B4FF)),
      Availability.processing => (l10n.statusRequested, const Color(0xFFB9B4FF)),
      Availability.downloading => (l10n.statusDownloading, const Color(0xFF7FD8FF)),
      Availability.partial => (l10n.statusPartial, Zc.request),
      Availability.available => (l10n.statusAvailable, Zc.success),
      Availability.blocked => (l10n.statusUnavailable, Zc.textFaint),
    };

class RequestStateBuilder extends StatelessWidget {
  const RequestStateBuilder({super.key, required this.media, required this.builder});

  final SeerrMedia media;
  final Widget Function(BuildContext context, Availability availability, ReleaseInfo? release) builder;

  static final _changes = Listenable.merge([RequestStatuses.changed, ReleaseInfos.changed]);

  @override
  Widget build(BuildContext context) {
    if (ReleaseInfos.of(media) == null) ReleaseInfos.ensure(AppServicesScope.read(context).seerr, media);
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) => builder(context, RequestStatuses.of(media), ReleaseInfos.of(media)),
    );
  }
}

class ReleasePill extends StatelessWidget {
  const ReleasePill(this.release, {super.key});

  final ReleaseInfo? release;

  @override
  Widget build(BuildContext context) {
    final r = release;
    final l10n = context.l10n;
    return switch (r?.stage) {
      ReleaseStage.inCinemas => Pill(l10n.releaseInCinemas, icon: Icons.theaters_rounded, color: Zc.cinema, textColor: Zc.background),
      ReleaseStage.upcoming => Pill(
          r!.cinema != null ? l10n.releaseComing(r.cinema!).toUpperCase() : l10n.releaseNotYet,
          icon: Icons.event_rounded,
          color: Zc.cinema,
          textColor: Zc.background),
      _ => const SizedBox.shrink(),
    };
  }
}

String? releaseNote(L10n l10n, ReleaseInfo? r, {required bool requested}) {
  if (r == null || !r.notOut) return null;
  final digital = r.digital;
  if (requested) return digital != null ? l10n.requestedWaitsDigital(digital) : l10n.requestedWaits;
  return switch (r.stage) {
    ReleaseStage.inCinemas => digital != null ? l10n.noteInCinemasDigital(digital) : l10n.noteInCinemas,
    _ => r.cinema != null ? l10n.noteUpcoming(r.cinema!) : l10n.noteUpcomingNoDate,
  };
}

class CollectionCard extends StatelessWidget {
  const CollectionCard({super.key, required this.item, this.onSelect, this.onFocus, this.autofocus = false, this.width = 560});

  final EmbyItem item;
  final VoidCallback? onSelect;
  final VoidCallback? onFocus;
  final bool autofocus;
  final double width;

  String _size(L10n l10n) {
    final owned = item.childCount ?? item.recursiveItemCount ?? 0;
    final total = item.id.isEmpty ? item.recursiveItemCount : null;
    return total != null && total > owned ? l10n.filmsOwnedOfTotal(owned, total) : l10n.filmCount(owned);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = AppServicesScope.read(context).catalog;
    final height = width * 0.42;
    final logo = catalog.logo(item, width: 600);
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      onFocusChange: (f) => f ? onFocus?.call() : null,
      builder: (context, focused) => FocusFrame(
        focused: focused,
        scale: 1.05,
        radius: Zs.radiusLarge,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            NetImage(
              url: catalog.backdrop(item, width: (width * 1.5).round()) ?? catalog.landscape(item, width: width),
              width: width,
              fallback: TitleArt(title: '', icon: Icons.collections_bookmark_outlined),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [Color(0xE6000000), Color(0x22000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(26),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                if (logo != null)
                  SizedBox(
                    height: 70,
                    width: width * 0.6,
                    child: NetImage(url: logo, fit: BoxFit.contain, alignment: Alignment.bottomLeft, width: width * 0.6,
                        fallback: Text(item.name, style: Zt.title)),
                  )
                else
                  Text(item.name, maxLines: 2, style: Zt.title),
                const SizedBox(height: 8),
                Text(
                  _size(context.l10n),
                  style: Zt.caption.copyWith(color: Zc.textMuted),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
