import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/auto_crop.dart';

const scope = 0.128;
const imax = 0.032;

BarSample bars(double m) => BarSample(m, m);
const dark = BarSample(0.3, 0.3, dark: true);

final class Feed {
  final crop = AutoCrop();
  var at = Duration.zero;

  CropDecision add(BarSample s, {int seconds = 2}) {
    at += Duration(seconds: seconds);
    return crop.add(s, at);
  }

  CropDecision run(BarSample s, int count, {int seconds = 2}) {
    var d = crop.decision;
    for (var i = 0; i < count; i++) {
      d = add(s, seconds: seconds);
    }
    return d;
  }

  List<double> trace(Iterable<BarSample> samples) => [for (final s in samples) add(s).crop];
}

void main() {
  test('starts uncropped and looks for bars', () {
    final f = Feed();
    expect(f.crop.decision, const CropDecision(0, AutoCrop.searchInterval));
  });

  test('steady scope film is cropped after a few matching samples', () {
    final f = Feed();
    expect(f.trace([bars(scope), bars(scope)]), [0, 0]);
    expect(f.add(bars(scope)).crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(f.crop.decision.interval, AutoCrop.watchInterval);
    final d = f.run(bars(scope + 0.002), 200);
    expect(d.crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(f.crop.locked, isTrue);
  });

  test('takes the smallest of the confirming samples', () {
    final f = Feed();
    f.trace([bars(0.130), bars(0.126), bars(0.128)]);
    expect(f.crop.bars, closeTo(0.126, 1e-9));
  });

  test('steady 16:9 stays uncropped and slows down once settled', () {
    final f = Feed();
    var d = f.run(bars(0), 10);
    expect(d.crop, 0);
    expect(d.interval, AutoCrop.searchInterval);
    d = f.run(bars(0.004), 60);
    expect(d.crop, 0);
    expect(d.interval, AutoCrop.idleInterval);
    expect(f.crop.locked, isFalse);
  });

  test('a dark-edged scene in a settled 16:9 show does not crop', () {
    final f = Feed();
    f.run(bars(0), 70);
    expect(f.run(bars(0.1), AutoCrop.lateConfirmations - 1, seconds: 8).crop, 0);
  });

  test('a long full-frame opening still crops the scope film after it', () {
    final f = Feed();
    f.run(bars(0), 100);
    expect(f.run(bars(scope), AutoCrop.lateConfirmations, seconds: 8).crop, closeTo(scope - AutoCrop.edge, 1e-9));
  });

  test('one stray narrower reading does not shrink the crop', () {
    final f = Feed();
    f.run(bars(scope), 3);
    expect(f.add(bars(imax)).crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(f.add(bars(scope)).crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(f.crop.locked, isFalse);
  });

  test('searching slows down after half a minute and gives up after five', () {
    final f = Feed();
    expect(f.run(bars(0), 10).interval, AutoCrop.searchInterval);
    expect(f.run(bars(0), 10).interval, AutoCrop.idleInterval);
    expect(f.run(bars(0), 30, seconds: 10).interval, Duration.zero);
  });

  test('at start only stops checking once the crop has settled', () {
    final f = Feed()..crop.startOnly = true;
    f.run(bars(scope), 3);
    expect(f.crop.decision.interval, AutoCrop.watchInterval);
    final d = f.run(bars(scope), 70);
    expect(d.crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(d.interval, Duration.zero);
  });

  test('at start only stops on a settled 16:9 picture', () {
    final f = Feed()..crop.startOnly = true;
    expect(f.run(bars(0), 70).interval, Duration.zero);
  });

  test('a settled crop is checked less often', () {
    final f = Feed();
    f.run(bars(scope), 3);
    expect(f.crop.decision.interval, AutoCrop.watchInterval);
    expect(f.run(bars(scope), 70).interval, AutoCrop.idleInterval);
  });

  test('opening logos then a scope film still crops', () {
    final f = Feed();
    f.run(bars(0), 10);
    f.run(dark, 5);
    expect(f.run(bars(scope), 3).crop, closeTo(scope - AutoCrop.edge, 1e-9));
  });

  test('IMAX alternation locks to the largest picture after the first opening', () {
    final f = Feed();
    f.run(bars(scope), 3);
    expect(f.crop.decision.crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(f.run(bars(imax), AutoCrop.shrinkConfirmations).crop, closeTo(imax - AutoCrop.edge, 1e-9));
    expect(f.crop.locked, isTrue);
    final crops = <double>{};
    for (var i = 0; i < 20; i++) {
      for (final d in [f.run(bars(scope), 40), f.run(bars(imax), 40), f.run(dark, 3)]) {
        crops.add(d.crop);
      }
    }
    expect(crops, everyElement(closeTo(imax - AutoCrop.edge, 1e-9)));
  });

  test('picture opening up further than the lock loosens again at once', () {
    final f = Feed();
    f.run(bars(scope), 3);
    f.run(bars(imax), AutoCrop.shrinkConfirmations);
    expect(f.run(bars(0), AutoCrop.shrinkConfirmations).crop, 0);
    expect(f.crop.decision.interval, Duration.zero);
  });

  test('IMAX film that opens in 1.90:1 keeps that crop once it has run for a while', () {
    final f = Feed();
    f.run(bars(imax), 3);
    f.run(bars(imax), 70);
    expect(f.crop.locked, isTrue);
    expect(f.run(bars(scope), 20).crop, closeTo(imax - AutoCrop.edge, 1e-9));
  });

  test('before settling a wider ratio tightens, later openings lock', () {
    final f = Feed();
    f.run(bars(imax), 3);
    expect(f.run(bars(scope), 3).crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(f.run(bars(imax), AutoCrop.shrinkConfirmations).crop, closeTo(imax - AutoCrop.edge, 1e-9));
    expect(f.run(bars(scope), 30).crop, closeTo(imax - AutoCrop.edge, 1e-9));
  });

  test('dark scenes and fades are ignored', () {
    final f = Feed();
    f.run(bars(scope), 3);
    expect(f.run(dark, 20).crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(f.add(const BarSample(0.27, 0.27)).crop, closeTo(scope - AutoCrop.edge, 1e-9));
    expect(f.crop.locked, isFalse);
  });

  test('dark samples do not break a confirming run', () {
    final f = Feed();
    expect(f.trace([bars(scope), dark, bars(scope), dark, bars(scope)]).last, closeTo(scope - AutoCrop.edge, 1e-9));
  });

  test('noise and lopsided frames do not crop', () {
    final f = Feed();
    final noisy = [0.05, 0.12, 0.08, 0.15, 0.03, 0.11, 0.07, 0.14, 0.06, 0.1];
    expect(f.trace([for (final m in noisy) bars(m)]), everyElement(0));
    expect(f.trace([for (var i = 0; i < 6; i++) const BarSample(0.2, 0.05)]), everyElement(0));
  });

  test('jitter within tolerance keeps the crop steady', () {
    final f = Feed();
    f.run(bars(scope), 3);
    final crops = f.trace([for (var i = 0; i < 50; i++) bars(scope + (i.isEven ? 0.004 : -0.004))]);
    expect(crops, everyElement(closeTo(scope - AutoCrop.edge, 1e-9)));
  });

  test('a burned-in subtitle in one bar does not uncrop', () {
    final f = Feed();
    f.run(bars(scope), 3);
    expect(f.add(const BarSample(scope, 0.06)).crop, closeTo(scope - AutoCrop.edge, 1e-9));
  });

  test('picture reaching both crop edges uncrops at once and remeasures', () {
    final f = Feed();
    f.run(bars(scope), 3);
    final d = f.add(const BarSample(scope - AutoCrop.edge, scope - AutoCrop.edge, clipped: true));
    expect(d.crop, 0);
    expect(f.crop.locked, isTrue);
    expect(f.add(bars(scope)).crop, 0);
    expect(f.add(bars(imax)).crop, closeTo(imax - AutoCrop.edge, 1e-9));
    expect(f.run(bars(scope), 20).crop, closeTo(imax - AutoCrop.edge, 1e-9));
  });

  test('reset starts a new file from scratch', () {
    final f = Feed();
    f.run(bars(scope), 3);
    f.add(bars(imax));
    f.crop.reset();
    expect(f.crop.decision, const CropDecision(0, AutoCrop.searchInterval));
    expect(f.crop.locked, isFalse);
    expect(f.run(bars(scope), 3).crop, closeTo(scope - AutoCrop.edge, 1e-9));
  });

  test('parses the native sample message', () {
    final s = BarSample.parse('{"top":0.1250,"bottom":0.1300,"dark":false,"clip":true}')!;
    expect(s.top, 0.125);
    expect(s.bottom, 0.13);
    expect(s.dark, isFalse);
    expect(s.clipped, isTrue);
    expect(BarSample.parse('nope'), isNull);
    expect(BarSample.parse(null), isNull);
    expect(const CropDecision(0.1244444, Duration(seconds: 2)).toJson(), {'crop': 0.1244, 'interval': 2.0});
  });
}
