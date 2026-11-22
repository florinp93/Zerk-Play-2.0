import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/season_events.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../core/navigation.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/common.dart';
import '../widgets/event_panel.dart';
import '../widgets/media_row.dart';
import '../widgets/mixed_cards.dart';
import '../widgets/rows_scroll_view.dart';
import 'details_parts.dart';
import 'routes.dart';

Route<void> eventRoute(SeasonEvent event) => tvRoute(EventPage(event: event), name: 'event:${event.id}');

class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.event});

  final SeasonEvent event;

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  late final AppServices _services = AppServicesScope.read(context);
  late Future<EventContent> _load = _services.eventLoader.content(widget.event);
  final _backdrop = ValueNotifier<Uri?>(null);

  @override
  void initState() {
    super.initState();
    _services.libraryChanged.addListener(_reload);
  }

  @override
  void dispose() {
    _services.libraryChanged.removeListener(_reload);
    _backdrop.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _load = _services.eventLoader.content(widget.event));
  }

  Uri? _backdropOf(Object item) => switch (item) {
        final EmbyItem i => _services.catalog.backdrop(i),
        final SeerrMedia m => m.backdrop(),
        _ => null,
      };

  void _open(Object item) => switch (item) {
        final EmbyItem i => openItem(context, i),
        final SeerrMedia m => openRequest(context, m),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<EventContent>(
      future: _load,
      builder: (context, snap) {
        final content = snap.data;
        if (content == null) {
          return snap.hasError
              ? Center(child: Text('${snap.error}', style: Zt.body))
              : const Center(child: CircularProgressIndicator(color: Zc.accent));
        }
        final accent = eventAccent(content.event);
        final next = content.next;
        final target = content.target;
        final text = content.event.spotlight?.text ?? '';
        return Stack(children: [
          Positioned.fill(
            child: ValueListenableBuilder(
              valueListenable: _backdrop,
              builder: (_, url, _) => Backdrop(url: url ?? content.backdrop, dim: 0.15),
            ),
          ),
          PageScrollView(
            padding: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.16, bottom: 120),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: pageLeft, right: 700),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Pill(content.event.name.toUpperCase(), color: accent, textColor: Colors.white),
                  const SizedBox(height: 14),
                  Text(content.title, style: Zt.display),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(text, style: Zt.body),
                  ],
                  const SizedBox(height: 22),
                  EventStatus(content: content),
                  const SizedBox(height: 30),
                  FocusZone(
                    debugLabel: 'event-page-actions',
                    revealsTop: true,
                    child: Wrap(spacing: 16, runSpacing: 16, children: [
                      if (next != null)
                        TvButton(
                          label: l10n.watchNextTitle(next.name),
                          icon: Icons.play_arrow_rounded,
                          primary: true,
                          accent: accent,
                          autofocus: true,
                          onSelect: () => openItem(context, next),
                        ),
                      if (target != null)
                        TvButton(
                          label: target is EmbyItem ? target.name : (target as SeerrMedia).title,
                          icon: target is EmbyItem ? Icons.movie_outlined : Icons.add_circle_outline_rounded,
                          autofocus: next == null,
                          onSelect: () => _open(target),
                        ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 50),
              for (final (row, items) in content.rows)
                if (items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Zs.rowGap),
                    child: MediaRow(
                      left: pageLeft,
                      title: row.title,
                      trailingTitle: Text('${items.length}', style: Zt.meta.copyWith(color: Zc.textFaint)),
                      height: cardAreaHeight(CardStyle.poster),
                      itemCount: items.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: mixedCard(
                          context,
                          items[i],
                          style: CardStyle.poster,
                          onFocus: () => _backdrop.value = _backdropOf(items[i]),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ]);
      },
    );
  }
}
