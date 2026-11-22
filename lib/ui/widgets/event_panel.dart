import 'package:flutter/material.dart';

import '../../data/season_events.dart';
import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'media_row.dart';
import 'mixed_cards.dart';

String? countdownLabel(L10n l10n, EventSpotlight? s, DateTime now) {
  final days = s?.daysLeft(now);
  if (days == null) return null;
  if (days < 0) return l10n.countdownOut;
  if (days == 0) return l10n.countdownToday;
  return l10n.countdownDays(days);
}

Color eventAccent(SeasonEvent e) => Color(e.accent ?? Zc.accent.toARGB32());

class EventStatus extends StatelessWidget {
  const EventStatus({super.key, required this.content, this.barWidth = 320});

  final EventContent content;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accent = eventAccent(content.event);
    final countdown = countdownLabel(l10n, content.event.spotlight, DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (countdown != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.schedule_rounded, color: accent, size: 30),
          const SizedBox(width: 10),
          Text(countdown, style: Zt.title.copyWith(color: Colors.white)),
        ]),
      if (content.total > 0) ...[
        const SizedBox(height: 14),
        Text(l10n.eventProgress(content.watched, content.total), style: Zt.meta),
        const SizedBox(height: 10),
        SizedBox(
          width: barWidth,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: content.progress,
              minHeight: 8,
              color: accent,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
            ),
          ),
        ),
      ],
    ]);
  }
}

class EventPanel extends StatelessWidget {
  const EventPanel({
    super.key,
    required this.content,
    required this.onOpen,
    required this.onOpenItem,
    this.onFocusEvent,
    this.onFocusItem,
    this.autofocus = false,
  });

  final EventContent content;
  final VoidCallback onOpen;
  final void Function(Object item) onOpenItem;
  final VoidCallback? onFocusEvent;
  final void Function(Object item)? onFocusItem;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accent = eventAccent(content.event);
    final next = content.next;
    final upNext = content.upNext();
    final cardH = cardAreaHeight(CardStyle.poster);
    return RevealBox(
      child: Padding(
        padding: const EdgeInsets.only(left: contentLeft - 24, right: 48),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Zs.radius * 2),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color.lerp(Zc.background, accent, 0.30)!.withValues(alpha: 0.92),
                Color.lerp(Zc.background, accent, 0.10)!.withValues(alpha: 0.82),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 0, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 420,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (f) => f ? onFocusEvent?.call() : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Pill(content.event.name.toUpperCase(), color: accent, textColor: Colors.white),
                    const SizedBox(height: 18),
                    EventStatus(content: content, barWidth: 360),
                    const SizedBox(height: 24),
                    FocusZone(
                      debugLabel: 'event-actions',
                      child: SizedBox(
                        width: 360,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          TvButton(
                            label: l10n.openEvent,
                            icon: Icons.auto_awesome_rounded,
                            primary: true,
                            accent: accent,
                            autofocus: autofocus,
                            onSelect: onOpen,
                          ),
                          if (next != null) ...[
                            const SizedBox(height: 14),
                            TvButton(label: l10n.watchNext, icon: Icons.play_arrow_rounded, onSelect: () => onOpenItem(next)),
                          ],
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: upNext.isEmpty
                    ? const SizedBox.shrink()
                    : MediaRow(
                        left: 0,
                        title: l10n.upNext,
                        height: cardH,
                        itemCount: upNext.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: mixedCard(
                            context,
                            upNext[i],
                            style: CardStyle.poster,
                            onFocus: () => onFocusItem?.call(upNext[i]),
                          ),
                        ),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
