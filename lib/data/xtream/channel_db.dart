part of 'live_catalog.dart';

enum Genre { general, news, sports, movies, series, kids, music, documentary, entertainment, other }

const _genres = {
  'sports': Genre.sports,
  'news': Genre.news,
  'weather': Genre.news,
  'business': Genre.news,
  'kids': Genre.kids,
  'animation': Genre.kids,
  'movies': Genre.movies,
  'series': Genre.series,
  'music': Genre.music,
  'documentary': Genre.documentary,
  'science': Genre.documentary,
  'travel': Genre.documentary,
  'outdoor': Genre.documentary,
  'education': Genre.documentary,
  'culture': Genre.documentary,
  'general': Genre.general,
  'public': Genre.general,
  'legislative': Genre.general,
  'entertainment': Genre.entertainment,
  'comedy': Genre.entertainment,
  'lifestyle': Genre.entertainment,
  'cooking': Genre.entertainment,
  'classic': Genre.entertainment,
  'family': Genre.entertainment,
  'auto': Genre.entertainment,
  'relax': Genre.entertainment,
};

final class _DbChannel {
  _DbChannel(this.id, this.country, this.genre, this.adult, this.logo);

  final String id;
  final String country;
  Genre genre;
  final bool adult;
  final String? logo;
}

final class _ChannelDb {
  _ChannelDb._(this._byId, this._byName);

  final Map<String, _DbChannel> _byId;

  final Map<String, List<_DbChannel>> _byName;

  static const _api = 'https://iptv-org.github.io/api';

  static Future<_ChannelDb?> load(http.Client client, String? folder) async {
    try {
      final channels = await _file(client, folder, 'channels.json');
      final logos = await _file(client, folder, 'logos.json');
      final logo = <String, (int, String)>{};
      for (final l in jsonDecode(logos) as List) {
        if (l['feed'] != null || l['in_use'] == false) continue;
        final format = '${l['format']}'.toUpperCase();
        if (format == 'SVG') continue;
        final width = (l['width'] as num?)?.toInt() ?? 0;
        final id = '${l['channel']}';
        if ((logo[id]?.$1 ?? -1) < width) logo[id] = (width, '${l['url']}');
      }
      final byId = <String, _DbChannel>{};
      final byName = <String, List<_DbChannel>>{};
      for (final c in jsonDecode(channels) as List) {
        if (c['closed'] != null) continue;
        final categories = (c['categories'] as List?)?.cast<String>() ?? const [];
        final genre = _genres.entries.where((e) => categories.contains(e.key)).firstOrNull?.value ?? Genre.other;
        final id = '${c['id']}';
        final channel = _DbChannel(
          id,
          '${c['country']}',
          genre,
          c['is_nsfw'] == true || categories.contains('xxx'),
          logo[id]?.$2,
        );
        byId[id.toLowerCase()] = channel;
        for (final n in [c['name'], ...?(c['alt_names'] as List?)]) {
          (byName[_fold(n.toString())] ??= []).add(channel);
        }
      }
      for (final list in byName.values) {
        final genre = list.map((c) => c.genre).where((g) => g != Genre.other).firstOrNull;
        if (genre == null) continue;
        for (final c in list.where((c) => c.genre == Genre.other)) {
          c.genre = genre;
        }
      }
      return _ChannelDb._(byId, byName);
    } catch (e) {
      debugPrint('[channels] iptv-org: $e');
      return null;
    }
  }

  static Future<String> _file(http.Client client, String? folder, String name) async {
    final file = folder == null ? null : File(p.join(folder, 'iptv-org-$name'));
    if (file != null &&
        await file.exists() &&
        DateTime.now().difference(await file.lastModified()) < const Duration(days: 7)) {
      return file.readAsString();
    }
    try {
      final res = await client.get(Uri.parse('$_api/$name')).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final text = utf8.decode(res.bodyBytes);
      await file?.writeAsString(text);
      return text;
    } catch (_) {
      if (file != null && await file.exists()) return file.readAsString();
      rethrow;
    }
  }

  (_DbChannel, bool)? find(String name, String country, Iterable<String> epgIds) {
    final exact = _byFolded(_fold(name), country) ?? _byFolded(_fold('$name ${_countryWord[country]}'), country);
    if (exact != null) return (exact, true);
    for (final id in epgIds) {
      final hit = _byId[id];
      if (hit != null) return (hit, true);
    }
    var words = name.replaceAll(RegExp(r'\s*\+\s*1$'), '').split(' ');
    if (words.join(' ') != name) {
      final hit = _byFolded(_fold(words.join(' ')), country);
      if (hit != null) return (hit, false);
    }
    while (words.length > 2) {
      words = words.sublist(0, words.length - 1);
      final shorter = words.join(' ');
      if (_fold(shorter).length < 5) break;
      final hit = _byFolded(_fold(shorter), country);
      if (hit != null) return (hit, false);
    }
    return null;
  }

  _DbChannel? _byFolded(String key, String country) {
    final list = _byName[key];
    if (list == null || list.isEmpty) return null;
    return list.where((c) => c.country == country).firstOrNull ?? list.first;
  }

  static const _countryWord = {'RO': 'Romania', 'UK': 'UK', 'IE': 'Ireland'};

  static const _numbers = {'1': 'one', '2': 'two', '3': 'three', '4': 'four', '5': 'five'};

  static String _fold(String s) {
    final words = s
        .toLowerCase()
        .split('')
        .map((c) => _fold1[c] ?? c)
        .join()
        .replaceAll('&', ' and ')
        .split(RegExp(r'[^a-z0-9+]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => _numbers[w] ?? w);
    return words.join();
  }

  static const _fold1 = {
    'ă': 'a', 'â': 'a', 'á': 'a', 'à': 'a', 'ä': 'a', 'î': 'i', 'í': 'i', 'ș': 's', 'ş': 's', 'ț': 't', 'ţ': 't',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ó': 'o', 'ö': 'o', 'ő': 'o', 'ú': 'u', 'ü': 'u', 'ű': 'u', 'ñ': 'n', 'ç': 'c',
  };
}

Genre _listGenre(String category) {
  final c = _plain(category).toUpperCase();
  for (final (pattern, genre) in const [
    ('SPORT', Genre.sports),
    ('NEWS', Genre.news),
    ('KIDS', Genre.kids),
    ('MUSIC', Genre.music),
    ('DOCUMENTARY', Genre.documentary),
    ('DISCOVERY', Genre.documentary),
    ('CINEMA', Genre.movies),
    ('MOVIES', Genre.movies),
    ('ENTERTAINMENT', Genre.entertainment),
    ('GENERAL', Genre.general),
  ]) {
    if (c.contains(pattern)) return genre;
  }
  return Genre.other;
}
