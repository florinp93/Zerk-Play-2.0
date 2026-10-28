import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/recommendations.dart';
import '../../data/seerr_api.dart';
import '../../data/title_tags.dart';
import '../../l10n/l10n.dart';
import '../../playback/trailer/trailers.dart';
import '../../playback/versions.dart';
import '../core/artwork.dart';
import '../core/input_mode.dart';
import '../core/playback_launcher.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/rows_scroll_view.dart';
import '../widgets/trailer.dart';
import 'details_parts.dart';
import 'hero.dart';
import 'routes.dart';
import 'title_extras.dart';

class SeriesPage extends StatefulWidget {
  const SeriesPage({super.key, required this.seriesId, this.focusEpisodeId, this.initialSeasonId});

  final String seriesId;

  final String? focusEpisodeId;
  final String? initialSeasonId;

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  EmbyItem? _series;
  List<EmbyItem> _seasons = const [];
  final _episodes = <String, List<EmbyItem>>{};
  String? _seasonId;
  EmbyItem? _nextUp;
  MixedItems _similar = const [];
  List<TitleTag> _tags = const [];
  Object? _error;

  final _scroll = RevealController(mode: RevealMode.minimal, margin: 160);
  final _playNode = FocusNode(debugLabel: 'series-play');
  final _seasonNodes = <String, FocusNode>{};
  final _episodeNodes = <String, FocusNode>{};
  late final _trailer = TrailerController(AppServicesScope.read(context));
  final _trailerNode = FocusNode(debugLabel: 'trailer');

  @override
  void initState() {
    super.initState();
    _load(focusEpisodeId: widget.focusEpisodeId, seasonId: widget.initialSeasonId);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _playNode.dispose();
    _trailer.dispose();
    _trailerNode.dispose();
    for (final n in [..._seasonNodes.values, ..._episodeNodes.values]) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode _seasonNode(String id) => _seasonNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'season:$id'));
  FocusNode _episodeNode(String id) => _episodeNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'episode:$id'));

  Future<void> _load({String? focusEpisodeId, String? seasonId}) async {
    final c = AppServicesScope.read(context).catalog;
    try {
      final results = await Future.wait([
        c.item(widget.seriesId),
        c.seasons(widget.seriesId),
        c.nextUp(seriesId: widget.seriesId, limit: 1),
      ]);
      if (!mounted) return;
      final series = results[0] as EmbyItem;
      final seasons = _orderSeasons(results[1] as List<EmbyItem>);
      final nextUp = (results[2] as List<EmbyItem>).firstOrNull;

      String? focusSeason = seasonId;
      EmbyItem? focusEpisode;
      if (focusEpisodeId != null) {
        focusEpisode = await c.item(focusEpisodeId);
        focusSeason ??= focusEpisode.seasonId;
      }
      focusSeason ??= nextUp?.seasonId ??
          seasons.where((s) => (s.unplayedItemCount ?? 0) > 0 && (s.indexNumber ?? 0) > 0).firstOrNull?.id ??
          seasons.firstOrNull?.id;

      setState(() {
        _series = series;
        _seasons = seasons;
        _nextUp = nextUp;
        _seasonId = focusSeason;
        _error = null;
        _episodes.clear();
      });
      if (focusSeason != null) await _loadEpisodes(focusSeason);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = focusEpisode == null ? null : _episodeNodes[focusEpisode.id];
        (target ?? _playNode).requestFocus();
      });
      final services = AppServicesScope.read(context);
      final tmdbId = series.tmdbId;
      if (tmdbId != null) {
        services.titleTags?.of(tmdbId, SeerrMediaType.tv).then((v) {
          if (mounted) setState(() => _tags = v);
        });
      }
      final animated = RecommendationFilter.isAnimated(series);
      services.recommender
          .moreLikeThis(embyId: series.id, tmdbId: tmdbId, type: SeerrMediaType.tv, animated: animated)
          .then((v) {
        if (mounted) setState(() => _similar = v);
      }).catchError((Object e) {
        debugPrint('[series] more like ${series.id}: $e');
      });
      _trailer.load(series.id, () => Trailers.forItem(services, series));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static List<EmbyItem> _orderSeasons(List<EmbyItem> seasons) {
    final regular = seasons.where((s) => (s.indexNumber ?? 1) > 0).toList()
      ..sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
    return [...regular, ...seasons.where((s) => s.indexNumber == 0)];
  }

  Future<void> _loadEpisodes(String seasonId) async {
    if (_episodes.containsKey(seasonId)) return;
    final c = AppServicesScope.read(context).catalog;
    final eps = await c.episodes(widget.seriesId, seasonId: seasonId);
    if (mounted) setState(() => _episodes[seasonId] = eps);
  }

  void _selectSeason(String id) {
    if (id == _seasonId) return;
    setState(() => _seasonId = id);
    _loadEpisodes(id);
  }

  Future<void> _playEpisode(EmbyItem episode, {bool fromStart = false}) async {
    final s = AppServicesScope.read(context);
    final pref = s.settings.versionPreferences[widget.seriesId];
    final source = episode.mediaSources.isEmpty ? null : pickVersion(episode.mediaSources, preferenceKey: pref);
    final outcome = await playItem(context, episode, start: fromStart ? Duration.zero : null, mediaSourceId: source?.id);
    if (!mounted || outcome == null) return;
    final last = outcome.lastItem ?? episode;
    await _load(focusEpisodeId: last.id, seasonId: last.seasonId);
  }

  Future<void> _openEpisode(EmbyItem episode) async {
    await Navigator.of(context).push(detailsRoute(episode));
    if (!mounted) return;
    await _load(focusEpisodeId: episode.id, seasonId: episode.seasonId);
  }

  Future<void> _playMain() async {
    final next = _nextUp;
    if (next != null) return _playEpisode(next);
    final first = _seasons.firstOrNull;
    if (first == null) return;
    await _loadEpisodes(first.id);
    final ep = _episodes[first.id]?.where((e) => e.isPlayable).firstOrNull;
    if (ep != null) await _playEpisode(ep);
  }

  Future<void> _toggleWatched() async {
    final series = _series!;
    try {
      final services = AppServicesScope.read(context);
      await services.catalog.setPlayed(series.id, !series.isPlayed);
      services.markLibraryChanged();
      await _load();
    } catch (_) {
      UiSounds.play(UiSound.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = _series;
    if (series == null) {
      return _error == null
          ? const Center(child: SkeletonBox(width: 600, height: 140))
          : Center(child: Text('${context.l10n.couldNotLoadShow}\n$_error', style: Zt.body, textAlign: TextAlign.center));
    }
    final s = AppServicesScope.of(context);
    final c = s.catalog;
    final l10n = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final episodes = _seasonId == null ? null : _episodes[_seasonId];
    final next = _nextUp;
    final playLabel = next == null
        ? l10n.play
        : next.resumePosition != null
            ? l10n.resumeEpisode(next.episodeCode ?? '')
            : l10n.playEpisode(next.episodeCode ?? '');

    return Stack(children: [
      Positioned.fill(child: Backdrop(url: c.backdrop(series), drift: true, video: TrailerVideo(controller: _trailer))),
      PageScrollView(
        controller: _scroll,
        padding: EdgeInsets.only(top: size.height * 0.16, bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: pageLeft, right: 700),
            child: TitleBlock(
              item: series,
              logo: c.logo(series),
              extraMeta: [
                _years(l10n, series),
                l10n.seasonCount(_seasons.where((s) => (s.indexNumber ?? 1) > 0).length),
                series.officialRating,
                if (series.genres.isNotEmpty) series.genres.take(3).join(', '),
              ],
            ),
          ),
          if (series.overview != null)
            Padding(
              padding: const EdgeInsets.only(left: pageLeft, right: 760, top: 22),
              child: Text(series.overview!, maxLines: 3, overflow: TextOverflow.ellipsis, style: Zt.body),
            ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(left: pageLeft, top: 18),
              child: Text(l10n.upNextEpisode('${next.episodeCode ?? ''}  ${next.name}'), style: Zt.meta.copyWith(color: Zc.text)),
            ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.only(left: pageLeft),
            child: FocusZone(
              debugLabel: 'series-actions',
              revealsTop: true,
              child: Wrap(spacing: 18, children: [
                TvButton(focusNode: _playNode, label: playLabel, icon: Icons.play_arrow_rounded, primary: true, onSelect: _playMain),
                if (next?.resumePosition != null)
                  TvButton(label: l10n.fromBeginning, icon: Icons.replay_rounded, onSelect: () => _playEpisode(next!, fromStart: true)),
                TrailerButtons(controller: _trailer, title: series.name, focusNode: _trailerNode, collapsed: true),
                TvButton(
                  label: series.isPlayed ? l10n.watched : l10n.markWatched,
                  icon: series.isPlayed ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                  collapsed: true,
                  onSelect: _toggleWatched,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 56),
          if (_seasons.length > 1) _seasonStrip(),
          if (episodes == null)
            const SkeletonRow(cardWidth: Zs.landscapeWidth, cardHeight: Zs.landscapeWidth * 9 / 16)
          else
            MediaRow(
              key: ValueKey('episodes:$_seasonId'),
              left: pageLeft,
              title: _seasons.length == 1 ? (_seasons.first.name) : l10n.episodes,
              height: Zs.landscapeWidth * 9 / 16 + 110,
              itemCount: episodes.length,
              itemBuilder: (context, i) {
                final e = episodes[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: Zs.landscapeWidth,
                    child: LandscapeCard(
                      focusNode: _episodeNode(e.id),
                      item: e,
                      title: '${e.indexNumber ?? '•'}${e.indexNumberEnd != null ? '-${e.indexNumberEnd}' : ''}. ${e.name}',
                      subtitle: [
                        formatRuntime(l10n, e.runtime),
                        if (e.hasVersions) l10n.versionCount(e.mediaSources.length),
                        if (e.isVirtual && e.premiereDate != null) l10n.airsOn(formatDate(l10n, e.premiereDate!.toLocal())),
                      ].whereType<String>().join('  ·  '),
                      onSelect: () => _openEpisode(e),
                      onMenu: () => _playEpisode(e),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: Zs.rowGap),
          CastRow(people: series.people),
          if (_tags.isNotEmpty) ...[const SizedBox(height: Zs.rowGap), TagRow(tags: _tags)],
          if (_similar.isNotEmpty) ...[const SizedBox(height: Zs.rowGap), MoreLikeThisRow(items: _similar)],
        ],
      ),
    ]);
  }

  Widget _seasonStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: SizedBox(
        height: 64,
        child: FocusZone(
          debugLabel: 'seasons',
          preferredEntry: () => _seasonId == null ? null : _seasonNodes[_seasonId!],
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: pageLeft),
            itemCount: _seasons.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final season = _seasons[i];
              final selected = season.id == _seasonId;
              final unwatched = season.unplayedItemCount ?? 0;
              return TvFocusable(
                focusNode: _seasonNode(season.id),
                onFocusChange: (f) => f && !InputMode.isPointer ? _selectSeason(season.id) : null,
                onSelect: () => InputMode.isPointer
                    ? _selectSeason(season.id)
                    : ZoneNavigator.move(TraversalDirection.down),
                selectSound: InputMode.isPointer ? UiSound.select : null,
                builder: (context, focused) => AnimatedContainer(
                  duration: Zm.fast,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: focused ? Colors.white : (selected ? Colors.white.withValues(alpha: 0.16) : Colors.transparent),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: selected || focused ? Colors.transparent : Zc.outline),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(season.indexNumber == 0 ? context.l10n.specials : season.name,
                        style: Zt.label.copyWith(color: focused ? Zc.background : Zc.text, fontSize: 22)),
                    if (season.isPlayed) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.check_rounded, size: 22, color: focused ? Zc.accent : Zc.accentSoft),
                    ] else if (unwatched > 0) ...[
                      const SizedBox(width: 10),
                      Text('$unwatched', style: Zt.caption.copyWith(color: focused ? Zc.accent : Zc.accentSoft, fontWeight: FontWeight.w800)),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String? _years(L10n l10n, EmbyItem s) {
    final start = s.productionYear;
    if (start == null) return null;
    if (s.status == 'Continuing') return l10n.yearsToPresent(start);
    final end = s.endDate?.year;
    return end == null || end == start ? '$start' : '$start – $end';
  }
}
