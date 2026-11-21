import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/media_row.dart';
import '../widgets/rows_scroll_view.dart';
import 'routes.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

typedef _Favorites = ({List<EmbyItem> movies, List<EmbyItem> shows, List<EmbyItem> episodes});

class _FavoritesPageState extends State<FavoritesPage> {
  late final AppServices _services = AppServicesScope.read(context);
  _Favorites? _items;

  @override
  void initState() {
    super.initState();
    _services.libraryChanged.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _services.libraryChanged.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final c = _services.catalog;
    Future<List<EmbyItem>> of(String type) =>
        c.query(types: [type], filters: 'IsFavorite', limit: 300).then((p) => p.items);
    try {
      final results = await Future.wait([of('Movie'), of('Series'), of('Episode')]);
      if (mounted) setState(() => _items = (movies: results[0], shows: results[1], episodes: results[2]));
    } catch (e) {
      debugPrint('[favorites] $e');
      if (mounted) setState(() => _items ??= (movies: const [], shows: const [], episodes: const []));
    }
  }

  static Widget _count(int n) => Text('$n', style: Zt.meta.copyWith(color: Zc.textFaint));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = _items;
    final empty = items != null && items.movies.isEmpty && items.shows.isEmpty && items.episodes.isEmpty;
    final firstRow = items == null
        ? null
        : [items.movies, items.shows, items.episodes].where((l) => l.isNotEmpty).firstOrNull;
    Widget posters(String title, List<EmbyItem> list) => Padding(
          padding: const EdgeInsets.only(bottom: Zs.rowGap),
          child: MediaRow(
            title: title,
            trailingTitle: _count(list.length),
            height: Zs.posterWidth * 1.5 + 90,
            itemCount: list.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: PosterCard(
                item: list[i],
                autofocus: i == 0 && identical(list, firstRow),
                onSelect: () => openItem(context, list[i]),
              ),
            ),
          ),
        );
    return PageScrollView(
      padding: const EdgeInsets.only(top: 70, bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: contentLeft, bottom: 26),
          child: Text(l10n.favorites, style: Zt.headline),
        ),
        if (items == null)
          const SkeletonRow(cardWidth: Zs.posterWidth, cardHeight: Zs.posterWidth * 1.5)
        else if (empty)
          Padding(
            padding: const EdgeInsets.only(left: contentLeft, right: 120),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Text(l10n.favoritesEmpty, style: Zt.body),
            ),
          )
        else ...[
          if (items.movies.isNotEmpty) posters(l10n.movies, items.movies),
          if (items.shows.isNotEmpty) posters(l10n.shows, items.shows),
          if (items.episodes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Zs.rowGap),
              child: MediaRow(
                title: l10n.episodes,
                trailingTitle: _count(items.episodes.length),
                height: Zs.landscapeWidth * 9 / 16 + 110,
                itemCount: items.episodes.length,
                itemBuilder: (context, i) {
                  final e = items.episodes[i];
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: Zs.landscapeWidth,
                      child: LandscapeCard(
                        item: e,
                        autofocus: i == 0 && identical(items.episodes, firstRow),
                        title: e.seriesName ?? e.name,
                        subtitle: [e.episodeCode, e.name].whereType<String>().join('  '),
                        onSelect: () => openItem(context, e),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}
