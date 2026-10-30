import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/log/logging_http_client.dart';

final class TitleRatings {
  const TitleRatings({this.critics, this.audience, this.certified = false});

  final int? critics;
  final int? audience;
  final bool certified;

  bool get fresh => (critics ?? 0) >= 60;
}

final class MdbListApi {
  MdbListApi(this.apiKey, {http.Client? client}) : _http = client ?? LoggingHttpClient(tag: 'mdblist');

  final String apiKey;
  final http.Client _http;
  final _cache = <String, Future<TitleRatings?>>{};

  Future<Map<String, dynamic>> _title(int tmdbId, bool tv) async {
    final uri = Uri.parse('https://api.mdblist.com/tmdb/${tv ? 'show' : 'movie'}/$tmdbId')
        .replace(queryParameters: {'apikey': apiKey});
    final res = await _http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', uri.replace(query: ''));
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<TitleRatings?> ratings(int tmdbId, {required bool tv}) => _cache.putIfAbsent('$tv:$tmdbId', () async {
        try {
          final json = await _title(tmdbId, tv);
          int? score(String source) {
            for (final r in (json['ratings'] as List? ?? const []).whereType<Map>()) {
              if (r['source'] == source) return (r['value'] as num?)?.round();
            }
            return null;
          }

          final critics = score('tomatoes'), audience = score('popcorn');
          if (critics == null && audience == null) return null;
          final features = json['whatson_features'];
          return TitleRatings(
            critics: critics,
            audience: audience,
            certified: features is Map && features['rotten_tomatoes_critics_certified'] == true,
          );
        } catch (e) {
          debugPrint('[mdblist] ${tv ? 'show' : 'movie'} $tmdbId: $e');
          return null;
        }
      });

  Future<String?> check() async {
    try {
      await _title(603, false);
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
