import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/catalog_api.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../core/navigation.dart';
import '../core/playback_launcher.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/net_image.dart';
import '../widgets/rows_scroll_view.dart';
import '../widgets/side_panel.dart';
import 'details_parts.dart';
import 'hero.dart';

Route<void> albumRoute(String albumId) => tvRoute(AlbumPage(albumId: albumId), name: 'album:$albumId');

void openMusicLibrary(BuildContext context, ServerLibrary library) => Navigator.of(context)
    .push(tvRoute(MusicLibraryPage(library: library), name: 'music:${library.id}'));

enum _AlbumSort {
  artist('AlbumArtist,SortName', false),
  name('SortName', false),
  added('DateCreated,SortName', true),
  year('ProductionYear,SortName', true);

  const _AlbumSort(this.field, this.descending);

  final String field;
  final bool descending;
}

class MusicLibraryPage extends StatefulWidget {
  const MusicLibraryPage({super.key, required this.library});

  final ServerLibrary library;

  @override
  State<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage> {
  final _grid = RevealController(margin: 120);
  _AlbumSort _sort = _AlbumSort.artist;
  List<EmbyItem>? _albums;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final page = await AppServicesScope.read(context).catalog.query(
          parentId: widget.library.id,
          types: const ['MusicAlbum'],
          sortBy: _sort.field,
          descending: _sort.descending,
          limit: 5000,
          localize: false,
        );
    if (mounted) setState(() => _albums = page.items);
  }

  Future<void> _pickSort() async {
    final l10n = context.l10n;
    final chosen = await showSidePanel<_AlbumSort>(context, title: l10n.sortBy, options: [
      for (final s in _AlbumSort.values) PanelOption(value: s, title: _sortLabel(l10n, s), selected: s == _sort),
    ]);
    if (chosen == null || chosen == _sort || !mounted) return;
    setState(() {
      _sort = chosen;
      _albums = null;
    });
    await _load();
  }

  static String _sortLabel(L10n l10n, _AlbumSort s) => switch (s) {
        _AlbumSort.artist => l10n.sortArtist,
        _AlbumSort.name => l10n.sortAToZ,
        _AlbumSort.added => l10n.sortRecentlyAdded,
        _AlbumSort.year => l10n.sortReleaseDate,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final albums = _albums;
    final columns = AppServicesScope.of(context).settings.posterSize.columns + 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: pageLeft, top: 70, right: 120, bottom: 26),
        child: Row(children: [
          Text(widget.library.name, style: Zt.headline),
          const SizedBox(width: 18),
          if (albums != null) Text('${albums.length}', style: Zt.title.copyWith(color: Zc.textFaint)),
          const Spacer(),
          FocusZone(
            debugLabel: 'music-toolbar',
            child: TvButton(label: _sortLabel(l10n, _sort), icon: Icons.sort_rounded, onSelect: _pickSort),
          ),
        ]),
      ),
      Expanded(
        child: albums != null && albums.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(left: pageLeft),
                child: Text(l10n.noAlbums, style: Zt.body),
              )
            : LayoutBuilder(builder: (context, box) {
                final cardW = posterGridCardWidth(box.maxWidth - pageLeft + contentLeft, columns);
                return FocusZone(
                  debugLabel: 'albums-grid',
                  child: GridView.builder(
                    controller: _grid,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.fromLTRB(pageLeft, 16, 120, 140),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 26,
                      crossAxisSpacing: Zs.cardGap,
                      childAspectRatio: cardW / (cardW + captionSpace(context, 70)),
                    ),
                    itemCount: albums?.length ?? columns * 2,
                    itemBuilder: (context, i) {
                      if (albums == null) return SkeletonBox(width: cardW, height: cardW);
                      return Align(
                        alignment: Alignment.topLeft,
                        child: LayoutBuilder(
                          builder: (context, box) => AlbumCard(
                            item: albums[i],
                            width: box.maxWidth,
                            autofocus: i == 0,
                            onSelect: () => Navigator.of(context).push(albumRoute(albums[i].id)),
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

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.albumId});

  final String albumId;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late final Future<(EmbyItem, List<EmbyItem>)> _load = () async {
    final c = AppServicesScope.read(context).catalog;
    final results = await Future.wait([
      c.item(widget.albumId),
      c
          .query(
            parentId: widget.albumId,
            types: const ['Audio'],
            sortBy: 'ParentIndexNumber,IndexNumber,SortName',
            limit: 500,
            localize: false,
          )
          .then((p) => p.items),
    ]);
    return (results[0] as EmbyItem, results[1] as List<EmbyItem>);
  }();

  void _play(List<EmbyItem> tracks, int from) {
    if (tracks.isEmpty) return;
    playItem(context, tracks[from], start: Duration.zero, queue: tracks);
  }

  void _shuffle(List<EmbyItem> tracks) {
    final shuffled = [...tracks]..shuffle(math.Random());
    _play(shuffled, 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final catalog = AppServicesScope.of(context).catalog;
    return FutureBuilder(
      future: _load,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${snap.error}', style: Zt.body));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Zc.accent));
        final (album, tracks) = snap.data!;
        final total = tracks.fold(Duration.zero, (sum, t) => sum + (t.runtime ?? Duration.zero));
        final discs = tracks.map((t) => t.parentIndexNumber).toSet().length > 1;
        return PageScrollView(
          padding: const EdgeInsets.only(top: 90, bottom: 120),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: pageLeft, right: 120),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Zs.radius),
                  child: SizedBox.square(
                    dimension: 340,
                    child: NetImage(
                      url: catalog.albumCover(album, width: 680),
                      width: 340,
                      fallback: TitleArt(title: album.name, icon: Icons.album_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(album.name, style: Zt.display, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (album.albumArtist != null) ...[
                      const SizedBox(height: 10),
                      Text(album.albumArtist!, style: Zt.title.copyWith(color: Zc.textMuted)),
                    ],
                    const SizedBox(height: 14),
                    MetaLine([
                      album.productionYear?.toString(),
                      l10n.trackCount(tracks.length),
                      formatRuntime(l10n, total),
                    ].whereType<String>().toList()),
                    const SizedBox(height: 30),
                    FocusZone(
                      debugLabel: 'album-actions',
                      revealsTop: true,
                      child: Wrap(spacing: 18, children: [
                        TvButton(
                          label: l10n.play,
                          icon: Icons.play_arrow_rounded,
                          primary: true,
                          autofocus: true,
                          onSelect: () => _play(tracks, 0),
                        ),
                        TvButton(label: l10n.shuffle, icon: Icons.shuffle_rounded, onSelect: () => _shuffle(tracks)),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 50),
            FocusZone(
              debugLabel: 'album-tracks',
              child: Padding(
                padding: const EdgeInsets.only(left: pageLeft - 24, right: 96),
                child: Column(children: [
                  for (final (i, t) in tracks.indexed)
                    _TrackRow(
                      track: t,
                      number: discs && t.parentIndexNumber != null
                          ? '${t.parentIndexNumber}.${t.indexNumber ?? i + 1}'
                          : '${t.indexNumber ?? i + 1}',
                      showArtist: t.albumArtist != null && t.albumArtist != album.albumArtist,
                      onSelect: () => _play(tracks, i),
                    ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.number, required this.showArtist, required this.onSelect});

  final EmbyItem track;
  final String number;
  final bool showArtist;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onSelect,
      builder: (context, focused) {
        final fg = focused ? Zc.background : Zc.text;
        return AnimatedContainer(
          duration: Zm.fast,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: focused ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(Zs.radius),
          ),
          child: Row(children: [
            SizedBox(
              width: 64,
              child: Text(number, style: Zt.body.copyWith(color: focused ? Zc.background : Zc.textFaint)),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: track.name, style: Zt.label.copyWith(color: fg, fontSize: 22)),
                  if (showArtist)
                    TextSpan(
                      text: '  ·  ${track.albumArtist}',
                      style: Zt.body.copyWith(color: focused ? Zc.background : Zc.textMuted),
                    ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(_duration(track.runtime) ?? '', style: Zt.body.copyWith(color: focused ? Zc.background : Zc.textMuted)),
            if (track.isFavorite) ...[
              const SizedBox(width: 16),
              Icon(Icons.favorite_rounded, size: 22, color: focused ? Zc.favoriteOnLight : Zc.favorite),
            ],
          ]),
        );
      },
    );
  }

  static String? _duration(Duration? d) {
    if (d == null) return null;
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
