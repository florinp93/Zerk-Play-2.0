import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/net_image.dart';
import '../widgets/side_panel.dart';
import 'details_parts.dart';
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

  Future<void> _pickView(AppServices services) async {
    final l10n = context.l10n;
    final current = services.settings.libraryView;
    final chosen = await showSidePanel<LibraryView>(context, title: l10n.libraryViewSetting, options: [
      for (final v in LibraryView.values) PanelOption(value: v, title: _viewLabel(l10n, v), icon: _viewIcon(v), selected: v == current),
    ]);
    if (chosen != null && chosen != current) await services.updateSettings(services.settings.copyWith(libraryView: chosen));
  }

  static String _viewLabel(L10n l10n, LibraryView v) => switch (v) {
        LibraryView.posters => l10n.viewPosters,
        LibraryView.cards => l10n.viewCards,
        LibraryView.list => l10n.viewList,
      };

  static IconData _viewIcon(LibraryView v) => switch (v) {
        LibraryView.posters => Icons.grid_view_rounded,
        LibraryView.cards => Icons.view_module_rounded,
        LibraryView.list => Icons.view_list_rounded,
      };

  Widget _tile(BuildContext context, LibraryView view, int i, double cardW) {
    if (i >= _items.length) {
      return switch (view) {
        LibraryView.posters => SkeletonBox(width: cardW, height: cardW * 1.5),
        LibraryView.cards => SkeletonBox(width: cardW, height: cardW * 9 / 16),
        LibraryView.list => SkeletonBox(width: cardW, height: _ListRow.height - 24),
      };
    }
    if (i > _items.length - 40) _loadMore();
    final item = _items[i];
    void open() => openItem(context, item);
    return switch (view) {
      LibraryView.posters => Align(
          alignment: Alignment.topLeft,
          child: LayoutBuilder(
            builder: (context, box) => PosterCard(item: item, width: box.maxWidth, autofocus: i == 0, onSelect: open),
          ),
        ),
      LibraryView.cards => Align(
          alignment: Alignment.topLeft,
          child: LayoutBuilder(
            builder: (context, box) => LandscapeCard(
              item: item,
              width: box.maxWidth,
              autofocus: i == 0,
              preferEpisodeStill: false,
              subtitle: [?item.productionYear?.toString(), ?item.officialRating].join('  ·  '),
              onSelect: open,
            ),
          ),
        ),
      LibraryView.list => _ListRow(item: item, autofocus: i == 0, onSelect: open),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.kind == LibraryKind.movies ? l10n.movies : l10n.shows;
    final services = AppServicesScope.of(context);
    final view = services.settings.libraryView;
    final columns = switch (view) {
      LibraryView.posters => services.settings.posterSize.columns,
      LibraryView.cards => (services.settings.posterSize.columns / 2).ceil(),
      LibraryView.list => 1,
    };
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
              const SizedBox(width: 14),
              TvButton(
                label: _viewLabel(l10n, view),
                icon: _viewIcon(view),
                collapsed: true,
                onSelect: () => _pickView(services),
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
                final cardW = view == LibraryView.list ? box.maxWidth - contentLeft - 120 : posterGridCardWidth(box.maxWidth, columns);
                return FocusZone(
                  debugLabel: 'library-grid',
                  child: GridView.builder(
                    key: ValueKey('$_generation:${view.name}'),
                    controller: _grid,
                    clipBehavior: Clip.none,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(900),
                    padding: const EdgeInsets.fromLTRB(contentLeft, 16, 120, 140),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 26,
                      crossAxisSpacing: Zs.cardGap,
                      childAspectRatio: switch (view) {
                        LibraryView.posters => cardW / (cardW * 1.5 + 70),
                        LibraryView.cards => cardW / (cardW * 9 / 16 + 76),
                        LibraryView.list => cardW / _ListRow.height,
                      },
                    ),
                    itemCount: _total < 0 ? 14 : _items.length,
                    itemBuilder: (context, i) => _tile(context, view, i, cardW),
                  ),
                );
              }),
      ),
    ]);
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.item, required this.onSelect, this.autofocus = false});

  static const double height = 200;

  final EmbyItem item;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final catalog = AppServicesScope.read(context).catalog;
    final meta = standardMeta(context.l10n, item).whereType<String>().where((s) => s.isNotEmpty).join('  ·  ');
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (context, focused) => AnimatedContainer(
        duration: Zm.fast,
        height: height - 24,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: focused ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(Zs.radius),
          border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 3),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Zs.radius - 4),
            child: SizedBox(
              width: (height - 54) / 1.5,
              height: height - 54,
              child: NetImage(url: catalog.poster(item, width: 160), width: 160, fallback: TitleArt(title: item.name)),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.title.copyWith(fontSize: 26)),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.meta),
              ],
              if (item.overview != null) ...[
                const SizedBox(height: 10),
                Text(item.overview!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.body.copyWith(fontSize: 20)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
