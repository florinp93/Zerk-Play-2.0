import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app/app_services.dart';
import '../../data/release_calendar.dart';
import '../../data/seerr_api.dart';
import '../../data/tmdb_api.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/net_image.dart';
import '../widgets/side_panel.dart';
import 'routes.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  List<CalendarEntry>? _entries;
  Map<DateTime, List<CalendarEntry>> _byDay = const {};
  List<CalendarEntry> _undated = const [];
  DateTime? _loadedAt;
  bool _loading = false;
  AppServices? _services;

  late DateTime _month = _thisMonth;
  DateTime? _day;
  final _backdrop = Debounced<Uri?>(null);

  final _cells = List.generate(42, (i) => FocusNode(debugLabel: 'calendar-day-$i'));

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime get _thisMonth => DateTime(_today.year, _today.month);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = AppServicesScope.read(context);
    _services!.libraryChanged.addListener(_reload);
    RequestStatuses.changed.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _services?.libraryChanged.removeListener(_reload);
    RequestStatuses.changed.removeListener(_reload);
    _backdrop.dispose();
    for (final n in _cells) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    if (_loading) return;
    _loading = true;
    final s = AppServicesScope.read(context);
    final calendar = ReleaseCalendar(
      catalog: s.catalog,
      seerr: s.seerr,
      tmdb: s.tmdb,
      language: s.settings.tmdbLanguage,
    );
    List<CalendarEntry> entries;
    try {
      entries = await calendar.load();
    } catch (e) {
      debugPrint('[calendar] $e');
      entries = _entries ?? const [];
    }
    _loading = false;
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _byDay = {};
      for (final e in entries) {
        if (e.date != null) (_byDay[e.date!] ??= []).add(e);
      }
      _undated = [for (final e in entries) if (e.date == null) e];
      _loadedAt = DateTime.now();
    });
    final day = _day;
    if (day != null) _backdrop.set(_art(_byDay[day]?.firstOrNull), immediate: true);
  }

  void _refreshIfStale() {
    final at = _loadedAt;
    if (at == null || _loading) return;
    final now = DateTime.now();
    if (now.day != at.day || now.difference(at) > const Duration(minutes: 30)) _reload();
  }

  DateTime get _firstMonth => DateTime(_thisMonth.year, _thisMonth.month - 1);

  DateTime get _lastMonth {
    final last = _byDay.keys.fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final m = last == null ? _thisMonth : DateTime(last.year, last.month);
    return m.isAfter(_thisMonth) ? m : _thisMonth;
  }

  bool _canTurn(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    return !next.isBefore(_firstMonth) && !next.isAfter(_lastMonth);
  }

  void _turn(int delta, {int? row, int? column}) {
    if (!_canTurn(delta)) return;
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    if (row == null || column == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final weeks = _weeks(_month);
      _cells[row.clamp(0, weeks - 1) * 7 + column].requestFocus();
    });
  }

  int get _firstWeekday => MaterialLocalizations.of(context).firstDayOfWeekIndex;

  DateTime _gridStart(DateTime month) {
    final offset = (month.weekday % 7 - _firstWeekday + 7) % 7;
    return DateTime(month.year, month.month, 1 - offset);
  }

  int _weeks(DateTime month) {
    final offset = DateTime(month.year, month.month).difference(_gridStart(month)).inDays;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    return ((offset + days) / 7).ceil();
  }

  KeyEventResult _onGridKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final delta = key == LogicalKeyboardKey.arrowLeft ? -1 : (key == LogicalKeyboardKey.arrowRight ? 1 : 0);
    if (delta == 0) return KeyEventResult.ignored;
    final i = _cells.indexWhere((n) => n.hasPrimaryFocus);
    if (i < 0 || i % 7 != (delta < 0 ? 0 : 6)) return KeyEventResult.ignored;
    if (!_canTurn(delta)) return KeyEventResult.ignored;
    _turn(delta, row: i ~/ 7, column: delta < 0 ? 6 : 0);
    return KeyEventResult.handled;
  }

  void _focusDay(DateTime day) {
    setState(() => _day = day);
    final first = _byDay[day]?.firstOrNull;
    if (first != null) _backdrop.set(_art(first));
  }

  Uri? _art(CalendarEntry? e) {
    if (e == null) return null;
    final item = e.libraryItem;
    return e.backdropPath != null
        ? TmdbApi.imageUrl(e.backdropPath!, width: 1280, backdrop: true)
        : (item != null ? AppServicesScope.read(context).catalog.backdrop(item) : null);
  }

  void _open(CalendarEntry e) {
    final item = e.libraryItem;
    if (item != null) return openItem(context, item);
    final media = e.media;
    if (media != null && AppServicesScope.read(context).seerr != null) openRequest(context, media);
  }

  Future<void> _choose(String title, List<CalendarEntry> entries) async {
    if (entries.isEmpty) return;
    if (entries.length == 1) return _open(entries.first);
    final l10n = context.l10n;
    final chosen = await showSidePanel<CalendarEntry>(context, title: title, options: [
      for (final e in entries)
        PanelOption(
          value: e,
          title: e.title,
          subtitle: _subtitle(l10n, e),
          icon: e.isTv ? Icons.tv_rounded : Icons.movie_outlined,
        ),
    ]);
    if (chosen != null && mounted) _open(chosen);
  }

  @override
  Widget build(BuildContext context) {
    if (TickerMode.valuesOf(context).enabled) WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfStale());
    final l10n = context.l10n;
    final entries = _entries;
    return Stack(children: [
      Positioned.fill(
        child: ValueListenableBuilder(valueListenable: _backdrop, builder: (_, url, _) => Backdrop(url: url)),
      ),
      Positioned.fill(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: contentLeft, top: 48, right: 36, bottom: 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Eyebrow(l10n.calendar),
                const SizedBox(height: 10),
                _header(),
                const SizedBox(height: 22),
                _weekdays(),
                const SizedBox(height: 10),
                Expanded(child: _grid()),
              ]),
            ),
          ),
          SizedBox(
            width: 560,
            child: Padding(
              padding: const EdgeInsets.only(top: 150, right: 72, bottom: 40),
              child: entries != null && entries.isEmpty
                  ? Text(l10n.calendarEmpty, style: Zt.body)
                  : _DayPanel(day: _day, entries: _day == null ? const [] : _byDay[_day] ?? const []),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _header() {
    final l10n = context.l10n;
    return Row(children: [
      ExcludeFocus(
        child: Row(children: [
          _Arrow(icon: Icons.chevron_left_rounded, label: l10n.calendarPrevMonth, onSelect: _canTurn(-1) ? () => _turn(-1) : null),
          const SizedBox(width: 10),
          _Arrow(icon: Icons.chevron_right_rounded, label: l10n.calendarNextMonth, onSelect: _canTurn(1) ? () => _turn(1) : null),
        ]),
      ),
      const SizedBox(width: 24),
      Text(_capitalize(l10n.calendarMonth(_month)), style: Zt.headline),
      const Spacer(),
      if (_undated.isNotEmpty)
        FocusZone(
          debugLabel: 'calendar-undated',
          child: TvButton(
            label: '${l10n.calendarNoDate}  ·  ${_undated.length}',
            icon: Icons.event_busy_rounded,
            onSelect: () => _choose(l10n.calendarNoDate, _undated),
          ),
        ),
    ]);
  }

  Widget _weekdays() {
    final format = DateFormat.E(context.l10n.localeName);
    final start = _gridStart(_month);
    return Row(children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              format.format(start.add(Duration(days: i))).toUpperCase(),
              style: Zt.caption.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700),
            ),
          ),
        ),
    ]);
  }

  Widget _grid() {
    final start = _gridStart(_month);
    final weeks = _weeks(_month);
    final today = _today;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onGridKey,
      child: FocusZone(
        debugLabel: 'calendar-grid',
        child: Column(children: [
          for (var w = 0; w < weeks; w++)
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: () {
                      final day = DateTime(start.year, start.month, start.day + w * 7 + d);
                      return Padding(
                        padding: const EdgeInsets.all(4),
                        child: _DayCell(
                          day: day,
                          node: _cells[w * 7 + d],
                          inMonth: day.month == _month.month,
                          today: day == today,
                          entries: _byDay[day] ?? const [],
                          autofocus: day == today,
                          onFocus: () => _focusDay(day),
                          onSelect: () => _choose(_capitalize(context.l10n.calendarDay(day)), _byDay[day] ?? const []),
                        ),
                      );
                    }(),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String? _relative(L10n l10n, DateTime day) {
  final now = DateTime.now();
  final days = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  return switch (days) {
    0 => l10n.calendarToday,
    1 => l10n.calendarTomorrow,
    -1 => l10n.calendarYesterday,
    > 1 && <= 21 => l10n.calendarInDays(days),
    < -1 => l10n.calendarDaysAgo(-days),
    _ => null,
  };
}

String? _homeRelease(L10n l10n, HomeRelease? r) => switch (r) {
      HomeRelease.digital => l10n.calendarDigital,
      HomeRelease.disc => l10n.calendarDisc,
      HomeRelease.tv => l10n.calendarTv,
      null => null,
    };

String? _subtitle(L10n l10n, CalendarEntry e) => e.isTv
    ? [e.episodeCode, e.episodeName ?? (e.episodeCount > 1 ? l10n.calendarEpisodes(e.episodeCount) : null)].nonNulls.join('  ·  ')
    : _homeRelease(l10n, e.homeRelease);

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Zt.caption.copyWith(letterSpacing: 6, color: Zc.accentSoft, fontWeight: FontWeight.w700),
      );
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.label, this.onSelect});

  final IconData icon;
  final String label;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onSelect == null ? 0.3 : 1,
        child: Tooltip(message: label, child: TvButton(label: label, icon: icon, compact: true, onSelect: onSelect)),
      );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.node,
    required this.inMonth,
    required this.today,
    required this.entries,
    required this.onFocus,
    required this.onSelect,
    this.autofocus = false,
  });

  final DateTime day;
  final FocusNode node;
  final bool inMonth;
  final bool today;
  final List<CalendarEntry> entries;
  final VoidCallback onFocus;
  final VoidCallback onSelect;
  final bool autofocus;

  static const _maxCovers = 3;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: node,
      autofocus: autofocus,
      reveal: false,
      selectSound: entries.isEmpty ? null : UiSound.select,
      onSelect: entries.isEmpty ? null : onSelect,
      onFocusChange: (f) => f ? onFocus() : null,
      builder: (context, focused) => AnimatedContainer(
        duration: Zm.fast,
        decoration: BoxDecoration(
          color: focused
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: inMonth ? (entries.isEmpty ? 0.035 : 0.07) : 0.015),
          borderRadius: BorderRadius.circular(Zs.radius),
          border: Border.all(color: focused ? Colors.white : (today ? Zc.accent : Colors.transparent), width: focused ? 3 : 2),
        ),
        child: Opacity(
          opacity: inMonth ? 1 : 0.45,
          child: LayoutBuilder(builder: (context, box) {
            final coverHeight = (box.maxHeight - 52).clamp(0.0, 200.0);
            return Stack(children: [
              Positioned(left: 12, top: 8, child: _DayNumber(day: day, today: today)),
              if (entries.isNotEmpty && coverHeight > 30)
                Positioned(left: 12, right: 12, bottom: 10, height: coverHeight, child: _covers(context, coverHeight)),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _covers(BuildContext context, double height) {
    final width = height * 2 / 3;
    final shown = entries.take(_maxCovers).toList();
    final more = entries.length - shown.length;
    final step = width * 0.42;
    return Stack(clipBehavior: Clip.none, children: [
      for (final (i, e) in shown.indexed.toList().reversed)
        Positioned(left: i * step, top: 0, width: width, height: height, child: _Cover(entry: e, width: width)),
      if (more > 0)
        Positioned(right: 0, bottom: 0, child: Pill(context.l10n.calendarMore(more), color: Colors.black.withValues(alpha: 0.75))),
    ]);
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({required this.day, required this.today});

  final DateTime day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final text = Text('${day.day}', style: Zt.label.copyWith(fontSize: 22, color: today ? Colors.white : Zc.textMuted));
    if (!today) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: Zc.accent, borderRadius: BorderRadius.circular(14)),
      child: text,
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.entry, required this.width});

  final CalendarEntry entry;
  final double width;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final item = e.libraryItem;
    final url = e.posterPath != null
        ? TmdbApi.imageUrl(e.posterPath!, width: (width * 2).round())
        : (item != null ? AppServicesScope.read(context).catalog.poster(item, width: width) : null);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: item == null ? Border.all(color: Zc.request, width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 8, offset: const Offset(2, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(item == null ? 6 : 8),
        child: NetImage(
          url: url,
          width: width,
          fallback: TitleArt(title: e.title, icon: e.isTv ? Icons.tv_rounded : Icons.movie_outlined),
        ),
      ),
    );
  }
}

class _DayPanel extends StatelessWidget {
  const _DayPanel({required this.day, required this.entries});

  final DateTime? day;
  final List<CalendarEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = day;
    if (d == null) return const SizedBox.shrink();
    final relative = _relative(l10n, d);
    return AnimatedSwitcher(
      duration: Zm.normal,
      child: Column(
        key: ValueKey(d),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(child: Text(_capitalize(l10n.calendarDay(d)), style: Zt.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (relative != null) ...[
              const SizedBox(width: 14),
              Pill(relative.toUpperCase(), color: relative == l10n.calendarToday ? Zc.accent : Zc.surfaceTop),
            ],
          ]),
          const SizedBox(height: 26),
          if (entries.isEmpty)
            Text(l10n.calendarNothingThisDay, style: Zt.body)
          else ...[
            _Featured(entry: entries.first),
            if (entries.length > 1) ...[
              const SizedBox(height: 28),
              for (final e in entries.skip(1).take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.title, style: Zt.label.copyWith(fontSize: 22), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (_subtitle(l10n, e) case final s? when s.isNotEmpty)
                      Text(s, style: Zt.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              if (entries.length > 7) Text(l10n.calendarMore(entries.length - 7), style: Zt.caption),
            ],
          ],
        ],
      ),
    );
  }
}

class _Featured extends StatelessWidget {
  const _Featured({required this.entry});

  final CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final e = entry;
    final item = e.libraryItem;
    final logo = e.logoPath != null
        ? TmdbApi.imageUrl(e.logoPath!, width: 500, logo: true)
        : (item != null ? AppServicesScope.read(context).catalog.logo(item) : null);
    final status = item == null && e.requested != null ? requestStatusLabel(l10n, e.requested!) : null;
    final highlight = switch (e) {
      CalendarEntry(finale: true) => l10n.calendarFinale,
      CalendarEntry(premiere: true, season: 1) => l10n.calendarSeriesPremiere,
      CalendarEntry(premiere: true) => l10n.calendarSeasonPremiere,
      _ => null,
    };
    final title = Text(e.title, style: Zt.display.copyWith(fontSize: 44), maxLines: 2, overflow: TextOverflow.ellipsis);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (logo != null)
        SizedBox(
          height: 110,
          width: 420,
          child: NetImage(url: logo, width: 420, fit: BoxFit.contain, alignment: Alignment.bottomLeft, fallback: title),
        )
      else
        title,
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (!e.isTv) Pill(l10n.calendarMovie),
        if (highlight != null) Pill(highlight, color: Zc.accent),
        if (status != null) Pill(status.$1, color: status.$2, textColor: Zc.background),
        if (_subtitle(l10n, e) case final s? when s.isNotEmpty) Text(s, style: Zt.meta),
      ]),
      if (e.overview != null) ...[
        const SizedBox(height: 16),
        Text(e.overview!, maxLines: 6, overflow: TextOverflow.ellipsis, style: Zt.body),
      ],
    ]);
  }
}
