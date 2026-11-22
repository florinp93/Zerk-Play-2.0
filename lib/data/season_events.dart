import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import 'catalog_api.dart';
import 'recommendations.dart';
import 'seerr_api.dart';
import 'tmdb_api.dart';

DateTime? _day(Object? v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

List<String> _strings(Object? v) => [for (final s in v is List ? v : const []) if (s is String && s.isNotEmpty) s];

typedef TmdbTitle = ({SeerrMediaType type, int id});

TmdbTitle? _title(Object? raw) {
  if (raw is! Map || raw['id'] is! int) return null;
  return (type: raw['type'] == 'tv' ? SeerrMediaType.tv : SeerrMediaType.movie, id: raw['id'] as int);
}

final class EventRow {
  const EventRow({
    required this.title,
    required this.source,
    this.media = 'both',
    this.ids = const [],
    this.titles = const [],
    this.names = const [],
    this.sort = 'popular',
    this.unwatchedFirst = false,
    this.missing = false,
  });

  final String title;
  final String source;
  final String media;
  final List<int> ids;
  final List<TmdbTitle> titles;
  final List<String> names;
  final String sort;
  final bool unwatchedFirst;
  final bool missing;

  static EventRow? fromJson(Object? raw) {
    if (raw is! Map || raw['title'] is! String || raw['source'] is! String) return null;
    return EventRow(
      title: raw['title'] as String,
      source: raw['source'] as String,
      media: raw['media'] is String ? raw['media'] as String : 'both',
      ids: [for (final v in raw['ids'] as List? ?? const []) if (v is int) v],
      titles: [for (final v in raw['titles'] as List? ?? const []) ?_title(v)],
      names: _strings(raw['names']),
      sort: raw['sort'] is String ? raw['sort'] as String : 'popular',
      unwatchedFirst: raw['unwatchedFirst'] == true,
      missing: raw['missing'] == true,
    );
  }

  List<SeerrMediaType> get types => switch (media) {
        'movie' => const [SeerrMediaType.movie],
        'tv' => const [SeerrMediaType.tv],
        _ => const [SeerrMediaType.movie, SeerrMediaType.tv],
      };
}

final class EventSpotlight {
  const EventSpotlight({required this.title, this.text = '', this.tmdb, this.countdown, this.image});

  final String title;
  final String text;
  final TmdbTitle? tmdb;
  final DateTime? countdown;
  final Uri? image;

  static EventSpotlight? fromJson(Object? raw) {
    if (raw is! Map || raw['title'] is! String) return null;
    final image = Uri.tryParse(raw['image'] as String? ?? '');
    return EventSpotlight(
      title: raw['title'] as String,
      text: raw['text'] as String? ?? '',
      tmdb: _title(raw['tmdb']),
      countdown: _day(raw['countdown']),
      image: image != null && image.scheme == 'https' ? image : null,
    );
  }

  int? daysLeft(DateTime now) {
    final target = countdown;
    if (target == null) return null;
    return target.difference(DateTime(now.year, now.month, now.day)).inDays;
  }
}

final class SeasonEvent {
  const SeasonEvent({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.accent,
    this.effect = 'none',
    this.badge = 'none',
    this.spotlight,
    this.rows = const [],
  });

  final String id;
  final String name;
  final DateTime start;
  final DateTime end;
  final int? accent;
  final String effect;
  final String badge;
  final EventSpotlight? spotlight;
  final List<EventRow> rows;

  static SeasonEvent? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['name'] is! String) return null;
    final start = _day(raw['start']), end = _day(raw['end']);
    if (start == null || end == null) return null;
    final look = raw['look'] is Map ? raw['look'] as Map : const {};
    final hex = look['accent'] is String ? (look['accent'] as String).replaceFirst('#', '') : '';
    return SeasonEvent(
      id: raw['id'] as String,
      name: raw['name'] as String,
      start: start,
      end: end,
      accent: hex.length == 6 ? int.tryParse('ff$hex', radix: 16) : null,
      effect: look['effect'] is String ? look['effect'] as String : 'none',
      badge: look['badge'] is String ? look['badge'] as String : 'none',
      spotlight: EventSpotlight.fromJson(raw['spotlight']),
      rows: [for (final r in raw['rows'] as List? ?? const []) ?EventRow.fromJson(r)],
    );
  }

  static List<SeasonEvent> list(Object? raw) => [for (final e in raw is List ? raw : const []) ?SeasonEvent.fromJson(e)];

  bool activeOn(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static List<SeasonEvent> active(List<SeasonEvent> events, DateTime now) => [for (final e in events) if (e.activeOn(now)) e];
}

final class SpotlightCardData {
  const SpotlightCardData({required this.event, required this.backdrop, this.target});

  final SeasonEvent event;
  final Uri? backdrop;
  final Object? target;

  EventSpotlight get spotlight => event.spotlight!;
}

final class SeasonEventLoader {
  SeasonEventLoader({required this.catalog, required this.recommender, required this.tmdb, required this.requests});

  final CatalogApi catalog;
  final Recommender recommender;
  final TmdbApi? tmdb;
  final bool requests;

  static const _pages = 3;
  static const _limit = 60;

  Future<MixedItems> row(EventRow row) async {
    final MixedItems items = switch (row.source) {
      'keyword' => await _keyword(row),
      'collection' => await _fromTmdb(row, await _collectionParts(row)),
      'titles' => await _fromTmdb(row, await _details(row.titles)),
      'genre' || 'tag' => await _library(row),
      _ => const [],
    };
    final kept = [
      for (final i in items)
        if (i is EmbyItem || (row.missing && requests)) i,
    ];
    if (!row.unwatchedFirst) return kept;
    bool watched(Object i) => i is EmbyItem && i.isPlayed;
    return [...kept.where((i) => !watched(i)), ...kept.where(watched)];
  }

  Future<MixedItems> _keyword(EventRow row) async {
    final keywords = row.ids.join('|');
    if (keywords.isEmpty) return const [];
    final media = <SeerrMedia>[];
    for (final type in row.types) {
      final tv = type == SeerrMediaType.tv;
      final sortBy = switch (row.sort) {
        'release' => tv ? 'first_air_date.asc' : 'primary_release_date.asc',
        _ => 'popularity.desc',
      };
      media.addAll(await Recommender.collect(
        (p) => recommender.discover(type, page: p, sortBy: sortBy, extra: {'with_keywords': keywords}),
        pages: _pages,
        limit: _limit,
        filter: false,
      ));
    }
    return _ordered(row, await recommender.resolve(media));
  }

  Future<List<SeerrMedia>> _collectionParts(EventRow row) async {
    final t = tmdb;
    if (t == null) return const [];
    final parts = <SeerrMedia>[];
    for (final id in row.ids) {
      final j = await t.get('/collection/$id', language: recommender.language);
      for (final p in j?['parts'] as List? ?? const []) {
        if (p is Map) parts.addAll([?SeerrMedia.fromTmdb(p.cast<String, dynamic>(), type: SeerrMediaType.movie)]);
      }
    }
    return parts;
  }

  Future<List<SeerrMedia>> _details(List<TmdbTitle> titles) async {
    final t = tmdb;
    if (t == null) return const [];
    final found = await Future.wait([
      for (final ref in titles.take(_limit))
        t
            .get('/${ref.type.name}/${ref.id}', language: recommender.language)
            .then((j) => j == null ? null : SeerrMedia.fromTmdb(j, type: ref.type))
            .catchError((Object _) => null),
    ]);
    return recommender.withStatuses(found.nonNulls.toList());
  }

  Future<MixedItems> _fromTmdb(EventRow row, List<SeerrMedia> media) async =>
      _ordered(row, await recommender.resolve([for (final m in media) if (row.types.contains(m.type)) m]));

  Future<MixedItems> _library(EventRow row) async {
    final page = await catalog.query(
      types: [for (final t in row.types) t == SeerrMediaType.tv ? 'Series' : 'Movie'],
      genres: row.source == 'genre' ? row.names : null,
      tags: row.source == 'tag' ? row.names : null,
      sortBy: switch (row.sort) {
        'release' => 'PremiereDate,SortName',
        'name' => 'SortName',
        _ => 'CommunityRating,SortName',
      },
      descending: row.sort == 'popular',
      limit: _limit,
    );
    return page.items;
  }

  MixedItems _ordered(EventRow row, MixedItems items) {
    if (row.sort != 'name') return items;
    String name(Object i) => (i is EmbyItem ? i.name : (i as SeerrMedia).title).toLowerCase();
    return [...items]..sort((a, b) => name(a).compareTo(name(b)));
  }

  Future<MixedItems> spotlight(SeasonEvent event) async {
    final s = event.spotlight;
    if (s == null) return const [];
    Object? target;
    Uri? backdrop = s.image;
    final ref = s.tmdb;
    if (ref != null && tmdb != null) {
      try {
        final media = (await _details([ref])).firstOrNull;
        if (media != null) {
          target = (await recommender.resolve([media])).firstOrNull;
          backdrop ??= media.backdrop();
        }
      } catch (e) {
        debugPrint('[events] spotlight ${event.name}: $e');
      }
    }
    if (target is SeerrMedia && !requests) target = null;
    return [SpotlightCardData(event: event, backdrop: backdrop, target: target)];
  }
}
