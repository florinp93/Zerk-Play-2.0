import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/seerr_api.dart';

@immutable
final class TrailerStream {
  const TrailerStream(this.video, {this.audio});

  final Uri video;
  final Uri? audio;
}

@immutable
final class TrailerRef {
  const TrailerRef(this.videoId, {this.label});

  final String videoId;

  final String? label;

  static final _cache = <String, ({DateTime at, Future<TrailerStream> streams})>{};

  static const _cacheFor = Duration(hours: 1);

  Future<TrailerStream> resolve() {
    final hit = _cache[videoId];
    if (hit != null && DateTime.now().difference(hit.at) < _cacheFor) return hit.streams;
    final streams = _resolve();
    _cache[videoId] = (at: DateTime.now(), streams: streams);
    streams.catchError((Object _) {
      _cache.remove(videoId);
      return TrailerStream(Uri());
    });
    return streams;
  }

  Future<TrailerStream> _resolve() async {
    final manifest = await Trailers._yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 15));
    int codecRank(VideoStreamInfo v) {
      final c = v.videoCodec.toLowerCase();
      return c.startsWith('avc') ? 0 : c.startsWith('vp9') || c.startsWith('vp09') ? 1 : 2;
    }

    final video = manifest.videoOnly.where((v) => v.videoResolution.height <= 1080).toList()
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
      return TrailerStream(video.first.url, audio: audio.first.url);
    }
    final muxed = manifest.muxed.sortByVideoQuality();
    if (muxed.isNotEmpty) return TrailerStream(muxed.first.url);
    throw StateError('no playable streams for $videoId');
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
  String toString() => label == null ? 'YouTube $videoId' : 'YouTube $videoId ($label)';
}

@immutable
final class _TrailerLanguage {
  const _TrailerLanguage({required this.queries, this.markers = const [], this.keywords = const []});

  final List<String> queries;

  final List<String> markers;

  final List<String> keywords;
}

abstract final class Trailers {
  static final _cache = <String, Future<List<TrailerRef>>>{};
  static final YoutubeExplode _yt = YoutubeExplode();

  static const _languages = {
    'ro': _TrailerLanguage(
      queries: ['trailer subtitrat in romana', 'trailer romana'],
      markers: ['subtitrat', 'subtitrare', 'romana', 'romania', 'romanesc', 'romaneasca', 'dublat'],
    ),
    'fr': _TrailerLanguage(
      queries: ['bande annonce vf', 'bande annonce vostfr'],
      markers: ['vf', 'vostfr', 'francais', 'french'],
      keywords: ['bande annonce', 'bande-annonce'],
    ),
    'de': _TrailerLanguage(queries: ['trailer deutsch'], markers: ['deutsch', 'german', 'ger']),
    'es': _TrailerLanguage(
      queries: ['trailer español', 'trailer subtitulado'],
      markers: ['espanol', 'castellano', 'subtitulado', 'latino', 'doblado'],
    ),
    'it': _TrailerLanguage(queries: ['trailer italiano'], markers: ['italiano', 'ita', 'sottotitoli']),
    'pt': _TrailerLanguage(
      queries: ['trailer legendado', 'trailer dublado'],
      markers: ['legendado', 'dublado', 'portugues', 'brasil'],
    ),
    'hu': _TrailerLanguage(
      queries: ['magyar előzetes', 'magyar feliratos előzetes'],
      markers: ['magyar', 'feliratos', 'szinkron'],
      keywords: ['elozetes'],
    ),
    'ja': _TrailerLanguage(queries: ['予告編'], markers: ['予告', '日本'], keywords: ['予告']),
    'ko': _TrailerLanguage(queries: ['예고편'], markers: ['예고편', '한국'], keywords: ['예고']),
  };

  static Future<List<TrailerRef>> forItem(AppServices s, EmbyItem item) {
    if (!item.isMovie && !item.isSeries) return Future.value(const []);
    return find(
      s,
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
    int? tmdbId,
    required bool tv,
    required List<String> titles,
    int? year,
  }) {
    final lang = s.settings.trailerLanguage.split('-').first;
    final key = '$lang:${tmdbId ?? titles.first}:${tv ? 'tv' : 'movie'}:$year';
    return _cache.putIfAbsent(key, () async {
      try {
        final stored = await _stored(key);
        if (stored != null) return stored;
        final refs = _dedupe(await _find(s, lang, tmdbId, tv, titles, year));
        await _store(key, refs);
        return refs;
      } catch (e) {
        debugPrint('[trailer] lookup ${titles.first}: $e');
        _cache.remove(key);
        return const <TrailerRef>[];
      }
    });
  }

  static const _storeKey = 'trailers.v1';

  static Future<List<TrailerRef>?> _stored(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = jsonDecode(prefs.getString(_storeKey) ?? '{}') as Map<String, dynamic>;
      final e = all[key];
      if (e is! Map) return null;
      final ids = (e['ids'] as List).cast<String>();
      final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(e['at'] as int));
      if (age > (ids.isEmpty ? const Duration(days: 1) : const Duration(days: 7))) return null;
      return [for (final id in ids) TrailerRef(id, label: 'cached')];
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
      all[key] = {'at': now.millisecondsSinceEpoch, 'ids': [for (final r in refs.take(6)) r.videoId]};
      await prefs.setString(_storeKey, jsonEncode(all));
    } catch (_) {}
  }

  static Future<List<TrailerRef>> _find(
      AppServices s, String lang, int? tmdbId, bool tv, List<String> titles, int? year) async {
    final tmdb = s.tmdb;
    final refs = <TrailerRef>[];
    final language = _languages[lang];
    if (language != null) {
      final localized = <String>{};
      if (tmdb != null && tmdbId != null) {
        try {
          final json = await tmdb.get('/${tv ? 'tv' : 'movie'}/$tmdbId', language: lang);
          final name = json?[tv ? 'name' : 'title'] as String?;
          if (name != null && !titles.contains(name)) localized.add(name);
        } catch (_) {}
      }
      if (tmdbId != null) refs.addAll(await _tmdbVideos(s, tmdbId, tv, only: lang));
      refs.addAll(await _search(titles, year, language, localized: localized));
    }
    if (tmdbId != null) refs.addAll(await _tmdbVideos(s, tmdbId, tv));
    if (refs.isEmpty) {
      refs.addAll(await _search(titles, year, const _TrailerLanguage(queries: ['official trailer'])));
    }
    return refs;
  }

  static Future<List<TrailerRef>> _tmdbVideos(AppServices s, int tmdbId, bool tv, {String? only}) async {
    try {
      final tmdb = s.tmdb;
      if (tmdb != null) {
        final json = await tmdb.get('/${tv ? 'tv' : 'movie'}/$tmdbId/videos', query: {
          'include_video_language': {?only, 'en', 'null'}.join(','),
        });
        final videos = [
          for (final v in (json?['results'] as List? ?? const []))
            if (v is Map &&
                v['site'] == 'YouTube' &&
                v['key'] is String &&
                (v['type'] == 'Trailer' || v['type'] == 'Teaser') &&
                (only == null || v['iso_639_1'] == only))
              v,
        ];
        double score(Map v) =>
            (v['type'] == 'Trailer' ? 4 : 0) + (v['official'] == true ? 2 : 0) + (v['iso_639_1'] == 'en' ? 1 : 0);
        final ranked = [for (var i = 0; i < videos.length; i++) (i, videos[i])]
          ..sort((a, b) {
            final c = score(b.$2).compareTo(score(a.$2));
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
        return [for (final (_, v) in ranked) TrailerRef(v['key'] as String, label: 'TMDB ${v['iso_639_1']}')];
      }
      final seerr = s.seerr;
      if (seerr != null && only == null) {
        final keys = await seerr.trailerKeys(tmdbId, tv ? SeerrMediaType.tv : SeerrMediaType.movie);
        return [for (final k in keys) TrailerRef(k, label: '*seerr')];
      }
    } catch (e) {
      debugPrint('[trailer] tmdb videos of $tmdbId: $e');
    }
    return const [];
  }

  static Future<List<TrailerRef>> _search(List<String> titles, int? year, _TrailerLanguage language,
      {Set<String> localized = const {}}) async {
    final names = {_bestTitle(titles), ...localized};
    final phrases = language.queries;
    for (var i = 0; i < phrases.length; i++) {
      final found = await _searchOnce(titles, year, language, localized, [
        for (final n in names) '$n${year == null ? '' : ' $year'} ${phrases[i]}',
      ]);
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  static Future<List<TrailerRef>> _searchOnce(
      List<String> titles, int? year, _TrailerLanguage language, Set<String> localized, List<String> queries) async {
    final pages = await Future.wait([
      for (final q in queries)
        _yt.search.search(q).timeout(const Duration(seconds: 15)).then<List<Video>>((r) => r, onError: (Object e) {
          debugPrint('[trailer] search "$q": $e');
          return const <Video>[];
        }),
    ]);
    final results = [for (final p in pages) ...p];
    final keywords = ['trailer', 'teaser', ...language.keywords];
    final filler = {
      ..._filler,
      for (final k in [...keywords, ...language.markers]) ..._words(k),
    };
    List<String> significant(String t) => _words(t).where((w) => w.length > 1 && !RegExp(r'^\d+$').hasMatch(w)).toList();
    final titleWords = [for (final t in titles) significant(t)];
    final localizedWords = [for (final t in localized) significant(t)];
    double matchOf(List<List<String>> names, List<Set<String>> segments) {
      var best = 0.0;
      for (final seg in segments) {
        for (final name in names) {
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
      final words = _words(v.title).toSet();
      final segments = [
        for (final part in _normalize(v.title).split(_separators))
          if (significant(part).where((w) => !filler.contains(w)).toSet() case final seg when seg.isNotEmpty) seg,
      ];
      final localMatch = matchOf(localizedWords, segments);
      final match = [matchOf(titleWords, segments), localMatch].reduce((a, b) => a > b ? a : b);
      if (match < 0.6) continue;
      if (year != null) {
        final years = RegExp(r'\b(19|20)\d\d\b').allMatches(text).map((m) => int.parse(m.group(0)!));
        if (years.isNotEmpty && years.every((y) => (y - year).abs() > 1)) continue;
      }
      final author = _normalize(v.author);
      final marked = language.markers.isEmpty ||
          localMatch >= 0.6 ||
          language.markers.any((m) => words.contains(m) || (m.length > 3 && (text.contains(m) || author.contains(m))));
      scored.add((match + (marked ? 2 : 0), i, v));
    }
    scored.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    final hasMarkers = language.markers.isNotEmpty;
    return [
      for (final (score, _, v) in scored)
        if (!hasMarkers || score >= 2) TrailerRef(v.id.value, label: 'search: ${v.title}'),
    ];
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
    return [for (final r in refs) if (seen.add(r.videoId)) r];
  }
}
