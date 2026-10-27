import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

class TvScale extends StatelessWidget {
  const TvScale({super.key, required this.child});

  static const designWidth = 1920.0;
  static const designHeight = 1080.0;
  static const maxHeight = 1200.0;

  final Widget child;

  static final videoUnderlay = ValueNotifier(false);

  static double decodeRatio(BuildContext context) {
    final view = View.maybeOf(context);
    final display = view?.display.size;
    if (display == null || display.isEmpty) return MediaQuery.devicePixelRatioOf(context);
    return math.min(display.width / designWidth, display.height / designHeight);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, box) {
      if (!box.hasBoundedWidth || !box.hasBoundedHeight || box.maxWidth == 0 || box.maxHeight == 0) return child;
      final scale = math.min(box.maxWidth / designWidth, box.maxHeight / designHeight);
      final size = Size(box.maxWidth / scale, math.min(box.maxHeight / scale, maxHeight));
      return ValueListenableBuilder<bool>(
        valueListenable: videoUnderlay,
        builder: (context, underlay, child) => ColoredBox(color: underlay ? const Color(0x00000000) : Zc.background, child: child),
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: size.width * scale,
            height: size.height * scale,
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: size,
                    devicePixelRatio: mq.devicePixelRatio * scale,
                    textScaler: TextScaler.noScaling,
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
