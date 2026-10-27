import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/recommendations.dart';
import '../../data/release_info.dart';
import '../../data/seerr_api.dart';
import '../../data/title_tags.dart';
import '../../l10n/l10n.dart';
import '../../playback/trailer/trailers.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/net_image.dart';
import '../widgets/trailer.dart';
import 'details_parts.dart';
import 'hero.dart';
import 'routes.dart';
import 'title_extras.dart';

class RequestPage extends StatefulWidget {
  const RequestPage({super.key, required this.media});

  final SeerrMedia media;

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  late SeerrMedia _media = widget.media;
  EmbyItem? _libraryItem;
  final _selectedSeasons = <int>{};
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  late final _trailer = TrailerController(AppServicesScope.read(context));
  final _trailerNode = FocusNode(debugLabel: 'trailer');
  List<TitleTag> _tags = const [];
  MixedItems _similar = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
    final s = AppServicesScope.read(context);
    final m = widget.media;
    _trailer.load(m.key, () => Trailers.forSeerr(s, m));
    s.titleTags?.of(m.tmdbId, m.type).then((v) {
      if (mounted) setState(() => _tags = v);
    });
    s.recommender.moreLikeThis(tmdbId: m.tmdbId, type: m.type, animated: m.genreIds.contains(16)).then((v) {
      if (mounted) setState(() => _similar = v);
    }).catchError((Object e) {
      debugPrint('[request] more like ${m.key}: $e');
    });
  }

  @override
  void dispose() {
    _trailer.dispose();
    _trailerNode.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = AppServicesScope.read(context);
    final seerr = s.seerr;
    if (seerr == null) return;
    try {
      final details = await seerr.details(_media.tmdbId, _media.type);
      EmbyItem? lib;
      if (details.availability.isOnServer) {
        try {
          lib = details.embyItemId != null
              ? await s.catalog.item(details.embyItemId!)
              : await s.catalog.byTmdbId(details.tmdbId, series: details.isTv);
        } catch (_) {
        }
      }
      RequestStatuses.record(details, details.availability);
      ReleaseInfos.record(details);
      if (!mounted) return;
      setState(() {
        _media = details;
        _libraryItem = lib;
        _selectedSeasons
          ..clear()
          ..addAll(_requestableSeasons);
      });
    } catch (e) {
      if (mounted) setState(() => _message = context.l10n.couldNotLoadDetails('$e'));
    }
  }

  Iterable<int> get _requestableSeasons =>
      _media.seasons.where((s) => s.number > 0 && s.availability == Availability.none).map((s) => s.number);

  Future<void> _request() async {
    final seerr = AppServicesScope.read(context).seerr;
    if (seerr == null || _busy) return;
    if (_media.isTv && _selectedSeasons.isEmpty) {
      UiSounds.play(UiSound.error);
      setState(() {
        _message = context.l10n.pickSeason;
        _messageIsError = true;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await seerr.request(_media, seasons: _media.isTv ? (_selectedSeasons.toList()..sort()) : null);
      RequestStatuses.record(_media, Availability.pending);
      if (!mounted) return;
      final waits = ReleaseInfos.of(_media)?.notOut ?? false;
      setState(() {
        _message = waits ? null : context.l10n.requestedMessage;
        _messageIsError = false;
      });
      await _refresh();
    } on SeerrException catch (e) {
      UiSounds.play(UiSound.error);
      if (!mounted) return;
      setState(() {
        _message = e.status == 403 ? context.l10n.requestNotAllowed : e.message;
        _messageIsError = true;
      });
    } catch (e) {
      UiSounds.play(UiSound.error);
      setState(() {
        _message = '$e';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _media;
    final l10n = context.l10n;
    final release = ReleaseInfos.of(m);
    final (statusLabel, statusColor) = requestStatusLabel(l10n, m.availability, release: release);
    final requested = switch (RequestStatuses.of(m)) {
      Availability.pending || Availability.processing => true,
      _ => false,
    };
    final note = releaseNote(l10n, release, requested: requested);
    final canRequest = m.availability.canRequest && (!m.isTv || _requestableSeasons.isNotEmpty);
    final size = MediaQuery.sizeOf(context);

    return Stack(children: [
      Positioned.fill(child: Backdrop(url: m.backdrop(), drift: true, dim: 0.15, video: TrailerVideo(controller: _trailer))),
      ListView(
        padding: EdgeInsets.only(top: size.height * 0.16, bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: pageLeft, right: 120),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Zs.radius),
                child: SizedBox(
                  width: 280,
                  height: 420,
                  child: NetImage(url: m.poster(width: 500), width: 280, fallback: TitleArt(title: m.title)),
                ),
              ),
              const SizedBox(width: 56),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Pill(statusLabel, color: statusColor, textColor: Zc.background),
                    if (release?.notOut ?? false) ...[const SizedBox(width: 10), ReleasePill(release)],
                    const SizedBox(width: 14),
                    Text(m.isTv ? l10n.series : l10n.movie, style: Zt.meta),
                  ]),
                  const SizedBox(height: 18),
                  Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.display),
                  const SizedBox(height: 14),
                  MetaLine(
                    [m.year?.toString(), if (m.runtimeMinutes != null) formatRuntime(l10n, Duration(minutes: m.runtimeMinutes!)), if (m.genres.isNotEmpty) m.genres.take(3).join(', ')],
                    leading: [if ((m.voteAverage ?? 0) > 0) RatingPill(m.voteAverage!)],
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 900,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline_rounded, size: 24, color: Zc.cinema),
                        const SizedBox(width: 10),
                        Expanded(child: Text(note, style: Zt.body.copyWith(color: Zc.cinema))),
                      ]),
                    ),
                  ],
                  if (m.tagline != null && m.tagline!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(m.tagline!, style: Zt.meta.copyWith(fontStyle: FontStyle.italic, color: Zc.text)),
                  ],
                  if (m.overview != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(width: 900, child: Text(m.overview!, maxLines: 5, overflow: TextOverflow.ellipsis, style: Zt.body)),
                  ],
                  const SizedBox(height: 34),
                  FocusZone(
                    debugLabel: 'request-actions',
                    child: Wrap(spacing: 18, children: [
                      if (_libraryItem != null)
                        TvButton(
                          label: l10n.openInLibrary,
                          icon: Icons.play_circle_rounded,
                          primary: true,
                          autofocus: true,
                          onSelect: () => Navigator.of(context).pushReplacement(itemRoute(_libraryItem!)),
                        ),
                      if (canRequest)
                        TvButton(
                          label: _busy
                              ? l10n.requesting
                              : m.isTv
                                  ? l10n.requestSeasons(_selectedSeasons.length)
                                  : l10n.request,
                          icon: Icons.add_circle_rounded,
                          primary: _libraryItem == null,
                          accent: Zc.request,
                          autofocus: _libraryItem == null,
                          onSelect: _request,
                        ),
                      if (!canRequest && _libraryItem == null)
                        TvButton(label: statusLabel, icon: Icons.schedule_rounded, autofocus: true, onSelect: () {}),
                      TrailerButtons(controller: _trailer, title: m.title, focusNode: _trailerNode),
                    ]),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(_message!, style: Zt.body.copyWith(color: _messageIsError ? Zc.danger : Zc.success)),
                    ),
                ]),
              ),
            ]),
          ),
          if (m.isTv && m.seasons.isNotEmpty) ...[
            const SizedBox(height: 50),
            Padding(
              padding: const EdgeInsets.only(left: pageLeft, bottom: 18),
              child: Text(l10n.seasons, style: Zt.rowTitle),
            ),
            Padding(
              padding: const EdgeInsets.only(left: pageLeft, right: 120),
              child: FocusZone(
                debugLabel: 'seasons',
                child: Wrap(spacing: 16, runSpacing: 16, children: [
                  for (final season in m.seasons.where((s) => s.number > 0)) _SeasonChip(
                    season: season,
                    selected: _selectedSeasons.contains(season.number),
                    onToggle: season.availability == Availability.none
                        ? () => setState(() => _selectedSeasons.contains(season.number)
                            ? _selectedSeasons.remove(season.number)
                            : _selectedSeasons.add(season.number))
                        : null,
                  ),
                ]),
              ),
            ),
          ],
          if (_tags.isNotEmpty) ...[const SizedBox(height: 50), TagRow(tags: _tags)],
          if (_similar.isNotEmpty) ...[const SizedBox(height: Zs.rowGap), MoreLikeThisRow(items: _similar)],
        ],
      ),
    ]);
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({required this.season, required this.selected, this.onToggle});

  final SeerrSeason season;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final locked = onToggle == null;
    final l10n = context.l10n;
    final (status, color) = requestStatusLabel(l10n, season.availability);
    return TvFocusable(
      onSelect: onToggle,
      builder: (context, focused) => AnimatedContainer(
        duration: Zm.fast,
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: focused ? Colors.white : Zc.surfaceHigh.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected && !focused ? Zc.request : Colors.transparent, width: 2),
        ),
        child: Row(children: [
          Icon(
            locked ? Icons.lock_outline_rounded : (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
            color: focused ? Zc.background : (selected ? Zc.request : Zc.textMuted),
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(season.name ?? l10n.seasonNumber(season.number), style: Zt.label.copyWith(color: focused ? Zc.background : Zc.text)),
              Text(
                locked ? status : (season.episodeCount == null ? l10n.episodes : l10n.episodeCount(season.episodeCount!)),
                style: Zt.caption.copyWith(color: focused ? Colors.black54 : (locked ? color : Zc.textFaint)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
