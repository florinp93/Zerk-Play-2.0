import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import 'catalog_api.dart';
import 'seerr_api.dart';
import 'tmdb_api.dart';

enum HomeRelease { digital, disc, tv }

@immutable
final class CalendarEntry {
  const CalendarEntry({
    required this.tmdbId,
    required this.isTv,
    required this.title,
    required this.date,
    this.season,
    this.episode,
    this.episodeEnd,
    this.episodeCount = 1,
    this.episodeName,
    this.finale = false,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.stillPath,
    this.logoPath,
    this.homeRelease,
    this.requested,
    this.watching = false,
    this.libraryItem,
    this.media,
  });

  final int tmdbId;
  final bool isTv;

  final String title;

  final DateTime? date;

  final int? season;
  final int? episode;

  final int? episodeEnd;
  final int episodeCount;

  final String? episodeName;
  final bool finale;
  final String? overview;

  final String? posterPath;
  final String? backdropPath;
  final String? stillPath;
  final String? logoPath;

  final HomeRelease? homeRelease;

  final Availability? requested;
  final bool watching;

  final EmbyItem? libraryItem;

  final SeerrMedia? media;

  String get key => '${isTv ? 'tv' : 'movie'}:$tmdbId:${date?.toIso8601String()}';

  bool get premiere => isTv && episode == 1;

  String? get episodeCode {
    if (!isTv || season == null) return null;
    final ep = episode == null ? null : (episodeEnd != null && episodeEnd != episode ? 'E$episode-E$episodeEnd' : 'E$episode');
    return ['S$season', ?ep].join(' · ');
  }

  CalendarEntry withLibraryItem(EmbyItem? item) => item == null
      ? this
      : CalendarEntry(
          tmdbId: tmdbId,
          isTv: isTv,
          title: title,
          date: date,
          season: season,
          episode: episode,
          episodeEnd: episodeEnd,
          episodeCount: episodeCount,
          episodeName: episodeName,
          finale: finale,
          overview: overview,
          posterPath: posterPath,
          backdropPath: backdropPath,
          stillPath: stillPath,
          logoPath: logoPath,
          homeRelease: homeRelease,
          requested: requested,
          watching: watching,
          libraryItem: item,
          media: media,
        );
}

final class ReleaseCalendar {
  ReleaseCalendar({required this.catalog, this.seerr, this.tmdb, this.language});

  final CatalogApi catalog;
  final SeerrApi? seerr;
  final TmdbApi? tmdb;

  final String? language;


  static const _cinemaWindow = Duration(days: 120);

  Future<List<CalendarEntry>> load({DateTime? now}) async {
    now ??= DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = DateTime(today.year, today.month - 1);

    final (watching, requests) = await (
      catalog.watchingSeries().catchError((Object e) {
        debugPrint('[calendar] watching: $e');
        return const <EmbyItem>[];
      }),
      (seerr?.myRequests() ?? Future.value(const <SeerrRequest>[])).catchError((Object e) {
        debugPrint('[calendar] requests: $e');
        return const <SeerrRequest>[];
      }),
    ).wait;

    final shows = <int, ({EmbyItem? item, Availability? requested})>{};
    for (final s in watching) {
      final id = s.tmdbId;
      if (id != null) shows[id] = (item: s, requested: null);
    }
    final movies = <int, Availability>{};
    for (final r in requests) {
      if (r.isTv) {
        shows[r.tmdbId] = (item: shows[r.tmdbId]?.item, requested: r.availability);
      } else if (r.availability != Availability.available ||
          (r.created?.isAfter(today.subtract(const Duration(days: 90))) ?? true)) {
        movies[r.tmdbId] = r.availability;
      }
    }

    final showEntries = _pool(shows.entries.toList(), (e) async {
      try {
        return await _show(e.key, from: from, item: e.value.item, requested: e.value.requested);
      } catch (err) {
        debugPrint('[calendar] tv ${e.key}: $err');
        return const <CalendarEntry>[];
      }
    });
    final movieEntries = _pool(movies.entries.toList(), (e) async {
      try {
        return await _movie(e.key, e.value, from: from, today: today);
      } catch (err) {
        debugPrint('[calendar] movie ${e.key}: $err');
        return null;
      }
    });
    final (tv, film) = await (showEntries, movieEntries).wait;
    var entries = [for (final list in tv) ...list, ...film.nonNulls];
    entries = await _matchLibrary(entries);
    entries.sort((a, b) {
      final ad = a.date, bd = b.date;
      if (ad == null || bd == null) return ad == bd ? a.title.compareTo(b.title) : (ad == null ? 1 : -1);
      final c = ad.compareTo(bd);
      return c != 0 ? c : a.title.compareTo(b.title);
    });
    return entries;
  }

  Future<List<CalendarEntry>> _show(int id, {required DateTime from, EmbyItem? item, Availability? requested}) async {
    final j = await _cached('tv:$id', () => tmdb != null ? _tmdbDetails('/tv/$id') : seerr!.tvJson(id));
    if (j == null) return const [];
    final seasons = <int>{
      for (final key in ['last_episode_to_air', 'lastEpisodeToAir', 'next_episode_to_air', 'nextEpisodeToAir'])
        if (j[key] case {'season_number': final num n} || {'seasonNumber': final num n}) n.toInt(),
    }..remove(0);
    if (seasons.isEmpty) return const [];

    final title = _str(j['name']) ?? _str(j['original_name']) ?? _str(j['originalName']) ?? item?.name ?? '';
    final media = _media(j, SeerrMediaType.tv, requested);
    final episodes = <Object?>[
      for (final n in seasons)
        ...?(await _cached('tv:$id:$n', () => tmdb != null ? _tmdbDetails('/tv/$id/season/$n', images: false) : seerr!.seasonJson(id, n)))
            ?['episodes'] as List?,
    ].whereType<Map>();

    final byDay = <DateTime, List<Map>>{};
    for (final e in episodes) {
      final date = _day(e['air_date'] ?? e['airDate']);
      if (date == null || date.isBefore(from)) continue;
      (byDay[date] ??= []).add(e);
    }
    return [
      for (final MapEntry(key: date, value: eps) in byDay.entries)
        () {
          eps.sort((a, b) => _num(a, 'episode_number', 'episodeNumber').compareTo(_num(b, 'episode_number', 'episodeNumber')));
          final first = eps.first, last = eps.last;
          final single = eps.length == 1;
          return CalendarEntry(
            tmdbId: id,
            isTv: true,
            title: title,
            date: date,
            season: _num(first, 'season_number', 'seasonNumber'),
            episode: _num(first, 'episode_number', 'episodeNumber'),
            episodeEnd: single ? null : _num(last, 'episode_number', 'episodeNumber'),
            episodeCount: eps.length,
            episodeName: single ? _str(first['name']) : null,
            finale: eps.any((e) => e['episode_type'] == 'finale' || e['episodeType'] == 'finale'),
            overview: (single ? _str(first['overview']) : null) ?? _str(j['overview']),
            posterPath: _str(j['poster_path'] ?? j['posterPath']),
            backdropPath: _str(j['backdrop_path'] ?? j['backdropPath']),
            stillPath: single ? _str(first['still_path'] ?? first['stillPath']) : null,
            logoPath: _logo(j),
            requested: requested,
            watching: item != null,
            libraryItem: item,
            media: media,
          );
        }(),
    ];
  }

  Future<CalendarEntry?> _movie(int id, Availability requested, {required DateTime from, required DateTime today}) async {
    final j = await _cached('movie:$id', () => tmdb != null ? _tmdbDetails('/movie/$id', extra: 'release_dates') : seerr!.movieJson(id));
    if (j == null) return null;
    final (release, kind, cinema) = homeRelease(j);
    if (release == null) {
      final first = cinema ?? _day(j['release_date'] ?? j['releaseDate']);
      if (requested == Availability.available || (first != null && today.difference(first) > _cinemaWindow)) return null;
    } else if (release.isBefore(from)) {
      return null;
    }
    return CalendarEntry(
      tmdbId: id,
      isTv: false,
      title: _str(j['title']) ?? _str(j['original_title']) ?? _str(j['originalTitle']) ?? '',
      date: release,
      overview: _str(j['overview']),
      posterPath: _str(j['poster_path'] ?? j['posterPath']),
      backdropPath: _str(j['backdrop_path'] ?? j['backdropPath']),
      logoPath: _logo(j),
      homeRelease: kind,
      requested: requested,
      media: _media(j, SeerrMediaType.movie, requested),
    );
  }

  static (DateTime?, HomeRelease?, DateTime?) homeRelease(Map<String, dynamic> j) {
    final first = <int, DateTime>{};
    final releases = j['release_dates'] ?? j['releases'];
    final countries = releases is Map ? releases['results'] as List? ?? const [] : const [];
    for (final c in countries) {
      if (c is! Map) continue;
      for (final d in (c['release_dates'] as List? ?? const [])) {
        if (d is! Map || d['type'] is! num) continue;
        final date = _day(d['release_date']);
        final type = (d['type'] as num).toInt();
        if (date != null && (first[type] == null || date.isBefore(first[type]!))) first[type] = date;
      }
    }
    final cinema = [first[1], first[2], first[3]].nonNulls.fold<DateTime?>(
        null, (a, b) => a == null || b.isBefore(a) ? b : a);
    for (final (type, kind) in const [(4, HomeRelease.digital), (5, HomeRelease.disc), (6, HomeRelease.tv)]) {
      if (first[type] != null) return (first[type], kind, cinema);
    }
    return (null, null, cinema);
  }

  Future<List<CalendarEntry>> _matchLibrary(List<CalendarEntry> entries) async {
    final wanted = {
      for (final e in entries)
        if (e.libraryItem == null) e.tmdbId,
    }.toList();
    final found = <String, EmbyItem>{};
    for (var i = 0; i < wanted.length; i += 50) {
      final ids = wanted.skip(i).take(50);
      try {
        final page = await catalog.query(
          types: const ['Movie', 'Series'],
          anyProviderIdEquals: ids.map((id) => 'tmdb.$id').join(','),
          limit: 200,
          localize: false,
        );
        for (final item in page.items) {
          final id = item.tmdbId;
          if (id != null && ids.contains(id)) found['${item.isSeries ? 'tv' : 'movie'}:$id'] = item;
        }
      } catch (e) {
        debugPrint('[calendar] library: $e');
      }
    }
    return [for (final e in entries) e.libraryItem != null ? e : e.withLibraryItem(found['${e.isTv ? 'tv' : 'movie'}:${e.tmdbId}'])];
  }

  static final _cache = <String, ({DateTime at, Future<Map<String, dynamic>?> json})>{};

  Future<Map<String, dynamic>?> _cached(String key, Future<Map<String, dynamic>?> Function() fetch) {
    final k = '${tmdb != null ? 'tmdb' : 'seerr'}:$language:$key';
    final hit = _cache[k];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 30)) return hit.json;
    final json = fetch()..catchError((Object _) {
      _cache.remove(k);
      return null;
    });
    _cache[k] = (at: DateTime.now(), json: json);
    return json;
  }

  Future<Map<String, dynamic>?> _tmdbDetails(String path, {String? extra, bool images = true}) {
    final lang = language?.split('-').first;
    return tmdb!.get(path, language: language, query: {
      if (images || extra != null) 'append_to_response': [if (images) 'images', ?extra].join(','),
      if (images) 'include_image_language': {?lang, 'en', 'null'}.join(','),
    });
  }

  String? _logo(Map<String, dynamic> j) {
    final logos = [
      for (final l in ((j['images'] as Map?)?['logos'] as List? ?? const []))
        if (l is Map && l['file_path'] is String) l,
    ];
    if (logos.isEmpty) return null;
    final lang = language?.split('-').first;
    for (final want in [?lang, 'en', null]) {
      for (final l in logos) {
        if (l['iso_639_1'] == want) return l['file_path'] as String;
      }
    }
    return null;
  }

  SeerrMedia? _media(Map<String, dynamic> j, SeerrMediaType type, Availability? requested) {
    final m = tmdb != null ? SeerrMedia.fromTmdb(j, type: type) : SeerrMedia.fromJson(j, type: type);
    return requested == null ? m : m?.withAvailability(requested);
  }

  static Future<List<R>> _pool<T, R>(List<T> items, Future<R> Function(T) f, {int width = 6}) async {
    final out = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final i = next++;
        out[i] = await f(items[i]);
      }
    }

    await Future.wait([for (var k = 0; k < width; k++) worker()]);
    return out.cast<R>();
  }

  static DateTime? _day(Object? v) {
    if (v is! String || v.length < 10) return null;
    final d = DateTime.tryParse(v.substring(0, 10));
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

  static int _num(Map m, String snake, String camel) => ((m[snake] ?? m[camel]) as num?)?.toInt() ?? 0;
}
