import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'xtream.dart';

part 'channel_db.dart';

final class ChannelSource {
  const ChannelSource({required this.name, required this.streamId, this.logo});

  final String name;
  final int streamId;
  final String? logo;

  String get label => _split(name).$2;
}

final class LiveChannel {
  const LiveChannel({
    required this.name,
    required this.country,
    required this.category,
    required this.sources,
    this.logo,
    this.epgId,
    this.genre = Genre.other,
    this.number,
  });

  final String name;

  final String country;

  final String category;

  final int? number;

  final Genre genre;

  final List<ChannelSource> sources;
  final String? logo;
  final String? epgId;
}

final class Programme {
  const Programme(this.title, this.start, this.end, [this.description]);

  final String title;
  final DateTime start;
  final DateTime end;
  final String? description;

  bool isOn(DateTime now) => !now.isBefore(start) && now.isBefore(end);
}

final class LiveCatalog {
  const LiveCatalog({required this.channels, required this.guide, required this.loadedAt});

  final List<LiveChannel> channels;

  final Map<String, List<Programme>> guide;
  final DateTime loadedAt;

  List<Programme> guideFor(LiveChannel c) => guide[c.epgId] ?? const [];

  Programme? onNow(LiveChannel c, DateTime now) => guideFor(c).where((p) => p.isOn(now)).firstOrNull;

  Programme? upNext(LiveChannel c, DateTime now) => guideFor(c).where((p) => p.start.isAfter(now)).firstOrNull;

  Map<String, Object?> toJson() => {
        'at': loadedAt.millisecondsSinceEpoch,
        'channels': [for (final c in channels) _channelJson(c)],
        'guide': {
          for (final e in guide.entries)
            e.key: [
              for (final p in e.value)
                [p.title, p.start.millisecondsSinceEpoch, p.end.millisecondsSinceEpoch, p.description],
            ],
        },
      };

  static LiveCatalog fromJson(Map<String, dynamic> j) {
    DateTime t(Object? v) => DateTime.fromMillisecondsSinceEpoch(v as int);
    return LiveCatalog(
      loadedAt: t(j['at']),
      channels: [for (final c in j['channels'] as List) _channelFromJson(c as Map)],
      guide: {
        for (final e in (j['guide'] as Map).entries)
          e.key as String: [
            for (final p in e.value as List) Programme(p[0] as String, t(p[1]), t(p[2]), p[3] as String?),
          ],
      },
    );
  }

  static Map<String, Object?> _channelJson(LiveChannel c) => {
        'n': c.name,
        'c': c.country,
        'g': c.category,
        'gn': c.genre.name,
        'l': c.logo,
        'e': c.epgId,
        'no': ?c.number,
        's': [for (final s in c.sources) [s.name, s.streamId, s.logo]],
      };

  static LiveChannel _channelFromJson(Map c) => LiveChannel(
        name: c['n'] as String,
        country: c['c'] as String,
        category: c['g'] as String,
        genre: Genre.values.asNameMap()[c['gn']] ?? Genre.other,
        logo: c['l'] as String?,
        epgId: c['e'] as String?,
        number: c['no'] as int?,
        sources: [
          for (final s in c['s'] as List) ChannelSource(name: s[0] as String, streamId: s[1] as int, logo: s[2] as String?),
        ],
      );
}

final class LiveTv {
  LiveTv(this.server);

  final XtreamServer server;

  static LiveCatalog? _memory;
  static String? _memoryKey;
  static Future<LiveCatalog>? _loading;
  static Timer? _refresher;

  static final latest = ValueNotifier<LiveCatalog?>(null);

  static final error = ValueNotifier<String?>(null);

  Future<void> warmUp() async {
    _refresher?.cancel();
    if (!server.configured) {
      latest.value = null;
      return;
    }
    final c = await cached();
    if (c != null) {
      latest.value = c;
    }
    _refresher = Timer.periodic(const Duration(minutes: 5), (_) => refreshIfStale());
    await refreshIfStale();
  }

  Future<void> refreshIfStale() async {
    final c = latest.value;
    if (c != null && _memoryKey == server.key && !isStale(c)) return;
    try {
      await load();
    } catch (e) {
      debugPrint('[live] load: $e');
      error.value = e.toString();
    }
  }

  Future<LiveCatalog?> cached() async {
    if (_memoryKey == server.key && _memory != null) return _memory;
    final c = await _readCache();
    if (c != null) {
      _memory = c;
      _memoryKey = server.key;
    }
    return c;
  }

  static LiveCatalog? _parseCache(({String text, String key}) a) {
    final j = jsonDecode(a.text) as Map<String, dynamic>;
    if (j['key'] != a.key) return null;
    return LiveCatalog.fromJson(j['data'] as Map<String, dynamic>);
  }

  static String _encodeCache(({LiveCatalog catalog, String key}) a) =>
      jsonEncode({'key': a.key, 'data': a.catalog.toJson()});

  static bool isStale(LiveCatalog c) => DateTime.now().difference(c.loadedAt) > const Duration(minutes: 20);

  Future<LiveCatalog> load() => _loading ??= _fetch().whenComplete(() => _loading = null);

  Future<LiveCatalog> _fetch() async {
    final c = await compute(_load, (
      base: server.base,
      accounts: [for (final a in server.accounts) (a.username, a.password)],
      days: 3,
      folder: await _supportFolder(),
    ));
    _memory = c;
    _memoryKey = server.key;
    latest.value = c;
    error.value = null;
    unawaited(_writeCache(c));
    return c;
  }

  Future<File?> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'live_tv_cache_v2.json'));
  }

  Future<LiveCatalog?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (file == null || !await file.exists()) return null;
      return await compute(_parseCache, (text: await file.readAsString(), key: server.key));
    } catch (e) {
      debugPrint('[live] cache: $e');
      return null;
    }
  }

  Future<void> _writeCache(LiveCatalog c) async {
    try {
      final file = await _cacheFile();
      if (file == null) return;
      await file.writeAsString(await compute(_encodeCache, (catalog: c, key: server.key)));
    } catch (e) {
      debugPrint('[live] cache write: $e');
    }
  }
}

Future<String?> _supportFolder() async {
  try {
    return (await getApplicationSupportDirectory()).path;
  } catch (_) {
    return null;
  }
}

typedef _Args = ({String base, List<(String, String)> accounts, int days, String? folder});

Future<LiveCatalog> _load(_Args a) async {
  final client = http.Client();
  final server = XtreamServer(a.base, [for (final (u, pw) in a.accounts) XtreamAccount(u, pw)]);
  try {
    Object? error;
    for (final account in server.accounts) {
      try {
        return await _loadWith(client, server, account, a.days, a.folder);
      } catch (e) {
        error = e;
      }
    }
    throw error ?? Exception('no account');
  } finally {
    client.close();
  }
}

Future<LiveCatalog> _loadWith(
    http.Client client, XtreamServer server, XtreamAccount account, int days, String? folder) async {
  Future<List> list(String action) async {
    final res = await client.get(server.api(account, action));
    if (res.statusCode != 200) throw Exception('$action: HTTP ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (body is! List) throw Exception('$action: not a list');
    return body;
  }

  final now = DateTime.now().toUtc();
  final categories = {
    for (final c in await list('get_live_categories')) '${c['category_id']}': (c['category_name'] ?? '').toString(),
  };

  final tv = <String, _ChannelBuilder>{};
  final numbered = <LiveChannel>[];
  for (final s in await list('get_live_streams')) {
    final id = int.tryParse('${s['stream_id']}');
    if (id == null) continue;
    final category = categories['${s['category_id']}'] ?? '';
    final icon = s['stream_icon']?.toString().trim();
    final source = ChannelSource(
      name: (s['name'] ?? '').toString().trim(),
      streamId: id,
      logo: icon == null || icon.isEmpty ? null : icon,
    );
    if (source.name.trimLeft().startsWith('#')) continue;
    final emptySlot = source.name.trimRight().endsWith(':') || _eventSlot.hasMatch(_plain(source.name));
    final epg = emptySlot ? '' : (s['epg_channel_id'] ?? '').toString().trim().toLowerCase();

    final lineup = emptySlot ? null : _lineupGroup.firstMatch(category);
    if (lineup != null) {
      numbered.add(LiveChannel(
        name: source.name,
        country: lineup[1]!,
        category: lineup[2]!,
        genre: _lineupGenre(lineup[2]!),
        sources: [source],
        logo: source.logo,
        epgId: epg.isEmpty ? null : epg,
        number: int.tryParse('${s['num']}'),
      ));
    }
    final country = emptySlot || lineup != null ? null : _tvCountry(category);
    if (country != null) {
      final (base, _) = _split(source.name);
      final b = tv['$country|$base'] ??= _ChannelBuilder(base, country, _categoryName(category));
      if (b.listGenre == Genre.other) b.listGenre = _listGenre(category);
      b.sources.add(source);
      b.logo ??= source.logo;
      if (epg.isNotEmpty) {
        b.epgId ??= epg;
        b.epgIds.add(epg);
      }
    }
  }
  final channels = <LiveChannel>[];
  final logos = <String, String>{};
  if (numbered.isNotEmpty) {
    channels.addAll(numbered..sort((a, b) => (a.number ?? 1 << 30).compareTo(b.number ?? 1 << 30)));
  } else {
    final db = await _ChannelDb.load(client, folder);
    for (final b in tv.values) {
      final found = db?.find(b.name, b.country, b.epgIds);
      if (found != null) {
        final (entry, exact) = found;
        if (entry.adult) continue;
        b.genre = entry.genre;
        if (exact && entry.logo != null) b.logo = entry.logo;
      }
      if (b.genre == Genre.other) b.genre = b.listGenre;
      final c = b.build();
      channels.add(c);
      if (found != null && found.$2 && c.logo != null) logos[c.name] = c.logo!;
    }
  }
  final tvEpg = {for (final c in channels) ?c.epgId};

  final guide = <String, List<Programme>>{};
  final from = now.subtract(const Duration(hours: 2));
  final to = now.add(const Duration(hours: 26));
  final res = await client.send(http.Request('GET', server.guide(account)));
  if (res.statusCode != 200) throw Exception('xmltv: HTTP ${res.statusCode}');
  final buf = StringBuffer();
  await for (final chunk in res.stream.transform(const Utf8Decoder(allowMalformed: true))) {
    buf.write(chunk);
    final text = buf.toString();
    var pos = 0;
    while (true) {
      final open = text.indexOf('<programme', pos);
      if (open < 0) break;
      final close = text.indexOf('</programme>', open);
      if (close < 0) {
        pos = open;
        break;
      }
      pos = close + 12;
      final block = text.substring(open, pos);
      final channel = _channelOf(block);
      if (channel == null) continue;
      if (tvEpg.contains(channel)) {
        final programme = _guideEntry(block, from, to);
        if (programme != null) (guide[channel] ??= []).add(programme);
      }
    }
    buf.clear();
    final rest = text.indexOf('<programme', pos);
    if (rest >= 0) buf.write(text.substring(rest));
  }
  for (final list in guide.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  return LiveCatalog(channels: channels, guide: guide, loadedAt: DateTime.now());
}

final _eventSlot = RegExp(r'\bEVENT\s*\d+', caseSensitive: false);

final _lineupGroup = RegExp(r'^(RO|UK|IE|US) \| (.+)$');

Genre _lineupGenre(String group) => switch (group) {
      'General' || 'Regional' => Genre.general,
      'News' => Genre.news,
      'Sports' => Genre.sports,
      'Movies' => Genre.movies,
      'Entertainment' || 'Lifestyle' => Genre.entertainment,
      'Documentary' => Genre.documentary,
      'Kids' => Genre.kids,
      'Music' => Genre.music,
      _ => Genre.other,
    };

final class _ChannelBuilder {
  _ChannelBuilder(this.name, this.country, this.category);

  final String name;
  final String country;
  final String category;
  final sources = <ChannelSource>[];
  String? logo;
  String? epgId;
  final epgIds = <String>{};
  Genre genre = Genre.other;

  Genre listGenre = Genre.other;

  LiveChannel build() => LiveChannel(
        name: name,
        country: country,
        category: category,
        sources: _bestFirst(sources),
        logo: logo,
        epgId: epgId,
        genre: genre,
      );
}

String? _tvCountry(String category) {
  final parts = category.split(RegExp(r'\s*[▎|]\s*'));
  final rest = parts.skip(1).join(' ').toUpperCase();
  final code = switch (parts.first.trim().toUpperCase()) {
    'UK' when !rest.startsWith('UKRAINE') => 'UK',
    'IE' => 'IE',
    'RO' || 'ROMANIA' => 'RO',
    _ => null,
  };
  if (code == null) return null;
  if (_notTv.hasMatch(_plain(category).toUpperCase())) return null;
  return code;
}

final _notTv = RegExp(
    r'PPV|24/7|REPLAY|SERIES|STORE|NETFLIX|ORIGINAL|REALITY|CINE PRO|MC VIDEO|DOCS|EVENT|▎\s*OD\b|\|\s*PRIME\b');

String _categoryName(String category) {
  final i = category.indexOf(RegExp(r'[▎|]'));
  if (i < 0) return '';
  return _split(category.substring(i + 1)).$1.replaceAll(RegExp(r'[/&]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _superscripts = {
  'ᴬ': 'A', 'ᴮ': 'B', 'ᴰ': 'D', 'ᴱ': 'E', 'ᴳ': 'G', 'ᴴ': 'H', 'ᴵ': 'I', 'ᴶ': 'J', 'ᴷ': 'K', 'ᴸ': 'L', 'ᴹ': 'M',
  'ᴺ': 'N', 'ᴼ': 'O', 'ᴾ': 'P', 'ᴿ': 'R', 'ᵀ': 'T', 'ᵁ': 'U', 'ⱽ': 'V', 'ᵂ': 'W', 'ᵃ': 'a', 'ᵇ': 'b', 'ᶜ': 'c',
  'ᵈ': 'd', 'ᵉ': 'e', 'ᶠ': 'f', 'ᵍ': 'g', 'ʰ': 'h', 'ᶦ': 'i', 'ⁱ': 'i', 'ʲ': 'j', 'ᵏ': 'k', 'ˡ': 'l', 'ᵐ': 'm',
  'ⁿ': 'n', 'ᵒ': 'o', 'ᵖ': 'p', 'ʳ': 'r', 'ˢ': 's', 'ᵗ': 't', 'ᵘ': 'u', 'ᵛ': 'v', 'ʷ': 'w', 'ˣ': 'x', 'ʸ': 'y',
  'ᶻ': 'z', '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9',
  '⁽': '(', '⁾': ')', '⁻': '-', 'ʀ': 'R', 'ᴀ': 'A', 'ᴡ': 'W',
};

String _plain(String s) => s.split('').map((c) => _superscripts[c] ?? c).join();

final _quality = RegExp(
    r'(?<![A-Za-z0-9])(FHD|UHD|HD|SD|4K|8K|HEVC|H\.?265|\d{3,4}P|\d{2,3} ?FPS|RAW|REC|VIP|GOLD|DOLBY AUDIO|HQ)(?![A-Za-z0-9])'
    r'|\(BK\d*\)|◉|\[[A-Z]{2}\]',
    caseSensitive: false);

final _family = RegExp(r'^\s*([A-Z]{2,6})\s*:\s*');

(String, String) _split(String name) {
  var n = _plain(name);
  final i = n.lastIndexOf('▎');
  if (i >= 0) n = n.substring(i + 1);
  final tags = <String>[];
  final family = _family.firstMatch(n);
  if (family != null) {
    tags.add(family[1]!);
    n = n.substring(family.end);
  }
  for (final m in _quality.allMatches(n)) {
    final t = m[0]!.toUpperCase();
    if (t == '◉' || t == 'REC' || t.startsWith('[')) continue;
    final tag = t.replaceAll(' ', '');
    if (!tags.contains(tag)) tags.add(tag);
  }
  final base = n
      .replaceAll(_quality, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'\s(RO|UK|IE)$'), '')
      .replaceAll(RegExp(r'[\s/&]+$'), '');
  return (base.isEmpty ? n.trim().toUpperCase() : base, tags.join(' '));
}

int _rank(String label) {
  final l = ' $label ';
  bool has(String pattern) => RegExp(pattern).hasMatch(l);
  var r = has(r' (4K|8K|UHD|2160P|3840P) ')
      ? 8
      : has(r' (FHD|1080P) ')
          ? 6
          : has(' RAW ')
              ? 5
              : has(r' (HD|720P) ')
                  ? 4
                  : has(' SD ')
                      ? 0
                      : 3;
  if (has(r'\dFPS')) r++;
  if (has(r'\(BK')) r -= 2;
  return r;
}

List<ChannelSource> _bestFirst(Iterable<ChannelSource> sources) {
  final list = sources.toList();
  final order = {for (final (i, s) in list.indexed) s: i};
  return list
    ..sort((a, b) {
      final q = _rank(b.label).compareTo(_rank(a.label));
      return q != 0 ? q : order[a]!.compareTo(order[b]!);
    });
}

final _channelAttr = RegExp(r'channel="([^"]*)"');

String? _channelOf(String block) {
  final head = block.substring(0, block.indexOf('>') + 1);
  final m = _channelAttr.firstMatch(head);
  return m == null ? null : _unescape(m[1]!).trim().toLowerCase();
}

final _titleTag = RegExp(r'<title[^>]*>([\s\S]*?)</title>');
final _descTag = RegExp(r'<desc[^>]*>([\s\S]*?)</desc>');

Programme? _guideEntry(String block, DateTime from, DateTime to) {
  final head = block.substring(0, block.indexOf('>') + 1);
  final attrs = {for (final m in _attr.allMatches(head)) m[1]!: m[2]!};
  final start = _time(attrs['start']);
  final end = _time(attrs['stop']);
  if (start == null || end == null || !end.isAfter(from) || start.isAfter(to)) return null;
  final title = _titleTag.firstMatch(block);
  if (title == null) return null;
  var desc = _descTag.firstMatch(block)?[1];
  if (desc != null) {
    desc = _unescape(desc).trim();
    if (desc.length > 400) desc = '${desc.substring(0, 400)}…';
  }
  return Programme(_unescape(title[1]!).trim(), start, end, desc == null || desc.isEmpty ? null : desc);
}

final _attr = RegExp(r'(\w+)="([^"]*)"');

DateTime? _time(String? v) {
  if (v == null || v.length < 14) return null;
  final d = int.tryParse;
  final t = DateTime.utc(d(v.substring(0, 4)) ?? 0, d(v.substring(4, 6)) ?? 1, d(v.substring(6, 8)) ?? 1,
      d(v.substring(8, 10)) ?? 0, d(v.substring(10, 12)) ?? 0, d(v.substring(12, 14)) ?? 0);
  final tz = RegExp(r'([+-])(\d\d)(\d\d)').firstMatch(v.substring(14));
  if (tz == null) return t;
  final offset = Duration(hours: int.parse(tz[2]!), minutes: int.parse(tz[3]!));
  return tz[1] == '+' ? t.subtract(offset) : t.add(offset);
}

String _unescape(String s) => s
    .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16) ?? 63))
    .replaceAll('&amp;', '&');
