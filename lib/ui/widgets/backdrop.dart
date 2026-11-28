import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/host.dart';
import '../core/effects.dart';
import '../core/tv_scale.dart';
import '../theme/tokens.dart';
import 'net_image.dart';

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.url, this.drift = false, this.dim = 0.0, this.scrims = true, this.video});

  final Uri? url;
  final bool drift;

  final double dim;
  final bool scrims;
  final Widget? video;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) => _build(context, box.biggest.isFinite ? box.biggest : MediaQuery.sizeOf(context)));

  Widget _build(BuildContext context, Size size) {
    final reduced = Effects.reduced;
    final ratio = TvScale.decodeRatio(context) * (reduced ? 2 / 3 : 1);
    final width = (size.width * ratio).round(), height = (size.height * ratio).round();
    final current = width > 0 && height > 0 ? url : null;
    final drifting = drift && !reduced;
    final bakeScrims = Host.isAndroid && video == null && !drifting && !reduced;
    return RepaintBoundary(child: Stack(fit: StackFit.expand, children: [
      AnimatedSwitcher(
        duration: reduced ? Duration.zero : Zm.slow,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: current == null
            ? const SizedBox.expand(key: ValueKey('none'))
            : _Drift(
                key: ValueKey(current),
                enabled: drifting,
                child: Stack(fit: StackFit.expand, children: [
                  Image(
                    image: BakedBackdrop(
                      current,
                      width: width,
                      height: height,
                      dim: bakeScrims ? dim : 0,
                      scrims: bakeScrims && scrims,
                    ),
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : const SizedBox.expand(),
                    errorBuilder: (_, error, _) {
                      debugPrint('[image] backdrop $current: $error');
                      return const SizedBox.expand();
                    },
                  ),
                  ?video,
                ]),
              ),
      ),
      if (current == null) ?video,
      if ((!bakeScrims || current == null) && (dim > 0 || scrims)) CustomPaint(painter: _ScrimPainter(dim: dim, scrims: scrims)),
    ]));
  }
}

@immutable
class BakedBackdrop extends ImageProvider<BakedBackdrop> {
  const BakedBackdrop(this.url, {required this.width, required this.height, required this.dim, required this.scrims});

  final Uri url;
  final int width;
  final int height;
  final double dim;
  final bool scrims;

  @override
  Future<BakedBackdrop> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(BakedBackdrop key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_bake(decode));

  Future<ImageInfo> _bake(ImageDecoderCallback decode) async {
    final codec = await NetImageProvider(url, decodeWidth: width).codec(decode);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final source = frame.image;
    try {
      final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(rect, Paint()..color = Zc.background);
      paintImage(
        canvas: canvas,
        rect: rect,
        image: source,
        fit: BoxFit.cover,
        alignment: Alignment.topRight,
        filterQuality: FilterQuality.medium,
      );
      _ScrimPainter.draw(canvas, rect, dim: dim, scrims: scrims);
      final picture = recorder.endRecording();
      final baked = await picture.toImage(width, height);
      picture.dispose();
      return ImageInfo(image: baked, debugLabel: 'backdrop $url');
    } finally {
      source.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BakedBackdrop &&
      other.url == url &&
      other.width == width &&
      other.height == height &&
      other.dim == dim &&
      other.scrims == scrims;

  @override
  int get hashCode => Object.hash(url, width, height, dim, scrims);
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({required this.dim, required this.scrims});

  final double dim;
  final bool scrims;

  static const _left = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    stops: [0, 0.45, 0.8],
    colors: [Zc.background, Color(0xB30B0B12), Color(0x000B0B12)],
  );
  static const _bottom = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    stops: [0, 0.5, 0.8],
    colors: [Zc.background, Color(0xCC0B0B12), Color(0x000B0B12)],
  );

  static final _cache = <(int, int, double, bool), ui.Image>{};

  static void draw(Canvas canvas, Rect rect, {required double dim, required bool scrims}) {
    if (dim > 0) canvas.drawRect(rect, Paint()..color = Colors.black.withValues(alpha: dim));
    if (scrims) {
      canvas.drawRect(rect, Paint()..shader = _left.createShader(rect));
      canvas.drawRect(rect, Paint()..shader = _bottom.createShader(rect));
    }
  }

  static ui.Image _image(int w, int h, double dim, bool scrims) => _cache.putIfAbsent((w, h, dim, scrims), () {
        final recorder = ui.PictureRecorder();
        draw(Canvas(recorder), Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), dim: dim, scrims: scrims);
        return recorder.endRecording().toImageSync(w, h);
      });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = (size.width / 4).ceil(), h = (size.height / 4).ceil();
    final image = _image(w, h, (dim * 100).roundToDouble() / 100, scrims);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Offset.zero & size,
        Paint()..filterQuality = FilterQuality.low);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.dim != dim || old.scrims != scrims;
}

class _Drift extends StatefulWidget {
  const _Drift({super.key, required this.child, required this.enabled});

  final Widget child;
  final bool enabled;

  @override
  State<_Drift> createState() => _DriftState();
}

class _DriftState extends State<_Drift> {
  static const _duration = Duration(seconds: 28);

  static const _step = Duration(milliseconds: 33);

  final _progress = ValueNotifier(0.0);
  final _clock = Stopwatch();
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    if (!widget.enabled || _progress.value >= 1) return;
    if (shown && _timer == null) {
      _clock.start();
      _timer = Timer.periodic(_step, (_) => _tick());
    } else if (!shown) {
      _clock.stop();
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick() {
    final t = (_clock.elapsedMicroseconds / _duration.inMicroseconds).clamp(0.0, 1.0);
    _progress.value = t;
    if (t >= 1) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return ValueListenableBuilder(
      valueListenable: _progress,
      builder: (context, progress, child) {
        final t = Curves.easeInOut.transform(progress);
        return Transform.scale(
          scale: 1.04 + 0.08 * t,
          alignment: Alignment(0.6 - 1.2 * t, -0.3),
          child: child,
        );
      },
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class Debounced<T> extends ValueNotifier<T> {
  Debounced(super.value, {this.delay = Zm.backdropDebounce});

  final Duration delay;
  Timer? _timer;

  void set(T next, {bool immediate = false}) {
    _timer?.cancel();
    if (immediate) {
      value = next;
    } else {
      _timer = Timer(delay, () => value = next);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
