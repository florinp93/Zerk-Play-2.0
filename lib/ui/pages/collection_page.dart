import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/release_info.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../core/playback_launcher.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/net_image.dart';
import '../widgets/scroll_arrows.dart';
import 'details_parts.dart';
import 'hero.dart';
import 'routes.dart';

class _Stop {
  _Stop.item(EmbyItem this.item) : media = null;
  _Stop.request(SeerrMedia this.media) : item = null;

  final EmbyItem? item;
  final SeerrMedia? media;

  int get year =>
      item?.productionYear ?? item?.premiereDate?.year ?? media?.year ?? 9999;
  DateTime get date => item?.premiereDate ?? DateTime(year);
}

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, required this.collection});

  final EmbyItem collection;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  List<_Stop>? _stops;
  bool _requesting = false;
  final _focused = Debounced<_Stop?>(
    null,
    delay: const Duration(milliseconds: 180),
  );
  final _timeline = RevealController(
    mode: RevealMode.anchored,
    anchor: pageLeft + 260,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focused.dispose();
    _timeline.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = AppServicesScope.read(context);
    final items = await s.catalog.collectionItems(widget.collection);
    final stops = [for (final i in items) _Stop.item(i)];

    final seerr = s.seerr;
    final tmdbCollection = int.tryParse(
      widget.collection.providerIds['Tmdb'] ?? '',
    );
    if (seerr != null && tmdbCollection != null) {
      try {
        final parts = await seerr.collectionParts(tmdbCollection);
        final owned = {for (final i in items) ?i.tmdbId};
        for (final p in parts) {
          if (!owned.contains(p.tmdbId) && !p.availability.isOnServer) stops.add(_Stop.request(p));
        }
      } catch (_) {}
    }
    stops.sort((a, b) => a.date.compareTo(b.date));
    if (!mounted) return;
    setState(() => _stops = stops);
    if (stops.isNotEmpty) _focused.set(stops.first, immediate: true);
  }

  Future<void> _playFromStart() async {
    final films =
        _stops?.map((s) => s.item).whereType<EmbyItem>().toList() ?? const [];
    final first =
        films.where((f) => !f.isPlayed).firstOrNull ?? films.firstOrNull;
    if (first != null) await playItem(context, first);
    if (mounted) _load();
  }

  List<SeerrMedia> get _requestable => [
        for (final s in _stops ?? const <_Stop>[])
          if (s.media != null && RequestStatuses.of(s.media!).canRequest) s.media!,
      ];

  Future<void> _requestAll() async {
    final seerr = AppServicesScope.read(context).seerr;
    final films = _requestable;
    if (seerr == null || films.isEmpty || _requesting) return;
    setState(() => _requesting = true);
    var done = 0, waiting = 0;
    String? error;
    for (final m in films) {
      try {
        await seerr.request(m);
        RequestStatuses.record(m, Availability.pending);
        done++;
        if ((await ReleaseInfos.load(seerr, m))?.notOut ?? false) waiting++;
      } on SeerrException catch (e) {
        if (!mounted) return;
        error ??= e.status == 403 ? context.l10n.requestNotAllowed : e.message;
      } catch (e) {
        error ??= '$e';
      }
    }
    if (!mounted) return;
    setState(() => _requesting = false);
    final l10n = context.l10n;
    UiSounds.play(error == null ? UiSound.select : UiSound.error);
    final result = error == null ? l10n.requestedAllMessage(done) : l10n.requestedSomeMessage(done, films.length, error);
    showToast(
      context,
      waiting == 0 ? result : '$result ${l10n.requestedNotOut(waiting)}',
      duration: Duration(seconds: waiting == 0 ? 3 : 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServicesScope.of(context);
    final c = s.catalog;
    final stops = _stops;
    final owned = stops?.where((x) => x.item != null).length ?? 0;
    final known = stops?.map((x) => x.year).where((y) => y != 9999).toList() ?? const [];
    final years = known.isEmpty
        ? null
        : (known.first == known.last ? '${known.first}' : '${known.first} – ${known.last}');

    return ValueListenableBuilder<_Stop?>(
      valueListenable: _focused,
      builder: (context, focus, _) {
        final backdrop = focus?.item != null
            ? (c.backdrop(focus!.item!) ?? c.backdrop(widget.collection))
            : focus?.media?.backdrop() ?? c.backdrop(widget.collection);
        final height = MediaQuery.sizeOf(context).height;
        return Stack(
          children: [
            Positioned.fill(
              child: Backdrop(url: backdrop, drift: true, dim: 0.1),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 70, bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: pageLeft,
                        right: 700,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.collectionLabel,
                            style: Zt.caption.copyWith(
                              letterSpacing: 6,
                              color: Zc.accentSoft,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (c.logo(widget.collection) != null)
                            SizedBox(
                              height: 110,
                              width: 560,
                              child: NetImage(
                                url: c.logo(widget.collection),
                                width: 560,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomLeft,
                                fallback: Text(
                                  widget.collection.name,
                                  style: Zt.display,
                                ),
                              ),
                            )
                          else
                            Text(
                              widget.collection.name,
                              maxLines: 2,
                              style: Zt.display,
                            ),
                          const SizedBox(height: 12),
                          MetaLine([
                            context.l10n.filmsInLibrary(owned),
                            years,
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: pageLeft,
                          right: 700,
                        ),
                        child: ClipRect(
                          child: AnimatedSwitcher(
                            duration: Zm.normal,
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topLeft,
                              children: [...previous, ?current],
                            ),
                            child: focus == null
                                ? const SizedBox.shrink()
                                : _FocusedFilm(
                                    key: ValueKey(focus),
                                    stop: focus,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: pageLeft,
                        top: 12,
                        bottom: 20,
                      ),
                      child: FocusZone(
                        debugLabel: 'collection-actions',
                        child: Row(
                          children: [
                            TvButton(
                              label: context.l10n.watchInOrder,
                              icon: Icons.play_arrow_rounded,
                              primary: true,
                              onSelect: _playFromStart,
                            ),
                            ValueListenableBuilder(
                              valueListenable: RequestStatuses.changed,
                              builder: (context, _, _) {
                                final missing = _requestable.length;
                                if (s.seerr == null || !(stops?.any((x) => x.media != null) ?? false)) {
                                  return const SizedBox.shrink();
                                }
                                final l10n = context.l10n;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 14),
                                  child: TvButton(
                                    label: _requesting
                                        ? l10n.requesting
                                        : missing == 0
                                            ? l10n.statusRequested
                                            : l10n.requestAllMissing(missing),
                                    icon: missing == 0 && !_requesting ? Icons.check_rounded : Icons.add_rounded,
                                    accent: Zc.request,
                                    onSelect: missing == 0 ? null : _requestAll,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      height: height * 0.44,
                      child: stops == null
                          ? const SizedBox.shrink()
                          : _timelineRow(stops),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _timelineRow(List<_Stop> stops) {
    return LayoutBuilder(
      builder: (context, box) {
        final cardW = ((box.maxHeight - 54 - 16 - 70) / 1.5).clamp(
          150.0,
          260.0,
        );
        return _buildTimeline(stops, cardW);
      },
    );
  }

  Widget _buildTimeline(List<_Stop> stops, double cardW) {
    return PointerScrollArrows(
      controller: _timeline,
      leftInset: pageLeft,
      child: _timelineList(stops, cardW),
    );
  }

  Widget _timelineList(List<_Stop> stops, double cardW) {
    return FocusZone(
      debugLabel: 'timeline',
      child: ListView.separated(
        controller: _timeline,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: pageLeft),
        itemCount: stops.length,
        separatorBuilder: (_, _) => const SizedBox(width: 30),
        itemBuilder: (context, i) {
          final stop = stops[i];
          final showYear = i == 0 || stops[i - 1].year != stop.year;
          return SizedBox(
            width: cardW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 54,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: -30,
                        right: i == stops.length - 1 ? cardW / 2 : -30,
                        top: 40,
                        child: Container(height: 2, color: Colors.white24),
                      ),
                      Positioned(
                        left: cardW / 2 - 7,
                        top: 34,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: stop.item != null ? Zc.accent : Zc.request,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (stop.item != null ? Zc.accent : Zc.request)
                                        .withValues(alpha: 0.7),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showYear)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: Text(
                            stop.year == 9999 ? context.l10n.tba : '${stop.year}',
                            textAlign: TextAlign.center,
                            style: Zt.label.copyWith(
                              color: Zc.textMuted,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (stop.item != null)
                  PosterCard(
                    item: stop.item!,
                    width: cardW,
                    autofocus: i == 0,
                    onFocus: () => _focused.set(stop),
                    onSelect: () => openItem(context, stop.item!),
                  )
                else
                  RequestPosterCard(
                    media: stop.media!,
                    width: cardW,
                    autofocus: i == 0,
                    onFocus: () => _focused.set(stop),
                    onSelect: () => openRequest(context, stop.media!),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FocusedFilm extends StatelessWidget {
  const _FocusedFilm({super.key, required this.stop});

  final _Stop stop;

  @override
  Widget build(BuildContext context) {
    final item = stop.item;
    final media = stop.media;
    final title = item?.name ?? media!.title;
    final overview = item?.overview ?? media?.overview;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (media != null) ...[
            RequestStateBuilder(
              media: media,
              builder: (context, availability, release) {
                final l10n = context.l10n;
                final requested = switch (availability) {
                  Availability.pending || Availability.processing => true,
                  _ => false,
                };
                final note = releaseNote(l10n, release, requested: requested);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        requested
                            ? Pill(
                                requestStatusLabel(l10n, availability, release: release).$1,
                                color: requestStatusLabel(l10n, availability, release: release).$2,
                                textColor: Zc.background,
                              )
                            : Pill(
                                l10n.notInLibraryBadge,
                                color: Zc.request,
                                textColor: Zc.background,
                              ),
                        if (release?.notOut ?? false) ...[
                          const SizedBox(width: 10),
                          ReleasePill(release),
                        ],
                      ],
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Zt.meta.copyWith(color: Zc.cinema),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Zt.headline,
          ),
          const SizedBox(height: 8),
          MetaLine(
            [
              stop.year == 9999 ? context.l10n.tba : '${stop.year}',
              if (item != null) formatRuntime(context.l10n, item.runtime),
              item?.officialRating,
              if (item != null && item.isPlayed) context.l10n.watched,
            ],
            leading: [
              if ((item?.communityRating ?? media?.voteAverage ?? 0) > 0)
                RatingPill(item?.communityRating ?? media!.voteAverage!),
            ],
          ),
          if (overview != null) ...[
            const SizedBox(height: 12),
            Text(
              overview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Zt.body,
            ),
          ],
        ],
      ),
    );
  }
}
