import 'dart:convert';
import 'dart:math' as math;

final class BarSample {
  const BarSample(this.top, this.bottom, {this.dark = false, this.clipped = false});

  final double top;
  final double bottom;
  final bool dark;
  final bool clipped;

  static BarSample? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final top = m['top'], bottom = m['bottom'];
      if (top is! num || bottom is! num) return null;
      return BarSample(top.toDouble(), bottom.toDouble(), dark: m['dark'] == true, clipped: m['clip'] == true);
    } on FormatException {
      return null;
    }
  }
}

final class CropDecision {
  const CropDecision(this.crop, this.interval);

  final double crop;
  final Duration interval;

  Map<String, Object> toJson() => {'crop': double.parse(crop.toStringAsFixed(4)), 'interval': interval.inMilliseconds / 1000};

  @override
  bool operator ==(Object other) => other is CropDecision && other.crop == crop && other.interval == interval;

  @override
  int get hashCode => Object.hash(crop, interval);

  @override
  String toString() => 'CropDecision(${crop.toStringAsFixed(4)}, ${interval.inMilliseconds} ms)';
}

final class AutoCrop {
  static const tolerance = 0.006;
  static const edge = 0.004;
  static const minBars = 0.01;
  static const maxBars = 0.23;
  static const asymmetry = 0.02;
  static const confirmations = 3;
  static const settle = Duration(minutes: 2);
  static const searchInterval = Duration(seconds: 3);
  static const watchInterval = Duration(seconds: 2);

  double _bars = 0;
  bool _locked = false;
  bool _probing = false;
  double _probeFrom = 0;
  Duration? _since;
  final _run = <double>[];

  double get bars => _bars;

  bool get locked => _locked;

  double get crop => _bars <= 0 ? 0 : math.max(0, _bars - edge);

  Duration get interval {
    if (_probing) return searchInterval;
    if (_bars > 0) return watchInterval;
    return _locked ? Duration.zero : searchInterval;
  }

  CropDecision get decision => CropDecision(crop, interval);

  void reset() {
    _bars = 0;
    _locked = false;
    _probing = false;
    _probeFrom = 0;
    _since = null;
    _run.clear();
  }

  CropDecision add(BarSample s, Duration at) {
    if (s.clipped) {
      if (_bars > 0) {
        _probeFrom = _bars;
        _bars = 0;
        _probing = true;
        _locked = true;
        _since = null;
        _run.clear();
      }
      return decision;
    }
    if (s.dark || (s.top - s.bottom).abs() > asymmetry) return decision;
    var m = math.min(s.top, s.bottom);
    if (m > maxBars) return decision;
    if (m < minBars) m = 0;
    if (_probing) {
      if (m < _probeFrom - tolerance) {
        _bars = m;
        _probing = false;
        _since = at;
      }
      return decision;
    }
    if (m < _bars - tolerance) {
      _bars = m;
      _locked = true;
      _since = at;
      _run.clear();
      return decision;
    }
    if (m <= _bars + tolerance) {
      _run.clear();
      final since = _since;
      if (since == null || at < since) {
        _since = at;
      } else if (at - since >= settle) {
        _locked = true;
      }
      return decision;
    }
    if (_locked) return decision;
    _run.add(m);
    if (_run.reduce(math.max) - _run.reduce(math.min) > tolerance) {
      _run
        ..clear()
        ..add(m);
    }
    if (_run.length >= confirmations) {
      _bars = _run.reduce(math.min);
      _since = at;
      _run.clear();
    }
    return decision;
  }
}
