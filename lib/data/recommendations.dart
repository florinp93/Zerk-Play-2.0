import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import 'catalog_api.dart';
import 'seerr_api.dart';
import 'title_tags.dart';
import 'tmdb_api.dart';

abstract final class RecommendationFilter {
  static const _excludedGenres = {10763, 10764, 10767};
  static const _animation = 16;

  static const _excludedLanguages = {
    'hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'pa', 'gu', 'or', 'as', 'ur', 'sa', 'bho', 'ks', 'sd', 'ne', 'si',
  };

  static bool hideAnimation = true;

  static bool keep(SeerrMedia m) {
    if (m.genreIds.any(_excludedGenres.contains)) return false;
    if (hideAnimation && m.genreIds.contains(_animation)) return false;
    final lang = m.originalLanguage;
    if (lang != null && _excludedLanguages.contains(lang)) return false;
    if (m.genreIds.contains(_animation) && (lang == 'ja' || lang == 'zh' || lang == 'ko')) return false;
    return true;
  }

  static bool isAnimated(EmbyItem i) => i.genres.any((g) => g.toLowerCase().contains('anim'));
}

extension RecommendationItemFilter on Object {
  bool get keptInRecommendations => switch (this) {
        SeerrMedia m => RecommendationFilter.keep(m),
        EmbyItem i => !RecommendationFilter.hideAnimation || !RecommendationFilter.isAnimated(i),
        _ => true,
      };
}

typedef MixedItems = List<Object>;

final class Recommender {
  Recommender({required this.catalog, required this.seerr, this.tmdb, this.language = 'en-US'});

  final CatalogApi catalog;
  final SeerrApi? seerr;

  final TmdbApi? tmdb;
  final String language;

  static const _excludedTvGenres = '10763|10764|10767';

  Future<List<SeerrMedia>> discover(
    SeerrMediaType type, {
    int page = 1,
    String? sortBy,
    String? watchProviders,
    String? watchRegion,
    int? voteCountGte,
    Map<String, String> extra = const {},
  }) async {
    final t = tmdb;
    if (t == null) {
      return seerr!.discover(type,
          page: page, sortBy: sortBy, watchProviders: watchProviders, watchRegion: watchRegion, voteCountGte: voteCountGte);
    }
    final tv = type == SeerrMediaType.tv;
    final raw = await t.discover(tv,
        page: page,
        language: language,
        sortBy: sortBy,
        watchProviders: watchProviders,
        watchRegion: watchRegion,
        voteCountGte: voteCountGte,
        extra: {...extra}..remove('without_genres'),
        withoutGenres: [
          if (tv) _excludedTvGenres,
          if (RecommendationFilter.hideAnimation) '${RecommendationFilter._animation}',
          ?extra['without_genres'],
        ].join('|').nullIfEmpty);
    return withStatuses([for (final r in raw) ?SeerrMedia.fromTmdb(r, type: type)]);
  }

  Future<List<SeerrMedia>> search(String query) async {
    final t = tmdb;
    if (t == null) return seerr?.search(query) ?? const [];
    final raw = await t.searchMulti(query, language: language);
    return withStatuses([for (final r in raw) ?SeerrMedia.fromTmdb(r)]);
  }

  Future<List<SeerrMedia>> recommendations(int tmdbId, SeerrMediaType type, {int page = 1}) async {
    final t = tmdb;
    if (t == null) return seerr?.recommendations(tmdbId, type, page: page) ?? const [];
    final path = '/${type == SeerrMediaType.tv ? 'tv' : 'movie'}/$tmdbId';
    var raw = await t.list('$path/recommendations', page: page, language: language);
    if (raw.isEmpty) raw = await t.list('$path/similar', page: page, language: language);
    return withStatuses([for (final r in raw) ?SeerrMedia.fromTmdb(r, type: type)]);
  }

  Future<MixedItems> moreLikeThis(
      {String? embyId, int? tmdbId, required SeerrMediaType type, bool animated = false, int limit = 30}) async {
    final library = embyId == null
        ? Future.value(const <EmbyItem>[])
        : catalog.similar(embyId, limit: 16).catchError((Object _) => const <EmbyItem>[]);
    MixedItems picks = const [];
    if (tmdbId != null && (tmdb != null || seerr != null)) {
      try {
        picks = await resolve(
            await collect((p) => recommendations(tmdbId, type, page: p), pages: 2, limit: limit, filter: !animated));
      } catch (e) {
        debugPrint('[recommend] more like $type $tmdbId: $e');
      }
    }
    if (seerr == null) picks = picks.whereType<EmbyItem>().toList();
    final self = '${type.name}:$tmdbId';
    final seen = <String>{?embyId};
    return [
      for (final p in picks)
        if (p is EmbyItem ? seen.add(p.id) : (p as SeerrMedia).key != self) p,
      for (final i in await library)
        if ((animated || i.keptInRecommendations) && seen.add(i.id)) i,
    ];
  }

  Future<MixedItems> tagged(TitleTag tag, SeerrMediaType type,
      {bool topRated = false, int pages = 2, bool hidePlayed = false}) async {
    if (tmdb == null || !tag.covers(type)) return const [];
    final tv = type == SeerrMediaType.tv;
    final extra = {
      ...tag.filter,
      'vote_count.gte': topRated ? (tv ? '200' : '500') : (tv ? '30' : '80'),
      if (topRated) 'sort_by': 'vote_average.desc',
    };
    final items = await mixed((p) => discover(type, page: p, extra: extra), pages: pages, hidePlayed: hidePlayed);
    return seerr != null ? items : items.whereType<EmbyItem>().toList();
  }

  Future<List<SeerrMedia>> withStatuses(List<SeerrMedia> media) async {
    final s = seerr;
    if (s == null || media.isEmpty) return media;
    final Map<String, ({Availability availability, String? embyItemId})> statuses;
    try {
      statuses = await s.mediaStatuses();
    } catch (e) {
      debugPrint('[recommend] *seerr statuses: $e');
      return media;
    }
    return [
      for (final m in media)
        if (statuses[m.key] case final st?) m.withAvailability(st.availability, embyItemId: st.embyItemId) else m,
    ];
  }

  static Future<List<SeerrMedia>> collect(
    Future<List<SeerrMedia>> Function(int page) fetch, {
    int pages = 3,
    int limit = 40,
    bool filter = true,
  }) async {
    final results = await Future.wait([
      for (var p = 1; p <= pages; p++)
        fetch(p).catchError((Object e) {
          if (p == 1) throw e;
          return <SeerrMedia>[];
        }),
    ]);
    final seen = <String>{};
    return [
      for (final page in results)
        for (final m in page)
          if ((!filter || RecommendationFilter.keep(m)) && seen.add(m.key)) m,
    ].take(limit).toList();
  }

  Future<MixedItems> resolve(List<SeerrMedia> media, {bool hidePlayed = false}) async {
    if (media.isEmpty) return const [];
    final library = <String, EmbyItem>{};
    try {
      final ids = {for (final m in media) m.tmdbId};
      final page = await catalog.query(
        types: const ['Movie', 'Series'],
        anyProviderIdEquals: ids.map((id) => 'tmdb.$id').join(','),
        limit: ids.length * 2,
      );
      for (final i in page.items) {
        final id = i.tmdbId;
        if (id != null) library.putIfAbsent('${i.isSeries ? 'tv' : 'movie'}:$id', () => i);
      }
    } catch (e) {
      debugPrint('[recommend] library match failed: $e');
    }
    return [
      for (final m in media)
        if (library[m.key] case final item?) ...[if (!hidePlayed || !item.isPlayed) item] else m,
    ];
  }

  Future<MixedItems> mixed(Future<List<SeerrMedia>> Function(int page) fetch,
          {int pages = 3, int limit = 40, bool hidePlayed = false}) async =>
      resolve(await collect(fetch, pages: pages, limit: limit), hidePlayed: hidePlayed);

  Future<List<SeerrMedia>> requestable(Future<List<SeerrMedia>> Function(int page) fetch,
          {int pages = 3, int limit = 40}) async =>
      (await mixed(fetch, pages: pages, limit: limit * 2)).whereType<SeerrMedia>().take(limit).toList();
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
