import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/tokens.dart';

abstract class _LoaderState<T extends StatefulWidget> extends State<T> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();
  final _clock = Stopwatch()..start();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Widget frame(BuildContext context, double t);

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _ticker, builder: (context, _) => frame(context, _clock.elapsedMilliseconds / 1000.0));
}

class _Caption extends StatelessWidget {
  const _Caption({required this.lines, required this.t});

  final List<String> lines;
  final double t;

  @override
  Widget build(BuildContext context) {
    final i = (t / 2.8).floor() % lines.length;
    return SizedBox(
      height: 34,
      child: AnimatedSwitcher(
        duration: Zm.slow,
        child: Text(lines[i], key: ValueKey(i), style: Zt.meta.copyWith(letterSpacing: 1.2)),
      ),
    );
  }
}

const _vignette = DecoratedBox(
  decoration: BoxDecoration(
    gradient: RadialGradient(
      radius: 0.9,
      colors: [Color(0x000B0B12), Color(0xCC0B0B12), Color(0xFF0B0B12)],
      stops: [0, 0.68, 1],
    ),
  ),
);

class LiveTvLoader extends StatefulWidget {
  const LiveTvLoader({super.key});

  @override
  State<LiveTvLoader> createState() => _LiveTvLoaderState();
}

class _LiveTvLoaderState extends _LoaderState<LiveTvLoader> {
  @override
  Widget frame(BuildContext context, double t) {
    final l = context.l10n;
    return ColoredBox(
      color: Zc.background,
      child: Stack(fit: StackFit.expand, children: [
        Opacity(opacity: 0.5, child: CustomPaint(painter: _GuidePainter(t))),
        _vignette,
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 460, height: 290, child: CustomPaint(painter: _ScreenPainter(t))),
            const SizedBox(height: 44),
            _Caption(lines: [l.liveTuningIn, l.liveLoadingChannels, l.liveLoadingGuide], t: t),
          ]),
        ),
      ]),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const rowH = 64.0, gap = 12.0, logoW = 110.0;
    final rows = (size.height / (rowH + gap)).ceil() + 1;
    final shift = t * 22;
    final block = Paint();
    final logo = Paint()..color = Zc.surfaceTop;
    for (var r = 0; r < rows; r++) {
      final y = r * (rowH + gap) + 10;
      final rnd = Random(r * 31 + 7);
      final lengths = [for (var i = 0; i < 6; i++) 160.0 + rnd.nextInt(5) * 70];
      final cycle = lengths.fold(0.0, (a, b) => a + b + gap);
      var x = logoW + 2 * gap - (shift + r * 53) % cycle;
      var i = 0;
      while (x < size.width) {
        final w = lengths[i % lengths.length];
        final highlighted = (r + i) % 7 == 3;
        block.color = highlighted ? Zc.accent.withValues(alpha: 0.35) : (i.isEven ? Zc.surfaceHigh : Zc.surface);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, rowH), const Radius.circular(10)), block);
        final text = Paint()..color = Colors.white.withValues(alpha: highlighted ? 0.35 : 0.12);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 16, y + 16, w * 0.55, 10), const Radius.circular(5)), text);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 16, y + 36, w * 0.3, 8), const Radius.circular(4)), text);
        x += w + gap;
        i++;
      }
      canvas.drawRect(Rect.fromLTWH(0, y - gap / 2, logoW + gap * 1.5, rowH + gap), Paint()..color = Zc.background);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(gap, y, logoW, rowH), const Radius.circular(10)), logo);
    }
    final nowX = size.width * 0.38;
    canvas.drawRect(Rect.fromLTWH(nowX - 1.5, 0, 3, size.height), Paint()..color = Zc.danger.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.t != t;
}

class _ScreenPainter extends CustomPainter {
  const _ScreenPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(28));
    canvas.drawRRect(
        screen.inflate(30),
        Paint()
          ..color = Zc.accent.withValues(alpha: 0.18 + 0.06 * sin(t * 3))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40));
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF101018));

    final rnd = Random((t * 20).floor());
    const cell = 6.0;
    final speck = Paint();
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final v = rnd.nextDouble();
        if (v < 0.45) continue;
        speck.color = Colors.white.withValues(alpha: (v - 0.45) * 0.38);
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), speck);
      }
    }
    final scan = Paint()..color = Colors.black.withValues(alpha: 0.28);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.5), scan);
    }
    final barY = (t * 90) % (size.height + 80) - 80;
    canvas.drawRect(
        Rect.fromLTWH(0, barY, size.width, 80),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white.withValues(alpha: 0.1), Colors.transparent],
          ).createShader(Rect.fromLTWH(0, barY, size.width, 80)));
    canvas.restore();

    canvas.drawRRect(
        screen,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.white.withValues(alpha: 0.5));

    final pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 4));
    final badge = RRect.fromRectAndRadius(const Rect.fromLTWH(22, 22, 92, 38), const Radius.circular(10));
    canvas.drawRRect(badge, Paint()..color = Zc.danger.withValues(alpha: pulse));
    canvas.drawCircle(const Offset(40, 41), 6, Paint()..color = Colors.white.withValues(alpha: pulse));
    _text(canvas, 'LIVE', const Offset(54, 28), 21, FontWeight.w800, Colors.white);

    final channel = 1 + ((t * 2).floor() * 7) % 98;
    _text(canvas, 'CH ${channel.toString().padLeft(2, '0')}', Offset(size.width - 118, 26), 24, FontWeight.w700,
        Zc.success.withValues(alpha: 0.9));
  }

  static void _text(Canvas canvas, String s, Offset at, double size, FontWeight weight, Color color) {
    final p = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: 1.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ScreenPainter old) => old.t != t;
}
