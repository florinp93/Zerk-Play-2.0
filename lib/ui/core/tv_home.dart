import 'package:flutter/services.dart';

import '../../app/app_settings.dart';
import '../../core/emby/models/emby_item.dart';
import '../../core/host.dart';
import '../../data/catalog_api.dart';
import '../../data/tmdb_api.dart';
import 'artwork.dart';

abstract final class TvHome {
  static const _channel = MethodChannel('zerk/tvhome');
  static const _limit = 12;

  static bool get supported => Host.isAndroid;

  static void onLaunch(VoidCallback handler) => _channel.setMethodCallHandler((call) async {
        if (call.method == 'launch') handler();
      });

  static Future<String?> takeLaunch() => _channel.invokeMethod<String>('takeLaunch');

  static Future<void> publish(CatalogApi catalog, {LauncherEpisodeArt episodeArt = LauncherEpisodeArt.series}) async {
    final items = await catalog.continueWatching(limit: _limit);
    final now = DateTime.now();
    await _channel.invokeMethod<void>('publish', [
      for (final (rank, i) in items.where((i) => i.isPlayable && !i.isChannel).take(_limit).indexed)
        _entry(catalog, i, now.subtract(Duration(minutes: rank)), episodeArt),
    ]);
  }

  static Future<void> clear() => _channel.invokeMethod<void>('clear');

  static Map<String, Object?> _entry(CatalogApi catalog, EmbyItem i, DateTime fallbackEngaged, LauncherEpisodeArt art) {
    final (image, aspect) = cardImage(catalog, i, art);
    return {
      'id': i.id,
      'title': i.isEpisode ? (i.seriesName ?? i.name) : i.name,
      'episodeTitle': i.isEpisode ? i.name : null,
      'season': i.isEpisode ? i.parentIndexNumber : null,
      'episode': i.isEpisode ? i.indexNumber : null,
      'overview': i.overview,
      'image': image?.toString(),
      'imageAspect': aspect.wire,
      'durationMs': i.runtime?.inMilliseconds,
      'positionMs': i.resumePosition?.inMilliseconds,
      'engagedMs': (i.lastPlayedDate ?? fallbackEngaged).millisecondsSinceEpoch,
    };
  }

  static (Uri?, CardAspect) cardImage(CatalogApi catalog, EmbyItem i, LauncherEpisodeArt art) {
    if (!i.isEpisode || art == LauncherEpisodeArt.episode) return (catalog.landscape(i, width: 640), CardAspect.wide);
    return switch (seriesArtSource(i)) {
      SeriesArtSource.thumb =>
        (catalog.image(i.parentThumbItemId!, ImageKind.thumb, tag: i.parentThumbImageTag, width: 960), CardAspect.wide),
      SeriesArtSource.localizedBackdrop => (TmdbApi.imageUrl(i.localizedBackdropPath!, width: 960, backdrop: true), CardAspect.wide),
      SeriesArtSource.backdrop => (
          catalog.image(i.parentBackdropItemId!, ImageKind.backdrop, tag: i.parentBackdropImageTags.first, width: 960),
          CardAspect.wide,
        ),
      SeriesArtSource.poster => (catalog.poster(i, width: 320), CardAspect.poster),
      SeriesArtSource.none => (catalog.landscape(i, width: 640), CardAspect.wide),
    };
  }

  static SeriesArtSource seriesArtSource(EmbyItem i) {
    if (i.localizedBackdropPath != null) return SeriesArtSource.localizedBackdrop;
    if (i.parentThumbItemId != null && i.parentThumbImageTag != null) return SeriesArtSource.thumb;
    if (i.parentBackdropItemId != null && i.parentBackdropImageTags.isNotEmpty) return SeriesArtSource.backdrop;
    if (i.localizedPosterPath != null || (i.seriesId != null && i.seriesPrimaryImageTag != null)) {
      return SeriesArtSource.poster;
    }
    return SeriesArtSource.none;
  }
}

enum SeriesArtSource { thumb, localizedBackdrop, backdrop, poster, none }

enum CardAspect {
  wide('16:9'),
  poster('2:3');

  const CardAspect(this.wire);

  final String wire;
}
