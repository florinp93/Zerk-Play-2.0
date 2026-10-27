import 'player_settings.dart';

abstract final class SubtitleStyle {
  static const _reference = 720.0;
  static const fontSize = 54.0;
  static const outline = 2.0;
  static const shadow = 2.0;

  static const textColor = 0xFFFFFFFF;
  static const outlineColor = 0xFF000000;
  static const shadowColor = 0xFF000000;

  static const boxPadding = 4.0;

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
        'textSizeFraction': fontSize / _reference * s.subtitleScale,
        'bottomPaddingFraction': s.subtitleBottomMargin / _reference,
        'shadowOffsetFraction': shadow / _reference * s.subtitleScale,
        'textColor': textColor,
        'outlineColor': outlineColor,
        'shadowColor': shadowColor,
        'background': s.subtitleBackground,
        'backgroundColor': boxColor(s),
        'applyEmbeddedStyles': !s.overrideAssStyles,
      };

  static String _mpvColor(int argb) => '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
