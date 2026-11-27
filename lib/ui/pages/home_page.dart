import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../app/home_rows.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/catalog_api.dart';
import '../../data/libraries.dart';
import '../../data/recommendations.dart';
import '../../data/season_events.dart';
import '../../data/seerr_api.dart';
import '../../data/taste_profile.dart';
import '../../data/title_tags.dart';
import '../../core/log/app_log.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../core/playback_launcher.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/cards.dart';
import '../widgets/cinema_loader.dart';
import '../widgets/event_panel.dart';
import '../widgets/item_menu.dart';
import '../widgets/media_row.dart';
import '../widgets/rows_scroll_view.dart';
import '../widgets/mixed_cards.dart';
import '../widgets/mood_shelf.dart';
import '../widgets/trailer.dart';
import 'event_page.dart';
import 'hero.dart';
import 'home_rows_page.dart';
import 'title_extras.dart';
import 'routes.dart';

enum _Kind {
  cards,

  event,

  continueWatching,
  collections,

  moods,
}

class _Row {
  _Row(this.title, this.load,
      {this.style = CardStyle.poster, this.kind = _Kind.cards, this.recommends = true, this.shuffled = false});

  String Function(L10n) title;

  final Future<MixedItems> Function() load;
  final CardStyle style;
  final _Kind kind;

  final bool recommends;

  final bool shuffled;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static final firstLoad = ValueNotifier(true);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _hero = Debounced<HeroInfo?>(null);
  final _scroll = RevealController(mode: RevealMode.anchored, anchor: 64);
  List<_Row>? _rows;
  final _data = <_Row, Future<MixedItems>>{};

  final _allowed = <_Row>{};
  int _loading = 0;
  static const _parallelRows = 3;

  final _resolved = <_Row, MixedItems>{};
  bool _heroSet = false;

  bool _loaded = false;
  bool _showLoader = false;

  Future<TasteProfile>? _taste;

  Future<List<TitleTag>>? _tasteTags;

  AppServices? _services;
  String _layoutKey = '';
  final _rowCache = <String, List<_Row>>{};

  _Row? _myListRow;
  String _myListKeys = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows == null) {
      final services = AppServicesScope.read(context);
      _layoutKey = _layoutKeyOf(services);
      _rows = _buildRows(services);
      _allowFirstRows();
      _scroll.addListener(_onScroll);
      _awaitFirstRows();
      if (services.isSignedIn) services.libraries();
    }
    if (_services == null) {
      _services = AppServicesScope.read(context);
      _services!.libraryChanged.addListener(refresh);
      _services!.profiles.addListener(_onProfile);
      _services!.addListener(_onServices);
    }
  }

  static List<(String, String)> _collections(AppServices s) =>
      s.isSignedIn ? s.settings.homeCollectionsOf(s.janus.session.userId) : const [];

  static String _collectionsKey(AppServices s) => [for (final (id, _) in _collections(s)) id].join(',');

  static String _layoutKeyOf(AppServices s) {
    final layout = homeRowLayout(s);
    return [
      _collectionsKey(s),
      for (final d in layout.visible(homeRowDefaults(s))) d.id,
      for (final l in s.knownLibraries) l.name,
    ].join('|');
  }

  void _onServices() {
    final key = _layoutKeyOf(_services!);
    if (key == _layoutKey || !mounted) return;
    _layoutKey = key;
    setState(() {
      final rows = _rows = _buildRows(_services!);
      final kept = rows.toSet();
      _data.removeWhere((r, _) => !kept.contains(r));
      _resolved.removeWhere((r, _) => !kept.contains(r));
      _allowed.removeWhere((r) => !kept.contains(r));
      if (_allowed.isEmpty) _allowFirstRows();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pump());
  }

  void _onProfile() {
    final keys = [for (final e in _services!.profiles.profile?.list ?? const []) e.key].join(',');
    if (keys == _myListKeys) return;
    _myListKeys = keys;
    final row = _myListRow;
    if (row != null && mounted) setState(() => _data.remove(row));
  }

  void _allowFirstRows() {
    _allowed
      ..clear()
      ..addAll(_rows!.take(6).where((r) => !r.recommends && r.kind != _Kind.moods));
  }

  void _pump({int upTo = -1}) {
    final rows = _rows!;
    var changed = false;
    for (var i = 0; i < rows.length && i <= upTo; i++) {
      changed |= _allowed.add(rows[i]);
    }
    if (_loaded) {
      for (final r in rows) {
        if (_loading >= _parallelRows) break;
        if (_allowed.add(r)) {
          changed = true;
          if (!_data.containsKey(r)) _loading++;
          _load(r, counted: true);
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _onScroll() {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final upTo = (offset + MediaQuery.sizeOf(context).height * 2) ~/ 320;
    if (upTo >= 0 && _rows!.take(upTo + 1).any((r) => !_allowed.contains(r))) _pump(upTo: upTo);
  }

  void _awaitFirstRows() {
    if (!AppServicesScope.read(context).isSignedIn) {
      _loaded = true;
      HomePage.firstLoad.value = false;
      return;
    }
    final first = _rows!
        .where((r) => r.kind == _Kind.continueWatching || (r.kind == _Kind.cards && !r.recommends))
        .take(2);
    Timer(const Duration(milliseconds: 400), () {
      if (mounted && !_loaded && AppServicesScope.read(context).isSignedIn) setState(() => _showLoader = true);
    });
    Future.wait(first.map((r) => _load(r).catchError((Object _) => const <Object>[])))
        .timeout(const Duration(seconds: 45), onTimeout: () => const [])
        .whenComplete(() {
      AppLog.mark('home rows loaded');
      HomePage.firstLoad.value = false;
      if (mounted) setState(() => _loaded = true);
      _pump();
    });
  }

  @override
  void dispose() {
    _services?.libraryChanged.removeListener(refresh);
    _services?.profiles.removeListener(_onProfile);
    _services?.removeListener(_onServices);
    _hero.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void refresh() {
    setState(() {
      _data.removeWhere((row, _) => !row.shuffled || !_resolved.containsKey(row));
      _taste = null;
      _tasteTags = null;
      _allowFirstRows();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pump());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.wait(_data.values.map((f) => f.catchError((Object _) => const <Object>[]))).whenComplete(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final focus = FocusManager.instance.primaryFocus;
          if (focus == null || focus.context == null || !focus.context!.mounted) _focusFirstCard();
        });
      });
    });
  }

  void _focusFirstCard() {
    final ctx = context;
    final scope = FocusScope.of(ctx);
    for (final n in scope.descendants) {
      if (n is ZoneScopeNode && n.items.isNotEmpty) {
        ZoneNavigator.enter(n);
        return;
      }
    }
  }

  Future<TasteProfile> _profile(AppServices s) => _taste ??= TasteProfile.load(s.catalog).catchError((Object e) {
        debugPrint('[home] taste profile: $e');
        return const TasteProfile();
      });

  Future<List<TitleTag>> _tags(AppServices s) => _tasteTags ??= () async {
        final tags = s.titleTags;
        if (tags == null) return const <TitleTag>[];
        return tags.taste(await _profile(s));
      }()
          .catchError((Object e) {
        debugPrint('[home] taste tags: $e');
        return const <TitleTag>[];
      });

  List<_Row> _buildRows(AppServices s) {
    final defaults = homeRowDefaults(s);
    final layout = homeRowLayout(s);
    final nextUp = defaults.any((d) => d.id == HomeRows.nextUp && layout.enabled(d));
    final libraries = {for (final l in s.knownLibraries) l.id: l};
    final fresh = <String, List<_Row>>{};
    final rows = <_Row>[];
    for (final d in layout.visible(defaults)) {
      final key = switch (d.id) {
        HomeRows.continueWatching => '${d.id}:$nextUp',
        HomeRows.homeCollections => '${d.id}:${_collectionsKey(s)}',
        _ when HomeRows.libraryOf(d.id) != null => '${d.id}:${libraries[HomeRows.libraryOf(d.id)]?.name}',
        _ => d.id,
      };
      rows.addAll(fresh[key] = _rowCache[key] ?? _rowsFor(s, d.id, nextUp: nextUp, libraries: libraries));
    }
    _rowCache
      ..clear()
      ..addAll(fresh);
    return rows;
  }

  static const _generatedStyles = {
    '${HomeRows.becauseMovie}.2': CardStyle.landscape,
    '${HomeRows.becauseShow}.1': CardStyle.landscape,
    '${HomeRows.starring}.2': CardStyle.landscape,
    '${HomeRows.tag}.2': CardStyle.landscape,
    '${HomeRows.genre}.2': CardStyle.landscape,
  };

  List<_Row> _rowsFor(AppServices s, String id, {required bool nextUp, required Map<String, ServerLibrary> libraries}) {
    final c = s.catalog;
    final seerr = s.seerr;
    final r = s.recommender;
    Future<MixedItems> items(Future<ItemPage> page) async => (await page).items;

    if (HomeRows.eventOf(id) case final event?) {
      final e = s.activeEvents.where((x) => x.id == event).firstOrNull;
      if (e == null) return const [];
      return [
        _Row((l) => e.name, () async {
          final content = await s.eventLoader.content(e);
          return content.total == 0 && content.target == null ? const [] : [content];
        }, kind: _Kind.event, recommends: false),
      ];
    }

    if (HomeRows.libraryOf(id) case final libraryId?) {
      final library = libraries[libraryId];
      if (library == null) return const [];
      return [
        _Row((l) => l.latestIn(library.name), () => c.latest(parentId: libraryId),
            style: Libraries.isMovies(library) ? CardStyle.poster : CardStyle.landscape, recommends: false),
      ];
    }
    if (HomeRows.generated(id) case (:final kind, :final index)) {
      final style = _generatedStyles[id] ?? CardStyle.poster;
      final row = switch (kind) {
        HomeRows.becauseMovie => _because(s, (t) => t.recentMovies, index, style: style),
        HomeRows.becauseShow => _because(s, (t) => t.recentSeries, index, style: style),
        HomeRows.starring => _starring(s, index, style: style),
        HomeRows.directedBy => _directedBy(s, index, style: style),
        HomeRows.tag => _likeTag(s, index, style: style),
        HomeRows.genre => _moreGenre(s, index, style: style),
        _ => null,
      };
      return [?row];
    }
    return switch (id) {
      HomeRows.continueWatching => [
          _Row((l) => l.continueWatching, () => nextUp ? c.resume() : c.continueWatching(),
              kind: _Kind.continueWatching, recommends: false),
        ],
      HomeRows.nextUp => [
          _Row((l) => l.homeRowNextUp, () => c.nextUp(), kind: _Kind.continueWatching, recommends: false),
        ],
      HomeRows.homeCollections => [
          for (final (id, name) in _collections(s))
            _Row((l) => name,
                () => items(c.query(parentId: id, recursive: false, sortBy: 'PremiereDate,ProductionYear,SortName', limit: 100)),
                recommends: false),
        ],
      HomeRows.myList => [_myListRow = _Row((l) => l.myList, s.myList, recommends: false)],
      HomeRows.latestMovies => [_Row((l) => l.latestMovies, () => c.latest(types: ['Movie']), recommends: false)],
      HomeRows.moods => [
          if (r.tmdb != null) _Row((l) => l.moodShelfTitle, () async => const [], kind: _Kind.moods, recommends: false),
        ],
      HomeRows.latestShows => [
          _Row((l) => l.latestShows, () => c.latest(types: ['Episode', 'Series']), style: CardStyle.landscape, recommends: false),
        ],
      HomeRows.trending => [
          if (seerr != null)
            _Row((l) => l.trendingThisWeek, () => r.mixed((p) => seerr.trending(page: p, timeWindow: 'week'), limit: 10),
                style: CardStyle.ranked),
        ],
      HomeRows.forYou => [_Row((l) => l.recommendedForYou, () => _forYou(s), style: CardStyle.spotlight, shuffled: true)],
      HomeRows.collections => [
          _Row((l) => l.collections, () => c.allCollections(recent: true, limit: 20), kind: _Kind.collections, recommends: false),
        ],
      HomeRows.topMovies => [
          _Row((l) => l.topRatedMovies,
              () => items(c.query(types: ['Movie'], sortBy: 'CommunityRating', descending: true, minCommunityRating: 7, limit: 24))),
        ],
      HomeRows.favorites => [
          _Row((l) => l.yourFavorites,
              () => items(c.query(types: ['Movie', 'Series'], filters: 'IsFavorite', sortBy: 'Random', limit: 30)),
              style: CardStyle.landscape, recommends: false, shuffled: true),
        ],
      HomeRows.recentlyReleased => [
          _Row((l) => l.recentlyReleased, () => items(c.query(types: ['Movie'], sortBy: 'PremiereDate', descending: true, limit: 24))),
        ],
      HomeRows.topShows => [
          _Row((l) => l.topRatedShows,
              () => items(c.query(types: ['Series'], sortBy: 'CommunityRating', descending: true, minCommunityRating: 7, limit: 24)),
              style: CardStyle.landscape),
        ],
      HomeRows.unseen => [
          _Row((l) => l.somethingUnseen, () => items(c.query(types: ['Movie'], sortBy: 'Random', filters: 'IsUnplayed', limit: 24)),
              shuffled: true),
        ],
      HomeRows.popularToRequest => [
          if (seerr != null)
            _Row((l) => l.popularToRequest, () async {
              final (movies, shows) = await (
                r.requestable((p) => r.discover(SeerrMediaType.movie, page: p, voteCountGte: 200), limit: 20),
                r.requestable((p) => r.discover(SeerrMediaType.tv, page: p, voteCountGte: 100), limit: 20),
              ).wait;
              return _interleave(movies, shows);
            }),
        ],
      _ => const [],
    };
  }

  static List<Object> _interleave(List<Object> a, List<Object> b) => [
        for (var i = 0; i < a.length || i < b.length; i++) ...[if (i < a.length) a[i], if (i < b.length) b[i]],
      ];

  _Row _because(AppServices s, List<EmbyItem> Function(TasteProfile) pick, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final seeds = pick(await _profile(s));
      if (seeds.length <= index) return const [];
      final seed = await s.catalog.localize(seeds[index]);
      row.title = (l) => l.becauseYouWatched(seed.name);
      final seerr = s.seerr;
      final tmdbId = seed.tmdbId;
      final MixedItems items;
      if (seerr != null && tmdbId != null) {
        items = await s.recommender.mixed(
            (p) => seerr.recommendations(tmdbId, seed.isSeries ? SeerrMediaType.tv : SeerrMediaType.movie, page: p),
            pages: 2,
            hidePlayed: true);
      } else {
        items = [for (final i in await s.catalog.similar(seed.id, limit: 24)) if (!i.isPlayed) i];
      }
      return [for (final i in items) if (i is! EmbyItem || i.id != seed.id) i];
    }, style: style);
  }

  _Row _likeTag(AppServices s, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final l10n = context.l10n;
      final said = <String>{};
      final tags = [
        for (final t in await _tags(s))
          if (tagRowTitle(l10n, t) case final title? when said.add(title)) t,
      ];
      if (tags.length <= index) return const [];
      final tag = tags[index];
      row.title = (l) => tagRowTitle(l, tag) ?? tagLabel(l, tag);
      final r = s.recommender;
      final (movies, shows) = await (
        r.tagged(tag, SeerrMediaType.movie, hidePlayed: true),
        r.tagged(tag, SeerrMediaType.tv, hidePlayed: true),
      ).wait;
      final all = _interleave(movies, shows);
      return all.length < 4 ? const [] : all.take(40).toList();
    }, style: style);
  }

  _Row _starring(AppServices s, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final actors = (await _profile(s)).actors;
      if (actors.length <= index) return const [];
      final person = actors[index].person;
      row.title = (l) => l.starring(person.name);
      return _personWork(s, person, types: const ['Movie', 'Series']);
    }, style: style);
  }

  _Row _directedBy(AppServices s, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final directors = (await _profile(s)).directors;
      if (directors.length <= index) return const [];
      final person = directors[index].person;
      row.title = (l) => l.directedBy(person.name);
      return _personWork(s, person, types: const ['Movie'], movieCreditsOnly: true);
    }, style: style);
  }

  static Future<MixedItems> _personWork(AppServices s, Person person,
      {required List<String> types, bool movieCreditsOnly = false}) async {
    final c = s.catalog;
    final seerr = s.seerr;
    final (library, details) = await (
      c.query(personIds: person.id, types: types, filters: 'IsUnplayed', sortBy: 'CommunityRating', descending: true, limit: 40),
      seerr == null ? Future<EmbyItem?>.value() : c.item(person.id).then<EmbyItem?>((v) => v, onError: (Object _) => null),
    ).wait;
    final requestable = <SeerrMedia>[];
    final tmdbId = details?.tmdbId;
    if (seerr != null && tmdbId != null) {
      try {
        final credits = await seerr.personCredits(tmdbId, name: person.name);
        final kept = [
          for (final m in credits)
            if (RecommendationFilter.keep(m) && (m.voteCount ?? 0) >= 50 && (!movieCreditsOnly || !m.isTv)) m,
        ].take(40).toList();
        requestable.addAll((await s.recommender.resolve(kept)).whereType<SeerrMedia>());
      } catch (e) {
        debugPrint('[home] credits of ${person.name}: $e');
      }
    }
    final all = <Object>[...library.items, ...requestable.take(24)];
    return all.length < 4 ? const [] : all;
  }

  _Row _moreGenre(AppServices s, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final genres = (await _profile(s)).genres;
      if (genres.length <= index) return const [];
      final genre = genres[index].genre;
      row.title = (l) => l.moreGenre(lowerFirst(genre));
      final page = await s.catalog.query(
          types: ['Movie', 'Series'], genres: [genre], filters: 'IsUnplayed', sortBy: 'Random', minCommunityRating: 6.5, limit: 30);
      return page.items;
    }, style: style, shuffled: true);
  }

  Future<MixedItems> _forYou(AppServices s) async {
    final genres = (await _profile(s)).genres.take(3).map((g) => g.genre).toList();
    final page = await s.catalog.query(
      types: ['Movie', 'Series'],
      genres: genres.isEmpty ? null : genres,
      filters: 'IsUnplayed',
      sortBy: 'Random',
      minCommunityRating: 7,
      limit: 12,
    );
    return [for (final i in page.items) if (s.catalog.backdrop(i) != null) i];
  }

  Future<MixedItems> _load(_Row row, {bool counted = false}) => _data.putIfAbsent(row, () async {
        if (!counted) _loading++;
        try {
          var items = await row.load();
          if (row.recommends) items = [for (final i in items) if (i.keptInRecommendations) i];
          _resolved[row] = items;
          return items;
        } finally {
          _loading--;
          scheduleMicrotask(() => mounted ? _pump() : null);
        }
      });

  void _focusData(Object data, {bool immediate = false}) {
    final l10n = context.l10n;
    _hero.set(
        switch (data) {
          final EmbyItem item => HeroInfo.fromItem(l10n, AppServicesScope.read(context), item),
          final EventContent e => HeroInfo(
              key: 'event:${e.event.id}',
              title: e.title,
              backdrop: e.backdrop,
              overview: e.event.spotlight?.text,
              meta: [e.event.name, countdownLabel(l10n, e.event.spotlight, DateTime.now())],
            ),
          _ => HeroInfo.fromRequest(l10n, data as SeerrMedia),
        },
        immediate: immediate);
  }

  Future<void> _play(EmbyItem item) => playItem(context, item);

  @override
  Widget build(BuildContext context) {
    final rows = _rows!;
    final height = MediaQuery.sizeOf(context).height;
    final heroHeight = height * 0.46;
    return Stack(children: [
      Positioned.fill(
        child: ValueListenableBuilder(
          valueListenable: _hero,
          builder: (_, info, _) => Backdrop(url: info?.backdrop),
        ),
      ),
      Positioned(
        left: contentLeft,
        top: 0,
        height: heroHeight,
        right: 600,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: ValueListenableBuilder(valueListenable: _hero, builder: (_, info, _) => HeroPanel(info: info)),
          ),
        ),
      ),
      Positioned.fill(
        top: heroHeight,
        child: CardTrailers(
          child: RowsScrollView(
            controller: _scroll,
            top: 24,
            children: [for (final (i, row) in rows.indexed) _buildRow(row, first: i == 0)],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: heroHeight,
        height: height * 0.035,
        child: const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF00B0B12), Color(0x000B0B12)],
              ),
            ),
          ),
        ),
      ),
      if (_showLoader && AppServicesScope.of(context).isSignedIn)
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _loaded,
            child: AnimatedOpacity(
              opacity: _loaded ? 0 : 1,
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              onEnd: () {
                if (_loaded && mounted) setState(() => _showLoader = false);
              },
              child: const CinemaLoader(),
            ),
          ),
        ),
    ]);
  }

  Widget _buildRow(_Row row, {required bool first}) {
    if (row.kind == _Kind.moods) {
      if (!_allowed.contains(row)) return const SizedBox.shrink();
      return MoodShelf(
        favoriteGenres: _profile(AppServicesScope.read(context)).then((t) => [for (final g in t.genres) g.genre]),
        onFocusHero: (info) => _hero.set(info),
      );
    }
    return FutureBuilder<MixedItems>(
      future: _allowed.contains(row) ? _load(row) : null,
      initialData: _resolved[row],
      builder: (context, snap) {
        final (cardW, areaH) = switch (row.kind) {
          _Kind.collections => (560.0, 560 * 0.42 + 44),
          _Kind.continueWatching => (Zs.landscapeWidth, cardAreaHeight(CardStyle.landscape)),
          _Kind.event => (cardWidth(CardStyle.poster), cardAreaHeight(CardStyle.poster) + 40),
          _ => (cardWidth(row.style), cardAreaHeight(row.style)),
        };
        if (snap.data == null && !snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Zs.rowGap),
            child: SkeletonRow(cardWidth: cardW, cardHeight: areaH - 100),
          );
        }
        final items = snap.data ?? const [];
        if (snap.hasError) debugPrint('[home] ${row.title(context.l10n)}: ${snap.error}');
        if (items.isEmpty) return const SizedBox.shrink();

        if (!_heroSet) {
          _heroSet = true;
          final firstItem = items.first;
          scheduleMicrotask(() {
            if (mounted) _focusData(firstItem, immediate: true);
          });
        }

        if (items.first case final EventContent content) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Zs.rowGap),
            child: EventPanel(
              content: content,
              autofocus: first,
              onOpen: () => Navigator.of(context).push(eventRoute(content.event)),
              onOpenItem: (item) => switch (item) {
                final EmbyItem i => openItem(context, i),
                final SeerrMedia m => openRequest(context, m),
                _ => null,
              },
              onFocusEvent: () => _focusData(content),
              onFocusItem: _focusData,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: Zs.rowGap),
          child: MediaRow(
            title: row.title(context.l10n),
            height: areaH,
            gap: switch ((row.kind, row.style)) {
              (_Kind.collections, _) => 28,
              (_, CardStyle.ranked) => 8,
              (_, CardStyle.spotlight) => 30,
              _ => Zs.cardGap,
            },
            itemCount: items.length,
            idOf: (i) => mediaId(items[i]),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _card(row, items[i], rank: i + 1, autofocus: first && i == 0),
            ),
          ),
        );
      },
    );
  }

  Widget _card(_Row row, Object data, {required int rank, required bool autofocus}) {
    if (row.kind == _Kind.collections && data is EmbyItem) {
      return CollectionCard(item: data, autofocus: autofocus, onFocus: () => _focusData(data), onSelect: () => openItem(context, data));
    }
    if (row.kind == _Kind.continueWatching && data is EmbyItem) {
      final item = data;
      final remaining = item.resumePosition == null || item.runtime == null
          ? null
          : formatRuntime(context.l10n, item.runtime! - item.resumePosition!);
      return LandscapeCard(
        item: item,
        autofocus: autofocus,
        title: item.isEpisode ? item.seriesName ?? item.name : item.name,
        subtitle: item.isEpisode
            ? [item.episodeCode, item.name].whereType<String>().join('  ')
            : remaining != null
                ? context.l10n.timeLeft(remaining)
                : item.productionYear?.toString(),
        preferEpisodeStill: false,
        onFocus: () => _focusData(item),
        onSelect: () => AppServicesScope.read(context).settings.continueWatchingAction == ContinueWatchingAction.play
            ? _play(item)
            : openItem(context, item),
        onMenu: itemMenuCallback(context, item, continueWatching: true),
        onPlay: () => _play(item),
      );
    }
    if (row.style == CardStyle.landscape && data is EmbyItem && data.isEpisode) {
      return LandscapeCard(
        item: data,
        autofocus: autofocus,
        title: data.seriesName ?? data.name,
        subtitle: [data.episodeCode, data.name].whereType<String>().join('  '),
        onFocus: () => _focusData(data),
        onSelect: () => openItem(context, data),
        onPlay: () => _play(data),
      );
    }
    return mixedCard(context, data, style: row.style, rank: rank, autofocus: autofocus, onFocus: () => _focusData(data));
  }
}
