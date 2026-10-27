import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/log/app_log.dart';
import '../../l10n/l10n.dart';
import '../core/input_mode.dart';
import '../core/navigation.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../pages/calendar_page.dart';
import '../pages/collections_page.dart';
import '../pages/discover_page.dart';
import '../pages/emby_live_tv_page.dart';
import '../pages/home_page.dart';
import '../pages/library_page.dart';
import '../pages/live_tv_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../theme/tokens.dart';
import '../widgets/exit_app.dart';
import '../widgets/zerk_logo.dart';

enum ShellTab {
  search(Icons.search_rounded),
  home(Icons.home_rounded),
  movies(Icons.movie_rounded),
  shows(Icons.tv_rounded),
  collections(Icons.collections_bookmark_rounded),
  discover(Icons.explore_rounded),
  calendar(Icons.calendar_month_rounded),
  liveTv(Icons.live_tv_rounded),
  settings(Icons.settings_rounded);

  const ShellTab(this.icon);

  final IconData icon;

  String label(L10n l10n) => switch (this) {
        search => l10n.search,
        home => l10n.home,
        movies => l10n.movies,
        shows => l10n.shows,
        collections => l10n.collections,
        discover => l10n.discover,
        calendar => l10n.calendar,
        liveTv => l10n.liveTv,
        settings => l10n.settings,
      };
}

class Shell extends StatefulWidget {
  const Shell({super.key, this.initialTab = ShellTab.home});

  final ShellTab initialTab;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late ShellTab _tab = widget.initialTab;
  late final _visited = <ShellTab>{widget.initialTab};
  final _railZoneKey = GlobalKey();
  final _pageZoneKeys = {for (final t in ShellTab.values) t: GlobalKey()};
  bool _railFocused = false;

  bool _railHovered = false;
  final _railNodes = {for (final t in ShellTab.values) t: FocusNode(debugLabel: 'rail:${t.name}')};

  @override
  void dispose() {
    for (final n in _railNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  List<ShellTab> _tabs(AppServices s) => [
    for (final t in ShellTab.values)
      if ((t != ShellTab.discover || s.seerr != null) && (t != ShellTab.calendar || s.tmdb != null || s.seerr != null) &&
          (t != ShellTab.liveTv || s.liveTvAvailable || s.embyTvAvailable)) t,
  ];

  void _select(ShellTab tab) {
    final firstVisit = !_visited.contains(tab);
    final watch = Stopwatch()..start();
    AppLog.where = 'tab:${tab.name}';
    WidgetsBinding.instance.addPostFrameCallback((_) => AppLog.write(
        '[nav] tab ${tab.name}${firstVisit ? ' (first visit)' : ''}: first frame after ${watch.elapsedMilliseconds} ms'));
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ZoneNavigator.move(TraversalDirection.right),
    );
  }

  bool _onBack() {
    if (!_railFocused) {
      _focusRail();
      UiSounds.play(UiSound.back);
      return true;
    }
    if (_tab != ShellTab.home) {
      UiSounds.play(UiSound.back);
      _select(ShellTab.home);
      return true;
    }
    UiSounds.play(UiSound.back);
    confirmExit(context);
    return true;
  }

  void _focusRail() {
    final zone = FocusZone.nodeOf(_railZoneKey);
    if (zone != null) ZoneNavigator.enter(zone);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.of(context);
    final tabs = _tabs(services);
    if (!tabs.contains(_tab)) _tab = ShellTab.home;

    return BackHandler(
      onBack: _onBack,
      child: Material(
        color: Zc.background,
        child: Stack(
          children: [
            for (final t in tabs)
              if (_visited.contains(t))
                Offstage(
                  key: _pageZoneKeys[t],
                  offstage: t != _tab,
                  child: TickerMode(
                    enabled: t == _tab,
                    child: ExcludeFocus(excluding: t != _tab, child: _page(t)),
                  ),
                ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: ValueListenableBuilder(
                valueListenable: HomePage.firstLoad,
                builder: (context, loading, rail) {
                  final hidden = loading && _tab == ShellTab.home;
                  return IgnorePointer(
                    ignoring: hidden,
                    child: ExcludeFocus(
                      excluding: hidden,
                      child: AnimatedOpacity(opacity: hidden ? 0 : 1, duration: const Duration(milliseconds: 600), child: rail),
                    ),
                  );
                },
                child: MouseRegion(
                  onEnter: (_) => setState(() => _railHovered = true),
                  onExit: (_) => setState(() => _railHovered = false),
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (f) => setState(() => _railFocused = f),
                    child: FocusZone(
                      key: _railZoneKey,
                      debugLabel: 'rail',
                      preferredEntry: () => _railNodes[_tab],
                      child: ValueListenableBuilder(
                        valueListenable: InputMode.pointer,
                        builder: (context, pointer, _) => _Rail(
                          tabs: tabs,
                          current: _tab,
                          expanded: _railFocused && (!pointer || _railHovered),
                          onSelect: _select,
                          nodes: _railNodes,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(ShellTab t) => switch (t) {
    ShellTab.home => const HomePage(),
    ShellTab.search => const SearchPage(),
    ShellTab.movies => const LibraryPage(kind: LibraryKind.movies),
    ShellTab.shows => const LibraryPage(kind: LibraryKind.shows),
    ShellTab.collections => const CollectionsPage(),
    ShellTab.discover => const DiscoverPage(),
    ShellTab.calendar => const CalendarPage(),
    ShellTab.liveTv => AppServicesScope.read(context).liveTvAvailable ? const LiveTvPage() : const EmbyLiveTvPage(),
    ShellTab.settings => const SettingsPage(),
  };
}

enum _Group {
  library(Icons.video_library_rounded, [ShellTab.movies, ShellTab.shows, ShellTab.collections]),
  explore(Icons.explore_rounded, [ShellTab.discover, ShellTab.calendar]);

  const _Group(this.icon, this.tabs);

  final IconData icon;
  final List<ShellTab> tabs;

  String label(L10n l10n) => switch (this) {
        library => l10n.navLibrary,
        explore => l10n.navExplore,
      };
}

const List<Object> _railOrder = [
  ShellTab.search,
  ShellTab.home,
  _Group.library,
  _Group.explore,
  ShellTab.liveTv,
];

class _Rail extends StatefulWidget {
  const _Rail({
    required this.tabs,
    required this.current,
    required this.expanded,
    required this.onSelect,
    required this.nodes,
  });

  final Map<ShellTab, FocusNode> nodes;
  final List<ShellTab> tabs;
  final ShellTab current;
  final bool expanded;
  final ValueChanged<ShellTab> onSelect;

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  final _groupNodes = {for (final g in _Group.values) g: FocusNode(debugLabel: 'rail-group:${g.name}')};

  _Group? _focusGroup;

  @override
  void dispose() {
    for (final n in _groupNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  bool _open(_Group g) =>
      widget.expanded && (_focusGroup == g || (_focusGroup == null && g.tabs.contains(widget.current)));

  Widget _item(ShellTab t, {bool child = false}) => _RailItem(
        tab: t,
        node: widget.nodes[t]!,
        selected: t == widget.current,
        expanded: widget.expanded,
        child: child,
        onSelect: () => widget.onSelect(t),
      );

  Widget _group(_Group g, List<ShellTab> tabs) {
    final open = _open(g);
    final holdsCurrent = tabs.contains(widget.current);
    final focusable = open || (!widget.expanded && holdsCurrent);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() {
        if (f) {
          _focusGroup = g;
        } else if (_focusGroup == g) {
          _focusGroup = null;
        }
      }),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _RailItem(
          icon: g.icon,
          label: g.label(context.l10n),
          node: _groupNodes[g]!,
          selected: holdsCurrent,
          expanded: widget.expanded,
          open: open,
          onSelect: () => widget.onSelect(holdsCurrent ? widget.current : tabs.first),
        ),
        ClipRect(
          child: AnimatedAlign(
            duration: Zm.normal,
            curve: Zm.curve,
            alignment: Alignment.topLeft,
            heightFactor: open ? 1 : 0,
            child: ExcludeFocus(
              excluding: !focusable,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final t in tabs) _item(t, child: true),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final expanded = widget.expanded;
    return AnimatedContainer(
      duration: Zm.normal,
      curve: Zm.curve,
      width: expanded ? Zs.railExpanded + 120 : Zs.railCollapsed,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: const [0, 0.55, 1],
          colors: expanded
              ? const [Color(0xF20B0B12), Color(0xE00B0B12), Color(0x000B0B12)]
              : const [Color(0xCC0B0B12), Color(0x990B0B12), Color(0x000B0B12)],
        ),
      ),
      padding: const EdgeInsets.only(left: 20, top: 48, bottom: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Logo(expanded: expanded),
          const Spacer(),
          for (final entry in _railOrder)
            if (entry is ShellTab && tabs.contains(entry))
              _item(entry)
            else if (entry is _Group)
              switch (entry.tabs.where(tabs.contains).toList()) {
                [] => const SizedBox.shrink(),
                [final only] => _item(only),
                final some => _group(entry, some),
              },
          const Spacer(),
          _item(ShellTab.settings),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          const ZerkLogo(size: 48),
          if (expanded)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text.rich(
                  const TextSpan(children: [
                    TextSpan(text: 'Zerk', style: TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: ' Play', style: TextStyle(fontWeight: FontWeight.w400, color: Zc.textMuted)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: Zt.title.copyWith(height: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    this.tab,
    this.icon,
    this.label,
    required this.node,
    required this.selected,
    required this.expanded,
    required this.onSelect,
    this.child = false,
    this.open,
  });

  final ShellTab? tab;
  final IconData? icon;
  final String? label;

  final bool child;

  final bool? open;
  final FocusNode node;
  final bool selected;
  final bool expanded;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final group = open != null;
    return Padding(
      padding: EdgeInsets.only(top: 3, bottom: 3, left: child && expanded ? 26 : 0),
      child: TvFocusable(
        focusNode: node,
        reveal: false,
        onSelect: onSelect,
        builder: (context, focused) {
          final fg = focused
              ? Zc.background
              : (selected ? Colors.white : (child ? Zc.textMuted : Zc.textFaint));
          return AnimatedContainer(
            duration: Zm.fast,
            curve: Zm.curve,
            height: child ? 50 : 58,
            width: expanded ? Zs.railExpanded - 20 - (child ? 26 : 0) : 64,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white
                  : (selected && !expanded
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(30),
            ),
            clipBehavior: Clip.hardEdge,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: Zs.railExpanded - 56 - (child ? 26 : 0),
              maxWidth: Zs.railExpanded - 56 - (child ? 26 : 0),
              child: Row(
                children: [
                  Icon(icon ?? tab!.icon, size: child ? 24 : 28, color: fg),
                  if (expanded)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 18),
                        child: Text(
                          label ?? tab!.label(context.l10n),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: Zt.label.copyWith(color: fg, fontSize: child ? 20 : 22),
                        ),
                      ),
                    ),
                  if (expanded && group)
                    AnimatedRotation(
                      turns: open! ? 0.5 : 0,
                      duration: Zm.normal,
                      child: Icon(Icons.expand_more_rounded, size: 26, color: fg),
                    )
                  else if (expanded && selected && !focused)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Zc.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
