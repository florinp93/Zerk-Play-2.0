final class HomeRowDef {
  const HomeRowDef(this.id, {this.defaultOn = true});

  final String id;
  final bool defaultOn;

  @override
  bool operator ==(Object other) => other is HomeRowDef && other.id == id && other.defaultOn == defaultOn;

  @override
  int get hashCode => Object.hash(id, defaultOn);

  @override
  String toString() => id;
}

abstract final class HomeRows {
  static const continueWatching = 'continueWatching';
  static const nextUp = 'nextUp';
  static const homeCollections = 'homeCollections';
  static const myList = 'myList';
  static const latestMovies = 'latestMovies';
  static const moods = 'moods';
  static const latestShows = 'latestShows';
  static const trending = 'trending';
  static const forYou = 'forYou';
  static const collections = 'collections';
  static const topMovies = 'topMovies';
  static const favorites = 'favorites';
  static const recentlyReleased = 'recentlyReleased';
  static const topShows = 'topShows';
  static const unseen = 'unseen';
  static const popularToRequest = 'popularToRequest';

  static const becauseMovie = 'becauseMovie';
  static const becauseShow = 'becauseShow';
  static const starring = 'starring';
  static const directedBy = 'directedBy';
  static const tag = 'tag';
  static const genre = 'genre';

  static const latestPrefix = 'latest:';

  static String latestIn(String libraryId) => '$latestPrefix$libraryId';

  static String? libraryOf(String id) => id.startsWith(latestPrefix) ? id.substring(latestPrefix.length) : null;

  static ({String kind, int index})? generated(String id) {
    final dot = id.lastIndexOf('.');
    if (dot <= 0) return null;
    final n = int.tryParse(id.substring(dot + 1));
    if (n == null || n < 1) return null;
    return (kind: id.substring(0, dot), index: n - 1);
  }

  static List<HomeRowDef> defaults({
    bool seerr = false,
    bool moods = false,
    bool tags = false,
    List<String> libraries = const [],
  }) =>
      [
        const HomeRowDef(continueWatching),
        const HomeRowDef(nextUp, defaultOn: false),
        const HomeRowDef(homeCollections),
        const HomeRowDef(myList),
        const HomeRowDef('$becauseMovie.1'),
        const HomeRowDef(latestMovies),
        if (moods) const HomeRowDef(HomeRows.moods),
        const HomeRowDef(latestShows),
        for (final id in libraries) HomeRowDef(latestIn(id), defaultOn: false),
        if (seerr) const HomeRowDef(trending),
        const HomeRowDef(forYou),
        const HomeRowDef('$starring.1'),
        if (tags) const HomeRowDef('$tag.1'),
        const HomeRowDef(collections),
        const HomeRowDef('$becauseShow.1'),
        const HomeRowDef(topMovies),
        const HomeRowDef('$directedBy.1'),
        if (tags) const HomeRowDef('$tag.2'),
        const HomeRowDef('$becauseMovie.2'),
        const HomeRowDef(favorites),
        const HomeRowDef('$starring.2'),
        const HomeRowDef('$genre.1'),
        if (tags) const HomeRowDef('$tag.3'),
        const HomeRowDef(recentlyReleased),
        const HomeRowDef('$becauseShow.2'),
        const HomeRowDef(topShows),
        const HomeRowDef('$starring.3'),
        const HomeRowDef('$genre.2'),
        if (tags) const HomeRowDef('$tag.4'),
        const HomeRowDef(unseen),
        if (seerr) const HomeRowDef(popularToRequest),
      ];
}

final class HomeRowLayout {
  const HomeRowLayout({this.order = const [], this.toggles = const {}});

  final List<String> order;

  final Map<String, bool> toggles;

  bool get isDefault => order.isEmpty && toggles.isEmpty;

  bool enabled(HomeRowDef row) => toggles[row.id] ?? row.defaultOn;

  List<HomeRowDef> arrange(List<HomeRowDef> defaults) {
    final byId = {for (final d in defaults) d.id: d};
    final result = <HomeRowDef>[];
    final placed = <String>{};
    for (final id in order) {
      final def = byId[id];
      if (def != null && placed.add(id)) result.add(def);
    }
    for (final (i, def) in defaults.indexed) {
      if (placed.contains(def.id)) continue;
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final k = result.indexWhere((r) => r.id == defaults[j].id);
        if (k >= 0) {
          at = k + 1;
          break;
        }
      }
      result.insert(at, def);
      placed.add(def.id);
    }
    return result;
  }

  List<HomeRowDef> visible(List<HomeRowDef> defaults) => [
        for (final r in arrange(defaults))
          if (enabled(r)) r,
      ];

  HomeRowLayout toggled(String id, bool on) => HomeRowLayout(order: order, toggles: {...toggles, id: on});

  HomeRowLayout reordered(List<String> ids) {
    final shown = ids.toSet();
    return HomeRowLayout(order: [...ids, for (final id in order) if (!shown.contains(id)) id], toggles: toggles);
  }

  HomeRowLayout moved(List<HomeRowDef> defaults, String id, int delta) {
    final ids = [for (final d in arrange(defaults)) d.id];
    final from = ids.indexOf(id);
    if (from < 0) return this;
    final to = (from + delta).clamp(0, ids.length - 1);
    if (to == from) return this;
    ids.insert(to, ids.removeAt(from));
    return reordered(ids);
  }

  Map<String, Object> toJson() => {'order': order, 'on': toggles};

  static HomeRowLayout fromJson(Object? raw) {
    if (raw is! Map) return const HomeRowLayout();
    return HomeRowLayout(
      order: [for (final id in raw['order'] as List? ?? const []) if (id is String) id],
      toggles: {
        for (final MapEntry(:key, :value) in ((raw['on'] as Map?) ?? const {}).entries)
          if (value is bool) '$key': value,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HomeRowLayout &&
      other.order.length == order.length &&
      other.order.indexed.every((e) => order[e.$1] == e.$2) &&
      other.toggles.length == toggles.length &&
      other.toggles.entries.every((e) => toggles[e.key] == e.value);

  @override
  int get hashCode => Object.hash(Object.hashAll(order), Object.hashAllUnordered(toggles.entries.map((e) => '${e.key}=${e.value}')));
}
