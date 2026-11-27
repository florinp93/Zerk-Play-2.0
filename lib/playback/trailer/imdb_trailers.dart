import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

@immutable
final class ImdbPlayback {
  const ImdbPlayback({required this.url, required this.mime, required this.definition});

  final Uri url;
  final String mime;
  final String definition;

  int get height => switch (definition) {
        'DEF_1080p' => 1080,
        'DEF_720p' => 720,
        'DEF_480p' => 480,
        _ => 0,
      };

  DateTime? get expires {
    final seconds = int.tryParse(url.queryParameters['Expires'] ?? '');
    return seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}

@immutable
final class ImdbVideo {
  const ImdbVideo({
    required this.id,
    required this.name,
    required this.seconds,
    required this.isTrailer,
    this.playbacks = const [],
  });

  final String id;
  final String name;
  final int seconds;
  final bool isTrailer;
  final List<ImdbPlayback> playbacks;
}

abstract final class Imdb {
  static final _endpoint = Uri.parse('https://api.graphql.imdb.com/');

  static const _headers = {
    'content-type': 'application/json',
    'x-imdb-client-name': 'imdb-web-next',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/131.0.0.0 Safari/537.36',
  };

  static const _minimumTrailer = 60;

  static Future<List<ImdbVideo>> trailers(String titleId) async {
    final json = await _query('{ title(id:"$titleId") { primaryVideos(first:10) { edges { node { id name{value} '
        'runtime{value} contentType{id} } } } } }');
    return rank(parseTitle(json));
  }

  static Future<ImdbPlayback?> playback(String videoId) async {
    final json = await _query('{ video(id:"$videoId") { id playbackURLs { url videoMimeType videoDefinition } } }');
    final node = (json['data'] as Map?)?['video'];
    return node is Map<String, dynamic> ? bestPlayback(_video(node)) : null;
  }

  static Future<Map<String, dynamic>> _query(String query) async {
    final res = await http
        .post(_endpoint, headers: _headers, body: jsonEncode({'query': query}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode >= 300) throw http.ClientException('IMDb ${res.statusCode}', _endpoint);
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  static List<ImdbVideo> parseTitle(Map<String, dynamic> json) {
    final title = (json['data'] as Map?)?['title'] as Map?;
    final edges = (title?['primaryVideos'] as Map?)?['edges'] as List? ?? const [];
    return [
      for (final edge in edges)
        if (edge is Map && edge['node'] is Map<String, dynamic>) _video(edge['node'] as Map<String, dynamic>),
    ];
  }

  static ImdbVideo _video(Map<String, dynamic> node) => ImdbVideo(
        id: node['id'] as String,
        name: (node['name'] as Map?)?['value'] as String? ?? '',
        seconds: ((node['runtime'] as Map?)?['value'] as num?)?.toInt() ?? 0,
        isTrailer: (node['contentType'] as Map?)?['id'] == 'amzn1.imdb.video.contenttype.trailer',
        playbacks: [
          for (final p in node['playbackURLs'] as List? ?? const [])
            if (p is Map && p['url'] is String)
              ImdbPlayback(
                url: Uri.parse(p['url'] as String),
                mime: p['videoMimeType'] as String? ?? '',
                definition: p['videoDefinition'] as String? ?? '',
              ),
        ],
      );

  static List<ImdbVideo> rank(List<ImdbVideo> videos) {
    final trailers = videos.where((v) => v.isTrailer).toList();
    final long = trailers.where((v) => v.seconds >= _minimumTrailer).toList();
    final candidates = long.isEmpty ? trailers : long;
    int score(ImdbVideo v) {
      final name = v.name.toLowerCase();
      return name.contains('official trailer') ? 2 : name.contains('trailer') ? 1 : 0;
    }

    return candidates.toList()
      ..sort((a, b) {
        final byName = score(b).compareTo(score(a));
        return byName != 0 ? byName : b.seconds.compareTo(a.seconds);
      });
  }

  static ImdbPlayback? bestPlayback(ImdbVideo video) {
    final mp4 = video.playbacks.where((p) => p.mime == 'MP4').toList()..sort((a, b) => b.height.compareTo(a.height));
    if (mp4.isNotEmpty) return mp4.first;
    final hls = video.playbacks.where((p) => p.mime == 'M3U8');
    return hls.isEmpty ? null : hls.first;
  }
}
