import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/catalog_api.dart' show CatalogApi, ServerLibrary;
import '../../data/collection_index.dart';
import '../../data/libraries.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../core/navigation.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/net_image.dart';
import '../widgets/side_panel.dart';
import 'details_parts.dart';
import 'music_pages.dart';
import 'routes.dart';

enum LibraryKind { movies, shows, folder }

bool opensAsFolder(EmbyItem item) => item.isFolder && !item.isSeries && !item.isSeason && !item.isCollection;

void openFolder(BuildContext context, String id, String title) => Navigator.of(context).push(
    tvRoute(LibraryPage(kind: LibraryKind.folder, parentId: id, title: title), name: 'folder:$id'));

void openLibrary(BuildContext context, ServerLibrary library) {
  if (Libraries.isMusic(library) || Libraries.isAudiobooks(library)) return openMusicLibrary(context, library);
  final kind = Libraries.isMovies(library)
      ? LibraryKind.movies
      : Libraries.isShows(library)
          ? LibraryKind.shows
          : LibraryKind.folder;
  Navigator.of(context).push(tvRoute(LibraryPage(kind: kind, parentId: library.id, title: library.name),
      name: 'library:${library.id}'));
}

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
  const LibraryPage({super.key, required this.kind, this.parentId, this.title});

  final LibraryKind kind;

  final String? parentId;
  final String? title;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _pageSize = 120;

  late _Sort _sort = widget.kind == LibraryKind.folder ? _Sort.name : _Sort.added;
  _Watched _watched = _Watched.all;
  String? _genre;
  List<String> _genres = const [];

  final _items = <EmbyItem>[];
  int _total = -1;
  int _offset = 0;
  int _serverTotal = -1;
  int _hiddenTotal = 0;
  bool _loading = false;
  int _generation = 0;
  int _resets = 0;
  int _firstLimit = _pageSize;
  final _grid = RevealController(margin: 120);

  late final AppServices _services = AppServicesScope.read(context);
  String? _picked;

  bool get _pickable =>
      widget.parentId == null && (widget.kind == LibraryKind.movies || widget.kind == LibraryKind.shows);

  String get _pickKey => widget.kind.name;

  String? get _parentId => widget.parentId ?? _picked;

  List<ServerLibrary> _choices(AppServices s) =>
      _pickable ? Libraries.ofKind(s.knownLibraries, s.hiddenLibraries, shows: widget.kind == LibraryKind.shows) : const [];

  List<String>? get _types => switch (widget.kind) {
        LibraryKind.movies => const ['Movie'],
        LibraryKind.shows => const ['Series'],
        LibraryKind.folder => null,
      };

  String? get _filters => switch (_watched) {
        _Watched.all => null,
        _Watched.unwatched => 'IsUnplayed',
        _Watched.watched => 'IsPlayed',
        _Watched.favorites => 'IsFavorite',
      };

  @override
  void initState() {
    super.initState();
    if (_pickable && _services.isSignedIn) _picked = _services.settings.libraryPickOf(_services.janus.session.userId, _pickKey);
    _reload();
    _loadGenres();
    _services.libraryChanged.addListener(_onLibraryChanged);
    if (_pickable && _services.isSignedIn) _services.libraries().then((_) => _checkPick());
  }

  void _loadGenres() {
    if (widget.kind == LibraryKind.folder) return;
    _services.catalog.genres(parentId: _parentId, types: _types).then((g) {
      if (mounted) setState(() => _genres = g);
    }).catchError((_) {});
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    if (_pickable && _services.isSignedIn) _services.libraries().then((_) => _checkPick());
    _reload(keepPosition: true);
  }

  void _checkPick() {
    if (!mounted || _picked == null) return;
    if (Libraries.pickOrNull(_picked, _choices(_services)) != null) return;
    setState(() => _picked = null);
    _reload();
    _loadGenres();
  }

  Future<void> _pickLibrary() async {
    final l10n = context.l10n;
    final choices = _choices(_services);
    final chosen = await showSidePanel<String>(context, title: l10n.navLibrary, options: [
      PanelOption(value: '', title: l10n.allLibraries, selected: _picked == null),
      for (final l in choices) PanelOption(value: l.id, title: l.name, selected: l.id == _picked),
    ]);
    if (chosen == null || !mounted) return;
    final next = chosen.isEmpty ? null : chosen;
    if (next == _picked) return;
    setState(() {
      _picked = next;
      _genre = null;
      _genres = const [];
    });
    _reload();
    _loadGenres();
    if (_services.isSignedIn) {
      await _services.updateSettings(_services.settings.withLibraryPick(_services.janus.session.userId, _pickKey, next));
    }
  }

  @override
  void dispose() {
    _services.libraryChanged.removeListener(_onLibraryChanged);
    _grid.dispose();
    super.dispose();
  }

  void _reload({bool keepPosition = false}) {
    _firstLimit = keepPosition ? math.max(_items.length, _pageSize) : _pageSize;
    setState(() {
      if (!keepPosition) {
        _items.clear();
        _total = -1;
        _resets++;
      }
      _offset = 0;
      _serverTotal = -1;
      _hiddenTotal = 0;
      _generation++;
    });
    if (!keepPosition && _grid.hasClients) _grid.jumpTo(0);
    _loading = false;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || (_serverTotal >= 0 && _offset >= _serverTotal)) return;
    _loading = true;
    final generation = _generation;
    final settings = _services.settings;
    if (_grouped(settings)) return _loadGrouped(generation);
    try {
      final catalog = _services.catalog;
      final genres = _genre == null ? null : [_genre!];
      final first = _offset == 0;
      final (page, hidden) = await (
        catalog.query(
          parentId: _parentId,
          recursive: widget.kind != LibraryKind.folder,
          types: _types,
          sortBy: _sort.field,
          descending: _sort.descending,
          start: _offset,
          limit: first ? _firstLimit : _pageSize,
          genres: genres,
          filters: _filters,
        ),
        first && _parentId == null ? catalog.hiddenTotal(types: _types, filters: _filters, genres: genres) : Future.value(_hiddenTotal),
      ).wait;
      if (!mounted || generation != _generation) return;
      setState(() {
        if (first) _items.clear();
        _items.addAll(widget.kind == LibraryKind.folder ? page.items.where(_browsable) : page.items);
        _offset += page.fetched;
        _serverTotal = page.fetched == 0 ? _offset : page.total;
        _hiddenTotal = hidden;
        _total = _offset >= _serverTotal ? _items.length : (_serverTotal - hidden).clamp(_items.length, _serverTotal);
      });
      if (page.items.length < 40 && _offset < _serverTotal) Future.microtask(_loadMore);
    } catch (e) {
      debugPrint('[library] $e');
    } finally {
      if (generation == _generation) _loading = false;
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

  Future<void> _loadGrouped(int generation) async {
    try {
      final page = await AppServicesScope.read(context).catalog.query(
            parentId: _parentId,
            types: _types,
            sortBy: 'SortName',
            limit: 5000,
            collapseBoxSets: true,
            fields: '${CatalogApi.cardFields},DateCreated',
          );
      if (!mounted || generation != _generation) return;
      final items = await _withTmdbCollections(page.items);
      if (!mounted || generation != _generation) return;
      int newest(DateTime? a, DateTime? b) => (b ?? DateTime(1900)).compareTo(a ?? DateTime(1900));
      switch (_sort) {
        case _Sort.name:
          break;
        case _Sort.added:
          items.sort((a, b) => newest(a.dateCreated, b.dateCreated));
        case _Sort.released:
          items.sort((a, b) => newest(a.premiereDate, b.premiereDate));
        case _Sort.rating:
          items.sort((a, b) => (b.communityRating ?? 0).compareTo(a.communityRating ?? 0));
        case _Sort.played:
          items.sort((a, b) => newest(a.lastPlayedDate, b.lastPlayedDate));
        case _Sort.random:
          items.shuffle();
      }
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _total = items.length;
        _offset = _serverTotal = items.length;
      });
    } catch (e) {
      debugPrint('[library] grouped: $e');
    } finally {
      _loading = false;
    }
  }

  Future<List<EmbyItem>> _withTmdbCollections(List<EmbyItem> grouped) async {
    final index = AppServicesScope.read(context).catalog.collections;
    if (index == null) return [...grouped];
    final List<LibraryCollection> tmdb;
    try {
      tmdb = await index.all();
    } catch (e) {
      debugPrint('[library] tmdb collections: $e');
      return [...grouped];
    }
    final loose = {for (final i in grouped) if (i.isMovie) i.id: i};
    final serverSets = {for (final i in grouped) if (i.isCollection) ?i.tmdbId};
    final hidden = <String>{};
    final added = <EmbyItem>[];
    for (final c in tmdb) {
      final members = [for (final id in c.ownedIds) ?loose[id]];
      if (members.isEmpty) continue;
      if (serverSets.contains(c.info.id)) {
        hidden.addAll(members.map((m) => m.id));
        continue;
      }
      if (members.length < 2) continue;
      hidden.addAll(members.map((m) => m.id));
      DateTime? latest(Iterable<DateTime?> dates) =>
          dates.nonNulls.fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      added.add(CollectionIndex.itemFor(
        c.info,
        owned: members.length,
        added: latest(members.map((m) => m.dateCreated)),
        released: latest(members.map((m) => m.premiereDate)),
      ));
    }
    debugPrint('[library] grouped: ${grouped.length} from the server, ${added.length} TMDB collections '
        'replace ${hidden.length} films');
    return [for (final i in grouped) if (!hidden.contains(i.id)) i, ...added]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  bool _grouped(AppSettings settings) =>
      widget.kind == LibraryKind.movies && settings.groupCollections && _genre == null && _watched == _Watched.all;

  Future<void> _toggleGrouping(AppServices services) async {
    await services.updateSettings(services.settings.copyWith(groupCollections: !services.settings.groupCollections));
    if (mounted) _reload();
  }

  Future<void> _pickView(AppServices services) async {
    final l10n = context.l10n;
    final current = services.settings.libraryView;
    final chosen = await showSidePanel<LibraryView>(context, title: l10n.libraryViewSetting, options: [
      for (final v in LibraryView.values) PanelOption(value: v, title: _viewLabel(l10n, v), icon: _viewIcon(v), selected: v == current),
    ]);
    if (chosen != null && chosen != current) await services.updateSettings(services.settings.copyWith(libraryView: chosen));
  }

  static const _unplayable = {'Audio', 'MusicAlbum', 'MusicArtist', 'Photo', 'PhotoAlbum', 'Book', 'AudioBook', 'Playlist'};

  static bool _browsable(EmbyItem item) => !_unplayable.contains(item.type);

  static String _short(String text) => text.length <= 22 ? text : '${text.substring(0, 21).trimRight()}…';

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
    void open() => opensAsFolder(item) ? openFolder(context, item.id, item.name) : openItem(context, item);
    return switch (view) {
      LibraryView.posters => Align(
          key: ValueKey(item.id),
          alignment: Alignment.topLeft,
          child: LayoutBuilder(
            builder: (context, box) => PosterCard(item: item, width: box.maxWidth, autofocus: i == 0, onSelect: open),
          ),
        ),
      LibraryView.cards => Align(
          key: ValueKey(item.id),
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
      LibraryView.list => _ListRow(key: ValueKey(item.id), item: item, autofocus: i == 0, onSelect: open),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final services = AppServicesScope.of(context);
    final choices = _choices(services);
    final pickedName = [for (final l in choices) if (l.id == _picked) l.name].firstOrNull;
    final title = widget.title ??
        switch (widget.kind) {
          LibraryKind.movies => l10n.movies,
          LibraryKind.shows => l10n.shows,
          LibraryKind.folder => l10n.libraries,
        };
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
          Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.headline)),
          const SizedBox(width: 18),
          if (_total >= 0) Text('$_total', style: Zt.title.copyWith(color: Zc.textFaint)),
          const Spacer(),
          FocusZone(
            debugLabel: 'library-toolbar',
            child: Row(children: [
              if (choices.length > 1 || _picked != null) ...[
                TvButton(
                  label: _short(pickedName ?? l10n.allLibraries),
                  icon: Icons.video_library_outlined,
                  primary: _picked != null,
                  onSelect: _pickLibrary,
                ),
                const SizedBox(width: 14),
              ],
              TvButton(
                label: _sort.label(l10n),
                icon: Icons.sort_rounded,
                onSelect: () => _pick(l10n.sortBy, {for (final s in _Sort.values) s: s.label(l10n)}, _sort, (v) => _sort = v),
              ),
              if (widget.kind != LibraryKind.folder) ...[
                const SizedBox(width: 14),
                TvButton(
                  label: _genre ?? l10n.allGenres,
                  icon: Icons.category_outlined,
                  onSelect: () => _pick<String>(l10n.genre, {'': l10n.allGenres, for (final g in _genres) g: g}, _genre ?? '',
                      (v) => _genre = v.isEmpty ? null : v),
                ),
              ],
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
              if (widget.kind == LibraryKind.movies) ...[
                const SizedBox(width: 14),
                TvButton(
                  label: l10n.groupCollections,
                  icon: services.settings.groupCollections ? Icons.collections_bookmark_rounded : Icons.collections_bookmark_outlined,
                  collapsed: true,
                  primary: services.settings.groupCollections,
                  onSelect: () => _toggleGrouping(services),
                ),
              ],
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
                    key: ValueKey('$_resets:${view.name}'),
                    controller: _grid,
                    clipBehavior: Clip.none,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(900),
                    padding: const EdgeInsets.fromLTRB(contentLeft, 16, 120, 140),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 26,
                      crossAxisSpacing: Zs.cardGap,
                      childAspectRatio: switch (view) {
                        LibraryView.posters => cardW / (cardW * 1.5 + captionSpace(context, 70)),
                        LibraryView.cards => cardW / (cardW * 9 / 16 + captionSpace(context, 76)),
                        LibraryView.list => cardW / _ListRow.height,
                      },
                    ),
                    itemCount: _total < 0 ? 14 : _items.length,
                    findChildIndexCallback: (key) {
                      final index = key is ValueKey ? _items.indexWhere((e) => e.id == key.value) : -1;
                      return index < 0 ? null : index;
                    },
                    itemBuilder: (context, i) => _tile(context, view, i, cardW),
                  ),
                );
              }),
      ),
    ]);
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({super.key, required this.item, required this.onSelect, this.autofocus = false});

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
                Flexible(
                  child: Text(item.overview!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.body.copyWith(fontSize: 20)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
