import 'dart:math';

import '../core/emby/models/emby_item.dart';
import 'catalog_api.dart';
import 'recommendations.dart';

typedef FavoritePerson = ({Person person, int count});

final class TasteProfile {
  const TasteProfile({
    this.recentMovies = const [],
    this.recentSeries = const [],
    this.actors = const [],
    this.directors = const [],
    this.genres = const [],
  });

  final List<EmbyItem> recentMovies;

  final List<EmbyItem> recentSeries;
  final List<FavoritePerson> actors;
  final List<FavoritePerson> directors;
  final List<({String genre, int count})> genres;

  bool get isEmpty => recentMovies.isEmpty && recentSeries.isEmpty;

  static const _fields = 'ProviderIds,Genres,People,ProductionYear,DateLastPlayed';

  static const _billedCast = 8;

  static final _launch = Random().nextInt(1 << 30);

  static List<T> _rotate<T>(List<T> list, int pool, int salt) {
    final head = list.take(pool).toList()..shuffle(Random(_launch + salt));
    return [...head, ...list.skip(pool)];
  }

  static Future<TasteProfile> load(CatalogApi c) async {
    final (movies, episodes) = await (
      c.query(
          types: ['Movie'], filters: 'IsPlayed', sortBy: 'DatePlayed', descending: true, limit: 80,
          fields: _fields, localize: false),
      c.query(
          types: ['Episode'], filters: 'IsPlayed', sortBy: 'DatePlayed', descending: true, limit: 300,
          fields: 'SeriesId', localize: false),
    ).wait;

    final seriesOrder = <String>[];
    final episodesPerSeries = <String, int>{};
    for (final e in episodes.items) {
      final id = e.seriesId;
      if (id == null) continue;
      if (!episodesPerSeries.containsKey(id)) seriesOrder.add(id);
      episodesPerSeries[id] = (episodesPerSeries[id] ?? 0) + 1;
    }
    final seriesIds = seriesOrder.take(30).toList();
    final series = seriesIds.isEmpty
        ? const <EmbyItem>[]
        : (await c.query(ids: seriesIds, types: ['Series'], limit: seriesIds.length, fields: _fields, localize: false))
            .items;
    final byId = {for (final s in series) s.id: s};
    final recentSeries = [
      for (final id in seriesIds)
        if (byId[id] case final s? when s.keptInRecommendations) s,
    ];
    final recentMovies = [for (final m in movies.items) if (m.keptInRecommendations) m];

    final actors = <String, ({Person person, double score})>{};
    final directors = <String, ({Person person, double score})>{};
    final genres = <String, double>{};
    void add(EmbyItem item, double weight) {
      var billed = 0;
      for (final p in item.people) {
        if (p.type == 'Actor' && billed++ < _billedCast) {
          final prev = actors[p.id];
          actors[p.id] = (person: p, score: (prev?.score ?? 0) + weight);
        } else if (p.type == 'Director' && item.isMovie) {
          final prev = directors[p.id];
          directors[p.id] = (person: p, score: (prev?.score ?? 0) + weight);
        }
      }
      for (final g in item.genres) {
        genres[g] = (genres[g] ?? 0) + weight;
      }
    }

    for (final (i, m) in recentMovies.indexed) {
      add(m, i < 15 ? 1.5 : 1);
    }
    for (final (i, s) in recentSeries.indexed) {
      final episodes = episodesPerSeries[s.id] ?? 1;
      add(s, (i < 5 ? 1.5 : 1) * (episodes >= 6 ? 2 : 1));
    }

    List<FavoritePerson> top(Map<String, ({Person person, double score})> m, double min) => ([...m.values]
          ..removeWhere((e) => e.score < min)
          ..sort((a, b) => b.score.compareTo(a.score)))
        .map((e) => (person: e.person, count: e.score.round()))
        .take(10)
        .toList();

    final topGenres = ([...genres.entries]..sort((a, b) => b.value.compareTo(a.value)))
        .where((e) => !RecommendationFilter.hideAnimation || !e.key.toLowerCase().contains('anim'))
        .map((e) => (genre: e.key, count: e.value.round()))
        .take(6)
        .toList();
    return TasteProfile(
      recentMovies: _rotate(recentMovies, 10, 1),
      recentSeries: _rotate(recentSeries, 6, 2),
      actors: _rotate(top(actors, 3), 8, 3),
      directors: _rotate(top(directors, 2), 5, 4),
      genres: _rotate(topGenres, 4, 5),
    );
  }
}
