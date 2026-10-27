import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:intl/intl.dart';

import '../../app/app_services.dart';
import '../../data/emby_live_tv.dart';
import '../../l10n/l10n.dart';
import '../core/playback_launcher.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/live_loaders.dart';
import '../widgets/media_row.dart' show contentLeft;
import '../widgets/net_image.dart';

class EmbyLiveTvPage extends StatefulWidget {
  const EmbyLiveTvPage({super.key});

  @override
  State<EmbyLiveTvPage> createState() => _EmbyLiveTvPageState();
}

class _EmbyLiveTvPageState extends State<EmbyLiveTvPage> {
  List<TvChannel>? _channels;
  int _total = 0;
  bool _loadingMore = false;
  Object? _error;
  TvChannel? _focused;
  final _guides = <String, Future<List<TvProgram>>>{};
  Timer? _tick;
  Timer? _focusDebounce;
  DateTime _loadedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loading = false;

  EmbyLiveTv get _tv => AppServicesScope.read(context).embyLiveTv;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final stale = _channels?.any((c) => c.current != null && !c.current!.end.isAfter(now)) ?? false;
      if (stale && now.difference(_loadedAt) > const Duration(minutes: 2)) unawaited(_load());
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _focusDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    _loadedAt = DateTime.now();
    try {
      final page = await _tv.channels(limit: (_channels?.length ?? 0).clamp(300, 3000));
      if (!mounted) return;
      setState(() {
        _channels = page.channels;
        _total = page.total;
        _error = null;
        final channels = page.channels;
        _guides.clear();
        if (_focused != null) _focused = channels.where((c) => c.id == _focused!.id).firstOrNull;
      });
    } catch (e) {
      debugPrint('[livetv] channels: $e');
      if (mounted && _channels == null) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadMore() async {
    final have = _channels;
    if (have == null || _loadingMore || _loading || have.length >= _total) return;
    _loadingMore = true;
    try {
      final page = await _tv.channels(start: have.length);
      if (!mounted || _channels != have) return;
      setState(() {
        _channels = [...have, ...page.channels];
        _total = page.total;
      });
    } catch (e) {
      debugPrint('[livetv] more channels: $e');
    } finally {
      _loadingMore = false;
    }
  }

  Future<List<TvProgram>> _guide(TvChannel c) => _guides[c.id] ??= _tv.guide(c.id).catchError((Object e) {
        debugPrint('[livetv] guide of ${c.name}: $e');
        _guides.remove(c.id);
        return <TvProgram>[];
      });

  void _onFocus(TvChannel c) {
    _focusDebounce?.cancel();
    _focusDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted && _focused?.id != c.id) setState(() => _focused = c);
    });
  }

  Future<void> _play(TvChannel c) async {
    debugPrint('[livetv] playing ${c.name} (${c.id})');
    await playItem(context, c.asItem());
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final channels = _channels;
    if (channels == null) {
      if (_error == null) return const LiveTvLoader();
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.liveLoadFailed('$_error'), style: Zt.body, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FocusZone(
            child: TvButton(
              label: l10n.tryAgain,
              icon: Icons.refresh_rounded,
              autofocus: true,
              onSelect: () {
                setState(() => _error = null);
                unawaited(_load());
              },
            ),
          ),
        ]),
      );
    }
    if (channels.isEmpty) return Center(child: Text(l10n.liveNoChannels, style: Zt.body));
    final focused = _focused ?? channels.first;
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(left: contentLeft, top: 70, right: 56),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(l10n.liveTv, style: Zt.headline),
          const SizedBox(width: 18),
          Text('$_total', style: Zt.title.copyWith(color: Zc.textFaint)),
        ]),
        const SizedBox(height: 24),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: FocusZone(
                debugLabel: 'emby-channels',
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 120),
                  scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
                  itemCount: channels.length,
                  itemBuilder: (context, i) {
                    if (i > channels.length - 60) unawaited(_loadMore());
                    final c = channels[i];
                    return _ChannelRow(
                      channel: c,
                      logo: _tv.logo(c),
                      now: now,
                      autofocus: i == 0,
                      onFocus: () => _onFocus(c),
                      onSelect: () => _play(c),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 36),
            SizedBox(
              width: 500,
              child: _Schedule(
                key: ValueKey(focused.id),
                channel: focused,
                logo: _tv.logo(focused),
                guide: _guide(focused),
                now: now,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.channel, required this.url, this.width = 110, this.height = 76});

  final TvChannel channel;
  final Uri? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final words = channel.name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Zc.surfaceTop, borderRadius: BorderRadius.circular(10)),
      child: NetImage(
        url: url,
        width: width,
        fit: BoxFit.contain,
        fallback: Center(child: Text(initials, style: Zt.label.copyWith(color: Zc.textMuted))),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.logo,
    required this.now,
    required this.onFocus,
    required this.onSelect,
    this.autofocus = false,
  });

  final TvChannel channel;
  final Uri? logo;
  final DateTime now;
  final VoidCallback onFocus;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hm = DateFormat.Hm(l10n.localeName);
    final current = channel.current != null && channel.current!.isOn(now) ? channel.current : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        autofocus: autofocus,
        onFocusChange: (f) => f ? onFocus() : null,
        onSelect: onSelect,
        builder: (context, focused) {
          final fg = focused ? Zc.background : Zc.text;
          final muted = focused ? Colors.black54 : Zc.textFaint;
          return AnimatedContainer(
            duration: Zm.fast,
            height: 104,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: focused ? Colors.white : Zc.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              SizedBox(
                width: 58,
                child: Text(channel.number ?? '', style: Zt.label.copyWith(fontSize: 20, color: muted)),
              ),
              _Logo(channel: channel, url: logo),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.label.copyWith(fontSize: 22, color: fg)),
                  const SizedBox(height: 6),
                  Text(
                    current == null ? l10n.liveNoGuide : '${hm.format(current.start)}  ${current.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Zt.caption.copyWith(fontSize: 18, color: focused ? Colors.black87 : Zc.textMuted),
                  ),
                  if (current != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: current.progress(now),
                        minHeight: 4,
                        backgroundColor: focused ? Colors.black12 : Colors.white12,
                        color: Zc.accent,
                      ),
                    ),
                  ],
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Schedule extends StatelessWidget {
  const _Schedule({super.key, required this.channel, required this.logo, required this.guide, required this.now});

  final TvChannel channel;
  final Uri? logo;
  final Future<List<TvProgram>> guide;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hm = DateFormat.Hm(l10n.localeName);
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(color: Zc.surface, borderRadius: BorderRadius.circular(Zs.radiusLarge)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Logo(channel: channel, url: logo, width: 96, height: 64),
          const SizedBox(width: 16),
          Expanded(child: Text(channel.name, maxLines: 2, style: Zt.label.copyWith(fontSize: 22))),
        ]),
        const SizedBox(height: 22),
        Flexible(
          child: FutureBuilder<List<TvProgram>>(
            future: guide,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
                );
              }
              final upcoming = snap.data!.where((p) => p.end.isAfter(now)).take(16).toList();
              if (upcoming.isEmpty) return Text(l10n.liveNoGuide, style: Zt.caption);
              return ListView(padding: EdgeInsets.zero, children: [
                for (final (i, p) in upcoming.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 64,
                        child: Text(hm.format(p.start),
                            style: Zt.caption.copyWith(fontSize: 18, color: p.isOn(now) ? Zc.accentSoft : Zc.textFaint)),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            p.episodeTitle == null ? p.title : '${p.title} · ${p.episodeTitle}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Zt.label.copyWith(fontSize: 18, color: p.isOn(now) ? Zc.text : Zc.textMuted),
                          ),
                          if (i == 0 && p.overview != null) ...[
                            const SizedBox(height: 6),
                            Text(p.overview!, maxLines: 4, overflow: TextOverflow.ellipsis, style: Zt.caption.copyWith(fontSize: 16)),
                          ],
                        ]),
                      ),
                    ]),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
