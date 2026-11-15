import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/app_services.dart';
import '../../data/catalog_api.dart';
import '../../data/libraries.dart';
import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/net_image.dart';
import '../widgets/setting_rows.dart';
import 'library_page.dart';

IconData libraryIcon(ServerLibrary l) => switch (l.collectionType?.toLowerCase()) {
      'movies' => Icons.movie_rounded,
      'tvshows' => Icons.tv_rounded,
      'boxsets' => Icons.collections_bookmark_rounded,
      'homevideos' => Icons.videocam_rounded,
      'musicvideos' => Icons.music_video_rounded,
      'music' => Icons.library_music_rounded,
      'books' || 'audiobooks' => Icons.menu_book_rounded,
      'photos' => Icons.photo_library_rounded,
      'livetv' => Icons.live_tv_rounded,
      'playlists' => Icons.playlist_play_rounded,
      _ => Icons.folder_rounded,
    };

class LibrariesPage extends StatefulWidget {
  const LibrariesPage({super.key});

  @override
  State<LibrariesPage> createState() => _LibrariesPageState();
}

class _LibrariesPageState extends State<LibrariesPage> {
  final _grid = RevealController(margin: 120);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AppServicesScope.read(context).libraries().whenComplete(() => mounted ? setState(() => _loaded = true) : null);
  }

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final services = AppServicesScope.of(context);
    final libraries = services.visibleLibraries;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: contentLeft, top: 70, right: 120, bottom: 30),
        child: Text(l10n.libraries, style: Zt.headline),
      ),
      Expanded(
        child: libraries.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(left: contentLeft),
                child: _loaded ? Text(l10n.librariesNone, style: Zt.body) : const SizedBox.shrink(),
              )
            : FocusZone(
                debugLabel: 'libraries-grid',
                child: GridView.builder(
                  controller: _grid,
                  clipBehavior: Clip.none,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(800),
                  padding: const EdgeInsets.fromLTRB(contentLeft, 10, 120, 140),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 30,
                    crossAxisSpacing: 30,
                    childAspectRatio: 16 / 11.5,
                  ),
                  itemCount: libraries.length,
                  itemBuilder: (context, i) => _LibraryTile(
                    library: libraries[i],
                    autofocus: i == 0,
                    onSelect: () => openLibrary(context, libraries[i]),
                  ),
                ),
              ),
      ),
    ]);
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.library, required this.onSelect, this.autofocus = false});

  final ServerLibrary library;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final catalog = AppServicesScope.read(context).catalog;
    final tag = library.imageTag;
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (context, focused) => LayoutBuilder(
        builder: (context, box) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FocusFrame(
            focused: focused,
            scale: 1.05,
            child: SizedBox(
              width: box.maxWidth,
              height: box.maxWidth * 9 / 16,
              child: NetImage(
                url: tag == null ? null : catalog.image(library.id, ImageKind.primary, tag: tag, width: 640),
                width: box.maxWidth,
                fallback: TitleArt(title: library.name, icon: libraryIcon(library)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Icon(libraryIcon(library), size: 24, color: focused ? Zc.text : Zc.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(library.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.label.copyWith(color: focused ? Zc.text : Zc.textMuted)),
            ),
          ]),
        ]),
      ),
    );
  }
}

class LibrariesSettingsPage extends StatefulWidget {
  const LibrariesSettingsPage({super.key});

  @override
  State<LibrariesSettingsPage> createState() => _LibrariesSettingsPageState();
}

class _LibrariesSettingsPageState extends State<LibrariesSettingsPage> {
  late final AppServices _services = AppServicesScope.read(context);
  late final Future<List<ServerLibrary>> _all = _services.libraries();

  void _toggle(String id, bool shown) {
    final userId = _services.janus.session.userId;
    final hidden = _services.settings.hiddenLibrariesOf(userId);
    shown ? hidden.remove(id) : hidden.add(id);
    _services.updateSettings(_services.settings.withHiddenLibraries(userId, hidden));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final services = AppServicesScope.of(context);
    final hidden = services.hiddenLibraries;
    return Padding(
      padding: const EdgeInsets.only(left: contentLeft, top: 90, right: 120),
      child: SizedBox(
        width: 1100,
        child: FutureBuilder<List<ServerLibrary>>(
          future: _all,
          builder: (context, snap) {
            final all = [for (final l in snap.data ?? const <ServerLibrary>[]) if (Libraries.browsable(l)) l];
            return FocusZone(
              debugLabel: 'settings-libraries',
              autofocus: true,
              child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
                Text(l10n.librariesSetting, style: Zt.headline),
                const SizedBox(height: 12),
                Text(l10n.librariesIntro, style: Zt.body),
                const SizedBox(height: 30),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(padding: EdgeInsets.all(24), child: SkeletonBox(width: 600, height: 60, radius: 12))
                else if (all.isEmpty)
                  Text(l10n.librariesNone, style: Zt.body)
                else
                  for (final l in all)
                    SettingToggleRow(
                      title: l.name,
                      value: !hidden.contains(l.id),
                      onChanged: (v) => _toggle(l.id, v),
                    ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
