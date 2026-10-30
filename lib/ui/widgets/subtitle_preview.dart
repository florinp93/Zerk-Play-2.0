import 'package:flutter/material.dart';

import '../../core/host.dart';
import '../../l10n/l10n.dart';
import '../../playback/player_settings.dart';
import '../../playback/subtitle_style.dart';

class SubtitlePreview extends StatelessWidget {
  const SubtitlePreview({super.key, required this.settings});

  final PlayerSettings settings;

  static const _width = 640.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: _width,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF3B5B7A), Color(0xFF9C7A5B), Color(0xFF2B2420)],
                    stops: [0, 0.55, 1],
                  ),
                ),
                child: LayoutBuilder(builder: (context, c) {
                  final unit = c.maxHeight / SubtitleStyle.reference;
                  return Stack(children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: settings.subtitleBottomMargin * unit,
                      child: _Caption(lines: [l10n.subtitlePreviewLine1, l10n.subtitlePreviewLine2], settings: settings, unit: unit),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.lines, required this.settings, required this.unit});

  final List<String> lines;
  final PlayerSettings settings;
  final double unit;

  static double get _em => Host.isAndroid ? 1.0 : 0.895;

  @override
  Widget build(BuildContext context) {
    final scale = settings.subtitleScale;
    final style = TextStyle(
      fontFamily: Host.isWindows ? 'Arial' : null,
      fontWeight: FontWeight.w400,
      fontSize: SubtitleStyle.fontSize * unit * scale * _em,
      height: 1.15,
    );
    final text = lines.join('\n');
    if (settings.subtitleBackground) {
      return Center(
        child: Container(
          padding: EdgeInsets.all(SubtitleStyle.boxPadding * unit),
          color: Color(SubtitleStyle.boxColor(settings)),
          child: Text(text, textAlign: TextAlign.center, style: style.copyWith(color: const Color(SubtitleStyle.textColor))),
        ),
      );
    }
    final stroke = SubtitleStyle.outline * unit * scale * 2;
    final shadow = SubtitleStyle.shadow * unit * scale;
    Widget layer(Color fill, Color edge) => Stack(alignment: Alignment.center, children: [
          Text(text, textAlign: TextAlign.center, style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeJoin = StrokeJoin.round
              ..color = edge,
          )),
          Text(text, textAlign: TextAlign.center, style: style.copyWith(color: fill)),
        ]);
    return Stack(alignment: Alignment.center, children: [
      Transform.translate(
        offset: Offset(shadow, shadow),
        child: layer(const Color(SubtitleStyle.shadowColor), const Color(SubtitleStyle.shadowColor)),
      ),
      layer(const Color(SubtitleStyle.textColor), const Color(SubtitleStyle.outlineColor)),
    ]);
  }
}
