import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/mpv/mpv_options.dart';
import 'package:zerk_play/playback/player_settings.dart';

void main() {
  test('new installs keep the scaler the quality preset picks', () {
    final p = PlayerSettings.fromJson({});
    expect(p.scaler, VideoScaler.auto);
    expect(p.antiRinging, isFalse);
    final o = buildMpvOptions(settings: p);
    expect(o['scale'], 'spline36');
    expect(o.containsKey('scale-antiring'), isFalse);
  });

  test('scaler choices survive a save and load', () {
    final p = const PlayerSettings().copyWith(scaler: VideoScaler.ewaLanczos, antiRinging: true);
    final back = PlayerSettings.fromJson(p.toJson());
    expect(back.scaler, VideoScaler.ewaLanczos);
    expect(back.antiRinging, isTrue);
  });

  test('a chosen scaler is applied after the high quality profile', () {
    final p = const PlayerSettings(videoQuality: VideoQuality.high, scaler: VideoScaler.lanczos, antiRinging: true);
    final keys = buildMpvOptions(settings: p).keys.toList();
    expect(keys.indexOf('scale'), greaterThan(keys.indexOf('profile')));
    expect(keys.indexOf('scale-antiring'), greaterThan(keys.indexOf('profile')));
    final o = buildMpvOptions(settings: p);
    expect(o['scale'], 'lanczos');
    expect(o['scale-antiring'], '0.6');
  });
}
