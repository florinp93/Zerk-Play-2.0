import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/subtitle_delay.dart';

void main() {
  test('steps snap to tenths and stay inside the range', () {
    expect(SubtitleDelay.clamp(0.1 + 0.2), 0.3);
    expect(SubtitleDelay.clamp(-0.04), 0);
    expect(SubtitleDelay.clamp(12), SubtitleDelay.max);
    expect(SubtitleDelay.clamp(-12), SubtitleDelay.min);
  });

  test('offset is sent to the player in microseconds', () {
    expect(SubtitleDelay.micros(0.3), 300000);
    expect(SubtitleDelay.micros(-1.5), -1500000);
    expect(SubtitleDelay.micros(0), 0);
    var v = 0.0;
    for (var i = 0; i < 7; i++) {
      v = SubtitleDelay.clamp(v + SubtitleDelay.step);
    }
    expect(SubtitleDelay.micros(v), 700000);
  });

  test('labels show the sign like mpv does', () {
    expect(SubtitleDelay.format(0), '0.0s');
    expect(SubtitleDelay.format(-0.0), '0.0s');
    expect(SubtitleDelay.format(0.3), '+0.3s');
    expect(SubtitleDelay.format(-2.5), '-2.5s');
  });

  test('the zero mark sits on the slider', () {
    expect(SubtitleDelay.marks, contains(0.0));
    expect(SubtitleDelay.marks.first, SubtitleDelay.min);
    expect(SubtitleDelay.marks.last, SubtitleDelay.max);
  });
}
