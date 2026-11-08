import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/dialogue_downmix.dart';
import 'package:zerk_play/playback/player_settings.dart';

void main() {
  List<double> column(List<double> m, int out) => [for (var i = out; i < m.length; i += 2) m[i]];
  double sum(List<double> v) => v.fold(0.0, (a, b) => a + b);

  test('every layout up to 8 channels has a stereo matrix', () {
    for (var c = 1; c <= DialogueDownmix.maxChannels; c++) {
      expect(DialogueDownmix.matrix(c), hasLength(c * 2), reason: '$c channels');
    }
    expect(DialogueDownmix.matrix(0), isNull);
    expect(DialogueDownmix.matrix(9), isNull);
  });

  test('each output sums to unity so a full-scale mix cannot clip', () {
    for (var c = 2; c <= DialogueDownmix.maxChannels; c++) {
      final m = DialogueDownmix.matrix(c)!;
      expect(sum(column(m, 0)), closeTo(1, 1e-9), reason: 'left, $c channels');
      expect(sum(column(m, 1)), closeTo(1, 1e-9), reason: 'right, $c channels');
    }
  });

  test('5.1 weights the centre above the fronts and surrounds, drops the LFE', () {
    final m = DialogueDownmix.matrix(6)!;
    final fl = m[0], fc = m[4], lfe = m[6], sl = m[8];
    expect(fc, greaterThan(fl));
    expect(fl, greaterThan(sl));
    expect(fc / fl, closeTo(DialogueDownmix.center / DialogueDownmix.front, 1e-9));
    expect(lfe, 0);
    expect(m[1], 0);
    expect(m[8 + 1], 0);
    expect(m[10], 0);
    expect(m[5], fc);
  });

  test('centre share of 5.1 dialogue is louder than the ITU downmix', () {
    final m = DialogueDownmix.matrix(6)!;
    const itu = 0.7071 / (1 + 0.7071 + 0.7071);
    expect(m[4], greaterThan(itu));
  });

  test('7.1 sends each side and back pair to its own side', () {
    final m = DialogueDownmix.matrix(8)!;
    for (final ch in [4, 6]) {
      expect(m[ch * 2], greaterThan(0));
      expect(m[ch * 2 + 1], 0);
      expect(m[(ch + 1) * 2], 0);
      expect(m[(ch + 1) * 2 + 1], greaterThan(0));
    }
  });

  test('stereo passes through and mono feeds both sides', () {
    expect(DialogueDownmix.matrix(2), [1, 0, 0, 1]);
    expect(DialogueDownmix.matrix(1), [1, 1]);
  });

  test('android config carries a matrix per channel count', () {
    final config = DialogueDownmix.androidConfig();
    final matrices = config['matrices']! as Map<String, List<double>>;
    expect(matrices.keys, ['1', '2', '3', '4', '5', '6', '7', '8']);
    expect(config['threshold'], DialogueDownmix.threshold);
  });

  test('mpv filter mirrors the Android levels', () {
    final f = DialogueDownmix.mpvFilter;
    expect(f, startsWith('lavfi=[aresample=ochl=stereo:'));
    expect(f, contains('clev=1.429'));
    expect(f, contains('slev=0.714'));
    expect(f, contains('lfe_mix_level=0:'));
    expect(f, contains('rematrix_maxval=1'));
    expect(f, contains('acompressor=threshold=0.18:ratio=3:attack=10:release=200:makeup=2.2'));
    expect(f, endsWith('alimiter=limit=0.98:level=disabled]'));
  });

  test('the setting persists and defaults to off', () {
    expect(const PlayerSettings().stereoDownmix, isFalse);
    final on = const PlayerSettings().copyWith(stereoDownmix: true);
    expect(PlayerSettings.fromJson(on.toJson()).stereoDownmix, isTrue);
    expect(PlayerSettings.fromJson(const {}).stereoDownmix, isFalse);
  });
}
