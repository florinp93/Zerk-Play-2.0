import 'package:flutter/material.dart';

import '../../data/season_events.dart';
import '../../l10n/l10n.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'net_image.dart';

const double eventSpotlightWidth = 1000;
const double eventSpotlightHeight = 340;

String? countdownLabel(L10n l10n, EventSpotlight s, DateTime now) {
  final days = s.daysLeft(now);
  if (days == null) return null;
  if (days < 0) return l10n.countdownOut;
  if (days == 0) return l10n.countdownToday;
  return l10n.countdownDays(days);
}

class EventSpotlightCard extends StatelessWidget {
  const EventSpotlightCard({super.key, required this.data, this.onFocus, this.onSelect, this.autofocus = false});

  final SpotlightCardData data;
  final VoidCallback? onFocus;
  final VoidCallback? onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final s = data.spotlight;
    final accent = Color(data.event.accent ?? Zc.accent.toARGB32());
    final countdown = countdownLabel(context.l10n, s, DateTime.now());
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      onFocusChange: (f) => f ? onFocus?.call() : null,
      builder: (context, focused) => FocusFrame(
        focused: focused,
        scale: 1.03,
        glowColor: accent,
        child: SizedBox(
          width: eventSpotlightWidth,
          height: eventSpotlightHeight,
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: Color.lerp(Zc.background, accent, 0.35)!),
            if (data.backdrop != null)
              NetImage(url: data.backdrop, width: eventSpotlightWidth, fit: BoxFit.cover, alignment: Alignment.topRight),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0, 0.55, 1],
                  colors: [Zc.background.withValues(alpha: 0.92), Zc.background.withValues(alpha: 0.5), Colors.transparent],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 34, 40, 34),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Pill(data.event.name.toUpperCase(), color: accent, textColor: Colors.white),
                const Spacer(),
                SizedBox(
                  width: eventSpotlightWidth * 0.55,
                  child: Text(s.title, style: Zt.headline.copyWith(fontSize: 46, height: 1.05), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (s.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: eventSpotlightWidth * 0.55,
                    child: Text(s.text, style: Zt.body.copyWith(color: Zc.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ],
                if (countdown != null) ...[
                  const SizedBox(height: 16),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule_rounded, color: accent, size: 26),
                    const SizedBox(width: 8),
                    Text(countdown, style: Zt.title.copyWith(color: Colors.white)),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
