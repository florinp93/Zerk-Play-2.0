import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/net_image.dart';

class PlayerLoadingView extends StatelessWidget {
  const PlayerLoadingView({super.key, required this.title, required this.subtitle, this.backdrop, this.logo});

  final String title;
  final String subtitle;
  final Uri? backdrop;
  final Uri? logo;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      if (backdrop != null)
        Image(
          image: NetImageProvider(backdrop!, decodeWidth: 1920),
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: sync ? Duration.zero : const Duration(milliseconds: 400),
            child: child,
          ),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [Color(0xF2000000), Color(0x99000000), Color(0x33000000)],
            stops: [0, 0.45, 1],
          ),
        ),
      ),
      Positioned(
        left: 120,
        right: 120,
        bottom: 120,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (logo != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 220),
              child: Image(
                image: NetImageProvider(logo!, decodeWidth: 960),
                fit: BoxFit.contain,
                alignment: Alignment.bottomLeft,
                errorBuilder: (_, _, _) => Text(title, style: Zt.display.copyWith(fontSize: 64)),
              ),
            )
          else
            Text(title, style: Zt.display.copyWith(fontSize: 64), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(subtitle, style: Zt.title.copyWith(color: Zc.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 40),
          const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 5)),
        ]),
      ),
    ]);
  }
}

class PlayerErrorView extends StatelessWidget {
  const PlayerErrorView({super.key, required this.title, required this.message, required this.onBack});

  final String title;
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 900,
            child: FocusZone(
              autofocus: true,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline_rounded, color: Zc.danger, size: 72),
                const SizedBox(height: 24),
                Text(title, style: Zt.headline, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(message, style: Zt.body, textAlign: TextAlign.center),
                const SizedBox(height: 36),
                TvButton(label: context.l10n.back, icon: Icons.arrow_back_rounded, primary: true, autofocus: true, onSelect: onBack),
              ]),
            ),
          ),
        ),
      );
}
