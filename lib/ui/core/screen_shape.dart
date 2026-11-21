import 'package:flutter/widgets.dart';

import '../../playback/player_settings.dart';

class ScreenShape extends StatelessWidget {
  const ScreenShape({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: PlayerSettings.screen,
        child: child,
        builder: (context, shape, child) => LayoutBuilder(builder: (context, box) {
          if (!box.hasBoundedWidth || !box.hasBoundedHeight || box.maxHeight == 0) return child!;
          if (shape.anamorphic > 1) {
            return FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(width: box.maxWidth * shape.anamorphic, height: box.maxHeight, child: child),
            );
          }
          if (shape.scope <= box.maxWidth / box.maxHeight + 0.01) return child!;
          return ColoredBox(
            color: const Color(0xFF000000),
            child: Center(child: SizedBox(width: box.maxWidth, height: box.maxWidth / shape.scope, child: child)),
          );
        }),
      );
}
