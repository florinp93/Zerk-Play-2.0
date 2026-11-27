import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/core/emby/models/media_source.dart';
import 'package:zerk_play/l10n/app_localizations_en.dart';
import 'package:zerk_play/playback/emby_playback_api.dart';
import 'package:zerk_play/playback/playback_info.dart';

MediaStream _video({String? type, String? subType, String? range, String? codec, double? level}) => MediaStream(
      index: 0,
      type: MediaStreamType.video,
      codec: codec ?? 'hevc',
      level: level,
      width: 3840,
      height: 2160,
      extendedVideoType: type,
      extendedVideoSubType: subType,
      videoRange: range,
    );

MediaSourceInfo _source(MediaStream video) => MediaSourceInfo(id: '1', streams: [video], chapters: const []);

void main() {
  final l10n = L10nEn();

  test('bitrates read in kbps below 1 Mbps and Mbps above', () {
    expect(PlaybackInfo.bitrate(null), isNull);
    expect(PlaybackInfo.bitrate(0), isNull);
    expect(PlaybackInfo.bitrate(640000), '640 kbps');
    expect(PlaybackInfo.bitrate(5200000), '5.2 Mbps');
    expect(PlaybackInfo.bitrate(62400000), '62 Mbps');
  });

  test('sample rates read in kHz', () {
    expect(PlaybackInfo.sampleRate(48000), '48 kHz');
    expect(PlaybackInfo.sampleRate(44100), '44.1 kHz');
    expect(PlaybackInfo.sampleRate(0), isNull);
  });

  test('frame rates drop trailing zeros', () {
    expect(PlaybackInfo.frameRate(24), '24');
    expect(PlaybackInfo.frameRate(23.976023976), '23.976');
    expect(PlaybackInfo.frameRate(29.97002997), '29.97');
    expect(PlaybackInfo.frameRate(null), isNull);
  });

  test('levels follow the numbering of each codec', () {
    expect(PlaybackInfo.level('h264', 41), 'L4.1');
    expect(PlaybackInfo.level('hevc', 153), 'L5.1');
    expect(PlaybackInfo.level('hevc', 150), 'L5.0');
    expect(PlaybackInfo.level('av1', 8), isNull);
    expect(PlaybackInfo.level('h264', 0), isNull);
  });

  test('channel layouts come from the server name or the channel count', () {
    MediaStream audio({String? layout, int? channels}) =>
        MediaStream(index: 1, type: MediaStreamType.audio, channelLayout: layout, channels: channels);
    expect(PlaybackInfo.channelLayout(audio(layout: '7.1', channels: 8)), '7.1');
    expect(PlaybackInfo.channelLayout(audio(layout: '5.1(side)', channels: 6)), '5.1');
    expect(PlaybackInfo.channelLayout(audio(layout: 'stereo', channels: 2)), 'Stereo');
    expect(PlaybackInfo.channelLayout(audio(layout: 'mono')), 'Mono');
    expect(PlaybackInfo.channelLayout(audio(channels: 6)), '5.1');
    expect(PlaybackInfo.channelLayout(audio()), isNull);
  });

  test('Dolby Vision profiles split the profile from the compatibility id', () {
    expect(PlaybackInfo.dolbyVisionProfile(_video(subType: 'DoviProfile81')), '8.1');
    expect(PlaybackInfo.dolbyVisionProfile(_video(subType: 'DoviProfile50')), '5');
    expect(PlaybackInfo.dolbyVisionProfile(_video(subType: 'DoviProfile76')), '7.6');
    expect(PlaybackInfo.dolbyVisionProfile(_video(subType: 'DoviProfile100')), '10');
    expect(PlaybackInfo.dolbyVisionProfile(_video()), isNull);
  });

  test('dynamic range names the HDR format and the Dolby Vision profile', () {
    expect(PlaybackInfo.dynamicRange(_source(_video()), 'Profile'), isNull);
    expect(PlaybackInfo.dynamicRange(_source(_video(range: 'HDR')), 'Profile'), 'HDR10');
    expect(PlaybackInfo.dynamicRange(_source(_video(type: 'Hdr10Plus')), 'Profile'), 'HDR10+');
    expect(PlaybackInfo.dynamicRange(_source(_video(type: 'HyperLogGamma')), 'Profile'), 'HLG');
    expect(
      PlaybackInfo.dynamicRange(_source(_video(type: 'DolbyVision', subType: 'DoviProfile81')), 'Profile'),
      'Dolby Vision  ·  Profile 8.1',
    );
  });

  test('transcode reasons become short phrases without repeats', () {
    expect(
      PlaybackInfo.reasonLabels(l10n, 'VideoCodecNotSupported,VideoProfileNotSupported,AudioCodecNotSupported'),
      ['Video format not supported', 'Audio format not supported'],
    );
    expect(PlaybackInfo.reasonLabels(l10n, 'ContainerBitrateExceedsLimit,VideoBitrateNotSupported'), ['Bitrate above the limit']);
    expect(PlaybackInfo.reasonLabels(l10n, 'SubtitleCodecNotSupported'), ['Subtitle format not supported']);
    expect(PlaybackInfo.reasonLabels(l10n, 'SomethingNew'), ['Something New']);
    expect(PlaybackInfo.reasonLabels(l10n, null), isEmpty);
  });

  test('rows list the method and only show a reason when transcoding', () {
    final source = _source(_video());
    List<String> labels(PlayMethod method, {String? reasons}) => [
          for (final r in PlaybackInfo.rows(l10n, source: source, method: method, transcodeReasons: reasons)) r.label,
        ];
    expect(labels(PlayMethod.directPlay, reasons: 'VideoCodecNotSupported'), isNot(contains('Transcode reason')));
    expect(labels(PlayMethod.transcode, reasons: 'VideoCodecNotSupported'), contains('Transcode reason'));
    final rows = PlaybackInfo.rows(l10n, source: source, method: PlayMethod.directStream);
    expect(rows.first.detail, 'Direct stream');
    expect(rows.firstWhere((r) => r.label == 'Dynamic range').detail, 'SDR');
    expect(rows.firstWhere((r) => r.label == 'Subtitles').detail, 'Off');
  });
}
