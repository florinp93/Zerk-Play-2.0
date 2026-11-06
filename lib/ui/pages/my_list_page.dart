import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/recommendations.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import 'routes.dart';

class MyListPage extends StatefulWidget {
  const MyListPage({super.key});

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  final _grid = RevealController(margin: 120);
  MixedItems? _items;
  AppServices? _services;

  String _loadedKeys = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services == null) {
      _services = AppServicesScope.read(context);
      _services!.profiles.addListener(_maybeReload);
      _services!.libraryChanged.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _services?.profiles.removeListener(_maybeReload);
    _services?.libraryChanged.removeListener(_reload);
    _grid.dispose();
    super.dispose();
  }

  String get _keys => [for (final e in _services!.profiles.profile?.list ?? const []) e.key].join(',');

  void _maybeReload() {
    if (_keys != _loadedKeys) _reload();
  }

  Future<void> _reload() async {
    final s = _services!;
    _loadedKeys = _keys;
    try {
      final items = await s.myList();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      debugPrint('[my list] $e');
      if (mounted) setState(() => _items ??= const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = _items;
    final columns = AppServicesScope.of(context).settings.posterSize.columns;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: contentLeft, top: 70, right: 120, bottom: 26),
        child: Row(children: [
          Text(l10n.myList, style: Zt.headline),
          const SizedBox(width: 18),
          if (items != null && items.isNotEmpty) Text('${items.length}', style: Zt.title.copyWith(color: Zc.textFaint)),
        ]),
      ),
      Expanded(
        child: items != null && items.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(left: contentLeft, top: 40, right: 120),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900), child: Text(l10n.myListEmpty, style: Zt.body)),
              )
            : LayoutBuilder(builder: (context, box) {
                final cardW = posterGridCardWidth(box.maxWidth, columns);
                return FocusZone(
                  debugLabel: 'my-list-grid',
                  child: GridView.builder(
                    controller: _grid,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.fromLTRB(contentLeft, 16, 120, 140),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 26,
                      crossAxisSpacing: Zs.cardGap,
                      childAspectRatio: cardW / (cardW * 1.5 + 70),
                    ),
                    itemCount: items?.length ?? 7,
                    itemBuilder: (context, i) {
                      if (items == null) return SkeletonBox(width: cardW, height: cardW * 1.5);
                      final data = items[i];
                      return Align(
                        alignment: Alignment.topLeft,
                        child: LayoutBuilder(
                          builder: (context, box) => data is SeerrMedia
                              ? RequestPosterCard(
                                  media: data, width: box.maxWidth, onSelect: () => openRequest(context, data))
                              : PosterCard(
                                  item: data as EmbyItem,
                                  width: box.maxWidth,
                                  onSelect: () => openItem(context, data),
                                ),
                        ),
                      );
                    },
                  ),
                );
              }),
      ),
    ]);
  }
}
