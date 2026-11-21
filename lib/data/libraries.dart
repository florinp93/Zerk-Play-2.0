import '../core/emby/models/emby_item.dart';
import 'catalog_api.dart';

abstract final class Libraries {
  static const unsupported = {'books', 'audiobooks', 'livetv', 'photos', 'playlists', 'games'};

  static bool isMovies(ServerLibrary l) => l.collectionType == 'movies';

  static bool isShows(ServerLibrary l) => l.collectionType == 'tvshows';

  static bool isCollections(ServerLibrary l) => l.collectionType == 'boxsets';

  static bool isMusic(ServerLibrary l) => l.collectionType == 'music';

  static bool browsable(ServerLibrary l) => !unsupported.contains(l.collectionType?.toLowerCase());

  static bool hasLatest(ServerLibrary l) => browsable(l) && !isCollections(l) && !isMusic(l);

  static bool isOther(ServerLibrary l) => browsable(l) && !isMovies(l) && !isShows(l);

  static List<ServerLibrary> visible(List<ServerLibrary> all, Set<String> hidden) => [
        for (final l in all)
          if (browsable(l) && !hidden.contains(l.id)) l,
      ];

  static List<ServerLibrary> ofKind(List<ServerLibrary> all, Set<String> hidden, {required bool shows}) => [
        for (final l in visible(all, hidden))
          if (shows ? isShows(l) : isMovies(l)) l,
      ];

  static String? pickOrNull(String? picked, List<ServerLibrary> choices) =>
      picked != null && choices.any((l) => l.id == picked) ? picked : null;
}

final class HiddenContent {
  const HiddenContent(this.ids);

  static const none = HiddenContent({});

  final Set<String> ids;

  bool get isEmpty => ids.isEmpty;

  bool hides(EmbyItem item) =>
      ids.contains(item.id) ||
      (item.seriesId != null && ids.contains(item.seriesId)) ||
      (item.seasonId != null && ids.contains(item.seasonId));

  List<EmbyItem> filter(List<EmbyItem> items) => isEmpty ? items : [for (final i in items) if (!hides(i)) i];
}
