import 'dart:math' as math;

import 'package:flutter/material.dart';

class ZerkLogo extends StatelessWidget {
  const ZerkLogo({super.key, this.size = 48, this.tile = true, this.color = Colors.white});

  final double size;
  final bool tile;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ZerkLogoPainter(tile: tile, color: color)),
    );
  }
}

class _ZerkLogoPainter extends CustomPainter {
  _ZerkLogoPainter({required this.tile, required this.color});

  final bool tile;
  final Color color;

  static const _gradientTop = Color(0xFF8E87FF);
  static const _gradientBottom = Color(0xFF4F46E5);

  static const _triangle = [Offset(27, 20), Offset(27, 80), Offset(79, 50)];
  static const _cornerRadius = 6.0;
  static const _cut = [Offset(0, 40), Offset(50, 40), Offset(33, 60), Offset(100, 60)];
  static const _cutWidth = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.scale(s);
    const box = Rect.fromLTWH(0, 0, 100, 100);

    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(23)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_gradientTop, _gradientBottom],
          ).createShader(box),
      );
    }

    canvas.saveLayer(box, Paint());
    canvas.drawPath(_roundedTriangle(), Paint()..color = tile ? Colors.white : color);
    final cut = Path()..addPolygon(_cut, false);
    canvas.drawPath(
      cut,
      Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeWidth = _cutWidth
        ..strokeJoin = StrokeJoin.miter
        ..strokeMiterLimit = 10,
    );
    canvas.restore();
  }

  static Path _roundedTriangle() {
    final path = Path();
    const pts = _triangle;
    for (var i = 0; i < pts.length; i++) {
      final prev = pts[(i + pts.length - 1) % pts.length];
      final p = pts[i];
      final next = pts[(i + 1) % pts.length];
      final u1 = (prev - p) / (prev - p).distance;
      final u2 = (next - p) / (next - p).distance;
      final angle = math.acos(u1.dx * u2.dx + u1.dy * u2.dy);
      final t = _cornerRadius / math.tan(angle / 2);
      final a = p + u1 * t;
      final b = p + u2 * t;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.arcToPoint(b, radius: const Radius.circular(_cornerRadius), clockwise: false);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_ZerkLogoPainter old) => old.tile != tile || old.color != color;
}
