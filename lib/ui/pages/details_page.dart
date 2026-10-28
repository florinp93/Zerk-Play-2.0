import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../core/emby/models/media_source.dart';
import '../../data/recommendations.dart';
import '../../data/seerr_api.dart';
import '../../data/title_tags.dart';
import '../../l10n/l10n.dart';
import '../../playback/player_settings.dart';
import '../../playback/trailer/trailers.dart';
import '../../playback/track_labels.dart';
import '../../playback/track_policy.dart';
import '../../playback/versions.dart';
import '../core/artwork.dart';
import '../core/playback_launcher.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/rows_scroll_view.dart';
import '../widgets/side_panel.dart';
import '../widgets/trailer.dart';
import 'details_parts.dart';
import 'hero.dart';
import 'routes.dart';
import 'title_extras.dart';

class DetailsPage extends StatefulWidget {
  const DetailsPage({super.key, required this.itemId, this.initial});

  final String itemId;
  final EmbyItem? initial;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  EmbyItem? _item;
  Object? _error;
  MediaSourceInfo? _source;
  int? _audio;
  int? _subtitle;
  bool _tracksTouched = false;
  PlayerSettings _player = const PlayerSettings();
  MixedItems _similar = const [];
  List<TitleTag> _tags = const [];
  List<EmbyItem> _siblings = const [];
  List<ChapterInfo> _chapters = const [];
  ({EmbyItem collection, List<EmbyItem> films, int? total})? _collection;

  List<SeerrMedia> _collectionRequestable = const [];
  final _scroll = RevealController(mode: RevealMode.minimal, margin: 140);
  final _playNode = FocusNode(debugLabel: 'play');
  late final _trailer = TrailerController(AppServicesScope.read(context));
  final _trailerNode = FocusNode(debugLabel: 'trailer');

  @override
  void initState() {
    super.initState();
    _item = widget.initial;
    _load(widget.itemId);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _playNode.dispose();
    _trailer.dispose();
    _trailerNode.dispose();
    super.dispose();
  }

  Future<void> _load(String id, {bool focusPlay = true}) async {
    final s = AppServicesScope.read(context);
    try {
      final results = await Future.wait([s.catalog.item(id), PlayerSettings.load()]);
      final item = results[0] as EmbyItem;
      _player = results[1] as PlayerSettings;
      debugPrint('[details] ${item.type} "${item.name}" (${item.id}): resume ${item.resumePosition ?? 'none'}, '
          'played ${item.isPlayed}, ${item.mediaSources.length} version(s), tmdb ${item.tmdbId ?? '-'}');
      if (!mounted) return;
      setState(() {
        _item = item;
        _error = null;
        _selectSource(_preferredSource(item));
      });
      if (focusPlay) WidgetsBinding.instance.addPostFrameCallback((_) => _playNode.requestFocus());
      _trailer.load(item.id, () => Trailers.forItem(s, item));
      s.playback.chapters(item, fetch: false).then((v) {
        if (mounted && _item?.id == item.id) setState(() => _chapters = v);
      }).catchError((Object e) {
        debugPrint('[details] chapters of ${item.id}: $e');
      });
      _loadExtras(s, item);
      if (item.isMovie) {
        s.catalog.collectionOf(item).then((v) {
          debugPrint('[details] collection of ${item.name}: ${v == null ? 'none' : '${v.collection.name} (${v.films.length} films)'}');
          if (mounted) setState(() => _collection = v);
          final cid = v?.collection.tmdbId;
          final seerr = s.seerr;
          if (v == null || cid == null || seerr == null) return;
          seerr.collectionParts(cid).then((parts) {
            final owned = {for (final f in v.films) ?f.tmdbId};
            final missing = [for (final p in parts) if (!owned.contains(p.tmdbId) && !p.availability.isOnServer) p];
            if (mounted) setState(() => _collectionRequestable = missing);
          }).catchError((Object e) {
            debugPrint('[details] collection parts of $cid: $e');
          });
        }).catchError((Object e) {
          debugPrint('[details] collection of ${item.id}: $e');
        });
      }
      if (item.isEpisode && item.seriesId != null) {
        s.catalog.episodes(item.seriesId!, seasonId: item.seasonId).then((v) {
          if (mounted) setState(() => _siblings = v);
        }).catchError((_) {});
      }
    } catch (e) {
      debugPrint('[details] loading $id failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadExtras(AppServices s, EmbyItem item) async {
    var title = item;
    if (item.isEpisode && item.seriesId != null) {
      try {
        title = await s.catalog.item(item.seriesId!);
      } catch (_) {
        return;
      }
    }
    final type = title.isSeries ? SeerrMediaType.tv : SeerrMediaType.movie;
    final tmdbId = title.tmdbId;
    if (tmdbId != null) {
      s.titleTags?.of(tmdbId, type).then((v) {
        if (mounted) setState(() => _tags = v);
      });
    }
    final animated = RecommendationFilter.isAnimated(title);
    s.recommender.moreLikeThis(embyId: title.id, tmdbId: tmdbId, type: type, animated: animated).then((v) {
      if (mounted) setState(() => _similar = v);
    }).catchError((Object e) {
      debugPrint('[details] more like ${title.id}: $e');
    });
  }

  String _prefScope(EmbyItem i) => i.seriesId ?? i.id;

  MediaSourceInfo? _preferredSource(EmbyItem item) {
    if (item.mediaSources.isEmpty) return null;
    final pref = AppServicesScope.read(context).settings.versionPreferences[_prefScope(item)];
    return pickVersion(item.mediaSources, preferenceKey: pref);
  }

  void _selectSource(MediaSourceInfo? next) {
    final previous = _source;
    _source = next;
    if (next == null) return;
    if (previous != null && _tracksTouched) {
      final oldAudio = _audio == null ? null : previous.streamByIndex(_audio!);
      final oldSub = _subtitle == null ? null : previous.streamByIndex(_subtitle!);
      final policy = TrackPolicy.choose(next, _player);
      _audio = TrackMatcher.match(oldAudio, next.audioStreams)?.index ?? policy.audioIndex;
      _subtitle = oldSub == null ? null : (TrackMatcher.match(oldSub, next.subtitleStreams)?.index ?? policy.subtitleIndex);
    } else {
      final policy = TrackPolicy.choose(next, _player);
      _audio = policy.audioIndex;
      _subtitle = policy.subtitleIndex;
    }
  }

  Future<void> _pickVersion() async {
    final item = _item!;
    final chosen = await showSidePanel<MediaSourceInfo>(
      context,
      title: context.l10n.version,
      options: [
        for (final src in item.mediaSources)
          PanelOption(
            value: src,
            title: VersionInfo(src).label,
            subtitle: VersionInfo(src).summary,
            selected: src.id == _source?.id,
            icon: VersionInfo(src).is4k ? Icons.four_k_rounded : Icons.hd_rounded,
          ),
      ],
    );
    if (chosen == null || !mounted) return;
    setState(() => _selectSource(chosen));
    final s = AppServicesScope.read(context);
    final prefs = Map<String, String>.from(s.settings.versionPreferences)
      ..[_prefScope(item)] = VersionInfo(chosen).preferenceKey;
    await s.updateSettings(s.settings.copyWith(versionPreferences: prefs));
  }

  Future<void> _pickAudio() async {
    final src = _source;
    if (src == null) return;
    final l10n = context.l10n;
    final chosen = await showSidePanel<int>(
      context,
      title: l10n.audio,
      options: [
        for (final a in src.audioStreams)
          PanelOption(value: a.index, title: TrackLabels.title(a, l10n), subtitle: TrackLabels.detail(a, l10n), selected: a.index == _audio),
      ],
    );
    if (chosen != null && mounted) {
      setState(() {
        _audio = chosen;
        _tracksTouched = true;
      });
    }
  }

  Future<void> _pickSubtitle() async {
    final src = _source;
    if (src == null) return;
    final l10n = context.l10n;
    final chosen = await showSidePanel<int>(
      context,
      title: l10n.subtitles,
      options: [
        PanelOption(value: -1, title: l10n.subtitleOff, selected: _subtitle == null),
        for (final s in src.subtitleStreams)
          PanelOption(value: s.index, title: TrackLabels.title(s, l10n), subtitle: TrackLabels.detail(s, l10n), selected: s.index == _subtitle),
      ],
    );
    if (chosen != null && mounted) {
      setState(() {
        _subtitle = chosen < 0 ? null : chosen;
        _tracksTouched = true;
      });
    }
  }

  Future<void> _play({bool fromStart = false, Duration? at}) async {
    final item = _item;
    if (item == null) return;
    final outcome = await playItem(
      context,
      item,
      start: at ?? (fromStart ? Duration.zero : null),
      mediaSourceId: _source?.id,
      audioIndex: _audio,
      subtitleIndex: _subtitle ?? -1,
    );
    if (!mounted || outcome == null) return;
    await _load(outcome.lastItem?.id ?? item.id);
  }

  Future<void> _toggleWatched() async {
    final item = _item!;
    final s = AppServicesScope.read(context);
    try {
      await s.catalog.setPlayed(item.id, !item.isPlayed);
      setState(() => _item = item.copyWithUserData(isPlayed: !item.isPlayed, playbackPositionTicks: 0));
      s.markLibraryChanged();
    } catch (_) {
      UiSounds.play(UiSound.error);
    }
  }

  Future<void> _toggleFavorite() async {
    final item = _item!;
    final s = AppServicesScope.read(context);
    try {
      await s.catalog.setFavorite(item.id, !item.isFavorite);
      setState(() => _item = item.copyWithUserData(isFavorite: !item.isFavorite));
      s.markLibraryChanged();
    } catch (_) {
      UiSounds.play(UiSound.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (item == null) {
      return _error != null ? _ErrorView(error: _error!, onRetry: () => _load(widget.itemId)) : const _Loading();
    }
    final s = AppServicesScope.of(context);
    final c = s.catalog;
    final l10n = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final resume = item.resumePosition;
    final audio = _source == null || _audio == null ? null : _source!.streamByIndex(_audio!);
    final sub = _source == null || _subtitle == null ? null : _source!.streamByIndex(_subtitle!);

    return Stack(children: [
      Positioned.fill(
        child: Backdrop(
          url: c.backdrop(item) ?? c.landscape(item, width: 1600),
          drift: true,
          video: TrailerVideo(controller: _trailer),
        ),
      ),
      PageScrollView(
        controller: _scroll,
        padding: EdgeInsets.only(top: size.height * 0.2, bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: pageLeft, right: 700),
            child: TitleBlock(item: item, logo: c.logo(item), source: _source, extraMeta: standardMeta(l10n, item)),
          ),
          const SizedBox(height: 22),
          if (item.tagline != null)
            Padding(
              padding: const EdgeInsets.only(left: pageLeft, bottom: 10),
              child: Text(item.tagline!, style: Zt.meta.copyWith(fontStyle: FontStyle.italic, color: Zc.text)),
            ),
          if (item.overview != null)
            Padding(
              padding: const EdgeInsets.only(left: pageLeft, right: 760),
              child: Text(item.overview!, maxLines: 4, overflow: TextOverflow.ellipsis, style: Zt.body),
            ),
          const SizedBox(height: 34),
          Padding(
            padding: const EdgeInsets.only(left: pageLeft, right: 120),
            child: FocusZone(
              debugLabel: 'actions',
              revealsTop: true,
              child: Wrap(spacing: 18, runSpacing: 18, children: [
                if (item.isPlayable)
                  TvButton(
                    focusNode: _playNode,
                    label: resume != null ? l10n.resumeTimeLeft(formatRuntime(l10n, (item.runtime ?? resume) - resume) ?? '') : l10n.play,
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    onSelect: _play,
                  ),
                if (resume != null)
                  TvButton(label: l10n.fromBeginning, icon: Icons.replay_rounded, onSelect: () => _play(fromStart: true)),
                if (item.mediaSources.length > 1)
                  TvButton(
                    label: _source == null ? l10n.version : VersionInfo(_source!).label,
                    icon: Icons.layers_rounded,
                    onSelect: _pickVersion,
                  ),
                if ((_source?.subtitleStreams.length ?? 0) > 0)
                  TvButton(
                    label: sub == null
                        ? l10n.subtitlesOff
                        : sub.isForced
                            ? l10n.forcedTrack(TrackLabels.title(sub, l10n))
                            : TrackLabels.title(sub, l10n),
                    icon: Icons.subtitles_rounded,
                    collapsed: true,
                    onSelect: _pickSubtitle,
                  ),
                TrailerButtons(controller: _trailer, title: item.name, focusNode: _trailerNode, collapsed: true),
                if ((_source?.audioStreams.length ?? 0) > 1)
                  TvButton(
                    label: audio == null ? l10n.audio : '${TrackLabels.title(audio, l10n)} · ${TrackLabels.audioCodec(audio)}',
                    icon: Icons.graphic_eq_rounded,
                    collapsed: true,
                    onSelect: _pickAudio,
                  ),
                TvButton(
                  label: item.isPlayed ? l10n.watched : l10n.markWatched,
                  icon: item.isPlayed ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                  collapsed: true,
                  onSelect: _toggleWatched,
                ),
                TvButton(
                  label: l10n.favorite,
                  icon: item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  collapsed: true,
                  onSelect: _toggleFavorite,
                ),
                if (item.isEpisode && item.seriesId != null)
                  TvButton(
                    label: l10n.goToSeries,
                    icon: Icons.tv_rounded,
                    collapsed: true,
                    onSelect: () => openSeries(context, item.seriesId!, focusEpisodeId: item.id),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 60),
          if (_siblings.length > 1) ...[
            MediaRow(
              left: pageLeft,
              title: item.seasonName ?? l10n.episodes,
              height: Zs.landscapeWidth * 9 / 16 + 90,
              itemCount: _siblings.length,
              itemBuilder: (context, i) {
                final e = _siblings[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LandscapeCard(
                    item: e,
                    title: '${e.indexNumber ?? ''}. ${e.name}',
                    subtitle: e.id == item.id ? l10n.nowShowing : formatRuntime(l10n, e.runtime),
                    onSelect: () {
                      if (e.id != item.id) Navigator.of(context).pushReplacement(detailsRoute(e));
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: Zs.rowGap),
          ],
          if (_collection case final col?) ...[
            CollectionHighlight(
              collection: col.collection,
              films: col.films,
              requestable: _collectionRequestable,
              current: item,
              total: col.total,
              onCurrent: () {
                _playNode.requestFocus();
                _scroll.animateTo(0, duration: Zm.normal, curve: Zm.curve);
              },
            ),
            const SizedBox(height: 60),
          ],
          if (ChaptersRow.worthShowing(_chapters)) ...[
            ChaptersRow(item: item, chapters: _chapters, onPlay: (at) => _play(at: at)),
            const SizedBox(height: Zs.rowGap),
          ],
          CastRow(people: item.people),
          if (_tags.isNotEmpty) ...[const SizedBox(height: Zs.rowGap), TagRow(tags: _tags)],
          if (_similar.isNotEmpty) ...[const SizedBox(height: Zs.rowGap), MoreLikeThisRow(items: _similar)],
          if (_source != null) _TechInfo(source: _source!),
        ],
      ),
    ]);
  }
}

class _TechInfo extends StatelessWidget {
  const _TechInfo({required this.source});

  final MediaSourceInfo source;

  @override
  Widget build(BuildContext context) {
    final v = VersionInfo(source);
    return Padding(
      padding: const EdgeInsets.only(left: pageLeft, top: 50, right: 120),
      child: Text(
        [v.summary, ?v.bitrate, ?source.container?.toUpperCase(), ?source.path?.split(RegExp(r'[\\/]')).last].join('   ·   '),
        style: Zt.caption,
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: pageLeft, top: 240),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SkeletonBox(width: 520, height: 120),
          SizedBox(height: 24),
          SkeletonBox(width: 420, height: 28, radius: 6),
          SizedBox(height: 24),
          SkeletonBox(width: 900, height: 90, radius: 8),
        ]),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: pageLeft, top: 240),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.l10n.couldNotLoadTitle, style: Zt.headline),
          const SizedBox(height: 12),
          Text('$error', style: Zt.body, maxLines: 3),
          const SizedBox(height: 30),
          FocusZone(child: TvButton(label: context.l10n.tryAgain, icon: Icons.refresh_rounded, autofocus: true, onSelect: onRetry)),
        ]),
      );
}
