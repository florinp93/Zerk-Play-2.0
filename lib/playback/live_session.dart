import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/xtream/live_catalog.dart' show LiveChannel;
import '../data/xtream/xtream.dart';
import '../l10n/app_localizations.dart';
import 'player_backend.dart';
import 'player_settings.dart';

final class LiveSource {
  const LiveSource(this.label, this.streamId);

  final String label;

  final int streamId;
}

final class ZapList {
  const ZapList(this.channels, {required this.onNow});

  final List<LiveChannel> channels;

  final String? Function(LiveChannel channel) onNow;

  static List<LiveSource> sourcesOf(LiveChannel c) => [
        for (final s in c.sources) LiveSource(c.sources.length > 1 && s.label.isNotEmpty ? s.label : c.name, s.streamId),
      ];
}

final class LiveSession {
  LiveSession({
    required this._player,
    required this.server,
    required this.title,
    required this.sources,
    required this.settings,
    required this.l10n,
    this.zap,
    this._channel = 0,
  });

  final PlayerBackend _player;
  final XtreamServer server;

  String title;
  List<LiveSource> sources;
  final PlayerSettings settings;
  final L10n l10n;

  final ZapList? zap;
  int _channel;
  Timer? _lineupRefresh;

  final _done = Completer<void>();
  StreamSubscription<PlayerEvent>? _events;
  AccountStatus? _account;
  int _index = 0;
  int _failures = 0;
  bool _loading = false;
  bool _recovering = false;
  bool _finishing = false;
  String? _trackSignature;

  Future<void> run(int index) async {
    _events = _player.events.listen(_onEvent);
    _player.state.addListener(_onState);
    await _player.open();
    _player.osd('config', {
      'seekStep': settings.seekStepSeconds,
      'autoSkipIntro': false,
      'versionsTitle': l10n.liveChannels,
      'zap': zap != null,
    });
    if (zap != null) _lineupRefresh = Timer.periodic(const Duration(minutes: 2), (_) => _sendLinks());
    _player.osd('next', null);
    _player.osd('segments', <String, Object?>{});
    unawaited(_play(index));
    return _done.future;
  }

  Future<void> _play(int index) async {
    _index = index;
    _loading = true;
    _trackSignature = null;
    _sendLinks();
    _state('loading');
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
      case PlayerLoadError(:final message):
        unawaited(_recover(message));
      case PlayerOsdEvent(:final name, :final arg):
        switch (name) {
          case 'back':
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
              unawaited(_play(i));
            }
          case 'audio':
            _player.selectTrack('audio', arg);
          case 'sub':
            _player.selectTrack('sub', arg == '-1' ? null : arg);
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
      final current = _account;
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
    if (step != 0) _zapTo((_channel + step) % channels.length);
  }

  void _zapTo(int i) {
    final channels = zap!.channels;
    if (i < 0 || i >= channels.length) return;
    final c = channels[i];
    _channel = i;
    title = c.name;
    sources = ZapList.sourcesOf(c);
    _failures = 0;
    unawaited(_play(0));
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _lineupRefresh?.cancel();
    await _events?.cancel();
    _player.state.removeListener(_onState);
    await _player.close();
    final account = _account;
    if (account != null) AccountPool.release(account.account);
    if (!_done.isCompleted) _done.complete();
  }
}
