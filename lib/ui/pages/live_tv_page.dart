import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/xtream/live_catalog.dart';
import '../../l10n/l10n.dart';
import '../../playback/live_session.dart' show ZapList;
import '../core/playback_launcher.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/live_loaders.dart';
import '../widgets/media_row.dart' show contentLeft;
import 'live_common.dart';

class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key});

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

typedef _Group = ({String country, String category})?;

const _countryOrder = ['RO', 'IE', 'UK', 'US'];

typedef _Focused = ({LiveChannel channel, Programme? programme});

class _LiveTvPageState extends State<LiveTvPage> {
  _Group _group;

  final _focus = ValueNotifier<_Focused?>(null);

  LiveCatalog? _for;
  _Group _forGroup;
  List<({String country, String category})> _groups = const [];
  List<LiveChannel> _channels = const [];
  ZapList? _zap;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LiveCatalogView(builder: _build, loader: const LiveTvLoader());

  void _derive(LiveCatalog catalog) {
    final all = catalog.channels;
    if (!identical(catalog, _for)) {
      final groups = <({String country, String category})>{};
      for (final country in [..._countryOrder, ...{for (final c in all) c.country}.difference(_countryOrder.toSet())]) {
        for (final c in all) {
          if (c.country == country) groups.add((country: country, category: c.category));
        }
      }
      _groups = groups.toList();
      _zap = ZapList(all, onNow: (c) => catalog.onNow(c, DateTime.now())?.title);
    }
    final group = _groups.contains(_group) ? _group : null;
    if (!identical(catalog, _for) || group != _forGroup) {
      _channels = group == null ? all : [for (final c in all) if (c.country == group.country && c.category == group.category) c];
    }
    _for = catalog;
    _forGroup = group;
  }

  Widget _build(BuildContext context, LiveCatalog catalog, DateTime now) {
    final l10n = context.l10n;
    final all = catalog.channels;
    if (all.isEmpty) return Center(child: Text(l10n.liveNoChannels, style: Zt.body));
    _derive(catalog);
    final groups = _groups, group = _forGroup, channels = _channels, zap = _zap!;

    return Padding(
      padding: const EdgeInsets.only(left: contentLeft, top: 56, right: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 196,
          child: ValueListenableBuilder(
            valueListenable: _focus,
            builder: (context, f, _) {
              final focus = f != null && channels.contains(f.channel)
                  ? f
                  : (channel: channels.first, programme: catalog.onNow(channels.first, now));
              return _Preview(channel: focus.channel, programme: focus.programme, now: now);
            },
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 250,
              child: FocusZone(
                debugLabel: 'live-groups',
                child: ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                  _GroupItem(
                    label: l10n.liveAllChannels,
                    selected: group == null,
                    onFocus: () => _select(null),
                  ),
                  for (final (i, g) in groups.indexed) ...[
                    if (i == 0 || groups[i - 1].country != g.country)
                      Padding(
                        padding: const EdgeInsets.only(top: 18, bottom: 6, left: 8),
                        child: Text(_countryName(l10n, g.country).toUpperCase(),
                            style: Zt.caption.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w600)),
                      ),
                    _GroupItem(
                      label: g.category.isEmpty ? _countryName(l10n, g.country) : g.category,
                      selected: g == group,
                      onFocus: () => _select(g),
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: FocusZone(
                debugLabel: 'live-guide',
                child: _Guide(
                  key: ValueKey(group),
                  channels: channels,
                  catalog: catalog,
                  now: now,
                  onFocus: (c, p) {
                    if (_focus.value?.channel != c || _focus.value?.programme != p) _focus.value = (channel: c, programme: p);
                  },
                  onPlay: (c) => playChannel(context, zap, all.indexOf(c)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  void _select(_Group g) {
    if (g == _group) return;
    _focus.value = null;
    setState(() => _group = g);
  }
}

String _countryName(L10n l10n, String country) => switch (country) {
      'RO' => l10n.liveCountryRO,
      'IE' => l10n.liveCountryIE,
      'US' => l10n.liveCountryUS,
      playlistCountry => l10n.livePlaylist,
      _ => l10n.liveCountryUK,
    };

class _GroupItem extends StatelessWidget {
  const _GroupItem({required this.label, required this.selected, required this.onFocus});

  final String label;
  final bool selected;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocusable(
        selectSound: null,
        onFocusChange: (f) => f ? onFocus() : null,
        onSelect: () => ZoneNavigator.move(TraversalDirection.right),
        builder: (context, focused) => AnimatedContainer(
          duration: Zm.fast,
          height: 50,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: focused ? Colors.white : (selected ? Colors.white.withValues(alpha: 0.10) : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Zt.label.copyWith(fontSize: 19, color: focused ? Zc.background : Zc.text)),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.channel, required this.programme, required this.now});

  final LiveChannel channel;
  final Programme? programme;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hm = DateFormat.Hm(l10n.localeName);
    final p = programme;
    final on = p != null && p.isOn(now);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ChannelLogo(name: channel.name, logo: channel.logo, width: 220, height: 140),
      const SizedBox(width: 32),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text([if (channel.number != null) '${channel.number}', channel.name].join('  ·  '),
              style: Zt.caption.copyWith(fontSize: 19, color: Zc.textMuted)),
          const SizedBox(height: 8),
          Text(p?.title ?? l10n.liveNoGuide,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.headline.copyWith(fontSize: 38)),
          if (p != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (on) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: Zc.accent, borderRadius: BorderRadius.circular(6)),
                  child: Text(l10n.liveNow.toUpperCase(), style: Zt.caption.copyWith(fontSize: 14, color: Colors.white)),
                ),
                const SizedBox(width: 12),
              ],
              Text('${hm.format(p.start.toLocal())} – ${hm.format(p.end.toLocal())}', style: Zt.caption.copyWith(fontSize: 19, color: Zc.text)),
              if (on) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (now.difference(p.start).inSeconds / p.end.difference(p.start).inSeconds.clamp(1, 1 << 30))
                          .clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      color: Zc.accent,
                    ),
                  ),
                ),
              ],
            ]),
            if (p.description != null) ...[
              const SizedBox(height: 10),
              Text(p.description!,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.caption.copyWith(fontSize: 18, color: Zc.textMuted)),
            ],
          ],
        ]),
      ),
    ]);
  }
}

class _Guide extends StatefulWidget {
  const _Guide({
    super.key,
    required this.channels,
    required this.catalog,
    required this.now,
    required this.onFocus,
    required this.onPlay,
  });

  final List<LiveChannel> channels;
  final LiveCatalog catalog;
  final DateTime now;
  final void Function(LiveChannel channel, Programme? programme) onFocus;
  final ValueChanged<LiveChannel> onPlay;

  @override
  State<_Guide> createState() => _GuideState();
}

const _rowHeight = 84.0;
const _headerHeight = 44.0;
const _channelWidth = 290.0;
const _window = Duration(minutes: 150);
const _slot = Duration(minutes: 30);

DateTime _floorSlot(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute - t.minute % 30);

class _GuideState extends State<_Guide> {
  final _node = FocusNode(debugLabel: 'live-guide-grid');
  final _scroll = ScrollController();
  bool _focused = false;
  int _row = 0;
  late DateTime _cursor = widget.now;
  late DateTime _start = _floorSlot(widget.now);

  final _rows = <int, (Object, Widget)>{};

  DateTime get _earliest => _floorSlot(widget.now).subtract(const Duration(hours: 1));
  DateTime get _latest => widget.now.add(const Duration(hours: 24));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(_Guide old) {
    super.didUpdateWidget(old);
    final floor = _floorSlot(widget.now).subtract(_slot);
    if (_start.isBefore(floor)) _start = floor;
    if (_cursor.isBefore(widget.now) && old.now.isBefore(widget.now)) _cursor = widget.now;
    _row = _row.clamp(0, math.max(0, widget.channels.length - 1));
    if (!identical(old.catalog, widget.catalog) || !identical(old.channels, widget.channels)) _rows.clear();
  }

  Widget _cachedRow(BuildContext context, int i, double width, double Function(DateTime) x, DateFormat hm) {
    final cursorRow = i == _row;
    final shows = (widget.channels[i], width, _start, widget.now, cursorRow ? (_focused, _current) : null);
    final hit = _rows[i];
    if (hit != null && hit.$1 == shows) return hit.$2;
    if (_rows.length > 200) _rows.clear();
    final row = _buildRow(context, i, width, x, hm);
    _rows[i] = (shows, row);
    return row;
  }

  @override
  void dispose() {
    _node.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Programme> _guide(LiveChannel c) => widget.catalog.guideFor(c);

  Programme? _at(LiveChannel c, DateTime t) => _guide(c).where((p) => p.isOn(t)).firstOrNull;

  Programme? get _current => widget.channels.isEmpty ? null : _at(widget.channels[_row], _cursor);

  void _report() {
    if (!mounted || widget.channels.isEmpty) return;
    widget.onFocus(widget.channels[_row], _current);
  }

  void _move(void Function() change) {
    setState(change);
    _reveal();
    _report();
  }

  void _reveal() {
    if (!_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    final top = _row * _rowHeight;
    var offset = _scroll.offset;
    if (top < offset) offset = top;
    if (top + _rowHeight > offset + view) offset = top + _rowHeight - view;
    if (offset != _scroll.offset) {
      _scroll.animateTo(offset.clamp(0, _scroll.position.maxScrollExtent), duration: Zm.fast, curve: Curves.easeOut);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || widget.channels.isEmpty) return KeyEventResult.ignored;
    final key = e.logicalKey;
    final p = _current;
    final rows = _scroll.hasClients ? (_scroll.position.viewportDimension / _rowHeight).floor() : 6;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_row == 0) return ZoneNavigator.move(TraversalDirection.up) ? KeyEventResult.handled : KeyEventResult.ignored;
      _move(() => _row--);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_row < widget.channels.length - 1) _move(() => _row++);
    } else if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp) {
      _move(() => _row = math.max(0, _row - rows));
    } else if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.channelDown) {
      _move(() => _row = math.min(widget.channels.length - 1, _row + rows));
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      final t = (p == null ? _cursor.subtract(_slot) : p.start.subtract(const Duration(minutes: 1)));
      if (t.isBefore(_earliest) || (p != null && !p.start.isAfter(_earliest))) {
        return ZoneNavigator.move(TraversalDirection.left) ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      _move(() {
        _cursor = t;
        if (_cursor.isBefore(_start)) _start = _floorSlot(_cursor);
      });
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final t = p == null ? _cursor.add(_slot) : p.end;
      if (!t.isBefore(_latest)) return KeyEventResult.handled;
      _move(() {
        _cursor = t.isBefore(_start) ? _start : t;
        final end = _start.add(_window);
        if (!_cursor.isBefore(end.subtract(_slot))) _start = _floorSlot(_cursor).subtract(_slot);
      });
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.gameButtonA) {
      if (e is! KeyRepeatEvent) widget.onPlay(widget.channels[_row]);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hm = DateFormat.Hm(l10n.localeName);
    return Focus(
      focusNode: _node,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth - _channelWidth;
        final perMinute = width / _window.inMinutes;
        double x(DateTime t) => t.difference(_start).inSeconds / 60 * perMinute;
        final nowX = x(widget.now);
        return Stack(children: [
          Column(children: [
            SizedBox(
              height: _headerHeight,
              child: Row(children: [
                SizedBox(
                  width: _channelWidth,
                  child: Text(DateFormat.MMMEd(l10n.localeName).format(_start),
                      style: Zt.caption.copyWith(fontSize: 17, color: Zc.textMuted)),
                ),
                Expanded(
                  child: Stack(clipBehavior: Clip.hardEdge, children: [
                    for (var t = _start; t.isBefore(_start.add(_window)); t = t.add(_slot))
                      Positioned(
                        left: x(t),
                        top: 0,
                        bottom: 0,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Center(
                            child: Text(hm.format(t), style: Zt.caption.copyWith(fontSize: 17, color: Zc.textMuted)),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _rowHeight,
                padding: const EdgeInsets.only(bottom: 40),
                itemCount: widget.channels.length,
                itemBuilder: (context, i) => _cachedRow(context, i, width, x, hm),
              ),
            ),
          ]),
          if (nowX >= 0 && nowX <= width)
            Positioned(
              left: _channelWidth + nowX - 1,
              top: _headerHeight - 8,
              bottom: 0,
              child: IgnorePointer(child: Container(width: 2, color: Zc.accent.withValues(alpha: 0.85))),
            ),
        ]);
      }),
    );
  }

  Widget _buildRow(BuildContext context, int i, double width, double Function(DateTime) x, DateFormat hm) {
    final l10n = context.l10n;
    final c = widget.channels[i];
    final end = _start.add(_window);
    final shown = _guide(c).where((p) => p.end.isAfter(_start) && p.start.isBefore(end)).toList();
    final cursorRow = i == _row;
    final current = cursorRow ? _current : null;

    Widget cell({required double left, required double right, required Widget child, required bool focused, bool on = false,
        VoidCallback? onTap}) {
      return Positioned(
        left: left,
        width: math.max(0, right - left),
        top: 0,
        bottom: 0,
        child: Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 6),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Zm.fast,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: focused ? Colors.white : (on ? Zc.surfaceHigh : Zc.surface),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: focused ? Zc.background : Zc.text),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    void tap(DateTime t) {
      _node.requestFocus();
      _move(() {
        _row = i;
        _cursor = t;
      });
      widget.onPlay(c);
    }

    return Row(children: [
      SizedBox(
        width: _channelWidth,
        child: Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 6),
          child: GestureDetector(
            onTap: () => tap(widget.now),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cursorRow && _focused ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                SizedBox(
                  width: 52,
                  child: Text(c.number?.toString() ?? '',
                      style: Zt.caption.copyWith(fontSize: 18, color: cursorRow ? Zc.text : Zc.textFaint)),
                ),
                ChannelLogo(name: c.name, logo: c.logo, width: 84, height: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.label.copyWith(fontSize: 17)),
                ),
              ]),
            ),
          ),
        ),
      ),
      Expanded(
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          if (shown.isEmpty)
            cell(
              left: 0,
              right: width,
              focused: cursorRow && _focused,
              onTap: () => tap(widget.now),
              child: Text(l10n.liveNoGuide,
                  style: Zt.caption.copyWith(fontSize: 17, color: cursorRow && _focused ? Zc.background : Zc.textMuted)),
            )
          else
            for (final p in shown)
              cell(
                left: math.max(0, x(p.start)),
                right: math.min(width, x(p.end)),
                focused: _focused && identical(p, current),
                on: p.isOn(widget.now),
                onTap: () => tap(p.start.isBefore(widget.now) ? widget.now : p.start),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Zt.label.copyWith(fontSize: 18, color: _focused && identical(p, current) ? Zc.background : Zc.text)),
                  if (x(p.end) - math.max(0, x(p.start)) > 150)
                    Text('${hm.format(p.start.toLocal())} – ${hm.format(p.end.toLocal())}',
                        maxLines: 1,
                        style: Zt.caption.copyWith(fontSize: 15, color: _focused && identical(p, current) ? Colors.black54 : Zc.textFaint)),
                ]),
              ),
        ]),
      ),
    ]);
  }
}
