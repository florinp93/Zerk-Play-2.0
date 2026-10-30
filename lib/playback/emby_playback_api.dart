import 'package:http/http.dart' as http;

import '../core/emby/models/emby_item.dart';
import '../core/emby/models/media_source.dart';
import '../core/host.dart';
import '../services/janus/janus_service.dart';
import 'device_profile.dart';
import 'media3/device_caps.dart';
import 'player_settings.dart';

enum PlayMethod { directPlay, directStream, transcode }

extension PlayMethodWire on PlayMethod {
  String get wire => switch (this) {
        PlayMethod.directPlay => 'DirectPlay',
        PlayMethod.directStream => 'DirectStream',
        PlayMethod.transcode => 'Transcode',
      };
}

final class ResolvedStream {
  ResolvedStream({
    required this.url,
    required this.method,
    required this.source,
    required this.playSessionId,
  });

  final Uri url;
  final PlayMethod method;
  final MediaSourceInfo source;
  final String playSessionId;

  bool get tracksMatchSource => method != PlayMethod.transcode;

  ResolvedStream withSource(MediaSourceInfo source) =>
      ResolvedStream(url: url, method: method, source: source, playSessionId: playSessionId);

  String? get copiedDolbyVision {
    if (method != PlayMethod.transcode || !url.path.toLowerCase().endsWith('.m3u8')) return null;
    final reasons = (url.queryParameters['TranscodeReasons'] ?? '').split(',').where((r) => r.isNotEmpty);
    bool copies(String r) => r.startsWith('Audio') || r == 'SecondaryAudioNotSupported' || r == 'ContainerNotSupported';
    if (reasons.isEmpty || !reasons.every(copies)) return null;
    final v = source.video;
    final sub = RegExp(r'DoviProfile(\d)').firstMatch(v?.extendedVideoSubType ?? '');
    if (v == null || v.codec != 'hevc' || v.extendedVideoType != 'DolbyVision' || sub == null) return null;
    const rates = [22118400, 27648000, 49766400, 62208000, 124416000, 199065600, 248832000, 398131200, 497664000,
      995328000, 995328000, 1990656000, 3981312000];
    final rate = (v.width ?? 3840) * (v.height ?? 2160) * (v.frameRate ?? 24);
    final level = rates.indexWhere((r) => rate <= r * 1.01) + 1;
    return 'dvhe.0${sub.group(1)}.${(level == 0 ? 13 : level).toString().padLeft(2, '0')}';
  }
}

final class RemoteSubtitle {
  const RemoteSubtitle({required this.id, required this.name, this.provider, this.format, this.downloads, this.hashMatch = false});

  final String id;
  final String name;
  final String? provider;
  final String? format;
  final int? downloads;
  final bool hashMatch;

  factory RemoteSubtitle.fromJson(Map<String, dynamic> j) => RemoteSubtitle(
        id: '${j['Id']}',
        name: j['Name'] as String? ?? '${j['Id']}',
        provider: j['ProviderName'] as String?,
        format: (j['Format'] as String?)?.toUpperCase(),
        downloads: (j['DownloadCount'] as num?)?.toInt(),
        hashMatch: j['IsHashMatch'] == true,
      );
}

final class PlaybackReport {
  PlaybackReport({
    required this.itemId,
    required this.stream,
    required this.position,
    this.isPaused = false,
    this.isMuted = false,
    this.volume = 100,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.eventName,
    this.playbackRate = 1.0,
  });

  final String itemId;
  final ResolvedStream stream;
  final Duration position;
  final bool isPaused;
  final bool isMuted;
  final int volume;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final String? eventName;
  final double playbackRate;

  Map<String, Object?> toJson(String deviceId) => {
        'ItemId': itemId,
        'MediaSourceId': stream.source.id,
        'PlaySessionId': stream.playSessionId,
        'PlayMethod': stream.method.wire,
        'PositionTicks': position.inMicroseconds * 10,
        'IsPaused': isPaused,
        'IsMuted': isMuted,
        'VolumeLevel': volume,
        'AudioStreamIndex': audioStreamIndex,
        'SubtitleStreamIndex': subtitleStreamIndex ?? -1,
        'LiveStreamId': ?stream.source.liveStreamId,
        'CanSeek': stream.source.liveStreamId == null,
        'PlaybackRate': playbackRate,
        'EventName': ?eventName,
        'DeviceId': deviceId,
      };
}

final class EmbyPlaybackApi {
  EmbyPlaybackApi({required this._janus});

  final JanusService _janus;

  static Future<Map<String, Object?>> _deviceProfile(int maxBitrate) async => Host.isAndroid
      ? buildAndroidDeviceProfile(await AndroidDeviceCaps.get(),
          maxBitrate: maxBitrate, output: (await PlayerSettings.load()).passthrough)
      : buildDesktopDeviceProfile(maxBitrate: maxBitrate);

  bool get _jellyfin => _janus.client.isJellyfin;

  Future<void> registerCapabilities({int maxBitrate = 0}) async {
    final profile = await _deviceProfile(maxBitrate);
    return _janus.client.postNoContent(
      '/Sessions/Capabilities/Full',
      body: {
        'PlayableMediaTypes': ['Video', 'Audio'],
        'SupportedCommands': _jellyfin
            ? ['Play', 'PlayState', 'SetAudioStreamIndex', 'SetSubtitleStreamIndex', 'DisplayMessage']
            : ['Play', 'Pause', 'Unpause', 'Stop', 'Seek', 'SetAudioStreamIndex', 'SetSubtitleStreamIndex', 'DisplayMessage'],
        'SupportsMediaControl': false,
        'DeviceProfile': profile,
      },
    );
  }

  Future<PlaybackInfoResponse> getPlaybackInfo(
    String itemId, {
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    Duration? start,
    int maxBitrate = 0,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
  }) async {
    final s = _janus.session;
    final profile = await _deviceProfile(maxBitrate);
    final bitrate = maxBitrate > 0 ? maxBitrate : kUnlimitedBitrate;
    final startTicks = start == null ? null : start.inMicroseconds * 10;
    final json = _jellyfin
        ? await _janus.client.postJson('/Items/$itemId/PlaybackInfo', body: {
            'UserId': s.userId,
            'AutoOpenLiveStream': true,
            'MediaSourceId': ?mediaSourceId,
            'AudioStreamIndex': ?audioStreamIndex,
            'SubtitleStreamIndex': ?subtitleStreamIndex,
            'StartTimeTicks': ?startTicks,
            'MaxStreamingBitrate': bitrate,
            'EnableDirectPlay': enableDirectPlay,
            'EnableDirectStream': enableDirectStream,
            'EnableTranscoding': true,
            'AllowVideoStreamCopy': true,
            'AllowAudioStreamCopy': true,
            'DeviceProfile': profile,
          })
        : await _janus.client.postJson(
            '/Items/$itemId/PlaybackInfo',
            queryParameters: {
              'UserId': s.userId,
              'IsPlayback': 'true',
              'AutoOpenLiveStream': 'true',
              'MediaSourceId': mediaSourceId,
              'AudioStreamIndex': audioStreamIndex?.toString(),
              'SubtitleStreamIndex': subtitleStreamIndex?.toString(),
              'StartTimeTicks': startTicks?.toString(),
              'MaxStreamingBitrate': '$bitrate',
              'EnableDirectPlay': '$enableDirectPlay',
              'EnableDirectStream': '$enableDirectStream',
            },
            body: {'DeviceProfile': profile},
          );
    final info = PlaybackInfoResponse.fromJson(json);
    if (info.errorCode != null) {
      throw PlaybackRefusedException(info.errorCode!);
    }
    if (info.mediaSources.isEmpty) {
      throw const PlaybackRefusedException('NoMediaSources');
    }
    return info;
  }

  ResolvedStream resolve(
    String itemId,
    PlaybackInfoResponse info, {
    String? mediaSourceId,
    bool streamSubtitles = false,
  }) {
    final source = info.mediaSources.firstWhere(
      (m) => m.id == mediaSourceId,
      orElse: () => info.mediaSources.first,
    );
    final s = _janus.session;

    if (source.supportsDirectPlay || source.supportsDirectStream && source.directStreamUrl == null) {
      final live = source.liveStreamId;
      final containers = (source.container ?? (live != null ? 'ts' : 'mkv')).split(',');
      final container = containers.contains('mp4') ? 'mp4' : containers.first;
      return ResolvedStream(
        url: _janus.client.buildUri('/Videos/$itemId/stream.$container', queryParameters: {
          'Static': 'true',
          'MediaSourceId': source.id,
          'LiveStreamId': ?live,
          'PlaySessionId': info.playSessionId,
          'DeviceId': s.deviceId,
          _janus.client.tokenParameter: s.accessToken,
        }),
        method: PlayMethod.directPlay,
        source: source,
        playSessionId: info.playSessionId,
      );
    }
    if (source.supportsDirectStream && source.directStreamUrl != null) {
      return ResolvedStream(
        url: absoluteUrl(source.directStreamUrl!),
        method: PlayMethod.directStream,
        source: source,
        playSessionId: info.playSessionId,
      );
    }
    if (source.transcodingUrl != null) {
      final url = absoluteUrl(source.transcodingUrl!);
      return ResolvedStream(
        url: streamSubtitles ? _withStreamSubtitles(url, source) : url,
        method: PlayMethod.transcode,
        source: source,
        playSessionId: info.playSessionId,
      );
    }
    throw const PlaybackRefusedException('NoCompatibleStream');
  }

  Uri _withStreamSubtitles(Uri url, MediaSourceInfo source) {
    if (_jellyfin) return url;
    final text = [
      for (final s in source.subtitleStreams)
        if (!s.isExternal && s.isTextSubtitleStream) s.index,
    ];
    final qp = Map<String, String>.from(url.queryParameters);
    if (text.isEmpty || !url.path.toLowerCase().endsWith('.m3u8')) return url;
    final burned = source.streamByIndex(int.tryParse(qp['SubtitleStreamIndex'] ?? '') ?? -1);
    if (qp['SubtitleMethod'] == 'Encode' || (burned != null && !burned.isTextSubtitleStream)) return url;
    qp
      ..['SubtitleMethod'] = 'Hls'
      ..['ManifestSubtitles'] = 'vtt'
      ..['SubtitleStreamIndexes'] = text.join(',');
    return url.replace(queryParameters: qp);
  }

  Uri absoluteUrl(String raw) {
    final s = _janus.session;
    final parsed = Uri.parse(raw);
    final base = parsed.hasScheme ? parsed : _janus.client.buildUri(parsed.path).replace(query: parsed.query);
    final qp = Map<String, String>.from(base.queryParameters);
    final key = _janus.client.tokenParameter;
    if (key != 'api_key') qp.remove('api_key');
    qp.putIfAbsent(key, () => s.accessToken);
    return base.replace(queryParameters: qp);
  }

  void warmUpSubtitle(Uri url) {
    http.get(url).timeout(const Duration(minutes: 20)).then((_) {}, onError: (Object _) {});
  }

  Uri subtitleUrl(String itemId, MediaSourceInfo source, MediaStream stream, {String format = 'ass'}) {
    if (stream.deliveryUrl != null && stream.deliveryMethod == SubtitleDeliveryMethod.external) {
      return absoluteUrl(stream.deliveryUrl!);
    }
    return absoluteUrl('/Videos/$itemId/${source.id}/Subtitles/${stream.index}/0/Stream.$format');
  }

  Future<List<RemoteSubtitle>> searchSubtitles(String itemId, String mediaSourceId, String language) async {
    final list = await _janus.client.getJsonList('/Items/$itemId/RemoteSearch/Subtitles/$language',
        queryParameters: {'MediaSourceId': mediaSourceId, 'IsPerfectMatch': 'false'});
    return [for (final e in list.whereType<Map<String, dynamic>>()) RemoteSubtitle.fromJson(e)]
      ..sort((a, b) => a.hashMatch != b.hashMatch ? (a.hashMatch ? -1 : 1) : (b.downloads ?? 0).compareTo(a.downloads ?? 0));
  }

  Future<void> downloadSubtitle(String itemId, String mediaSourceId, String subtitleId) => _janus.client.postNoContent(
      '/Items/$itemId/RemoteSearch/Subtitles/${Uri.encodeComponent(subtitleId)}',
      queryParameters: {'MediaSourceId': mediaSourceId});

  Future<List<MediaStream>?> currentStreams(String itemId, String mediaSourceId) async {
    final json = await _janus.client.getJson('/Users/${_janus.session.userId}/Items/$itemId',
        queryParameters: {'Fields': 'MediaSources,MediaStreams'});
    return EmbyItem.fromJson(json).mediaSources.where((m) => m.id == mediaSourceId).firstOrNull?.streams;
  }

  Future<void> reportStart(PlaybackReport r) =>
      _janus.client.postNoContent('/Sessions/Playing', body: r.toJson(_janus.session.deviceId));

  Future<void> reportProgress(PlaybackReport r) => _janus.client
      .postNoContent('/Sessions/Playing/Progress', body: r.toJson(_janus.session.deviceId));

  Future<void> reportStopped(PlaybackReport r) => _janus.client
      .postNoContent('/Sessions/Playing/Stopped', body: r.toJson(_janus.session.deviceId));

  Future<void> stopTranscode(String playSessionId) async {
    try {
      await _janus.client.deleteNoContent('/Videos/ActiveEncodings', queryParameters: {
        'DeviceId': _janus.session.deviceId,
        'PlaySessionId': playSessionId,
      });
    } catch (_) {
    }
  }

  Future<EmbyItem?> nextEpisode(EmbyItem episode) async {
    final seriesId = episode.seriesId;
    if (seriesId == null) return null;
    final s = _janus.session;
    final json = await _janus.client.getJson('/Shows/$seriesId/Episodes', queryParameters: {
      'UserId': s.userId,
      'StartItemId': episode.id,
      'Limit': '2',
      'Fields': 'Overview,UserData,Chapters,SeriesId,SeasonId,ParentId',
    });
    final items = json['Items'];
    if (items is! List) return null;
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = EmbyItem.fromJson(raw.cast<String, dynamic>());
      if (item.id != episode.id) return item;
    }
    return null;
  }

  Future<List<ChapterInfo>> chapters(EmbyItem item, {bool fetch = true}) async {
    final all = item.chapters.isNotEmpty || !fetch ? item.chapters : await _chapters(item.id);
    return _jellyfin ? all : [for (final c in all) if (c.markerType == null || c.markerType == 'Chapter') c];
  }

  Future<List<ChapterInfo>> _chapters(String itemId) async {
    final userId = _janus.session.userId;
    final json = _jellyfin
        ? await _janus.client.getJson('/Items/$itemId', queryParameters: {'userId': userId})
        : await _janus.client.getJson('/Users/$userId/Items/$itemId', queryParameters: {'Fields': 'Chapters'});
    return ChapterInfo.listFromJson(json['Chapters']);
  }

  Uri? chapterImage(String itemId, ChapterInfo chapter, {int width = 480}) => chapter.imageTag == null
      ? null
      : _janus.client.buildUri('/Items/$itemId/Images/Chapter/${chapter.index}',
          queryParameters: {'maxWidth': '$width', 'tag': chapter.imageTag});

  Future<({int? introStart, int? introEnd, int? creditsStart})?> segments(String itemId) async {
    if (!_jellyfin) return null;
    final json = await _janus.client.getJson('/MediaSegments/$itemId');
    int? introStart, introEnd, creditsStart;
    for (final raw in (json['Items'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final start = (raw['StartTicks'] as num?)?.toInt();
      switch (raw['Type']) {
        case 'Intro':
          introStart ??= start;
          introEnd ??= (raw['EndTicks'] as num?)?.toInt();
        case 'Outro':
          creditsStart ??= start;
      }
    }
    if (introStart == null && creditsStart == null) return null;
    return (introStart: introStart, introEnd: introEnd, creditsStart: creditsStart);
  }

  Future<void> markPlayed(String itemId) =>
      _janus.client.postNoContent('/Users/${_janus.session.userId}/PlayedItems/$itemId');
}

final class PlaybackRefusedException implements Exception {
  const PlaybackRefusedException(this.code);

  final String code;

  @override
  String toString() => 'Playback refused by server: $code';
}
