import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/moods.dart';
import '../../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'net_image.dart';

class CinemaLoader extends StatefulWidget {
  const CinemaLoader({super.key});

  @override
  State<CinemaLoader> createState() => _CinemaLoaderState();
}

class _CinemaLoaderState extends State<CinemaLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();
  final _clock = Stopwatch()..start();

  late final List<List<Uri>> _rows = [
    for (var r = 0; r < 7; r++) [for (final m in Mood.all) m.backdropUrl(width: 300)]..shuffle(Random(r * 7 + 3)),
  ];

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lines = [l.loadingLine1, l.loadingLine2, l.loadingLine3, l.loadingLine4, l.loadingLine5, l.loadingLine6];
    double now() => _clock.elapsedMilliseconds / 1000.0;
    double flickerAt(double t) => 0.92 + 0.08 * sin(t * 37) * sin(t * 13.7);
    return ColoredBox(
      color: Zc.background,
      child: Stack(fit: StackFit.expand, children: [
        _StillWall(rows: _rows, ticker: _ticker, now: now),
        AnimatedBuilder(
          animation: _ticker,
          builder: (context, _) => ColoredBox(color: Zc.background.withValues(alpha: 1 - 0.42 * flickerAt(now()))),
        ),
        AnimatedBuilder(
          animation: _ticker,
          builder: (context, _) {
            final t = now();
            final flicker = flickerAt(t);
            return Stack(fit: StackFit.expand, children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.85,
                    colors: [Color(0x330B0B12), Color(0xE60B0B12), Color(0xFF0B0B12)],
                    stops: [0, 0.7, 1],
                  ),
                ),
              ),
              CustomPaint(painter: _GrainPainter(seed: (t * 24).floor())),
              Align(alignment: Alignment.topCenter, child: _FilmStrip(t: t)),
              Align(alignment: Alignment.bottomCenter, child: _FilmStrip(t: t, reverse: true)),
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: CustomPaint(painter: _LeaderPainter(t: t, flicker: flicker)),
                  ),
                  const SizedBox(height: 46),
                  SizedBox(
                    height: 34,
                    child: AnimatedSwitcher(
                      duration: Zm.slow,
                      child: Text(
                        lines[(t / 2.6).floor() % lines.length],
                        key: ValueKey((t / 2.6).floor() % lines.length),
                        style: Zt.meta.copyWith(letterSpacing: 1.2),
                      ),
                    ),
                  ),
                ]),
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _StillWall extends StatelessWidget {
  const _StillWall({required this.rows, required this.ticker, required this.now});

  static const _w = 340.0, _h = 191.0, _gap = 16.0;

  final List<List<Uri>> rows;
  final Listenable ticker;
  final double Function() now;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.rotate(
          angle: -0.12,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (r, stills) in rows.indexed) ...[
              _row(stills, r),
              const SizedBox(height: _gap),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _row(List<Uri> stills, int r) {
    final length = stills.length * (_w + _gap);
    final speed = 18.0 + (r % 3) * 7;
    return SizedBox(
      width: 2600,
      height: _h,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: double.infinity,
        child: AnimatedBuilder(
          animation: ticker,
          builder: (context, strip) {
            final shift = (now() * speed) % length;
            final offset = r.isEven ? -shift : shift - length;
            return Transform.translate(offset: Offset(offset - 300, 0), child: strip);
          },
          child: RepaintBoundary(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final url in [...stills, ...stills, ...stills])
                Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: NetImage(url: url, width: _w, height: _h, fallback: const ColoredBox(color: Zc.surface)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LeaderPainter extends CustomPainter {
  const _LeaderPainter({required this.t, required this.flicker});

  final double t;
  final double flicker;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final frac = t % 1;

    canvas.drawCircle(
        c,
        r * 1.1,
        Paint()
          ..shader = RadialGradient(colors: [Zc.accent.withValues(alpha: 0.28 * flicker), Colors.transparent])
              .createShader(Rect.fromCircle(center: c, radius: r * 1.1)));
    canvas.drawCircle(c, r * 0.92, Paint()..color = const Color(0xFF15151F));

    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * pi,
        transform: const GradientRotation(-pi / 2),
        colors: [Colors.white.withValues(alpha: 0.04), Colors.white.withValues(alpha: 0.42 * flicker)],
        stops: [0, frac.clamp(0.001, 1)],
      ).createShader(Rect.fromCircle(center: c, radius: r * 0.92));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.92), -pi / 2, 2 * pi * frac, true, sweep);
    final edge = Offset(cos(-pi / 2 + 2 * pi * frac), sin(-pi / 2 + 2 * pi * frac));
    canvas.drawLine(c, c + edge * r * 0.92, Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2.5);

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(c, r * 0.92, line);
    canvas.drawCircle(c, r * 0.72, line..strokeWidth = 2);
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), line..strokeWidth = 1.5);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), line);

    final p = r * 0.3;
    final play = Path()
      ..moveTo(c.dx - p * 0.75, c.dy - p)
      ..lineTo(c.dx + p, c.dy)
      ..lineTo(c.dx - p * 0.75, c.dy + p)
      ..close();
    canvas.drawShadow(play, Colors.black, 10, false);
    canvas.drawPath(play, Paint()..color = Colors.white.withValues(alpha: 0.9 * flicker));
  }

  @override
  bool shouldRepaint(_LeaderPainter old) => old.t != t;
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(seed);
    final speck = Paint();
    for (var i = 0; i < 260; i++) {
      speck.color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(alpha: 0.04 + rnd.nextDouble() * 0.08);
      final s = 1 + rnd.nextDouble() * 2.2;
      canvas.drawRect(Rect.fromLTWH(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height, s, s), speck);
    }
    if (rnd.nextDouble() < 0.35) {
      final x = rnd.nextDouble() * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x + rnd.nextDouble() * 6 - 3, size.height), Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.seed != seed;
}

class _FilmStrip extends StatelessWidget {
  const _FilmStrip({required this.t, this.reverse = false});

  final double t;
  final bool reverse;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 46, width: double.infinity, child: CustomPaint(painter: _FilmStripPainter(t: t, reverse: reverse)));
}

class _FilmStripPainter extends CustomPainter {
  const _FilmStripPainter({required this.t, required this.reverse});

  final double t;
  final bool reverse;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF050508));
    const pitch = 34.0;
    final shift = (t * 60) % pitch;
    final hole = Paint()..color = Colors.white.withValues(alpha: 0.13);
    for (var x = -pitch + (reverse ? -shift : shift); x < size.width + pitch; x += pitch) {
      for (final y in [7.0, size.height - 17]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 18, 10), const Radius.circular(2.5)), hole);
      }
    }
  }

  @override
  bool shouldRepaint(_FilmStripPainter old) => old.t != t;
}
