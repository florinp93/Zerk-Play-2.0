import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/player_settings.dart';

void main() {
  test('the old auto-skip toggle becomes automatic intro skipping', () {
    expect(PlayerSettings.fromJson({'autoSkipIntro': true}).skipIntro, SkipMode.auto);
    expect(PlayerSettings.fromJson({'autoSkipIntro': false}).skipIntro, SkipMode.button);
  });

  test('new installs show buttons for intros and credits', () {
    final p = PlayerSettings.fromJson({});
    expect(p.skipIntro, SkipMode.button);
    expect(p.skipCredits, SkipMode.button);
  });

  test('skip choices survive a save and load', () {
    final p = const PlayerSettings().copyWith(skipIntro: SkipMode.off, skipCredits: SkipMode.auto);
    final back = PlayerSettings.fromJson(p.toJson());
    expect(back.skipIntro, SkipMode.off);
    expect(back.skipCredits, SkipMode.auto);
  });

  test('the old Remove black bars toggle becomes Continuous', () {
    expect(PlayerSettings.fromJson({'autoCrop': true}).autoCropMode, AutoCropMode.continuous);
    expect(PlayerSettings.fromJson({'autoCrop': false}).autoCropMode, AutoCropMode.off);
    final p = const PlayerSettings().copyWith(autoCropMode: AutoCropMode.start);
    expect(PlayerSettings.fromJson(p.toJson()).autoCropMode, AutoCropMode.start);
  });
}
