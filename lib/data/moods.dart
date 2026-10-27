import 'dart:math';

import 'recommendations.dart';
import 'seerr_api.dart';

final class Mood {
  const Mood(
    this.id, {
    required this.backdrop,
    this.movie,
    this.tv,
    this.hints = const [],
    this.hours,
    this.weekend = false,
    this.color = 0xFF6C63FF,
  });

  final String id;

  final String backdrop;

  Uri backdropUrl({int width = 780}) =>
      Uri.parse('https://image.tmdb.org/t/p/${width > 780 ? 'w1280' : 'w780'}$backdrop');

  final Map<String, String>? movie;
  final Map<String, String>? tv;

  final List<String> hints;

  final (int, int)? hours;

  final bool weekend;

  final int color;

  bool availableAt(DateTime t) {
    final h = hours;
    if (h == null) return true;
    final (from, to) = h;
    return from <= to ? t.hour >= from && t.hour < to : t.hour >= from || t.hour < to;
  }

  Future<MixedItems> items(Recommender r, {bool tv = false, bool topRated = false, int pages = 2}) {
    final query = tv ? this.tv : movie;
    if (query == null) return Future.value(const []);
    final extra = {
      ...query,
      if (topRated) 'sort_by': 'vote_average.desc',
      if (topRated) 'vote_count.gte': '${max(int.tryParse(query['vote_count.gte'] ?? '') ?? 0, tv ? 300 : 800)}',
    };
    return r.mixed(
      (p) => r.discover(tv ? SeerrMediaType.tv : SeerrMediaType.movie, page: p, extra: extra),
      pages: pages,
    );
  }

  static const _kw = 'with_keywords';
  static const _votes = 'vote_count.gte';

  static final _twoYearsAgo = DateTime.now().subtract(const Duration(days: 730)).toIso8601String().substring(0, 10);

  static final all = <Mood>[
    Mood('trueStory',
        backdrop: '/neeNHeXjMF5fXoCJRsOmkNGC7q.jpg',
        movie: {_kw: '9672', _votes: '300'},
        tv: {_kw: '9672', _votes: '100'},
        hints: ['histor', 'istor', 'biogra', 'drama', 'dramă'],
        color: 0xFFB08D57),
    Mood('heist',
        backdrop: '/ncoqdHs1poUaBqyKic9YI8ai7MP.jpg',
        movie: {_kw: '10051|191845', _votes: '200'},
        tv: {_kw: '10051', _votes: '50'},
        hints: ['crime', 'crim', 'thriller'],
        color: 0xFF2E9E8F),
    Mood('whodunit',
        backdrop: '/4HWAQu28e2yaWrtupFPGFkdNU7V.jpg',
        movie: {_kw: '12570|381354', _votes: '100'},
        tv: {_kw: '12570|381354', _votes: '50'},
        hints: ['myster', 'mister', 'crime', 'crim'],
        color: 0xFF7B5EA7),
    Mood('mindBending',
        backdrop: '/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg',
        movie: {'with_genres': '878', _votes: '3000', 'sort_by': 'vote_average.desc'},
        hints: ['science', 'sci-fi', 'sf', 'fantas'],
        color: 0xFF3D7BD9),
    Mood('space',
        backdrop: '/8sNiAPPYU14PUepFNeSNGUTiHW.jpg',
        movie: {_kw: '9882|3801', _votes: '300'},
        tv: {_kw: '9882|3801', _votes: '100'},
        hints: ['science', 'sci-fi', 'sf'],
        color: 0xFF4A3FB5),
    Mood('survival',
        backdrop: '/gqrnQA6Xppdl8vIb2eJc58VC1tW.jpg',
        movie: {_kw: '10349', _votes: '300'},
        tv: {_kw: '10349', _votes: '100'},
        hints: ['action', 'acțiune', 'actiune', 'aventur', 'adventure', 'thriller'],
        color: 0xFF7A8B3C),
    Mood('revenge',
        backdrop: '/ff2ti5DkA9UYLzyqhQfI2kZqEuh.jpg',
        movie: {_kw: '9748', _votes: '300'},
        hints: ['action', 'acțiune', 'actiune', 'thriller', 'crime'],
        color: 0xFFA8322D),
    Mood('conspiracy',
        backdrop: '/qiBILuWhv7ipF0pxiEqIJdkQzj8.jpg',
        movie: {_kw: '10410', _votes: '200'},
        tv: {_kw: '10410', _votes: '100'},
        hints: ['thriller', 'myster', 'mister', 'politic'],
        color: 0xFF4F6D7A),
    Mood('roadTrip',
        backdrop: '/twdtjJm31AExNx73DXaD4KRNU9c.jpg',
        movie: {_kw: '7312', _votes: '200'},
        hints: ['comed', 'aventur', 'adventure'],
        color: 0xFFE08E3C),
    Mood('comingOfAge',
        backdrop: '/yjGllQUm28R4X9xD9T5xMszirgw.jpg',
        movie: {_kw: '10683', _votes: '300'},
        tv: {_kw: '10683', _votes: '100'},
        hints: ['drama', 'dramă', 'comed'],
        color: 0xFFD9779B),
    Mood('feelGood',
        backdrop: '/jK65srQczOKTpW62wPxwwKztGgE.jpg',
        movie: {'with_genres': '35', 'vote_average.gte': '7', _votes: '1500'},
        tv: {'with_genres': '35', 'vote_average.gte': '7.5', _votes: '300'},
        hints: ['comed', 'romance', 'romant', 'family', 'famil'],
        weekend: true,
        color: 0xFFF2B33D),
    Mood('serialKiller',
        backdrop: '/i5H7zusQGsysGQ8i6P361Vnr0n2.jpg',
        movie: {_kw: '10714', _votes: '300'},
        tv: {_kw: '10714', _votes: '100'},
        hints: ['crime', 'crim', 'thriller', 'horror', 'groază'],
        hours: (19, 4),
        color: 0xFF8E1F2F),
    Mood('lateNightHorror',
        backdrop: '/AdKA2F1SzYPhSZdEbjH1Zh75UVQ.jpg',
        movie: {'with_genres': '27', _votes: '800'},
        tv: {'with_genres': '9648', _kw: '315058|6152', _votes: '50'},
        hints: ['horror', 'groază', 'groaza'],
        hours: (20, 4),
        color: 0xFF5A1A2B),
    Mood('classics',
        backdrop: '/5bzPWQ2dFUl2aZKkp7ILJVVkRed.jpg',
        movie: {'primary_release_date.gte': '1980-01-01', 'primary_release_date.lte': '1999-12-31', _votes: '3000',
            'sort_by': 'vote_average.desc'},
        tv: {'first_air_date.gte': '1980-01-01', 'first_air_date.lte': '1999-12-31', _votes: '500',
            'sort_by': 'vote_average.desc'},
        color: 0xFFB5651D),
    Mood('hiddenGems',
        backdrop: '/mvUAo9ACgmLpS4Ofc2IwD4n7WCt.jpg',
        movie: {'vote_average.gte': '7.2', _votes: '300', 'vote_count.lte': '2500', 'with_original_language': 'en',
            'without_genres': '99|10751|10770', 'primary_release_date.lte': _twoYearsAgo},
        tv: {'vote_average.gte': '7.8', _votes: '150', 'vote_count.lte': '1000', 'with_original_language': 'en',
            'without_genres': '99|10762|10751', 'first_air_date.lte': _twoYearsAgo},
        color: 0xFF2F8F5B),
    Mood('quickWatch',
        backdrop: '/fRGxZuo7jJUWQsVg9PREb98Aclp.jpg',
        movie: {'with_runtime.lte': '95', 'with_runtime.gte': '60', 'vote_average.gte': '7', _votes: '1000'},
        hours: (17, 24),
        color: 0xFF3AA6B9),
    Mood('bingeWorthy',
        backdrop: '/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg',
        tv: {'vote_average.gte': '8', _votes: '1000', 'with_status': '3', 'sort_by': 'vote_average.desc'},
        weekend: true,
        color: 0xFF6C63FF),
  ];

  static final _launch = Random().nextInt(1 << 30);

  static List<Mood> pick({required List<String> favoriteGenres, DateTime? now, int count = 8}) {
    final t = now ?? DateTime.now();
    final random = Random(_launch);
    final genres = [for (final g in favoriteGenres.take(5)) g.toLowerCase()];
    final weekend = t.weekday >= DateTime.saturday;
    final scored = [
      for (final m in all)
        if (m.availableAt(t))
          (
            mood: m,
            score: random.nextDouble() * 2 +
                [
                  for (final (i, g) in genres.indexed)
                    if (m.hints.any(g.contains)) 1.5 - i * 0.2,
                ].fold(0.0, (a, b) => a + b).clamp(0.0, 2.5) +
                (m.hours != null ? 1.2 : 0) +
                (m.weekend && weekend ? 1.0 : 0),
          ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return [for (final s in scored.take(count)) s.mood];
  }
}
