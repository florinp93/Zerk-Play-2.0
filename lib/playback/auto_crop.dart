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
  static const lateConfirmations = 6;
  static const shrinkConfirmations = 2;
  static const settle = Duration(minutes: 2);
  static const quickSearch = Duration(seconds: 30);
  static const giveUp = Duration(minutes: 5);
  static const searchInterval = Duration(seconds: 3);
  static const watchInterval = Duration(seconds: 4);
  static const idleInterval = Duration(seconds: 10);

  AutoCrop({this.startOnly = false});

  bool startOnly;

  double _bars = 0;
  bool _locked = false;
  bool _probing = false;
  double _probeFrom = 0;
  Duration? _since;
  Duration? _first;
  Duration _at = Duration.zero;
  final _run = <double>[];
  final _lower = <double>[];

  double get bars => _bars;

  bool get locked => _locked;

  double get crop => _bars <= 0 ? 0 : math.max(0, _bars - edge);

  bool get _settled {
    final since = _since;
    return since != null && _at - since >= settle;
  }

  Duration get interval {
    if (_probing) return searchInterval;
    if (_bars > 0) {
      if (!_settled) return watchInterval;
      return startOnly ? Duration.zero : idleInterval;
    }
    if (_locked) return Duration.zero;
    final searched = _first == null ? Duration.zero : _at - _first!;
    if (searched >= giveUp || startOnly && _settled) return Duration.zero;
    return searched >= quickSearch ? idleInterval : searchInterval;
  }

  CropDecision get decision => CropDecision(crop, interval);

  void reset() {
    _bars = 0;
    _locked = false;
    _probing = false;
    _probeFrom = 0;
    _since = null;
    _first = null;
    _at = Duration.zero;
    _run.clear();
    _lower.clear();
  }

  static void _collect(List<double> run, double m) {
    run.add(m);
    if (run.reduce(math.max) - run.reduce(math.min) > tolerance) {
      run
        ..clear()
        ..add(m);
    }
  }

  CropDecision add(BarSample s, Duration at) {
    _at = at;
    _first ??= at;
    if (s.clipped) {
      if (_bars > 0) {
        _probeFrom = _bars;
        _bars = 0;
        _probing = true;
        _locked = true;
        _since = null;
        _run.clear();
        _lower.clear();
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
      _collect(_lower, m);
      if (_lower.length < shrinkConfirmations) return decision;
      _bars = _lower.reduce(math.min);
      _locked = true;
      _since = at;
      _run.clear();
      _lower.clear();
      return decision;
    }
    _lower.clear();
    if (m <= _bars + tolerance) {
      _run.clear();
      final since = _since;
      if (since == null || at < since) {
        _since = at;
      } else if (at - since >= settle && _bars > 0) {
        _locked = true;
      }
      return decision;
    }
    if (_locked) return decision;
    _collect(_run, m);
    if (_run.length >= (_bars <= 0 && _settled ? lateConfirmations : confirmations)) {
      _bars = _run.reduce(math.min);
      _since = at;
      _run.clear();
    }
    return decision;
  }
}
