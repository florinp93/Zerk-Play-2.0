import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import 'recommendations.dart';
import 'seerr_api.dart';
import 'taste_profile.dart';
import 'tmdb_api.dart';

final class TitleTag {
  const TitleTag.keyword(int this.id, this.name)
      : genreIds = const [],
        type = null;

  const TitleTag.genres(this.genreIds, this.name, {required SeerrMediaType this.type}) : id = null;

  final int? id;
  final String name;

  final List<int> genreIds;

  final SeerrMediaType? type;

  bool get isKeyword => id != null;

  String get key => isKeyword ? 'k$id' : 'g${type!.name}${genreIds.join('-')}';

  Map<String, String> get filter => isKeyword ? {'with_keywords': '$id'} : {'with_genres': genreIds.join(',')};

  bool covers(SeerrMediaType t) => type == null || type == t;

  @override
  bool operator ==(Object other) => other is TitleTag && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

final class TitleTags {
  TitleTags(this.tmdb, {this.language});

  final TmdbApi tmdb;

  final String? language;

  final _cache = <String, Future<List<TitleTag>>>{};

  static const _noise = {
    'duringcreditsstinger', 'aftercreditsstinger', 'post-credits scene', 'mid-credits scene', 'woman director',
    'based on novel or book', 'based on comic', 'based on manga', 'based on young adult novel', 'based on short story',
    'based on play or musical', 'based on video game', 'based on tv series', 'based on movie', 'sequel', 'prequel',
    'remake', 'reboot', 'spin off', 'live action remake', '3d', 'imax', 'independent film', 'anime',
    'female protagonist', 'male protagonist', 'miniseries', 'limited series', 'tv movie', 'short film',
    'black and white', 'silent film', 'sitcom',
    'dramatic', 'suspenseful', 'intense', 'exhilarated', 'excited', 'hopeful', 'inspirational', 'amused', 'admiring',
    'awestruck', 'bold', 'playful', 'tense', 'cliché', 'thoughtful', 'witty', 'sincere', 'frustrated', 'defiant',
    'vibrant', 'appreciative', 'empathetic', 'compassionate', 'sympathetic', 'joyous', 'romantic', 'melodramatic',
    'absurd', 'provocative', 'harsh', 'grim', 'gloomy', 'somber', 'depressing', 'angry', 'disgusted', 'horrified',
    'ominous', 'foreboding', 'understated', 'enchanting', 'familiar', 'cautionary', 'complicated', 'distressing',
    'hilarious', 'mysterious', 'nostalgic', 'reflective', 'sentimental', 'urgent', 'whimsical', 'zany', 'bewildered',
    'celebratory', 'comforting', 'earnest', 'factual', 'informative', 'loving', 'tragic', 'anxious', 'audacious',
    'complex', 'cheerful', 'enthusiastic', 'joyful', 'powerful', 'adoring', 'aggressive', 'ambiguous', 'wonder',
    'shocking', 'frightened', 'intimate', 'dark', 'lighthearted', 'introspective', 'optimistic', 'enchant', 'critical',
    'melancholy', 'dreary', 'disturbed', 'cynical', 'calm', 'antagonistic', 'dignified', 'frantic', 'candid',
    'affectation', 'ambivalent', 'grand', 'commanding', 'mischievous', 'assertive', 'meditative', 'philosophical',
    'violence', 'brutality', 'sadism', 'biting', 'symbolism', 'tuwaderalit', '3d animation', 'pixar', 'cartoon',
    'adult animation', 'shounen', 'live action and animation', 'based on toy',
  };

  Future<List<TitleTag>> of(int tmdbId, SeerrMediaType type, {int max = 12}) =>
      _cache.putIfAbsent('${type.name}:$tmdbId', () => _load(tmdbId, type, max)).catchError((Object e) {
        debugPrint('[tags] $type $tmdbId: $e');
        _cache.remove('${type.name}:$tmdbId');
        return const <TitleTag>[];
      });

  Future<List<TitleTag>> _load(int tmdbId, SeerrMediaType type, int max) async {
    final tv = type == SeerrMediaType.tv;
    final j = await tmdb.get('/${tv ? 'tv' : 'movie'}/$tmdbId',
        language: language, query: const {'append_to_response': 'keywords'});
    if (j == null) return const [];
    final keywords = j['keywords'] is Map ? (j['keywords'] as Map)[tv ? 'results' : 'keywords'] : null;
    final genres = [
      for (final g in (j['genres'] as List? ?? const []))
        if (g is Map && g['id'] is num && g['name'] is String) (id: (g['id'] as num).toInt(), name: g['name'] as String),
    ];
    return [
      if (genres.length >= 2 && !(RecommendationFilter.hideAnimation && (genres[0].id == 16 || genres[1].id == 16)))
        TitleTag.genres([genres[0].id, genres[1].id], '${genres[0].name} · ${genres[1].name}', type: type),
      ...[
        for (final k in (keywords as List? ?? const []))
          if (k is Map && k['id'] is num && k['name'] is String && _telling(k['name'] as String))
            TitleTag.keyword((k['id'] as num).toInt(), _capitalize(k['name'] as String)),
      ].take(max),
    ];
  }

  static final _launch = Random().nextInt(1 << 30);

  Future<List<TitleTag>> taste(TasteProfile taste, {int count = 8}) async {
    final seeds = <(EmbyItem, double)>[
      for (final (i, m) in taste.recentMovies.take(25).indexed) (m, i < 10 ? 1.5 : 1),
      for (final (i, s) in taste.recentSeries.take(10).indexed) (s, i < 4 ? 1.5 : 1),
    ];
    final lists = await Future.wait([
      for (final (item, _) in seeds)
        if (item.tmdbId case final id?)
          of(id, item.isSeries ? SeerrMediaType.tv : SeerrMediaType.movie)
        else
          Future.value(const <TitleTag>[]),
    ]);
    final scores = <TitleTag, ({double score, int titles})>{};
    for (final (i, tags) in lists.indexed) {
      for (final t in tags) {
        final prev = scores[t];
        scores[t] = (score: (prev?.score ?? 0) + seeds[i].$2, titles: (prev?.titles ?? 0) + 1);
      }
    }
    final ranked = [
      for (final e in scores.entries)
        if (e.value.titles >= 2) (tag: e.key, score: e.value.score),
    ]..sort((a, b) => b.score.compareTo(a.score));
    var pairs = 0;
    final stems = <String>{};
    final kept = <TitleTag>[];
    for (final r in ranked) {
      final tag = r.tag;
      if (!tag.isKeyword && pairs++ > 0) continue;
      if (tag.isKeyword) {
        final own = _stems(tag.name);
        if (own.any(stems.contains)) continue;
        stems.addAll(own);
      }
      kept.add(tag);
    }
    return kept.take(count).toList()..shuffle(Random(_launch));
  }

  static Set<String> _stems(String keyword) => {
        for (final w in keyword.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
          if (w.length >= 4 && !const {'based', 'with', 'from', 'relationship'}.contains(w))
            w.substring(0, w.length < 5 ? w.length : 5),
      };

  static bool _telling(String keyword) => !keyword.contains(',') && !_noise.contains(keyword.toLowerCase());

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
