import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../core/host.dart';
import '../../data/seerr_api.dart';
import 'imdb_trailers.dart';

@immutable
final class TrailerStream {
  const TrailerStream(this.video, {this.audio, this.expires});

  final Uri video;
  final Uri? audio;
  final DateTime? expires;
}

enum TrailerSource { imdb, youtube }

final class _Resolved {
  _Resolved(this.stream) : at = DateTime.now();

  final Future<TrailerStream> stream;
  final DateTime at;
  DateTime? expires;

  bool get usable {
    final until = expires;
    if (until == null) return DateTime.now().difference(at) < const Duration(hours: 1);
    return until.difference(DateTime.now()) > const Duration(hours: 4);
  }
}

@immutable
final class TrailerRef {
  const TrailerRef(this.source, this.id, {this.label});

  final TrailerSource source;

  final String id;

  final String? label;

  static final _cache = <String, _Resolved>{};

  Future<TrailerStream> resolve() {
    final key = '${source.name}:$id';
    final hit = _cache[key];
    if (hit != null && hit.usable) return hit.stream;
    final stream = switch (source) {
      TrailerSource.imdb => _resolveImdb(),
      TrailerSource.youtube => _resolveYoutube(),
    };
    final entry = _cache[key] = _Resolved(stream);
    stream.then((s) => entry.expires = s.expires, onError: (Object _) {
      _cache.remove(key);
      return null;
    });
    return stream;
  }

  Future<TrailerStream> _resolveImdb() async {
    final playback = await Imdb.playback(id);
    if (playback == null) throw StateError('no playable streams for $id');
    debugPrint('[trailer] $id: ${playback.mime} ${playback.definition}');
    return TrailerStream(playback.url, expires: playback.expires);
  }

  Future<TrailerStream> _resolveYoutube() async {
    final manifest = await Trailers._yt.videos.streamsClient.getManifest(id).timeout(const Duration(seconds: 15));
    int codecRank(VideoStreamInfo v) {
      final c = v.videoCodec.toLowerCase();
      return c.startsWith('avc') ? 0 : c.startsWith('vp9') || c.startsWith('vp09') ? 1 : 2;
    }

    bool deepColour(VideoStreamInfo v) {
      final c = v.videoCodec.toLowerCase();
      return c.startsWith('vp09.02') || c.startsWith('vp9.2') || (c.startsWith('av01') && c.contains('.10'));
    }

    final video = manifest.videoOnly
        .where((v) => v.videoResolution.height <= 1080 && !deepColour(v) && (!Host.isAndroid || codecRank(v) == 0))
        .toList()
      ..sort((a, b) {
        final byHeight = b.videoResolution.height.compareTo(a.videoResolution.height);
        if (byHeight != 0) return byHeight;
        final byCodec = codecRank(a).compareTo(codecRank(b));
        return byCodec != 0 ? byCodec : b.bitrate.compareTo(a.bitrate);
      });
    final audio = manifest.audioOnly.toList()
      ..sort((a, b) {
        final aDefault = a.audioTrack?.audioIsDefault ?? true, bDefault = b.audioTrack?.audioIsDefault ?? true;
        if (aDefault != bDefault) return aDefault ? -1 : 1;
        return b.bitrate.compareTo(a.bitrate);
      });
    if (video.isNotEmpty && audio.isNotEmpty && await _servedInFull(video.first)) {
      final v = video.first;
      debugPrint('[trailer] $id: ${v.videoResolution.height}p ${v.videoCodec} ${v.container.name}'
          ' + ${audio.first.audioCodec} (${manifest.videoOnly.length} video streams offered)');
      return TrailerStream(v.url, audio: audio.first.url);
    }
    final muxed = manifest.muxed.sortByVideoQuality();
    if (muxed.isNotEmpty) {
      debugPrint('[trailer] $id: muxed ${muxed.first.videoResolution.height}p ${muxed.first.videoCodec}');
      return TrailerStream(muxed.first.url);
    }
    throw StateError('no playable streams for $id');
  }

  static Future<bool> _servedInFull(StreamInfo s) async {
    final at = s.size.totalBytes * 3 ~/ 4;
    try {
      final res = await http.get(Uri.parse('${s.url}&range=$at-${at + 1023}')).timeout(const Duration(seconds: 6));
      return res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  String toString() => label == null ? '${source.name} $id' : '${source.name} $id ($label)';
}

abstract final class Trailers {
  static final _cache = <String, Future<List<TrailerRef>>>{};
  static final YoutubeExplode _yt = YoutubeExplode();

  static Future<List<TrailerRef>> forItem(AppServices s, EmbyItem item) {
    if (!item.isMovie && !item.isSeries) return Future.value(const []);
    return find(
      s,
      imdbId: item.imdbId,
      tmdbId: item.tmdbId,
      tv: item.isSeries,
      titles: [item.name, ?item.originalTitle],
      year: item.productionYear,
    );
  }

  static Future<List<TrailerRef>> forSeerr(AppServices s, SeerrMedia m) =>
      find(s, tmdbId: m.tmdbId, tv: m.isTv, titles: [m.title], year: m.year);

  static Future<List<TrailerRef>> find(
    AppServices s, {
    String? imdbId,
    int? tmdbId,
    required bool tv,
    required List<String> titles,
    int? year,
  }) {
    final key = '${imdbId ?? tmdbId ?? titles.first}:${tv ? 'tv' : 'movie'}:$year';
    return _cache.putIfAbsent(key, () async {
      try {
        final stored = await _stored(key);
        if (stored != null) return stored;
        final refs = _dedupe(await _find(s, imdbId, tmdbId, tv, titles, year));
        await _store(key, refs);
        return refs;
      } catch (e) {
        debugPrint('[trailer] lookup ${titles.first}: $e');
        _cache.remove(key);
        return const <TrailerRef>[];
      }
    });
  }

  static const _storeKey = 'trailers.v2';

  static Future<List<TrailerRef>?> _stored(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = jsonDecode(prefs.getString(_storeKey) ?? '{}') as Map<String, dynamic>;
      final e = all[key];
      if (e is! Map) return null;
      final refs = [
        for (final r in e['refs'] as List)
          TrailerRef(TrailerSource.values.byName(r['source'] as String), r['id'] as String, label: 'cached'),
      ];
      final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(e['at'] as int));
      if (age > (refs.isEmpty ? const Duration(days: 1) : const Duration(days: 7))) return null;
      return refs;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _store(String key, List<TrailerRef> refs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = jsonDecode(prefs.getString(_storeKey) ?? '{}') as Map<String, dynamic>;
      final now = DateTime.now();
      all.removeWhere((_, e) =>
          e is! Map || now.difference(DateTime.fromMillisecondsSinceEpoch(e['at'] as int)) > const Duration(days: 7));
      all[key] = {
        'at': now.millisecondsSinceEpoch,
        'refs': [for (final r in refs.take(6)) {'source': r.source.name, 'id': r.id}],
      };
      await prefs.setString(_storeKey, jsonEncode(all));
    } catch (_) {}
  }

  static Future<List<TrailerRef>> _find(
      AppServices s, String? imdbId, int? tmdbId, bool tv, List<String> titles, int? year) async {
    final fromImdb = await _imdb(s, imdbId, tmdbId, tv);
    if (fromImdb.isNotEmpty) return fromImdb;
    return [
      if (tmdbId != null) ...await _tmdbVideos(s, tmdbId, tv),
      ...await _search(titles, year),
    ];
  }

  static Future<List<TrailerRef>> _imdb(AppServices s, String? imdbId, int? tmdbId, bool tv) async {
    try {
      final id = imdbId ?? await _imdbIdOf(s, tmdbId, tv);
      if (id == null) return const [];
      final videos = await Imdb.trailers(id);
      return [for (final v in videos.take(3)) TrailerRef(TrailerSource.imdb, v.id, label: v.name)];
    } catch (e) {
      debugPrint('[trailer] imdb lookup: $e');
      return const [];
    }
  }

  static Future<String?> _imdbIdOf(AppServices s, int? tmdbId, bool tv) async {
    if (tmdbId == null) return null;
    final tmdb = s.tmdb;
    if (tmdb != null) {
      final json = await tmdb.get('/${tv ? 'tv' : 'movie'}/$tmdbId/external_ids');
      return json?['imdb_id'] as String?;
    }
    return s.seerr?.imdbId(tmdbId, tv ? SeerrMediaType.tv : SeerrMediaType.movie);
  }

  static Future<List<TrailerRef>> _tmdbVideos(AppServices s, int tmdbId, bool tv) async {
    try {
      final tmdb = s.tmdb;
      if (tmdb != null) {
        final json = await tmdb.get('/${tv ? 'tv' : 'movie'}/$tmdbId/videos', query: {
          'include_video_language': 'en,null',
        });
        final videos = [
          for (final v in (json?['results'] as List? ?? const []))
            if (v is Map &&
                v['site'] == 'YouTube' &&
                v['key'] is String &&
                (v['type'] == 'Trailer' || v['type'] == 'Teaser'))
              v,
        ];
        double score(Map v) =>
            (v['type'] == 'Trailer' ? 4 : 0) + (v['official'] == true ? 2 : 0) + (v['iso_639_1'] == 'en' ? 1 : 0);
        final ranked = [for (var i = 0; i < videos.length; i++) (i, videos[i])]
          ..sort((a, b) {
            final c = score(b.$2).compareTo(score(a.$2));
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
        return [
          for (final (_, v) in ranked) TrailerRef(TrailerSource.youtube, v['key'] as String, label: 'TMDB ${v['iso_639_1']}'),
        ];
      }
      final seerr = s.seerr;
      if (seerr != null) {
        final keys = await seerr.trailerKeys(tmdbId, tv ? SeerrMediaType.tv : SeerrMediaType.movie);
        return [for (final k in keys) TrailerRef(TrailerSource.youtube, k, label: '*seerr')];
      }
    } catch (e) {
      debugPrint('[trailer] tmdb videos of $tmdbId: $e');
    }
    return const [];
  }

  static Future<List<TrailerRef>> _search(List<String> titles, int? year) async {
    final query = '${_bestTitle(titles)}${year == null ? '' : ' $year'} official trailer';
    final List<Video> results;
    try {
      results = (await _yt.search.search(query).timeout(const Duration(seconds: 15))).toList();
    } catch (e) {
      debugPrint('[trailer] search "$query": $e');
      return const [];
    }
    const keywords = ['trailer', 'teaser'];
    final filler = {..._filler, for (final k in keywords) ..._words(k)};
    List<String> significant(String t) => _words(t).where((w) => w.length > 1 && !RegExp(r'^\d+$').hasMatch(w)).toList();
    final titleWords = [for (final t in titles) significant(t)];
    double matchOf(List<Set<String>> segments) {
      var best = 0.0;
      for (final seg in segments) {
        for (final name in titleWords) {
          if (name.isEmpty) continue;
          final common = name.where(seg.contains).length;
          final coverage = common / name.length;
          if (coverage >= 0.6 && common / seg.length > 0.5 && coverage > best) best = coverage;
        }
      }
      return best;
    }
    final scored = <(double, int, Video)>[];
    final seen = <String>{};
    for (var i = 0; i < results.length; i++) {
      final v = results[i];
      if (!seen.add(v.id.value)) continue;
      final d = v.duration;
      if (d == null || d < const Duration(seconds: 50) || d > const Duration(minutes: 5)) continue;
      final text = _normalize(v.title);
      if (text.contains('#shorts') || !keywords.any(text.contains)) continue;
      if (_isNoise(text)) continue;
      final segments = [
        for (final part in _normalize(v.title).split(_separators))
          if (significant(part).where((w) => !filler.contains(w)).toSet() case final seg when seg.isNotEmpty) seg,
      ];
      final match = matchOf(segments);
      if (match < 0.6) continue;
      if (year != null) {
        final years = RegExp(r'\b(19|20)\d\d\b').allMatches(text).map((m) => int.parse(m.group(0)!));
        if (years.isNotEmpty && years.every((y) => (y - year).abs() > 1)) continue;
      }
      scored.add((match, i, v));
    }
    scored.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return [for (final (_, _, v) in scored) TrailerRef(TrailerSource.youtube, v.id.value, label: 'search: ${v.title}')];
  }

  static final _separators = RegExp(r'\s[-–—]\s|[|/()\[\]•·]');

  static const _filler = {
    'official', 'oficial', 'oficiala', 'officiel', 'officielle', 'ufficiale', 'offizieller', 'new', 'nou', 'noul',
    'noua', 'nouvelle', 'nuevo', 'neuer', 'final', 'main', 'hd', 'uhd', '4k', 'movie', 'film', 'filmul', 'in',
    'cu', 'with', 'au', 'cinema', 'cinemas', 'theaters', 'cinematografe', 'only', 'doar', 'exclusive',
  };

  static bool _isNoise(String t) => const [
        'review', 'recenzie', 'reaction', 'reactie', 'explained', 'breakdown', 'full movie', 'film complet',
        'fan made', 'fanmade', 'concept trailer', 'parody', 'parodie', 'game trailer', 'gameplay',
      ].any(t.contains);

  static String _bestTitle(List<String> titles) =>
      titles.reduce((a, b) => _words(b).length > _words(a).length ? b : a);

  static List<String> _words(String s) =>
      _normalize(s).split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).toList();

  static const _plain = {
    'ă': 'a', 'â': 'a', 'á': 'a', 'à': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'î': 'i', 'í': 'i', 'ì': 'i', 'ï': 'i',
    'ș': 's', 'ş': 's', 'ț': 't', 'ţ': 't',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'ő': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ű': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  static String _normalize(String s) {
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      b.write(_plain[ch] ?? ch);
    }
    return b.toString();
  }

  static List<TrailerRef> _dedupe(List<TrailerRef> refs) {
    final seen = <String>{};
    return [for (final r in refs) if (seen.add('${r.source.name}:${r.id}')) r];
  }
}
