import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/home_rows.dart';
import '../../data/catalog_api.dart' show ServerLibrary;
import '../../data/libraries.dart';
import '../../data/season_events.dart';
import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/setting_rows.dart';

List<HomeRowDef> homeRowDefaults(AppServices s) {
  final defaults = HomeRows.defaults(
    seerr: s.seerr != null,
    moods: s.tmdb != null,
    tags: s.tmdb != null,
    libraries: [for (final l in s.visibleLibraries) if (Libraries.hasLatest(l)) l.id],
  );
  final at = defaults.indexWhere((d) => d.id == HomeRows.nextUp) + 1;
  return [
    ...defaults.take(at),
    for (final e in s.activeEvents) HomeRowDef(HomeRows.event(e.id)),
    ...defaults.skip(at),
  ];
}

HomeRowLayout homeRowLayout(AppServices s) =>
    s.isSignedIn ? s.settings.homeRowsOf(s.janus.session.userId) : const HomeRowLayout();

String homeRowLabel(L10n l, String id,
    {Map<String, ServerLibrary> libraries = const {}, List<SeasonEvent> events = const []}) {
  if (HomeRows.libraryOf(id) case final library?) return l.latestIn(libraries[library]?.name ?? library);
  if (HomeRows.eventOf(id) case final event?) return events.where((x) => x.id == event).firstOrNull?.name ?? event;
  if (HomeRows.generated(id) case (:final kind, :final index)) {
    final name = switch (kind) {
      HomeRows.becauseMovie => l.homeRowBecauseMovie,
      HomeRows.becauseShow => l.homeRowBecauseShow,
      HomeRows.starring => l.homeRowStarring,
      HomeRows.directedBy => l.homeRowDirectedBy,
      HomeRows.tag => l.homeRowTaste,
      HomeRows.genre => l.homeRowGenre,
      _ => kind,
    };
    return kind == HomeRows.directedBy ? name : l.homeRowNumbered(name, index + 1);
  }
  return switch (id) {
    HomeRows.continueWatching => l.continueWatching,
    HomeRows.nextUp => l.homeRowNextUp,
    HomeRows.homeCollections => l.homeCollections,
    HomeRows.myList => l.myList,
    HomeRows.latestMovies => l.latestMovies,
    HomeRows.moods => l.moodShelfTitle,
    HomeRows.latestShows => l.latestShows,
    HomeRows.trending => l.trendingThisWeek,
    HomeRows.forYou => l.recommendedForYou,
    HomeRows.collections => l.collections,
    HomeRows.topMovies => l.topRatedMovies,
    HomeRows.favorites => l.yourFavorites,
    HomeRows.recentlyReleased => l.recentlyReleased,
    HomeRows.topShows => l.topRatedShows,
    HomeRows.unseen => l.somethingUnseen,
    HomeRows.popularToRequest => l.popularToRequest,
    _ => id,
  };
}

class HomeRowsPage extends StatefulWidget {
  const HomeRowsPage({super.key});

  @override
  State<HomeRowsPage> createState() => _HomeRowsPageState();
}

class _HomeRowsPageState extends State<HomeRowsPage> {
  late final AppServices _services = AppServicesScope.read(context);
  late final String _userId = _services.janus.session.userId;

  @override
  void initState() {
    super.initState();
    _services.libraries();
  }

  void _save(HomeRowLayout next) => _services.updateSettings(_services.settings.withHomeRows(_userId, next));

  void _move(List<HomeRowDef> defaults, HomeRowLayout layout, String id, int delta) {
    _save(layout.moved(defaults, id, delta));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (mounted && focused != null && focused.mounted) revealFocused(focused);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final services = AppServicesScope.of(context);
    final defaults = homeRowDefaults(services);
    final layout = services.settings.homeRowsOf(_userId);
    final rows = layout.arrange(defaults);
    final libraries = {for (final l in services.knownLibraries) l.id: l};
    return Padding(
      padding: const EdgeInsets.only(left: contentLeft, top: 90, right: 120),
      child: SizedBox(
        width: 1200,
        child: FocusZone(
          debugLabel: 'settings-home-rows',
          autofocus: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.homeRows, style: Zt.headline),
              const SizedBox(height: 12),
              Text(l10n.homeRowsIntro, style: Zt.body),
              const SizedBox(height: 24),
              TvButton(
                label: l10n.resetToDefault,
                icon: Icons.restart_alt_rounded,
                onSelect: layout.isDefault ? null : () => _save(const HomeRowLayout()),
              ),
              const SizedBox(height: 30),
              for (final (i, row) in rows.indexed)
                Row(key: ValueKey(row.id), children: [
                  Expanded(
                    child: SettingToggleRow(
                      title: homeRowLabel(l10n, row.id, libraries: libraries, events: services.activeEvents),
                      subtitle: switch (row.id) {
                        HomeRows.nextUp => l10n.homeRowNextUpHint,
                        HomeRows.homeCollections =>
                          l10n.homeCollectionsCount(services.settings.homeCollectionsOf(_userId).length),
                        _ when HomeRows.generated(row.id) != null => l10n.homeRowGeneratedHint,
                        _ => null,
                      },
                      value: layout.enabled(row),
                      onChanged: (v) => _save(layout.toggled(row.id, v)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _MoveButton(
                    label: l10n.moveUp,
                    icon: Icons.arrow_upward_rounded,
                    onSelect: i > 0 ? () => _move(defaults, layout, row.id, -1) : null,
                  ),
                  const SizedBox(width: 12),
                  _MoveButton(
                    label: l10n.moveDown,
                    icon: Icons.arrow_downward_rounded,
                    onSelect: i < rows.length - 1 ? () => _move(defaults, layout, row.id, 1) : null,
                  ),
                ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.label, required this.icon, required this.onSelect});

  final String label;
  final IconData icon;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Opacity(
          opacity: onSelect == null ? 0.35 : 1,
          child: Tooltip(
            message: label,
            child: TvButton(label: label, icon: icon, compact: true, onSelect: onSelect),
          ),
        ),
      );
}
