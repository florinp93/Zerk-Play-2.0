import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/xtream/live_catalog.dart' show LiveChannel;
import '../data/xtream/xtream.dart';
import '../l10n/app_localizations.dart';
import 'player_backend.dart';
import 'player_settings.dart';
import 'subtitle_style.dart';
import 'sync/watch_together.dart';

final class LiveSource {
  const LiveSource(this.label, this.streamId, [this.url]);

  final String label;

  final int streamId;

  final String? url;
}

final class ZapList {
  const ZapList(this.channels, {required this.onNow});

  final List<LiveChannel> channels;

  final String? Function(LiveChannel channel) onNow;

  static List<LiveSource> sourcesOf(LiveChannel c) => [
        for (final s in c.sources) LiveSource(c.sources.length > 1 && s.label.isNotEmpty ? s.label : c.name, s.streamId, s.url),
      ];
}

final class LiveShare {
  const LiveShare({required this.key, required this.title, required this.sources, this.first = 0});

  final String key;
  final String title;
  final List<LiveSource> sources;

  final int first;

  static String keyOf(LiveSource s) => 'live:channel:${s.url == null ? s.streamId : s.url!.hashCode.toUnsigned(32)}';

  Map<String, Object?> toJson() => {
        'title': title,
        'first': first,
        'sources': [for (final s in sources) [s.label, s.streamId, ?s.url]],
      };

  static LiveShare? fromRoom(RoomState r) {
    final j = r.live;
    final key = r.itemId;
    if (j == null || key == null) return null;
    final sources = [
      for (final s in (j['sources'] as List? ?? const []).whereType<List>())
        if (s.length >= 2 && s[1] is num) LiveSource('${s[0]}', (s[1] as num).toInt(), s.length > 2 && s[2] is String ? s[2] as String : null),
    ];
    if (sources.isEmpty) return null;
    return LiveShare(
      key: key,
      title: j['title'] as String? ?? r.itemTitle ?? '',
      sources: sources,
      first: ((j['first'] as num?)?.toInt() ?? 0).clamp(0, sources.length - 1),
    );
  }
}

final class LiveSession {
  LiveSession({
    required this._player,
    required this.server,
    required this.title,
    required this.sources,
    required this.settings,
    required this.l10n,
    this.together,
    this.share,
    this.zap,
    this._channel = 0,
  });

  final PlayerBackend _player;
  final XtreamServer server;

  String title;
  List<LiveSource> sources;
  final PlayerSettings settings;
  final L10n l10n;

  final WatchTogether? together;
  LiveShare? share;

  final ZapList? zap;
  int _channel;
  Timer? _lineupRefresh;
  Timer? _zapTimer;
  int? _pending;

  final _done = Completer<void>();
  StreamSubscription<PlayerEvent>? _events;
  AccountStatus? _account;
  int _index = 0;
  int _failures = 0;
  bool _loading = false;
  bool _recovering = false;
  bool _finishing = false;
  String? _trackSignature;
  StreamSubscription<RoomState>? _roomSub;
  bool _userExit = false;
  bool _closedByRoom = false;

  Future<void> run(int index) async {
    _events = _player.events.listen(_onEvent);
    _player.state.addListener(_onState);
    await _player.open();
    _player.osd('config', {
      'seekForward': settings.seekForwardSeconds,
      'seekBack': settings.seekBackSeconds,
      'scope': settings.scopeScreen,
      'anamorphic': settings.anamorphic,
      'autoSkipIntro': false,
      'versionsTitle': l10n.liveChannels,
      'zap': zap != null,
    });
    if (zap != null) _lineupRefresh = Timer.periodic(const Duration(minutes: 2), (_) => _sendLinks());
    _player.osd('next', null);
    _player.osd('segments', <String, Object?>{});
    final room = together, item = share;
    if (room != null && room.room != null && item != null) {
      room.watch(item.key, title: title, position: Duration.zero, live: item.toJson());
      _roomSub = room.updates.listen(_onRoom);
    }
    unawaited(_play(index));
    return _done.future;
  }

  Future<void> _play(int index) async {
    _index = index;
    _loading = true;
    _trackSignature = null;
    _sendLinks();
    _state('loading');
    final url = sources[index].url;
    if (url != null) {
      _player.load(Uri.parse(url));
      return;
    }
    var account = _account;
    if (account == null) {
      try {
        account = _account = await AccountPool.pick(server);
      } on AccountsBusy catch (e) {
        _loading = false;
        _state('error', message: _busyMessage(e));
        return;
      }
    }
    if (_finishing) return;
    _state('loading');
    _player.load(server.stream(account.account, sources[index].streamId));
  }

  void _onEvent(PlayerEvent e) {
    switch (e) {
      case PlayerLoaded():
        _loading = false;
        _failures = 0;
        _state('playing');
        together?.ready(true);
      case PlayerLoadError(:final message):
        unawaited(_recover(message));
      case PlayerOsdEvent(:final name, :final arg):
        switch (name) {
          case 'back':
            _userExit = true;
            unawaited(_finish());
          case 'version' when zap != null:
            final i = int.tryParse(arg ?? '');
            if (i != null) _zapTo(i);
          case 'channel' when zap != null:
            _zapBy(arg ?? '');
          case 'version':
            final i = int.tryParse(arg ?? '');
            if (i != null && i >= 0 && i < sources.length) {
              _failures = 0;
              if (share != null) together?.liveSource(i);
              unawaited(_play(i));
            }
          case 'audio':
            _player.selectTrack('audio', arg);
          case 'sub':
            _player.selectTrack('sub', arg == '-1' ? null : arg);
          case 'subscale-preview':
            SubtitleStyle.applyScale(_player, arg);
          case 'subscale':
            SubtitleStyle.applyScale(_player, arg, save: true);
        }
      case PlayerShutdown():
        unawaited(_finish());
    }
  }

  Future<void> _recover(String? message) async {
    if (_recovering || _finishing) return;
    _recovering = true;
    try {
      debugPrint('[live] ${sources[_index].label}: $message');
      final current = sources[_index].url == null ? _account : null;
      if (current != null) {
        final now = await server.status(current.account);
        if (_finishing) return;
        if (!now.free) {
          try {
            final next = _account = await AccountPool.pick(server, avoid: {current.account});
            _player.osd('toast', l10n.liveSwitchingAccount(next.number));
            await _play(_index);
            return;
          } on AccountsBusy catch (e) {
            _account = null;
            _loading = false;
            _state('error', message: _busyMessage(e));
            return;
          }
        }
      }
      if (++_failures < sources.length) {
        _player.osd('toast', l10n.liveLinkFailed(sources[_index].label));
        await _play((_index + 1) % sources.length);
      } else {
        _loading = false;
        _state('error', message: l10n.couldNotPlayVideo(message ?? l10n.unknownError));
      }
    } finally {
      _recovering = false;
    }
  }

  String _busyMessage(AccountsBusy e) {
    final broken = e.statuses.where((s) => !s.usable).toList();
    if (broken.isEmpty || broken.length < e.statuses.length) return l10n.liveAllAccountsBusy;
    return broken.map((s) => l10n.xtreamAccountProblem(s.number, s.problem!)).join('  ·  ');
  }

  void _onState() {
    final s = _player.state.value;
    if (s.ended && !_loading) {
      _loading = true;
      unawaited(_recover('stream ended'));
    }
    final tracks = s.tracks;
    final signature = tracks.map((t) => '${t.id}${t.selected}').join();
    if (signature == _trackSignature) return;
    _trackSignature = signature;
    List<Map<String, Object?>> of(String type, String label) {
      final list = tracks.where((t) => t.type == type && !t.external).toList();
      return [
        for (final (i, t) in list.indexed) {'id': t.id, 'label': '$label ${i + 1}', 'detail': '', 'selected': t.selected},
      ];
    }

    _player.osd('tracks', {'audio': of('audio', l10n.audio), 'subs': of('sub', l10n.subtitles)});
  }

  void _state(String phase, {String? message}) {
    final account = _account;
    final channel = zap?.channels[_channel];
    _player.osd('state', {
      'phase': phase,
      'title': channel?.number == null ? title : '${channel!.number}  $title',
      'subtitle': [
        if (channel != null) ?zap!.onNow(channel) else sources[_index].label,
        if (account != null && server.accounts.length > 1) l10n.liveAccount(account.number),
      ].join('  ·  '),
      'message': ?message,
    });
  }

  void _sendLinks() {
    final z = zap;
    _player.osd('versions', [
      if (z != null)
        for (final (i, c) in z.channels.indexed)
          {
            'id': i,
            'label': c.number == null ? c.name : '${c.number}   ${c.name}',
            'detail': z.onNow(c) ?? '',
            'selected': i == _channel,
          }
      else if (sources.length > 1)
        for (final (i, s) in sources.indexed) {'id': i, 'label': s.label, 'detail': '', 'selected': i == _index},
    ]);
  }

  void _zapBy(String arg) {
    final channels = zap!.channels;
    if (arg.startsWith('n:')) {
      final n = int.tryParse(arg.substring(2));
      final i = channels.indexWhere((c) => c.number == n);
      if (i < 0) {
        _player.osd('toast', l10n.liveNoChannelNumber(arg.substring(2)));
      } else {
        _zapTo(i);
      }
      return;
    }
    final step = int.tryParse(arg.replaceFirst('+', '')) ?? 0;
    if (step == 0) return;
    final target = ((_pending ?? _channel) + step) % channels.length;
    _pending = target;
    final c = channels[target];
    _player.osd('toast', [
      c.number == null ? c.name : '${c.number}   ${c.name}',
      ?zap!.onNow(c),
    ].join('  ·  '));
    _zapTimer?.cancel();
    _zapTimer = Timer(const Duration(milliseconds: 900), () {
      final i = _pending;
      _pending = null;
      if (i != null && i != _channel && !_finishing) _zapTo(i);
    });
  }

  void _zapTo(int i) {
    final channels = zap!.channels;
    if (i < 0 || i >= channels.length) return;
    _zapTimer?.cancel();
    _pending = null;
    final c = channels[i];
    _channel = i;
    title = c.name;
    sources = ZapList.sourcesOf(c);
    _failures = 0;
    final room = together;
    if (room != null && room.room != null && share != null) {
      final item = share = LiveShare(key: LiveShare.keyOf(sources.first), title: title, sources: sources);
      room.watch(item.key, title: title, position: Duration.zero, live: item.toJson());
    }
    unawaited(_play(0));
  }

  void _onRoom(RoomState r) {
    final room = together, item = share;
    if (room == null || item == null || r.by == null || r.by == room.me || _finishing) return;
    String name() => r.member(r.by)?.name ?? l10n.togetherSomeone;
    final stopped = r.action == 'stop' && r.itemId == null;
    final switched = r.action == 'item' && r.itemId != null && r.itemId != item.key;
    if (r.action == 'source' && r.itemId == item.key) {
      final i = (r.live?['first'] as num?)?.toInt();
      if (i == null || i < 0 || i >= sources.length || i == _index) return;
      _player.osd('toast', l10n.togetherSwitched(name(), sources[i].label));
      _failures = 0;
      unawaited(_play(i));
      return;
    }
    if (!stopped && !switched) return;
    _player.osd('toast', stopped ? l10n.togetherStopped(name()) : l10n.togetherStarted(name(), r.itemTitle ?? ''));
    _closedByRoom = true;
    Timer(const Duration(milliseconds: 1500), () => unawaited(_finish()));
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _lineupRefresh?.cancel();
    _zapTimer?.cancel();
    await _roomSub?.cancel();
    if (share != null) {
      _userExit && !_closedByRoom ? together?.stop() : together?.unwatch();
    }
    await _events?.cancel();
    _player.state.removeListener(_onState);
    await _player.close();
    final account = _account;
    if (account != null) AccountPool.release(account.account);
    if (!_done.isCompleted) _done.complete();
  }
}
