import 'package:flutter/widgets.dart';

import '../../playback/player_settings.dart';
import 'tv_scale.dart';

class ScreenShape extends StatelessWidget {
  const ScreenShape({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: PlayerSettings.screen,
        child: child,
        builder: (context, shape, child) => LayoutBuilder(builder: (context, box) {
          final width = box.hasBoundedWidth ? box.maxWidth : 0.0;
          final height = box.hasBoundedHeight ? box.maxHeight : 0.0;
          final lens = shape.anamorphic > 1 ? shape.anamorphic : 1.0;
          final band = lens == 1 && shape.scope > 0 && height > 0 && shape.scope > width / height + 0.01
              ? width / shape.scope
              : height;
          return ValueListenableBuilder(
            valueListenable: TvScale.videoUnderlay,
            builder: (context, underlay, child) =>
                ColoredBox(color: underlay ? const Color(0x00000000) : const Color(0xFF000000), child: child),
            child: Center(
              child: SizedBox(
                width: width,
                height: band,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(width: width * lens, height: band, child: child),
                ),
              ),
            ),
          );
        }),
      );
}
