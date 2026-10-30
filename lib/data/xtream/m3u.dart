part of 'live_catalog.dart';

final class M3uPlaylist {
  M3uPlaylist(String url, String guide)
      : url = url.trim(),
        guide = guide.trim();

  final String url;
  final String guide;

  bool get configured => url.isNotEmpty;

  String get key => configured ? '$url|$guide' : '';
}

const playlistCountry = 'M3U';

final _m3uAttr = RegExp(r'([\w-]+)="([^"]*)"');

Map<String, String> _m3uAttrs(String line) => {for (final m in _m3uAttr.allMatches(line)) m[1]!.toLowerCase(): m[2]!.trim()};

({List<LiveChannel> channels, String? guide}) parseM3u(String text, Uri base) {
  String? guide;
  Map<String, String>? info;
  var name = '';
  final channels = <LiveChannel>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      final a = _m3uAttrs(line);
      guide = (a['url-tvg'] ?? a['x-tvg-url'])?.split(',').first.trim();
    } else if (line.startsWith('#EXTINF')) {
      final comma = line.indexOf(',', line.lastIndexOf('"') + 1);
      info = _m3uAttrs(comma < 0 ? line : line.substring(0, comma));
      name = comma < 0 ? '' : line.substring(comma + 1).trim();
    } else if (!line.startsWith('#') && info != null) {
      final title = name.isNotEmpty ? name : info['tvg-name'] ?? line;
      final logo = info['tvg-logo'];
      final epg = info['tvg-id']?.toLowerCase();
      channels.add(LiveChannel(
        name: title,
        country: playlistCountry,
        category: info['group-title'] ?? '',
        number: int.tryParse(info['tvg-chno'] ?? ''),
        logo: logo == null || logo.isEmpty ? null : logo,
        epgId: epg == null || epg.isEmpty ? null : epg,
        sources: [ChannelSource(name: title, streamId: channels.length, logo: logo, url: base.resolve(line).toString())],
      ));
      info = null;
    }
  }
  return (channels: channels, guide: guide);
}

Future<LiveCatalog> _loadPlaylist(http.Client client, M3uPlaylist playlist) async {
  final base = Uri.parse(playlist.url);
  final res = await client.get(base);
  if (res.statusCode != 200) throw Exception('playlist: HTTP ${res.statusCode}');
  final parsed = parseM3u(utf8.decode(res.bodyBytes, allowMalformed: true), base);
  final guide = playlist.guide.isNotEmpty ? playlist.guide : parsed.guide;
  final ids = {for (final c in parsed.channels) ?c.epgId};
  return LiveCatalog(
    channels: parsed.channels,
    guide: guide == null || guide.isEmpty || ids.isEmpty ? const {} : await _readGuide(client, base.resolve(guide), ids),
    loadedAt: DateTime.now(),
  );
}
