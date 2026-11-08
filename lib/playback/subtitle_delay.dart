abstract final class SubtitleDelay {
  static const min = -5.0;
  static const max = 5.0;
  static const step = 0.1;
  static const marks = [-5.0, -2.5, 0.0, 2.5, 5.0];

  static double clamp(double seconds) => (seconds.clamp(min, max) * 10).roundToDouble() / 10;

  static int micros(double seconds) => (clamp(seconds) * 1000000).round();

  static String format(double seconds) {
    final s = clamp(seconds);
    if (s == 0) return '0.0s';
    return '${s > 0 ? '+' : ''}${s.toStringAsFixed(1)}s';
  }
}
