import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import 'routes.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  late final Future<List<EmbyItem>> _load = AppServicesScope.read(context).catalog.allCollections();
  final _grid = RevealController(margin: 120);

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.of(context);
    final settings = services.settings;
    final covers = settings.collectionsView == CollectionsView.covers;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: contentLeft, top: 70, right: 120, bottom: 30),
        child: Row(children: [
          Text(context.l10n.collections, style: Zt.headline),
          const Spacer(),
          FocusZone(
            debugLabel: 'collections-toolbar',
            child: TvButton(
              label: covers ? context.l10n.viewWide : context.l10n.viewCovers,
              icon: covers ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
              onSelect: () => services.updateSettings(
                  settings.copyWith(collectionsView: covers ? CollectionsView.wide : CollectionsView.covers)),
            ),
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<EmbyItem>>(
          future: _load,
          builder: (context, snap) {
            if (!snap.hasData) {
              return snap.hasError
                  ? Padding(padding: const EdgeInsets.only(left: contentLeft), child: Text('${snap.error}', style: Zt.body))
                  : const _BuildProgress();
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(left: contentLeft),
                child: Text(
                    AppServicesScope.read(context).catalog.collections == null
                        ? context.l10n.noCollectionsTmdb
                        : context.l10n.noCollectionsFound,
                    style: Zt.body),
              );
            }
            if (covers) return _posterGrid(items, settings.posterSize.columns);
            return FocusZone(
              debugLabel: 'collections-grid',
              child: GridView.builder(
                key: const ValueKey('wide'),
                controller: _grid,
                clipBehavior: Clip.none,
                scrollCacheExtent: const ScrollCacheExtent.pixels(800),
                padding: const EdgeInsets.fromLTRB(contentLeft, 10, 120, 140),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 36,
                  crossAxisSpacing: 36,
                  childAspectRatio: 1 / 0.42,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => LayoutBuilder(
                  builder: (context, box) => CollectionCard(
                    item: items[i],
                    width: box.maxWidth,
                    autofocus: i == 0,
                    onSelect: () => openItem(context, items[i]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _posterGrid(List<EmbyItem> items, int columns) => LayoutBuilder(builder: (context, box) {
        final cardW = posterGridCardWidth(box.maxWidth, columns);
        return FocusZone(
          debugLabel: 'collections-grid',
          child: GridView.builder(
            key: const ValueKey('covers'),
            controller: _grid,
            clipBehavior: Clip.none,
            scrollCacheExtent: const ScrollCacheExtent.pixels(900),
            padding: const EdgeInsets.fromLTRB(contentLeft, 10, 120, 140),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 26,
              crossAxisSpacing: Zs.cardGap,
              childAspectRatio: cardW / (cardW * 1.5 + 70),
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => Align(
              alignment: Alignment.topLeft,
              child: LayoutBuilder(
                builder: (context, box) => PosterCard(
                  item: items[i],
                  width: box.maxWidth,
                  autofocus: i == 0,
                  onSelect: () => openItem(context, items[i]),
                ),
              ),
            ),
          ),
        );
      });
}

class _BuildProgress extends StatelessWidget {
  const _BuildProgress();

  @override
  Widget build(BuildContext context) {
    final index = AppServicesScope.read(context).catalog.collections;
    if (index == null) return const SizedBox.shrink();
    return ValueListenableBuilder<double?>(
      valueListenable: index.progress,
      builder: (context, p, _) => p == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(left: contentLeft),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.l10n.buildingCollections((p * 100).round()), style: Zt.body),
                const SizedBox(height: 16),
                SizedBox(
                  width: 420,
                  child: ClipRRect(borderRadius: BorderRadius.circular(3), child: ProgressStrip(p, height: 6)),
                ),
              ]),
            ),
    );
  }
}
