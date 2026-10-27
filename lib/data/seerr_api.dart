import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/log/logging_http_client.dart';
import 'release_info.dart';

enum SeerrMediaType { movie, tv }

enum Availability {
  none,

  pending,

  processing,

  downloading,

  partial,

  available,

  blocked;

  static Availability fromStatus(int? status, {bool downloading = false}) => switch (status) {
        2 => pending,
        3 => downloading ? Availability.downloading : processing,
        4 => partial,
        5 => available,
        6 => blocked,
        _ => none,
      };

  bool get canRequest => this == none || this == partial;
  bool get isOnServer => this == available || this == partial;
}

abstract final class RequestStatuses {
  static final _known = <String, Availability>{};

  static final changed = ValueNotifier<int>(0);

  static Availability of(SeerrMedia m) => _known[m.key] ?? m.availability;

  static void record(SeerrMedia m, Availability a) {
    if (_known[m.key] == a) return;
    _known[m.key] = a;
    changed.value++;
  }
}

final class SeerrSeason {
  const SeerrSeason({required this.number, required this.name, this.episodeCount, this.availability = Availability.none});

  final int number;

  final String? name;
  final int? episodeCount;
  final Availability availability;
}

final class SeerrMedia {
  const SeerrMedia({
    required this.tmdbId,
    required this.type,
    required this.title,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.genres = const [],
    this.availability = Availability.none,
    this.availability4k = Availability.none,
    this.embyItemId,
    this.seasons = const [],
    this.runtimeMinutes,
    this.tagline,
    this.genreIds = const [],
    this.originalLanguage,
    this.voteCount,
    this.releaseDate,
    this.release,
  });

  final int tmdbId;
  final SeerrMediaType type;
  final String title;
  final int? year;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? voteAverage;
  final List<String> genres;
  final Availability availability;
  final Availability availability4k;

  final String? embyItemId;
  final List<SeerrSeason> seasons;
  final int? runtimeMinutes;
  final String? tagline;

  final List<int> genreIds;

  final String? originalLanguage;
  final int? voteCount;

  final DateTime? releaseDate;

  final ReleaseInfo? release;

  bool get isTv => type == SeerrMediaType.tv;

  String get key => '${type.name}:$tmdbId';

  Uri? poster({int width = 342}) => _tmdb(posterPath, 'w$width');
  Uri? backdrop({int width = 1280}) => _tmdb(backdropPath, width >= 1280 ? 'w1280' : 'w780');

  static Uri? _tmdb(String? path, String size) =>
      path == null || path.isEmpty ? null : Uri.parse('https://image.tmdb.org/t/p/$size$path');

  SeerrMedia withAvailability(Availability a, {String? embyItemId}) => SeerrMedia(
        tmdbId: tmdbId,
        type: type,
        title: title,
        year: year,
        overview: overview,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        genres: genres,
        availability: a,
        availability4k: availability4k,
        embyItemId: embyItemId ?? this.embyItemId,
        seasons: seasons,
        runtimeMinutes: runtimeMinutes,
        tagline: tagline,
        genreIds: genreIds,
        originalLanguage: originalLanguage,
        voteCount: voteCount,
        releaseDate: releaseDate,
        release: release,
      );

  static SeerrMedia? fromTmdb(Map<String, dynamic> j, {SeerrMediaType? type}) {
    final mediaType = type ??
        switch (j['media_type']) {
          'movie' => SeerrMediaType.movie,
          'tv' => SeerrMediaType.tv,
          _ => null,
        };
    final id = (j['id'] as num?)?.toInt();
    if (mediaType == null || id == null) return null;
    final date = (j['release_date'] ?? j['first_air_date']) as String?;
    return SeerrMedia(
      tmdbId: id,
      type: mediaType,
      title: (j['title'] ?? j['name'] ?? j['original_title'] ?? j['original_name'] ?? '') as String,
      year: date != null && date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      overview: (j['overview'] as String?)?.trim().isEmpty ?? true ? null : j['overview'] as String,
      posterPath: j['poster_path'] as String?,
      backdropPath: j['backdrop_path'] as String?,
      voteAverage: (j['vote_average'] as num?)?.toDouble(),
      voteCount: (j['vote_count'] as num?)?.toInt(),
      genreIds: [for (final g in (j['genre_ids'] as List? ?? const [])) if (g is num) g.toInt()],
      originalLanguage: j['original_language'] as String?,
      releaseDate: date == null ? null : DateTime.tryParse(date),
    );
  }

  static SeerrMedia? fromJson(Map<String, dynamic> j, {SeerrMediaType? type}) {
    final mediaType = type ??
        switch (j['mediaType']) {
          'movie' => SeerrMediaType.movie,
          'tv' => SeerrMediaType.tv,
          _ => null,
        };
    final id = (j['id'] as num?)?.toInt();
    if (mediaType == null || id == null) return null;
    final info = j['mediaInfo'] is Map ? (j['mediaInfo'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final date = (j['releaseDate'] ?? j['firstAirDate']) as String?;

    final downloads = info['downloadStatus'] as List? ?? const [];
    final downloads4k = info['downloadStatus4k'] as List? ?? const [];
    final downloadingSeasons = <int>{
      for (final d in downloads)
        if (d is Map && d['episode'] is Map && (d['episode'] as Map)['seasonNumber'] is num)
          ((d['episode'] as Map)['seasonNumber'] as num).toInt(),
    };

    final seasonStatus = <int, Availability>{};
    for (final s in (info['seasons'] as List? ?? const [])) {
      if (s is Map && s['seasonNumber'] is num) {
        final number = (s['seasonNumber'] as num).toInt();
        seasonStatus[number] = Availability.fromStatus((s['status'] as num?)?.toInt(),
            downloading: downloadingSeasons.contains(number));
      }
    }
    for (final r in (info['requests'] as List? ?? const [])) {
      if (r is! Map || r['status'] != 1) continue;
      for (final s in (r['seasons'] as List? ?? const [])) {
        if (s is Map && s['seasonNumber'] is num) {
          seasonStatus.putIfAbsent((s['seasonNumber'] as num).toInt(), () => Availability.pending);
        }
      }
    }

    return SeerrMedia(
      tmdbId: id,
      type: mediaType,
      title: (j['title'] ?? j['name'] ?? j['originalTitle'] ?? j['originalName'] ?? '') as String,
      year: date != null && date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      overview: j['overview'] as String?,
      posterPath: j['posterPath'] as String?,
      backdropPath: j['backdropPath'] as String?,
      voteAverage: (j['voteAverage'] as num?)?.toDouble(),
      genres: [
        for (final g in (j['genres'] as List? ?? const []))
          if (g is Map && g['name'] is String) g['name'] as String,
      ],
      availability: Availability.fromStatus((info['status'] as num?)?.toInt(), downloading: downloads.isNotEmpty),
      availability4k:
          Availability.fromStatus((info['status4k'] as num?)?.toInt(), downloading: downloads4k.isNotEmpty),
      embyItemId: (info['jellyfinMediaId'] ?? info['embyMediaId']) as String?,
      seasons: [
        for (final s in (j['seasons'] as List? ?? const []))
          if (s is Map && s['seasonNumber'] is num)
            SeerrSeason(
              number: (s['seasonNumber'] as num).toInt(),
              name: s['name'] as String?,
              episodeCount: (s['episodeCount'] as num?)?.toInt(),
              availability: seasonStatus[(s['seasonNumber'] as num).toInt()] ?? Availability.none,
            ),
      ],
      runtimeMinutes: (j['runtime'] as num?)?.toInt(),
      tagline: j['tagline'] as String?,
      genreIds: [
        for (final g in (j['genreIds'] as List? ?? const []))
          if (g is num) g.toInt(),
        for (final g in (j['genres'] as List? ?? const []))
          if (g is Map && g['id'] is num) (g['id'] as num).toInt(),
      ],
      originalLanguage: j['originalLanguage'] as String?,
      voteCount: (j['voteCount'] as num?)?.toInt(),
      releaseDate: date == null ? null : DateTime.tryParse(date),
      release: mediaType == SeerrMediaType.movie && j['releases'] is Map ? ReleaseInfo.fromDetails(j) : null,
    );
  }
}

final class SeerrRequest {
  const SeerrRequest({required this.type, required this.tmdbId, required this.availability, this.created});

  final SeerrMediaType type;
  final int tmdbId;

  final Availability availability;
  final DateTime? created;

  bool get isTv => type == SeerrMediaType.tv;
}

final class WatchProvider {
  const WatchProvider({required this.id, required this.name, this.logoPath});

  final int id;
  final String name;
  final String? logoPath;

  Uri? logo({int width = 154}) =>
      logoPath == null || logoPath!.isEmpty ? null : Uri.parse('https://image.tmdb.org/t/p/w$width$logoPath');
}

final class SeerrException implements Exception {
  const SeerrException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'Seerr $status: $message';
}

enum SeerrProblemKind { notConfigured, notSeerr, unreachable, keyRejected, keyCheckFailed }

final class SeerrProblem {
  const SeerrProblem(this.kind, {this.url, this.status});

  final SeerrProblemKind kind;
  final Uri? url;

  final int? status;

  @override
  String toString() => [kind.name, ?status, ?url].join(' ');
}

final class SeerrApi {
  SeerrApi({
    required this.baseUrl,
    required this.apiKey,
    this.language,
    this.embyUserId,
    http.Client? client,
  }) : _http = client ?? LoggingHttpClient(tag: 'seerr');

  final Uri baseUrl;
  final String apiKey;

  final String? Function()? embyUserId;

  final String? language;
  final http.Client _http;

  Future<bool> ping() async => await check() == null;

  Future<SeerrProblem?> check() async {
    try {
      await _get('/api/v1/status');
    } on SeerrException catch (e) {
      return SeerrProblem(SeerrProblemKind.notSeerr, url: baseUrl, status: e.status);
    } catch (_) {
      return SeerrProblem(SeerrProblemKind.unreachable, url: baseUrl);
    }
    try {
      await _get('/api/v1/auth/me');
      return null;
    } on SeerrException catch (e) {
      if (e.status == 401 || e.status == 403) return const SeerrProblem(SeerrProblemKind.keyRejected);
      return SeerrProblem(SeerrProblemKind.keyCheckFailed, status: e.status);
    } catch (_) {
      return SeerrProblem(SeerrProblemKind.unreachable, url: baseUrl);
    }
  }

  Future<List<SeerrMedia>> trending({int page = 1, String timeWindow = 'day'}) async {
    if (timeWindow != 'day') {
      try {
        return await _results('/api/v1/discover/trending', {'page': '$page', 'timeWindow': timeWindow});
      } on SeerrException catch (e) {
        if (e.status != 400) rethrow;
      }
    }
    return _results('/api/v1/discover/trending', {'page': '$page'});
  }

  Future<List<SeerrMedia>> popularMovies({int page = 1}) => discover(SeerrMediaType.movie, page: page);

  Future<List<SeerrMedia>> popularShows({int page = 1}) => discover(SeerrMediaType.tv, page: page);

  Future<List<SeerrMedia>> upcomingMovies({int page = 1}) =>
      _results('/api/v1/discover/movies/upcoming', {'page': '$page'}, type: SeerrMediaType.movie);

  Future<List<SeerrMedia>> discover(
    SeerrMediaType type, {
    int page = 1,
    String? sortBy,
    String? watchProviders,
    String? watchRegion,
    int? voteCountGte,
  }) async {
    final query = {
      'page': '$page',
      'sortBy': ?sortBy,
      'watchProviders': ?watchProviders,
      'watchRegion': ?watchRegion,
      if (voteCountGte != null) 'voteCountGte': '$voteCountGte',
    };
    final path = '/api/v1/discover/${type == SeerrMediaType.movie ? 'movies' : 'tv'}';
    try {
      return await _results(path, query, type: type, localized: false);
    } on SeerrException catch (e) {
      if (e.status != 400 || voteCountGte == null) rethrow;
      query.remove('voteCountGte');
      return _results(path, query, type: type, localized: false);
    }
  }

  Future<List<SeerrMedia>> recommendations(int tmdbId, SeerrMediaType type, {int page = 1}) => _results(
      '/api/v1/${type == SeerrMediaType.movie ? 'movie' : 'tv'}/$tmdbId/recommendations', {'page': '$page'});

  Future<List<SeerrMedia>> personCredits(int tmdbPersonId, {String? name}) async {
    final json = await _get('/api/v1/person/$tmdbPersonId/combined_credits', null, true);
    bool role(Map c) {
      if (_isSelf(c['character']) || (name != null && c['character'] == name)) return false;
      final episodes = c['episodeCount'];
      return c['mediaType'] != 'tv' || episodes is! num || episodes >= 3;
    }

    final cast = [
      for (final c in (json['cast'] as List? ?? const []))
        if (c is Map && role(c)) c.cast<String, dynamic>(),
    ]..sort((a, b) => ((b['popularity'] as num?) ?? 0).compareTo((a['popularity'] as num?) ?? 0));
    final seen = <String>{};
    return [
      for (final c in cast)
        if (SeerrMedia.fromJson(c) case final m? when seen.add(m.key)) m,
    ];
  }

  static bool _isSelf(Object? character) {
    if (character is! String) return false;
    final c = character.toLowerCase().trim();
    return c == 'self' || c.startsWith('self ') || c.startsWith('self -') || c.startsWith('himself') ||
        c.startsWith('herself') || c.startsWith('themselves') || c.contains('(guest)');
  }

  Future<List<WatchProvider>> watchProviders({String region = 'US', SeerrMediaType type = SeerrMediaType.tv}) async {
    final uri = _uri('/api/v1/watchproviders/${type == SeerrMediaType.movie ? 'movies' : 'tv'}')
        .replace(queryParameters: {'watchRegion': region});
    final res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
    if (res.statusCode >= 300) throw SeerrException(res.statusCode, _message(res.body));
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    return [
      for (final p in (json is List ? json : const []))
        if (p is Map && p['id'] is num && p['name'] is String)
          WatchProvider(id: (p['id'] as num).toInt(), name: p['name'] as String, logoPath: p['logoPath'] as String?),
    ];
  }

  Future<Map<String, ({Availability availability, String? embyItemId})>> mediaStatuses() {
    final fresh = _statusesAt != null && DateTime.now().difference(_statusesAt!) < const Duration(minutes: 3);
    if (_statuses != null && fresh) return _statuses!;
    _statusesAt = DateTime.now();
    return _statuses = () async {
      final out = <String, ({Availability availability, String? embyItemId})>{};
      const take = 500;
      for (var skip = 0; skip < 20 * take; skip += take) {
        final json = await _get('/api/v1/media', {'take': '$take', 'skip': '$skip', 'filter': 'all'});
        final results = json['results'] as List? ?? const [];
        for (final r in results) {
          if (r is! Map || r['tmdbId'] is! num) continue;
          final type = r['mediaType'] == 'tv' ? 'tv' : 'movie';
          out['$type:${(r['tmdbId'] as num).toInt()}'] = (
            availability: Availability.fromStatus((r['status'] as num?)?.toInt()),
            embyItemId: (r['jellyfinMediaId'] ?? r['embyMediaId']) as String?,
          );
        }
        if (results.length < take) break;
      }
      return out;
    }()
      ..catchError((Object e) {
        _statuses = null;
        return <String, ({Availability availability, String? embyItemId})>{};
      });
  }

  Future<Map<String, ({Availability availability, String? embyItemId})>>? _statuses;
  DateTime? _statusesAt;

  Future<List<SeerrMedia>> search(String query, {int page = 1}) =>
      _results('/api/v1/search', {'query': query, 'page': '$page'});

  Future<SeerrMedia> details(int tmdbId, SeerrMediaType type) async {
    final json = await _get('/api/v1/${type == SeerrMediaType.movie ? 'movie' : 'tv'}/$tmdbId', null, true);
    return SeerrMedia.fromJson(json, type: type)!;
  }

  Future<List<String>> trailerKeys(int tmdbId, SeerrMediaType type) async {
    final json = await _get('/api/v1/${type == SeerrMediaType.movie ? 'movie' : 'tv'}/$tmdbId');
    final videos = [
      for (final v in (json['relatedVideos'] as List? ?? const []))
        if (v is Map && v['site'] == 'YouTube' && v['key'] is String && (v['type'] == 'Trailer' || v['type'] == 'Teaser'))
          v,
    ];
    final trailers = [...videos.where((v) => v['type'] == 'Trailer'), ...videos.where((v) => v['type'] != 'Trailer')];
    return [for (final v in trailers) v['key'] as String];
  }

  Future<List<SeerrMedia>> collectionParts(int tmdbCollectionId) async {
    final json = await _get('/api/v1/collection/$tmdbCollectionId', null, true);
    return [
      for (final p in (json['parts'] as List? ?? const []))
        if (p is Map) ?SeerrMedia.fromJson(p.cast<String, dynamic>(), type: SeerrMediaType.movie),
    ];
  }

  Future<Map<String, dynamic>> movieJson(int tmdbId) => _get('/api/v1/movie/$tmdbId', null, true);

  Future<Map<String, dynamic>> tvJson(int tmdbId) => _get('/api/v1/tv/$tmdbId', null, true);

  Future<Map<String, dynamic>> seasonJson(int tmdbId, int season) =>
      _get('/api/v1/tv/$tmdbId/season/$season', null, true);

  Future<int?> linkedUserId() async {
    final emby = _normalizeId(embyUserId?.call());
    if (emby == null) return null;
    final known = _linked;
    if (known != null && known.emby == emby) return known.id;
    final json = await _get('/api/v1/user', {'take': '1000'});
    int? id;
    for (final u in (json['results'] as List? ?? const [])) {
      if (u is Map && u['id'] is num && _normalizeId(u['jellyfinUserId']) == emby) {
        id = (u['id'] as num).toInt();
        break;
      }
    }
    _linked = (emby: emby, id: id);
    return id;
  }

  ({String emby, int? id})? _linked;

  static String? _normalizeId(Object? id) =>
      id is String && id.isNotEmpty ? id.replaceAll('-', '').toLowerCase() : null;

  Future<List<SeerrRequest>> myRequests({int max = 300}) async {
    int? user;
    var scoped = false;
    try {
      user = await linkedUserId();
      if (user == null) return const [];
    } on SeerrException catch (e) {
      if (e.status != 403) rethrow;
      scoped = true;
    }
    final out = <SeerrRequest>[];
    final seen = <String>{};
    const take = 100;
    for (var skip = 0; skip < max; skip += take) {
      final json = await _get('/api/v1/request', {
        'take': '$take',
        'skip': '$skip',
        'filter': 'all',
        'sort': 'added',
        if (user != null) 'requestedBy': '$user',
      });
      final results = json['results'] as List? ?? const [];
      for (final r in results) {
        if (r is! Map || r['status'] == 3) continue;
        final by = r['requestedBy'];
        if (!scoped && (by is! Map || (by['id'] as num?)?.toInt() != user)) continue;
        final media = r['media'];
        if (media is! Map || media['tmdbId'] is! num) continue;
        final type = (r['type'] ?? media['mediaType']) == 'tv' ? SeerrMediaType.tv : SeerrMediaType.movie;
        final req = SeerrRequest(
          type: type,
          tmdbId: (media['tmdbId'] as num).toInt(),
          availability: Availability.fromStatus((media['status'] as num?)?.toInt()),
          created: DateTime.tryParse('${r['createdAt']}'),
        );
        if (seen.add('${type.name}:${req.tmdbId}')) out.add(req);
      }
      final pages = (json['pageInfo'] as Map?)?['pages'];
      if (pages is num ? skip ~/ take + 1 >= pages : results.length < take) break;
    }
    return out;
  }

  Future<void> request(SeerrMedia media, {List<int>? seasons, bool is4k = false}) async {
    final body = <String, Object?>{
      'mediaType': media.isTv ? 'tv' : 'movie',
      'mediaId': media.tmdbId,
      'is4k': is4k,
      if (media.isTv)
        'seasons': seasons ??
            [for (final s in media.seasons) if (s.number > 0 && s.availability == Availability.none) s.number],
    };
    int? asUser;
    try {
      asUser = await linkedUserId();
    } catch (_) {
    }
    final res = await _http.post(
      _uri('/api/v1/request'),
      headers: {..._headers, if (asUser != null) 'X-Api-User': '$asUser'},
      body: jsonEncode(body),
    );
    if (res.statusCode >= 300) throw SeerrException(res.statusCode, _message(res.body));
  }

  Uri _uri(String path) {
    final base = baseUrl.path.endsWith('/') ? baseUrl.path.substring(0, baseUrl.path.length - 1) : baseUrl.path;
    return baseUrl.replace(path: '$base$path', query: null);
  }

  Map<String, String> get _headers => {
        'X-Api-Key': apiKey,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<List<SeerrMedia>> _results(String path, Map<String, String> query,
      {SeerrMediaType? type, bool localized = true}) async {
    final json = await _get(path, query, localized);
    return [
      for (final r in (json['results'] as List? ?? const []))
        if (r is Map) ?SeerrMedia.fromJson(r.cast<String, dynamic>(), type: type),
    ];
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query, bool localized = false]) async {
    final lang = localized ? language?.split('-').first : null;
    final params = {...?query, 'language': ?lang};
    final uri = _uri(path).replace(queryParameters: params.isEmpty ? null : params);
    final res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
    if (res.statusCode >= 300) throw SeerrException(res.statusCode, _message(res.body));
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  static String _message(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['message'] is String) return j['message'] as String;
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }
}
