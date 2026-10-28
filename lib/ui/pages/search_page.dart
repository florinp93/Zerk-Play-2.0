import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../core/host.dart';
import '../../data/catalog_api.dart';
import '../../data/recommendations.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/playback_launcher.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/media_row.dart';
import '../widgets/tv_keyboard.dart';
import 'routes.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _field = FocusNode(debugLabel: 'search-field');
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  List<EmbyItem> _movies = const [];
  List<EmbyItem> _shows = const [];
  List<EmbyItem> _episodes = const [];
  List<EmbyItem> _collections = const [];
  List<SeerrMedia> _requestable = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(text.trim()));
  }

  Future<void> _search(String q) async {
    if (q == _query) return;
    _query = q;
    if (q.length < 2) {
      setState(() {
        _movies = _shows = _episodes = _collections = const [];
        _requestable = const [];
      });
      return;
    }
    setState(() => _searching = true);
    final s = AppServicesScope.read(context);
    final c = s.catalog;
    final external = s.tmdb == null && s.seerr == null
        ? null
        : s.recommender.search(q).then(s.recommender.resolve).then<MixedItems?>((v) => v, onError: (Object e) {
            debugPrint('[search] TMDB / *seerr: $e');
            return null;
          });
    final results = await Future.wait([
      c.query(searchTerm: q, types: ['Movie'], limit: 30, sortBy: 'SortName').then((p) => p.items).catchError((_) => <EmbyItem>[]),
      c.query(searchTerm: q, types: ['Series'], limit: 30, sortBy: 'SortName').then((p) => p.items).catchError((_) => <EmbyItem>[]),
      c.query(searchTerm: q, types: ['Episode'], limit: 30, sortBy: 'SortName').then((p) => p.items).catchError((_) => <EmbyItem>[]),
      _matchingCollections(c, q),
    ]);
    final movies = [...results[0]], shows = [...results[1]];
    if (!mounted || q != _query) return;
    setState(() {
      _movies = movies;
      _shows = shows;
      _episodes = results[2];
      _collections = results[3];
      _requestable = const [];
      _searching = external != null;
    });
    if (external == null) return;
    final resolved = await external ?? const [];
    if (!mounted || q != _query) return;
    final have = {for (final i in [...movies, ...shows]) i.id};
    final owned = {for (final i in [...movies, ...shows]) ?i.tmdbId};
    for (final item in resolved.whereType<EmbyItem>()) {
      if (!have.add(item.id)) continue;
      (item.isSeries ? shows : movies).add(item);
    }
    setState(() {
      _movies = [...movies];
      _shows = [...shows];
      _requestable = s.seerr == null
          ? const []
          : [
              for (final m in resolved.whereType<SeerrMedia>())
                if (!m.availability.isOnServer && !owned.contains(m.tmdbId)) m,
            ];
      _searching = false;
    });
  }

  static Future<List<EmbyItem>> _matchingCollections(CatalogApi c, String q) async {
    final words = _fold(q).split(' ').where((w) => w.isNotEmpty).toList();
    try {
      final all = await c.allCollections().timeout(const Duration(seconds: 8));
      return [
        for (final col in all)
          if (words.every(_fold(col.name).contains)) col,
      ].take(30).toList();
    } catch (e) {
      debugPrint('[search] collections: $e');
      return const [];
    }
  }

  static const _accents = {'ă': 'a', 'â': 'a', 'á': 'a', 'à': 'a', 'ä': 'a', 'î': 'i', 'í': 'i', 'ș': 's', 'ş': 's',
      'ț': 't', 'ţ': 't', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ó': 'o', 'ö': 'o', 'ô': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c'};

  static String _fold(String s) =>
      s.toLowerCase().split('').map((ch) => _accents[ch] ?? ch).join().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');

  @override
  Widget build(BuildContext context) {
    final nothing = _query.length >= 2 && !_searching && _movies.isEmpty && _shows.isEmpty &&
        _episodes.isEmpty && _collections.isEmpty && _requestable.isEmpty;
    return ListView(
      padding: const EdgeInsets.only(top: 70, bottom: 140),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: contentLeft, right: 600, bottom: 28),
          child: FocusZone(
            debugLabel: 'search-field',
            child: ListenableBuilder(
              listenable: _field,
              builder: (context, _) => AnimatedContainer(
                duration: Zm.fast,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
                decoration: BoxDecoration(
                  color: _field.hasFocus ? Zc.surfaceTop : Zc.surface,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: _field.hasFocus ? Colors.white : Zc.outline, width: 2),
                ),
                child: Row(children: [
                  const Icon(Icons.search_rounded, size: 34, color: Zc.textMuted),
                  const SizedBox(width: 18),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _field,
                      autofocus: true,
                      keyboardType: Host.isAndroid ? TextInputType.none : null,
                      onChanged: _onChanged,
                      onSubmitted: (v) {
                        _search(v.trim());
                        ZoneNavigator.move(TraversalDirection.down);
                      },
                      style: Zt.title.copyWith(fontWeight: FontWeight.w500),
                      cursorColor: Zc.accent,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: context.l10n.searchHint,
                        hintStyle: Zt.title.copyWith(color: Zc.textFaint, fontWeight: FontWeight.w400),
                      ),
                    ),
                  ),
                  if (_searching) const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
                ]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: contentLeft, bottom: 40),
          child: TvKeyboard(controller: _controller, onChanged: _onChanged),
        ),
        if (nothing)
          Padding(
            padding: const EdgeInsets.only(left: contentLeft),
            child: Text(context.l10n.noResultsFor(_query), style: Zt.body),
          ),
        if (_movies.isNotEmpty) _posterRow(context.l10n.movies, _movies),
        if (_shows.isNotEmpty) _posterRow(context.l10n.shows, _shows),
        if (_collections.isNotEmpty) _posterRow(context.l10n.collections, _collections),
        if (_episodes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Zs.rowGap),
            child: MediaRow(
              title: context.l10n.episodes,
              height: Zs.landscapeWidth * 9 / 16 + 90,
              itemCount: _episodes.length,
              itemBuilder: (context, i) {
                final e = _episodes[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LandscapeCard(
                    item: e,
                    title: e.seriesName ?? e.name,
                    subtitle: [e.episodeCode, e.name].whereType<String>().join('  '),
                    onSelect: () => openItem(context, e),
                    onPlay: () => playItem(context, e),
                  ),
                );
              },
            ),
          ),
        if (_requestable.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Zs.rowGap),
            child: MediaRow(
              title: context.l10n.notInLibrary,
              trailingTitle: Text(context.l10n.requestWithSeerr, style: Zt.caption.copyWith(color: Zc.request)),
              height: Zs.posterWidth * 1.5 + 90,
              itemCount: _requestable.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: RequestPosterCard(media: _requestable[i], onSelect: () => openRequest(context, _requestable[i])),
              ),
            ),
          ),
      ],
    );
  }

  Widget _posterRow(String title, List<EmbyItem> items) => Padding(
        padding: const EdgeInsets.only(bottom: Zs.rowGap),
        child: MediaRow(
          title: title,
          trailingTitle: Text(context.l10n.inYourLibrary, style: Zt.caption.copyWith(color: Zc.accentSoft)),
          height: Zs.posterWidth * 1.5 + 90,
          itemCount: items.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: PosterCard(item: items[i], onSelect: () => openItem(context, items[i])),
          ),
        ),
      );
}
