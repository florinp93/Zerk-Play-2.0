import 'dart:math' as math;

enum _Speaker { left, right, center, lfe, surroundLeft, surroundRight, surroundCenter }

abstract final class DialogueDownmix {
  static const front = 0.7;
  static const center = 1.0;
  static const surround = 0.5;
  static const lfe = 0.0;

  static const threshold = 0.18;
  static const ratio = 3.0;
  static const makeup = 2.2;
  static const attackMs = 10.0;
  static const releaseMs = 200.0;
  static const limit = 0.98;

  static const maxChannels = 8;

  static const _layouts = <int, List<_Speaker>>{
    2: [_Speaker.left, _Speaker.right],
    3: [_Speaker.left, _Speaker.right, _Speaker.center],
    4: [_Speaker.left, _Speaker.right, _Speaker.surroundLeft, _Speaker.surroundRight],
    5: [_Speaker.left, _Speaker.right, _Speaker.center, _Speaker.surroundLeft, _Speaker.surroundRight],
    6: [_Speaker.left, _Speaker.right, _Speaker.center, _Speaker.lfe, _Speaker.surroundLeft, _Speaker.surroundRight],
    7: [
      _Speaker.left, _Speaker.right, _Speaker.center, _Speaker.lfe,
      _Speaker.surroundCenter, _Speaker.surroundLeft, _Speaker.surroundRight,
    ],
    8: [
      _Speaker.left, _Speaker.right, _Speaker.center, _Speaker.lfe,
      _Speaker.surroundLeft, _Speaker.surroundRight, _Speaker.surroundLeft, _Speaker.surroundRight,
    ],
  };

  static (double, double) _weights(_Speaker s) => switch (s) {
        _Speaker.left => (front, 0.0),
        _Speaker.right => (0.0, front),
        _Speaker.center => (center, center),
        _Speaker.lfe => (lfe, lfe),
        _Speaker.surroundLeft => (surround, 0.0),
        _Speaker.surroundRight => (0.0, surround),
        _Speaker.surroundCenter => (surround * math.sqrt1_2, surround * math.sqrt1_2),
      };

  static List<double>? matrix(int channels) {
    if (channels == 1) return [1, 1];
    final layout = _layouts[channels];
    if (layout == null) return null;
    final weights = [for (final s in layout) _weights(s)];
    final left = weights.fold(0.0, (sum, w) => sum + w.$1);
    final right = weights.fold(0.0, (sum, w) => sum + w.$2);
    return [for (final (l, r) in weights) ...[l / left, r / right]];
  }

  static Map<String, Object> androidConfig() => {
        'matrices': {for (var c = 1; c <= maxChannels; c++) '$c': matrix(c)!},
        'threshold': threshold,
        'ratio': ratio,
        'makeup': makeup,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'limit': limit,
      };

  static String _fmt(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  static String get mpvFilter => 'lavfi=[aresample=ochl=stereo'
      ':clev=${_fmt(center / front)}:slev=${_fmt(surround / front)}:lfe_mix_level=${_fmt(lfe / front)}:rematrix_maxval=1,'
      'acompressor=threshold=${_fmt(threshold)}:ratio=${_fmt(ratio)}:attack=${_fmt(attackMs)}'
      ':release=${_fmt(releaseMs)}:makeup=${_fmt(makeup)},alimiter=limit=${_fmt(limit)}:level=disabled]';

  static const mpvLabel = 'zerkdownmix';
}
