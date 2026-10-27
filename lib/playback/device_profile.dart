library;

import 'player_settings.dart';

const int kUnlimitedBitrate = 1000000000;

Map<String, Object?> buildDesktopDeviceProfile({int maxBitrate = 0}) {
  final bitrate = maxBitrate > 0 ? maxBitrate : kUnlimitedBitrate;
  return {
    'Name': 'Zerk Play (libmpv)',
    'MaxStreamingBitrate': bitrate,
    'MaxStaticBitrate': bitrate,
    'MusicStreamingTranscodingBitrate': 320000,
    'DirectPlayProfiles': [
      {'Type': 'Video'},
      {'Type': 'Audio'},
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'VideoCodec': 'hevc,h264',
        'AudioCodec': 'eac3,ac3,aac,mp3',
        'MaxAudioChannels': '8',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
      {
        'Type': 'Audio',
        'Container': 'mp3',
        'Protocol': 'http',
        'Context': 'Streaming',
        'AudioCodec': 'mp3',
      },
    ],
    'ContainerProfiles': const <Object>[],
    'CodecProfiles': const <Object>[],
    'ResponseProfiles': const <Object>[],
    'SubtitleProfiles': [
      for (final f in _allSubtitleFormats) {'Format': f, 'Method': 'Embed'},
      for (final f in _textSubtitleFormats) {'Format': f, 'Method': 'External'},
    ],
  };
}

const _textSubtitleFormats = ['srt', 'subrip', 'ass', 'ssa', 'vtt', 'webvtt', 'sub', 'smi', 'ttml'];
const _allSubtitleFormats = [
  ..._textSubtitleFormats,
  'pgs', 'pgssub', 'dvdsub', 'vobsub', 'dvbsub', 'mov_text',
];

Map<String, Object?> buildAndroidDeviceProfile(Map<String, Object?>? caps,
    {int maxBitrate = 0, Set<PassthroughCodec> output = const {}}) {
  final bitrate = maxBitrate > 0 ? maxBitrate : kUnlimitedBitrate;
  final video = (caps?['video'] as Map?)?.cast<String, Object?>() ?? const {};
  bool has(String codec) => caps == null ? codec == 'h264' || codec == 'hevc' : video[codec] == true;

  final videoCodecs = [
    if (has('h264')) 'h264',
    if (has('hevc')) 'hevc',
    if (has('vp9')) 'vp9',
    if (has('av1')) 'av1',
    if (has('vp8')) 'vp8',
    if (has('mpeg2')) 'mpeg2video',
    if (has('mpeg4')) 'mpeg4',
    if (has('vc1')) 'vc1',
  ];
  final ffmpegAudio = ((caps?['ffmpegAudio'] as List?) ?? const []).cast<String>().toSet();
  final audioCodecs = {
    'aac', 'mp3', 'opus', 'vorbis', 'flac', 'pcm_s16le', 'pcm_s24le',
    ...ffmpegAudio.map((c) => c == 'dtshd' ? 'dts' : c),
    for (final e in ((caps?['passthrough'] as Map?) ?? const {}).entries)
      if (e.value == true) ...switch (e.key) {
        'ac3' => ['ac3'],
        'eac3' || 'eac3joc' => ['eac3'],
        'dts' || 'dtshd' => ['dts'],
        'truehd' => ['truehd'],
        _ => const <String>[],
      },
  }.toList();
  final bitstream = {
    for (final c in output)
      switch (c) {
        PassthroughCodec.ac3 => 'ac3',
        PassthroughCodec.eac3 => 'eac3',
        PassthroughCodec.dts || PassthroughCodec.dtshd => 'dts',
        PassthroughCodec.truehd => 'truehd',
      },
  };
  final stereoOnly = androidEncodesAc3(caps, output)
      ? const <String>[]
      : audioCodecs.where((c) => !bitstream.contains(c)).toList();
  final transcodeAudio = output.isEmpty
      ? const ['eac3', 'ac3', 'aac']
      : [if (bitstream.contains('eac3')) 'eac3', if (bitstream.contains('ac3')) 'ac3', 'aac'];
  final transcodeChannels = output.isEmpty || transcodeAudio.length > 1 ? 6 : 2;

  Map<String, Object?> cond(String property, String condition, Object value) =>
      {'Condition': condition, 'Property': property, 'Value': '$value', 'IsRequired': false};
  List<Map<String, Object?>> sizeLimit(Object? raw) {
    final size = (raw as List?)?.cast<int>();
    if (size == null || size.length < 2) return const [];
    return [cond('Width', 'LessThanEqual', size[0]), cond('Height', 'LessThanEqual', size[1])];
  }

  return {
    'Name': 'Zerk Play (Android TV)',
    'MaxStreamingBitrate': bitrate,
    'MaxStaticBitrate': bitrate,
    'MusicStreamingTranscodingBitrate': 320000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': 'mkv,webm,mp4,m4v,mov,ts,m2ts,mpegts,avi',
        'VideoCodec': videoCodecs.join(','),
        'AudioCodec': audioCodecs.join(','),
      },
      {'Type': 'Audio', 'AudioCodec': audioCodecs.join(',')},
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'VideoCodec': has('hevc') ? 'hevc,h264' : 'h264',
        'AudioCodec': transcodeAudio.join(','),
        'MaxAudioChannels': '$transcodeChannels',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
      {'Type': 'Audio', 'Container': 'mp3', 'Protocol': 'http', 'Context': 'Streaming', 'AudioCodec': 'mp3'},
    ],
    'ContainerProfiles': const <Object>[],
    'CodecProfiles': [
      if (output.isNotEmpty && stereoOnly.isNotEmpty)
        {'Type': 'VideoAudio', 'Codec': stereoOnly.join(','), 'Conditions': [cond('AudioChannels', 'LessThanEqual', 2)]},
      {'Type': 'Video', 'Codec': 'h264', 'Conditions': [cond('VideoBitDepth', 'LessThanEqual', 8), ...sizeLimit(caps?['maxH264'])]},
      {
        'Type': 'Video',
        'Codec': 'hevc',
        'Conditions': [
          if (caps != null && video['hevcMain10'] != true) cond('VideoBitDepth', 'LessThanEqual', 8),
          ...sizeLimit(caps?['maxHevc']),
        ],
      },
      if (caps != null && video['vp9Profile2'] != true)
        {'Type': 'Video', 'Codec': 'vp9', 'Conditions': [cond('VideoBitDepth', 'LessThanEqual', 8)]},
    ],
    'ResponseProfiles': const <Object>[],
    'SubtitleProfiles': [
      for (final f in _androidEmbeddedSubtitles) {'Format': f, 'Method': 'Embed'},
      for (final f in _androidExternalSubtitles) {'Format': f, 'Method': 'External'},
    ],
  };
}

bool androidEncodesAc3(Map<String, Object?>? caps, Set<PassthroughCodec> output) =>
    (caps?['passthrough'] as Map?)?['ac3'] == true &&
    (output.contains(PassthroughCodec.ac3) || output.contains(PassthroughCodec.eac3));

const _androidExternalSubtitles = ['srt', 'subrip', 'ass', 'ssa', 'vtt', 'webvtt', 'ttml'];
const _androidEmbeddedSubtitles = [..._androidExternalSubtitles, 'pgs', 'pgssub', 'dvdsub', 'vobsub', 'dvbsub', 'mov_text'];
