import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../core/emby/models/media_source.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../../playback/versions.dart';
import '../core/artwork.dart';
import '../core/input_mode.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/net_image.dart';
import '../widgets/scroll_arrows.dart';
import 'hero.dart';
import 'routes.dart';

const double pageLeft = 120;

class TitleBlock extends StatelessWidget {
  const TitleBlock({super.key, required this.item, this.logo, this.source, this.extraMeta = const [], this.logoHeight = 150});

  final EmbyItem item;
  final Uri? logo;
  final MediaSourceInfo? source;
  final List<String?> extraMeta;
  final double logoHeight;

  @override
  Widget build(BuildContext context) {
    final title = item.isEpisode ? (item.seriesName ?? item.name) : item.name;
    final v = source == null ? null : VersionInfo(source!);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (logo != null)
        SizedBox(
          height: logoHeight,
          width: 600,
          child: NetImage(url: logo, width: 600, fit: BoxFit.contain, alignment: Alignment.bottomLeft,
              fallback: Text(title, style: Zt.display)),
        )
      else
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.display),
      if (item.isEpisode) ...[
        const SizedBox(height: 14),
        Text([item.episodeCode, item.name].whereType<String>().join('  ·  '), style: Zt.title),
      ],
      const SizedBox(height: 16),
      MetaLine([...extraMeta], leading: [if (item.communityRating != null) RatingPill(item.communityRating!)]),
      if (v != null) ...[
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 8, children: [
          Pill(v.resolution == '2160p' ? '4K' : v.resolution, outlined: true),
          if (v.hdr != null) Pill(v.hdr!, outlined: true),
          if (v.bestAudio != null) Pill(v.bestAudio!, outlined: true),
          if (item.mediaSources.length > 1) Pill(context.l10n.versionCount(item.mediaSources.length), color: Zc.accent),
        ]),
      ],
    ]);
  }
}

String? endsAt(L10n l10n, Duration? runtime, {Duration? position}) {
  if (runtime == null || runtime.inMinutes <= 0) return null;
  final end = DateTime.now().add(runtime - (position ?? Duration.zero));
  return l10n.endsAt('${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}');
}

List<String?> standardMeta(L10n l10n, EmbyItem item) => [
      if (!item.isEpisode) item.productionYear?.toString(),
      if (item.isEpisode && item.premiereDate != null) formatDate(l10n, item.premiereDate!),
      formatRuntime(l10n, item.runtime),
      item.officialRating,
      endsAt(l10n, item.runtime, position: item.resumePosition),
    ];

String formatDate(L10n l10n, DateTime d) => '${d.day} ${l10n.monthsShort.split(' ')[d.month - 1]} ${d.year}';

class CastRow extends StatelessWidget {
  const CastRow({super.key, required this.people, this.left = pageLeft});

  final List<Person> people;
  final double left;

  @override
  Widget build(BuildContext context) {
    final cast = people.where((p) => p.type == 'Actor' || p.type == 'GuestStar').take(24).toList();
    final directors = people.where((p) => p.type == 'Director').toList();
    final shown = [...directors.take(1), ...cast];
    if (shown.isEmpty) return const SizedBox.shrink();
    final catalog = AppServicesScope.read(context).catalog;
    return MediaRow(
      left: left,
      title: context.l10n.castAndCrew,
      height: 260,
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final p = shown[i];
        return TvFocusable(
          onSelect: () => openPerson(context, p),
          builder: (context, focused) => SizedBox(
            width: 150,
            child: Column(children: [
              AnimatedScale(
                scale: focused ? 1.08 : 1,
                duration: Zm.normal,
                curve: Curves.easeOutBack,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 3),
                    color: Zc.surfaceHigh,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: NetImage(
                    url: catalog.personPhoto(p),
                    width: 140,
                    fallback: Center(child: Text(_initials(p.name), style: Zt.headline.copyWith(color: Zc.textFaint))),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: Zt.label.copyWith(fontSize: 19, color: focused ? Zc.text : Zc.textMuted)),
              Text(p.type == 'Director' ? context.l10n.director : (p.role ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center, style: Zt.caption.copyWith(fontSize: 16)),
            ]),
          ),
        );
      },
    );
  }

  static String _initials(String name) =>
      name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
}

class CollectionHighlight extends StatefulWidget {
  const CollectionHighlight({
    super.key,
    required this.collection,
    required this.films,
    required this.current,
    this.requestable = const [],
    this.total,
    this.onCurrent,
  });

  final EmbyItem collection;

  final List<EmbyItem> films;
  final EmbyItem current;

  final List<SeerrMedia> requestable;

  final int? total;

  final VoidCallback? onCurrent;

  @override
  State<CollectionHighlight> createState() => _CollectionHighlightState();
}

class _CollectionHighlightState extends State<CollectionHighlight> {
  static const _inset = 56.0;
  static const _cardWidth = 150.0;
  static const _gap = 22.0;

  RevealController? _row;

  @override
  void dispose() {
    _row?.dispose();
    super.dispose();
  }

  List<Object> get _entries {
    int year(Object o) => switch (o) {
          EmbyItem f => f.productionYear ?? f.premiereDate?.year ?? 9999,
          SeerrMedia m => m.year ?? 9999,
          _ => 9999,
        };
    final all = <Object>[...widget.films, ...widget.requestable];
    final indexed = all.indexed.toList()
      ..sort((a, b) {
        final byYear = year(a.$2).compareTo(year(b.$2));
        return byYear != 0 ? byYear : a.$1.compareTo(b.$1);
      });
    return [for (final (_, o) in indexed) o];
  }

  RevealController _rowController(double viewport, List<Object> entries) {
    if (_row != null) return _row!;
    final index = entries.indexWhere((f) => f is EmbyItem && f.id == widget.current.id);
    final content = entries.length * (_cardWidth + _gap) - _gap + 2 * _inset;
    final max = (content - viewport).clamp(0.0, double.infinity);
    final offset = index < 4 ? 0.0 : ((index - 1) * (_cardWidth + _gap)).clamp(0.0, max);
    return _row = RevealController(mode: RevealMode.anchored, anchor: _inset, initialScrollOffset: offset);
  }

  String? get _years {
    final years = [
      for (final f in widget.films) ?(f.productionYear ?? f.premiereDate?.year),
      for (final m in widget.requestable) ?m.year,
    ]..sort();
    if (years.isEmpty) return null;
    return years.first == years.last ? '${years.first}' : '${years.first} – ${years.last}';
  }

  @override
  Widget build(BuildContext context) {
    final catalog = AppServicesScope.read(context).catalog;
    final c = widget.collection;
    final backdrop = catalog.backdrop(c, width: 1920) ?? catalog.landscape(c, width: 1280) ?? catalog.backdrop(widget.current);
    final logo = catalog.logo(c, width: 640);
    final owned = widget.films.length;
    final total = widget.total;
    final l10n = context.l10n;
    final size = total != null && total > owned ? l10n.filmsOwnedOfTotal(owned, total) : l10n.filmCount(owned);

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        if (!has || InputMode.isPointer) return;
        final binding = WidgetsBinding.instance;
        binding.addPostFrameCallback((_) {
          binding.addPostFrameCallback((_) {
            if (mounted) revealFocused(context);
          });
          binding.scheduleFrame();
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(left: pageLeft, right: 120),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Zs.radiusLarge),
          child: Stack(children: [
            Positioned.fill(
              child: NetImage(url: backdrop, width: 1680, alignment: Alignment.topCenter,
                  fallback: const ColoredBox(color: Zc.surface)),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xF00B0B12), Color(0xB30B0B12), Color(0x260B0B12)],
                    stops: [0, 0.42, 1],
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000B0B12), Color(0xE60B0B12)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Zs.radiusLarge),
                    border: Border.all(color: Zc.outline),
                  ),
                ),
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(_inset, 48, 560, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l10n.partOfCollection,
                      style: Zt.caption.copyWith(letterSpacing: 6, color: Zc.accentSoft, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (logo != null)
                    SizedBox(
                      height: 96,
                      width: 520,
                      child: NetImage(url: logo, width: 520, fit: BoxFit.contain, alignment: Alignment.bottomLeft,
                          fallback: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.headline)),
                    )
                  else
                    Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.headline),
                  const SizedBox(height: 14),
                  MetaLine([size, _years]),
                  const SizedBox(height: 26),
                  FocusZone(
                    debugLabel: 'collection-highlight',
                    child: TvButton(
                      label: l10n.viewCollection,
                      icon: Icons.collections_bookmark_rounded,
                      onSelect: () => openItem(context, c),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 34),
              SizedBox(
                height: _cardWidth * 1.5 + 74,
                child: LayoutBuilder(builder: (context, box) {
                  final entries = _entries;
                  final controller = _rowController(box.maxWidth, entries);
                  return PointerScrollArrows(
                    controller: controller,
                    leftInset: _inset,
                    child: FocusZone(
                      debugLabel: 'collection-films',
                      child: ListView.separated(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.symmetric(horizontal: _inset),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(width: _gap),
                        itemBuilder: (context, i) {
                          final entry = entries[i];
                          if (entry is SeerrMedia) {
                            return RequestPosterCard(
                              media: entry,
                              width: _cardWidth,
                              onSelect: () => openRequest(context, entry),
                            );
                          }
                          final f = entry as EmbyItem;
                          final isCurrent = f.id == widget.current.id;
                          return PosterCard(
                            item: f,
                            width: _cardWidth,
                            marked: isCurrent ? l10n.nowViewing : null,
                            onSelect: isCurrent ? widget.onCurrent : () => openItem(context, f),
                          );
                        },
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
            ]),
          ]),
        ),
      ),
    );
  }
}
