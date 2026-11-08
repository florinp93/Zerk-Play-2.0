import 'package:flutter/services.dart';

import '../../core/emby/models/emby_item.dart';
import '../../core/host.dart';
import '../../data/catalog_api.dart';
import 'artwork.dart';

abstract final class TvHome {
  static const _channel = MethodChannel('zerk/tvhome');
  static const _limit = 12;

  static bool get supported => Host.isAndroid;

  static void onLaunch(VoidCallback handler) => _channel.setMethodCallHandler((call) async {
        if (call.method == 'launch') handler();
      });

  static Future<String?> takeLaunch() => _channel.invokeMethod<String>('takeLaunch');

  static Future<void> publish(CatalogApi catalog) async {
    final items = await catalog.continueWatching(limit: _limit);
    final now = DateTime.now();
    await _channel.invokeMethod<void>('publish', [
      for (final (rank, i) in items.where((i) => i.isPlayable && !i.isChannel).take(_limit).indexed)
        _entry(catalog, i, now.subtract(Duration(minutes: rank))),
    ]);
  }

  static Future<void> clear() => _channel.invokeMethod<void>('clear');

  static Map<String, Object?> _entry(CatalogApi catalog, EmbyItem i, DateTime fallbackEngaged) => {
        'id': i.id,
        'title': i.isEpisode ? (i.seriesName ?? i.name) : i.name,
        'episodeTitle': i.isEpisode ? i.name : null,
        'season': i.isEpisode ? i.parentIndexNumber : null,
        'episode': i.isEpisode ? i.indexNumber : null,
        'overview': i.overview,
        'image': catalog.landscape(i, width: 640)?.toString(),
        'durationMs': i.runtime?.inMilliseconds,
        'positionMs': i.resumePosition?.inMilliseconds,
        'engagedMs': (i.lastPlayedDate ?? fallbackEngaged).millisecondsSinceEpoch,
      };
}
