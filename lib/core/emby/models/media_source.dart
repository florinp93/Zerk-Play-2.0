int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
double? _double(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
bool _bool(Object? v) => v == true;

enum MediaStreamType { video, audio, subtitle, other }

enum SubtitleDeliveryMethod { embed, external, encode, hls, vobsub, unknown }

final class MediaStream {
  MediaStream({
    required this.index,
    required this.type,
    this.codec,
    this.profile,
    this.level,
    this.language,
    this.displayLanguage,
    this.title,
    this.displayTitle,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.isTextSubtitleStream = false,
    this.supportsExternalStream = false,
    this.deliveryMethod = SubtitleDeliveryMethod.unknown,
    this.deliveryUrl,
    this.channels,
    this.channelLayout,
    this.sampleRate,
    this.bitRate,
    this.bitDepth,
    this.width,
    this.height,
    this.frameRate,
    this.videoRange,
    this.extendedVideoType,
    this.extendedVideoSubType,
    this.extendedVideoSubTypeDescription,
    this.isInterlaced = false,
  });

  final int index;
  final MediaStreamType type;
  final String? codec;
  final String? profile;
  final double? level;
  final String? language;

  final String? displayLanguage;
  final String? title;
  final String? displayTitle;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;
  final bool isTextSubtitleStream;
  final bool supportsExternalStream;
  final SubtitleDeliveryMethod deliveryMethod;
  final String? deliveryUrl;
  final int? channels;
  final String? channelLayout;
  final int? sampleRate;
  final int? bitRate;
  final int? bitDepth;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? videoRange;

  final String? extendedVideoType;

  final String? extendedVideoSubType;
  final String? extendedVideoSubTypeDescription;
  final bool isInterlaced;

  String get codecLower => (codec ?? '').toLowerCase();

  String get label => displayTitle ?? title ?? language ?? 'Track $index';

  factory MediaStream.fromJson(Map<String, dynamic> j) {
    final type = switch (j['Type']) {
      'Video' => MediaStreamType.video,
      'Audio' => MediaStreamType.audio,
      'Subtitle' => MediaStreamType.subtitle,
      _ => MediaStreamType.other,
    };
    final delivery = switch ((j['DeliveryMethod'] as String?)?.toLowerCase()) {
      'embed' => SubtitleDeliveryMethod.embed,
      'external' => SubtitleDeliveryMethod.external,
      'encode' => SubtitleDeliveryMethod.encode,
      'hls' => SubtitleDeliveryMethod.hls,
      'vobsub' => SubtitleDeliveryMethod.vobsub,
      _ => SubtitleDeliveryMethod.unknown,
    };
    return MediaStream(
      index: _int(j['Index']) ?? -1,
      type: type,
      codec: _str(j['Codec']),
      profile: _str(j['Profile']),
      level: _double(j['Level']),
      language: _str(j['Language']),
      displayLanguage: _str(j['DisplayLanguage']),
      title: _str(j['Title']),
      displayTitle: _str(j['DisplayTitle']),
      isDefault: _bool(j['IsDefault']),
      isForced: _bool(j['IsForced']),
      isExternal: _bool(j['IsExternal']),
      isTextSubtitleStream: _bool(j['IsTextSubtitleStream']),
      supportsExternalStream: _bool(j['SupportsExternalStream']),
      deliveryMethod: delivery,
      deliveryUrl: _str(j['DeliveryUrl']),
      channels: _int(j['Channels']),
      channelLayout: _str(j['ChannelLayout']),
      sampleRate: _int(j['SampleRate']),
      bitRate: _int(j['BitRate']),
      bitDepth: _int(j['BitDepth']),
      width: _int(j['Width']),
      height: _int(j['Height']),
      frameRate: _double(j['RealFrameRate']) ?? _double(j['AverageFrameRate']),
      videoRange: _str(j['VideoRange']),
      extendedVideoType: _str(j['ExtendedVideoType']) ?? _jellyfinRangeType(j['VideoRangeType']),
      extendedVideoSubType: _str(j['ExtendedVideoSubType']) ?? _jellyfinDovi(j),
      extendedVideoSubTypeDescription: _str(j['ExtendedVideoSubTypeDescription']),
      isInterlaced: _bool(j['IsInterlaced']),
    );
  }
}

String? _jellyfinRangeType(Object? raw) => switch (raw) {
      'DOVIInvalid' || null => null,
      final String t when t.startsWith('DOVI') => 'DolbyVision',
      'HDR10Plus' => 'Hdr10Plus',
      'HDR10' => 'Hdr10',
      'HLG' => 'HyperLogGamma',
      'SDR' => 'None',
      _ => null,
    };

String? _jellyfinDovi(Map<String, dynamic> j) {
  final profile = _int(j['DvProfile']);
  if (profile == null || profile == 0) return null;
  return 'DoviProfile$profile${_int(j['DvBlSignalCompatibilityId']) ?? 0}';
}

final class ChapterInfo {
  ChapterInfo({required this.startTicks, this.name, this.markerType, this.imageTag, this.index = 0});

  final int startTicks;
  final String? name;

  final String? markerType;
  final String? imageTag;
  final int index;

  Duration get start => Duration(microseconds: startTicks ~/ 10);

  bool get isNamed => name != null && !RegExp(r'^\D*\d+$').hasMatch(name!.trim());

  factory ChapterInfo.fromJson(Map<String, dynamic> j, {int position = 0}) => ChapterInfo(
        startTicks: _int(j['StartPositionTicks']) ?? 0,
        name: _str(j['Name']),
        markerType: _str(j['MarkerType']),
        imageTag: _str(j['ImageTag']),
        index: _int(j['ChapterIndex']) ?? position,
      );

  static List<ChapterInfo> listFromJson(Object? raw) => raw is! List
      ? const []
      : [
          for (var i = 0; i < raw.length; i++)
            if (raw[i] case final Map c) ChapterInfo.fromJson(c.cast<String, dynamic>(), position: i),
        ];
}

final class MediaSourceInfo {
  MediaSourceInfo({
    required this.id,
    required this.streams,
    required this.chapters,
    this.name,
    this.path,
    this.protocol,
    this.container,
    this.size,
    this.bitrate,
    this.runTimeTicks,
    this.supportsDirectPlay = false,
    this.supportsDirectStream = false,
    this.supportsTranscoding = false,
    this.directStreamUrl,
    this.transcodingUrl,
    this.transcodingSubProtocol,
    this.defaultAudioStreamIndex,
    this.defaultSubtitleStreamIndex,
    this.isRemote = false,
    this.liveStreamId,
  });

  final String id;
  final String? name;
  final String? path;

  final String? protocol;
  final String? container;
  final int? size;
  final int? bitrate;
  final int? runTimeTicks;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;
  final bool supportsTranscoding;
  final String? directStreamUrl;
  final String? transcodingUrl;
  final String? transcodingSubProtocol;
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;
  final bool isRemote;

  final String? liveStreamId;
  final List<MediaStream> streams;
  final List<ChapterInfo> chapters;

  MediaStream? get video {
    for (final s in streams) {
      if (s.type == MediaStreamType.video) return s;
    }
    return null;
  }

  List<MediaStream> get audioStreams =>
      streams.where((s) => s.type == MediaStreamType.audio).toList(growable: false);

  List<MediaStream> get subtitleStreams =>
      streams.where((s) => s.type == MediaStreamType.subtitle).toList(growable: false);

  MediaStream? streamByIndex(int index) {
    for (final s in streams) {
      if (s.index == index) return s;
    }
    return null;
  }

  factory MediaSourceInfo.fromJson(Map<String, dynamic> j) {
    final streams = <MediaStream>[];
    final rawStreams = j['MediaStreams'];
    if (rawStreams is List) {
      for (final s in rawStreams) {
        if (s is Map) streams.add(MediaStream.fromJson(s.cast<String, dynamic>()));
      }
    }
    final chapters = ChapterInfo.listFromJson(j['Chapters']);
    return MediaSourceInfo(
      id: _str(j['Id']) ?? '',
      name: _str(j['Name']),
      path: _str(j['Path']),
      protocol: _str(j['Protocol']),
      container: _str(j['Container']),
      size: _int(j['Size']),
      bitrate: _int(j['Bitrate']),
      runTimeTicks: _int(j['RunTimeTicks']),
      supportsDirectPlay: _bool(j['SupportsDirectPlay']),
      supportsDirectStream: _bool(j['SupportsDirectStream']),
      supportsTranscoding: _bool(j['SupportsTranscoding']),
      directStreamUrl: _str(j['DirectStreamUrl']),
      transcodingUrl: _str(j['TranscodingUrl']),
      transcodingSubProtocol: _str(j['TranscodingSubProtocol']),
      defaultAudioStreamIndex: _int(j['DefaultAudioStreamIndex']),
      defaultSubtitleStreamIndex: _int(j['DefaultSubtitleStreamIndex']),
      isRemote: _bool(j['IsRemote']),
      liveStreamId: _str(j['LiveStreamId']),
      streams: streams,
      chapters: chapters,
    );
  }
}

final class PlaybackInfoResponse {
  PlaybackInfoResponse({
    required this.playSessionId,
    required this.mediaSources,
    this.errorCode,
  });

  final String playSessionId;
  final List<MediaSourceInfo> mediaSources;

  final String? errorCode;

  factory PlaybackInfoResponse.fromJson(Map<String, dynamic> j) {
    final sources = <MediaSourceInfo>[];
    final raw = j['MediaSources'];
    if (raw is List) {
      for (final s in raw) {
        if (s is Map) sources.add(MediaSourceInfo.fromJson(s.cast<String, dynamic>()));
      }
    }
    return PlaybackInfoResponse(
      playSessionId: _str(j['PlaySessionId']) ?? '',
      mediaSources: sources,
      errorCode: _str(j['ErrorCode']),
    );
  }
}
