import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/player_settings.dart';
import 'package:zerk_play/playback/subtitle_style.dart';

void main() {
  test('hex colours parse with or without the hash and reject anything else', () {
    expect(SubtitleStyle.parseHex('#FFD700'), 0xFFFFD700);
    expect(SubtitleStyle.parseHex(' ffd700 '), 0xFFFFD700);
    expect(SubtitleStyle.parseHex('#fff'), isNull);
    expect(SubtitleStyle.parseHex('#GGGGGG'), isNull);
    expect(SubtitleStyle.parseHex('#FFD7001'), isNull);
    expect(SubtitleStyle.parseHex(''), isNull);
  });

  test('colours format back to uppercase hex', () {
    expect(SubtitleStyle.formatHex(0xFF0A0B0C), '#0A0B0C');
    expect(SubtitleStyle.formatHex(SubtitleStyle.white), '#FFFFFF');
  });

  test('the default look is white regular text with an outline and shadow', () {
    final mpv = SubtitleStyle.mpvOptions(const PlayerSettings());
    expect(mpv['sub-bold'], 'no');
    expect(mpv['sub-color'], '#FFFFFFFF');
    expect(mpv['sub-border-style'], 'outline-and-shadow');
    final android = SubtitleStyle.androidStyle(const PlayerSettings());
    expect(android['bold'], false);
    expect(android['background'], false);
  });

  test('bold and a custom colour reach both players', () {
    final s = const PlayerSettings().copyWith(subtitleBold: true, subtitleColor: 0xFF123456);
    expect(SubtitleStyle.mpvOptions(s)['sub-bold'], 'yes');
    expect(SubtitleStyle.mpvOptions(s)['sub-color'], '#FF123456');
    expect(SubtitleStyle.androidStyle(s)['bold'], true);
    expect(SubtitleStyle.androidStyle(s)['textColor'], 0xFF123456);
  });

  test('the box can be fully solid', () {
    final s = const PlayerSettings().copyWith(subtitleBackground: true, subtitleBackgroundOpacity: 1.0);
    expect(SubtitleStyle.boxColor(s), 0xFF000000);
    expect(SubtitleStyle.mpvOptions(s)['sub-border-color'], '#FF000000');
    expect(SubtitleStyle.mpvOptions(s)['sub-border-style'], 'opaque-box');
    expect(SubtitleStyle.androidStyle(s)['backgroundColor'], 0xFF000000);
  });

  test('opacity is clamped and colours stay opaque when loaded', () {
    expect(PlayerSettings.fromJson({'subBgOpacity': 4}).subtitleBackgroundOpacity, 1.0);
    expect(PlayerSettings.fromJson({'subColor': 0x00123456}).subtitleColor, 0xFF123456);
  });

  test('bold and a custom colour survive a save and load', () {
    final p = const PlayerSettings().copyWith(subtitleBold: true, subtitleColor: 0xFFABCDEF);
    final back = PlayerSettings.fromJson(p.toJson());
    expect(back.subtitleBold, true);
    expect(back.subtitleColor, 0xFFABCDEF);
  });
}
