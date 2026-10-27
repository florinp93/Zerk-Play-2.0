import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/side_panel.dart';
import 'routes.dart';

enum LibraryKind { movies, shows }

enum _Sort {
  name('SortName', false),
  added('DateCreated,SortName', true),
  released('PremiereDate,SortName', true),
  rating('CommunityRating,SortName', true),
  played('DatePlayed,SortName', true),
  random('Random', false);

  const _Sort(this.field, this.descending);

  final String field;
  final bool descending;

  String label(L10n l10n) => switch (this) {
        name => l10n.sortAToZ,
        added => l10n.sortRecentlyAdded,
        released => l10n.sortReleaseDate,
        rating => l10n.sortRating,
        played => l10n.sortRecentlyWatched,
        random => l10n.sortRandom,
      };
}

enum _Watched { all, unwatched, watched, favorites }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.kind});

  final LibraryKind kind;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _pageSize = 120;

  _Sort _sort = _Sort.added;
  _Watched _watched = _Watched.all;
  String? _genre;
  List<String> _genres = const [];

  final _items = <EmbyItem>[];
  int _total = -1;
  bool _loading = false;
  int _generation = 0;
  final _grid = RevealController(margin: 120);

  String get _type => widget.kind == LibraryKind.movies ? 'Movie' : 'Series';

  @override
  void initState() {
    super.initState();
    _reload();
    AppServicesScope.read(context).catalog.genres(types: [_type]).then((g) {
      if (mounted) setState(() => _genres = g);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _items.clear();
      _total = -1;
      _generation++;
    });
    if (_grid.hasClients) _grid.jumpTo(0);
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || (_total >= 0 && _items.length >= _total)) return;
    _loading = true;
    final generation = _generation;
    try {
      final page = await AppServicesScope.read(context).catalog.query(
            types: [_type],
            sortBy: _sort.field,
            descending: _sort.descending,
            start: _items.length,
            limit: _pageSize,
            genres: _genre == null ? null : [_genre!],
            filters: switch (_watched) {
              _Watched.all => null,
              _Watched.unwatched => 'IsUnplayed',
              _Watched.watched => 'IsPlayed',
              _Watched.favorites => 'IsFavorite',
            },
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
      });
    } catch (e) {
      debugPrint('[library] $e');
    } finally {
      _loading = false;
    }
  }

  Future<void> _pick<T>(String title, Map<T, String> options, T current, ValueChanged<T> apply) async {
    final chosen = await showSidePanel<T>(context, title: title, options: [
      for (final e in options.entries) PanelOption(value: e.key, title: e.value, selected: e.key == current),
    ]);
    if (chosen != null && chosen != current) {
      apply(chosen);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.kind == LibraryKind.movies ? l10n.movies : l10n.shows;
    final columns = AppServicesScope.of(context).settings.posterSize.columns;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: contentLeft, top: 70, right: 120, bottom: 26),
        child: Row(children: [
          Text(title, style: Zt.headline),
          const SizedBox(width: 18),
          if (_total >= 0) Text('$_total', style: Zt.title.copyWith(color: Zc.textFaint)),
          const Spacer(),
          FocusZone(
            debugLabel: 'library-toolbar',
            child: Row(children: [
              TvButton(
                label: _sort.label(l10n),
                icon: Icons.sort_rounded,
                onSelect: () => _pick(l10n.sortBy, {for (final s in _Sort.values) s: s.label(l10n)}, _sort, (v) => _sort = v),
              ),
              const SizedBox(width: 14),
              TvButton(
                label: _genre ?? l10n.allGenres,
                icon: Icons.category_outlined,
                onSelect: () => _pick<String>(l10n.genre, {'': l10n.allGenres, for (final g in _genres) g: g}, _genre ?? '',
                    (v) => _genre = v.isEmpty ? null : v),
              ),
              const SizedBox(width: 14),
              TvButton(
                label: switch (_watched) {
                  _Watched.all => l10n.filterAll,
                  _Watched.unwatched => l10n.unwatched,
                  _Watched.watched => l10n.watched,
                  _Watched.favorites => l10n.favorites,
                },
                icon: Icons.filter_list_rounded,
                onSelect: () => _pick(l10n.filterShow, {
                  _Watched.all: l10n.filterEverything,
                  _Watched.unwatched: l10n.unwatched,
                  _Watched.watched: l10n.watched,
                  _Watched.favorites: l10n.favorites,
                }, _watched, (v) => _watched = v),
              ),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: _total == 0
            ? Padding(
                padding: const EdgeInsets.only(left: contentLeft, top: 40),
                child: Text(l10n.nothingWithFilters, style: Zt.body),
              )
            : LayoutBuilder(builder: (context, box) {
                final cardW = posterGridCardWidth(box.maxWidth, columns);
                return FocusZone(
                  debugLabel: 'library-grid',
                  child: GridView.builder(
                    key: ValueKey(_generation),
                    controller: _grid,
                    clipBehavior: Clip.none,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(900),
                    padding: const EdgeInsets.fromLTRB(contentLeft, 16, 120, 140),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 26,
                      crossAxisSpacing: Zs.cardGap,
                      childAspectRatio: cardW / (cardW * 1.5 + 70),
                    ),
                    itemCount: _total < 0 ? 14 : _items.length,
                    itemBuilder: (context, i) {
                      if (i >= _items.length) return SkeletonBox(width: cardW, height: cardW * 1.5);
                      if (i > _items.length - 40) _loadMore();
                      final item = _items[i];
                      return Align(
                        alignment: Alignment.topLeft,
                        child: LayoutBuilder(
                          builder: (context, box) => PosterCard(
                            item: item,
                            width: box.maxWidth,
                            autofocus: i == 0,
                            onSelect: () => openItem(context, item),
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
