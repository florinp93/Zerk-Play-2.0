import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/device_profile.dart';
import 'package:zerk_play/playback/emby_playback_api.dart';
import 'package:zerk_play/playback/player_settings.dart';
import 'package:zerk_play/playback/transcode_quality.dart';

void main() {
  const profile = {'Name': 'test'};

  test('steps run from 2 to 200 Mbps', () {
    expect(kTranscodeMbps.first, 2);
    expect(kTranscodeMbps.last, 200);
    expect(kTranscodeMbps, [2, 3, 4, 6, 8, 10, 15, 20, 30, 40, 60, 80, 100, 120, 150, 200]);
  });

  test('bitrates snap to the nearest step and stay in range', () {
    expect(normalizeTranscodeBitrate(0), 0);
    expect(normalizeTranscodeBitrate(-5), 0);
    expect(normalizeTranscodeBitrate(8000000), 8000000);
    expect(normalizeTranscodeBitrate(9000000), 8000000);
    expect(normalizeTranscodeBitrate(500000), 2000000);
    expect(normalizeTranscodeBitrate(900000000), 200000000);
    expect(mbpsLabel(15000000), '15 Mbps');
  });

  test('Emby forced transcode sends the cap and disables direct play and stream in the query', () {
    final r = PlaybackInfoRequest.build(
      jellyfin: false,
      userId: 'u1',
      deviceProfile: profile,
      mediaSourceId: 'ms',
      audioStreamIndex: 2,
      subtitleStreamIndex: -1,
      start: const Duration(seconds: 90),
      maxBitrate: 8000000,
      enableDirectPlay: false,
      enableDirectStream: false,
    );
    expect(r.query['MaxStreamingBitrate'], '8000000');
    expect(r.query['EnableDirectPlay'], 'false');
    expect(r.query['EnableDirectStream'], 'false');
    expect(r.query['AudioStreamIndex'], '2');
    expect(r.query['SubtitleStreamIndex'], '-1');
    expect(r.query['StartTimeTicks'], '900000000');
    expect(r.query['MediaSourceId'], 'ms');
    expect(r.query['UserId'], 'u1');
    expect(r.body, {'DeviceProfile': profile});
  });

  test('Jellyfin forced transcode puts everything in the body', () {
    final r = PlaybackInfoRequest.build(
      jellyfin: true,
      userId: 'u1',
      deviceProfile: profile,
      audioStreamIndex: 1,
      maxBitrate: 20000000,
      enableDirectPlay: false,
      enableDirectStream: false,
    );
    expect(r.query, isEmpty);
    expect(r.body['MaxStreamingBitrate'], 20000000);
    expect(r.body['EnableDirectPlay'], false);
    expect(r.body['EnableDirectStream'], false);
    expect(r.body['EnableTranscoding'], true);
    expect(r.body['AudioStreamIndex'], 1);
    expect(r.body['UserId'], 'u1');
    expect(r.body['DeviceProfile'], profile);
    expect(r.body.containsKey('SubtitleStreamIndex'), isFalse);
    expect(r.body.containsKey('StartTimeTicks'), isFalse);
  });

  test('the original path keeps direct play on with no cap', () {
    for (final jellyfin in [false, true]) {
      final r = PlaybackInfoRequest.build(jellyfin: jellyfin, userId: 'u1', deviceProfile: profile);
      final values = jellyfin ? r.body : r.query;
      expect('${values['MaxStreamingBitrate']}', '$kUnlimitedBitrate');
      expect('${values['EnableDirectPlay']}', 'true');
      expect('${values['EnableDirectStream']}', 'true');
    }
  });

  test('the device profile carries the transcode cap', () {
    expect(buildAndroidDeviceProfile(null, maxBitrate: 6000000)['MaxStreamingBitrate'], 6000000);
    expect(buildDesktopDeviceProfile(maxBitrate: 6000000)['MaxStreamingBitrate'], 6000000);
  });

  test('the default transcode bitrate survives a save and load', () {
    final restored = PlayerSettings.fromJson(const PlayerSettings(transcodeBitrate: 30000000).toJson());
    expect(restored.transcodeBitrate, 30000000);
    expect(PlayerSettings.fromJson(const {}).transcodeBitrate, 0);
    expect(PlayerSettings.fromJson(const {'transcodeBitrate': 7000000}).transcodeBitrate, 6000000);
  });
}
