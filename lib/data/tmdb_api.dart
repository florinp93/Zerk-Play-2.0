import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/log/logging_http_client.dart';

final class TmdbException implements Exception {
  const TmdbException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'TMDB $status: $message';
}

enum TmdbProblemKind { invalidKey, error, unreachable }

final class TmdbProblem {
  const TmdbProblem(this.kind, {this.status, this.message});

  final TmdbProblemKind kind;

  final int? status;
  final String? message;

  @override
  String toString() => [kind.name, ?status, ?message].join(' ');
}

final class TmdbApi {
  TmdbApi({required String apiKey, http.Client? client})
      : apiKey = apiKey.trim(),
        _http = client ?? LoggingHttpClient(tag: 'tmdb');

  final String apiKey;
  final http.Client _http;

  static final _base = Uri.parse('https://api.themoviedb.org/3');

  bool get _isToken => apiKey.startsWith('eyJ');

  Future<bool> ping() async => await check() == null;

  Future<TmdbProblem?> check() async {
    try {
      await get('/configuration');
      return null;
    } on TmdbException catch (e) {
      if (e.status == 401) return const TmdbProblem(TmdbProblemKind.invalidKey);
      return TmdbProblem(TmdbProblemKind.error, status: e.status, message: e.message);
    } catch (_) {
      return const TmdbProblem(TmdbProblemKind.unreachable);
    }
  }

  Future<Map<String, dynamic>?> get(String path, {String? language, Map<String, String> query = const {}}) async {
    final uri = _base.replace(path: '${_base.path}$path', queryParameters: {
      if (!_isToken) 'api_key': apiKey,
      'language': ?language,
      ...query,
    });
    final res = await _http.get(uri, headers: {
      'Accept': 'application/json',
      if (_isToken) 'Authorization': 'Bearer $apiKey',
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 300) throw TmdbException(res.statusCode, _message(res.body));
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> discover(
    bool tv, {
    int page = 1,
    String? language,
    String? sortBy,
    String? watchProviders,
    String? watchRegion,
    int? voteCountGte,
    String? withoutGenres,
    Map<String, String> extra = const {},
  }) async {
    final j = await get('/discover/${tv ? 'tv' : 'movie'}', language: language, query: {
      'page': '$page',
      'include_adult': 'false',
      'sort_by': sortBy ?? 'popularity.desc',
      'with_watch_providers': ?watchProviders,
      'watch_region': ?watchRegion,
      if (voteCountGte != null) 'vote_count.gte': '$voteCountGte',
      'without_genres': ?withoutGenres,
      ...extra,
    });
    return _results(j);
  }

  Future<List<Map<String, dynamic>>> searchMulti(String query, {int page = 1, String? language}) async {
    final j = await get('/search/multi', language: language, query: {
      'query': query,
      'page': '$page',
      'include_adult': 'false',
    });
    return _results(j);
  }

  Future<List<Map<String, dynamic>>> list(String path, {int page = 1, String? language}) async =>
      _results(await get(path, language: language, query: {'page': '$page'}));

  static List<Map<String, dynamic>> _results(Map<String, dynamic>? j) => [
        for (final r in (j?['results'] as List? ?? const []))
          if (r is Map) r.cast<String, dynamic>(),
      ];

  static Uri imageUrl(String path, {required int width, bool logo = false, bool backdrop = false}) {
    final sizes = logo
        ? const [92, 154, 185, 300, 500]
        : backdrop
            ? const [300, 780, 1280]
            : const [92, 154, 185, 342, 500, 780];
    final size = sizes.firstWhere((s) => s >= width, orElse: () => sizes.last);
    return Uri.parse('https://image.tmdb.org/t/p/w$size$path');
  }

  static String _message(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['status_message'] is String) return j['status_message'] as String;
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }
}
