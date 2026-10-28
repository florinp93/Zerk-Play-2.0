import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/media_row.dart';
import '../widgets/net_image.dart';
import '../widgets/rows_scroll_view.dart';
import 'details_parts.dart';
import 'routes.dart';

class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.person});

  final Person person;

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  late final Future<(List<EmbyItem>, List<EmbyItem>)> _load = () async {
    final c = AppServicesScope.read(context).catalog;
    final results = await Future.wait([
      c.query(personIds: widget.person.id, types: ['Movie'], sortBy: 'PremiereDate,SortName', descending: true, limit: 100),
      c.query(personIds: widget.person.id, types: ['Series'], sortBy: 'PremiereDate,SortName', descending: true, limit: 100),
    ]);
    return (results[0].items, results[1].items);
  }();

  @override
  Widget build(BuildContext context) {
    final c = AppServicesScope.of(context).catalog;
    final p = widget.person;
    return PageScrollView(
      padding: const EdgeInsets.only(top: 90, bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: pageLeft, bottom: 50),
          child: Row(children: [
            Container(
              width: 180,
              height: 180,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Zc.surfaceHigh),
              child: NetImage(
                url: c.personPhoto(p, width: 360),
                width: 180,
                fallback: const Icon(Icons.person_rounded, size: 90, color: Zc.textFaint),
              ),
            ),
            const SizedBox(width: 40),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: Zt.display),
              const SizedBox(height: 8),
              Text(context.l10n.inYourLibrary, style: Zt.meta),
            ]),
          ]),
        ),
        FutureBuilder(
          future: _load,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SkeletonRow(cardWidth: Zs.posterWidth, cardHeight: Zs.posterWidth * 1.5);
            }
            final (movies, shows) = snap.data!;
            if (movies.isEmpty && shows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(left: pageLeft),
                child: Text(context.l10n.nothingElseWith(p.name), style: Zt.body),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (title, items) in [(context.l10n.movies, movies), (context.l10n.shows, shows)])
                if (items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Zs.rowGap),
                    child: MediaRow(
                      left: pageLeft,
                      title: title,
                      height: Zs.posterWidth * 1.5 + 90,
                      itemCount: items.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: PosterCard(item: items[i], autofocus: i == 0 && items == (movies.isNotEmpty ? movies : shows),
                            onSelect: () => openItem(context, items[i])),
                      ),
                    ),
                  ),
            ]);
          },
        ),
      ],
    );
  }
}
