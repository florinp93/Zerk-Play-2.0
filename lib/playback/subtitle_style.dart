import 'dart:async';

import 'player_backend.dart';
import 'player_settings.dart';

abstract final class SubtitleStyle {
  static const reference = 720.0;
  static const fontSize = 54.0;
  static const outline = 2.0;
  static const shadow = 2.0;

  static const textColor = 0xFFFFFFFF;
  static const outlineColor = 0xFF000000;
  static const shadowColor = 0xFF000000;

  static const boxPadding = 4.0;

  static const minScale = 0.25;
  static const maxScale = 1.5;
  static const scaleStep = 0.05;

  static const marks = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5];

  static List<double> get scales => [for (var i = 0; minScale + i * scaleStep <= maxScale + 1e-9; i++) step(minScale, i)];

  static double step(double scale, int steps) =>
      ((scale + steps * scaleStep).clamp(minScale, maxScale) * 100).roundToDouble() / 100;

  static String percent(double scale) => '${(scale * 100).round()}%';

  static void applyScale(PlayerBackend player, String? arg, {bool save = false}) {
    final scale = double.tryParse(arg ?? '');
    if (scale == null) return;
    player.setSubtitleScale(scale);
    if (save) unawaited(PlayerSettings.load().then((p) => p.copyWith(subtitleScale: scale).save()));
  }

  static int boxColor(PlayerSettings s) => ((s.subtitleBackgroundOpacity.clamp(0.0, 1.0) * 255).round() << 24) & 0xFF000000;

  static Map<String, String> mpvOptions(PlayerSettings s) => {
        'sub-font': 'Arial',
        'sub-bold': 'no',
        'sub-font-size': fontSize.toStringAsFixed(0),
        'sub-color': _mpvColor(textColor),
        if (s.subtitleBackground) ...{
          'sub-border-style': 'opaque-box',
          'sub-border-color': _mpvColor(boxColor(s)),
          'sub-border-size': '$boxPadding',
          'sub-shadow-offset': '0',
        } else ...{
          'sub-border-style': 'outline-and-shadow',
          'sub-border-color': _mpvColor(outlineColor),
          'sub-border-size': '$outline',
          'sub-shadow-offset': '$shadow',
        },
        'sub-shadow-color': _mpvColor(shadowColor),
        'sub-blur': '0',
        'sub-back-color': '#00000000',
        'sub-scale': s.subtitleScale.toStringAsFixed(2),
        'sub-margin-y': '${s.subtitleBottomMargin}',
        'sub-ass-override': s.overrideAssStyles ? 'force' : 'scale',
      };

  static Map<String, Object> androidStyle(PlayerSettings s) => {
        'textSizeFraction': fontSize / reference * s.subtitleScale,
        'bottomPaddingFraction': s.subtitleBottomMargin / reference,
        'shadowOffsetFraction': shadow / reference * s.subtitleScale,
        'textColor': textColor,
        'outlineColor': outlineColor,
        'shadowColor': shadowColor,
        'background': s.subtitleBackground,
        'backgroundColor': boxColor(s),
        'applyEmbeddedStyles': !s.overrideAssStyles,
      };

  static String _mpvColor(int argb) => '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
