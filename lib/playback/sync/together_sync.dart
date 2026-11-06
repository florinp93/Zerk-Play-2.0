import 'dart:async';

import '../../core/emby/models/emby_item.dart';
import '../../l10n/app_localizations.dart';
import '../player_backend.dart';
import 'watch_together.dart';

final class TogetherSync {
  TogetherSync({
    required this._room,
    required this._player,
    required this.l10n,
    required this.toast,
    required this.follow,
    required this.close,
  });

  final WatchTogether _room;
  final PlayerBackend _player;
  final L10n l10n;
  final void Function(String text, {RoomMember? who}) toast;

  final void Function(String itemId) follow;

  final void Function() close;

  StreamSubscription<RoomState>? _sub;
  Timer? _tick;

  String? _itemId;
  bool _loading = true;
  int _seenRev = -1;
  Map<String, RoomMember> _members = const {};

  bool? _ownPause;
  int _ownPauseUntil = 0;
  Duration? _ownSeek;
  int _ownSeekUntil = 0;
  double _speed = 1;

  Duration _lastPosition = Duration.zero;
  int _lastAt = 0;
  bool _lastPaused = false;
  bool _lastMoving = false;
  Timer? _notReady;

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  void start() {
    _sub = _room.updates.listen(_onRoom);
    _player.state.addListener(_onState);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _correct());
  }

  void dispose({bool stopRoom = false}) {
    unawaited(_sub?.cancel());
    _tick?.cancel();
    _notReady?.cancel();
    _player.state.removeListener(_onState);
    stopRoom ? _room.stop() : _room.unwatch();
  }

  Duration? startFor(EmbyItem item) {
    final r = _room.room;
    return r != null && r.itemId == item.id ? r.positionAt(_room.serverNow) : null;
  }

  void opening(EmbyItem item, {required String title, required Duration start}) {
    _itemId = item.id;
    _loading = true;
    _notReady?.cancel();
    _setSpeed(1);
    _room.watch(item.id, title: title, position: start);
  }

  void loaded() {
    _loading = false;
    final s = _player.state.value;
    _remember(s);
    final r = _room.room;
    if (r != null && r.itemId == _itemId) _apply(r, initial: true);
    _updateReady(s);
  }

  void _onRoom(RoomState r) {
    if (r.rev == _seenRev) return;
    _seenRev = r.rev;
    final previous = _members;
    _members = {for (final m in r.members) m.id: m};
    final mine = r.by == _room.me;
    final who = _members[r.by] ?? previous[r.by];
    String name(String? id) => (_members[id] ?? previous[id])?.name ?? l10n.togetherSomeone;

    if (r.action == 'stop' && r.itemId == null && !mine && _itemId != null) {
      toast(l10n.togetherStopped(name(r.by)), who: who);
      _itemId = null;
      close();
      return;
    }
    if (r.itemId != null && r.itemId != _itemId) {
      if (r.action == 'item' && !mine) {
        toast(l10n.togetherStarted(name(r.by), r.itemTitle ?? ''), who: who);
        r.live != null ? close() : follow(r.itemId!);
      }
      return;
    }
    if (!mine && r.by != null) {
      switch (r.action) {
        case 'pause':
          toast(l10n.togetherPaused(name(r.by)), who: who);
        case 'play':
          toast(l10n.togetherPlayed(name(r.by)), who: who);
        case 'seek':
          toast(l10n.togetherSeeked(name(r.by), _clock(r.positionAt(_room.serverNow))), who: who);
        case 'joined':
          toast(l10n.togetherJoined(name(r.by)), who: who);
        case 'left':
          toast(l10n.togetherLeft(name(r.by)), who: who);
      }
    }
    if (r.action == 'wait') {
      final others = [for (final m in r.waitingFor) if (m.id != _room.me) m.name];
      if (others.isNotEmpty) toast(l10n.togetherWaiting(others.join(', ')));
    }
    if (!_loading) _apply(r);
  }

  void _apply(RoomState r, {bool initial = false}) {
    final s = _player.state.value;
    final paused = !r.running;
    if (s.paused != paused) {
      _ownPause = paused;
      _ownPauseUntil = _now + 3000;
      _player.setPaused(paused);
    }
    final target = r.positionAt(_room.serverNow);
    final off = (s.position - target).abs();
    final limit = initial || paused || r.action == 'seek' ? 400 : 1500;
    if (off.inMilliseconds > limit) _seek(target);
  }

  void _seek(Duration target) {
    _ownSeek = target;
    _ownSeekUntil = _now + 10000;
    _player.seek(target);
  }

  void _setSpeed(double speed) {
    if (speed == _speed) return;
    _speed = speed;
    _player.setSpeed(speed);
  }

  void _correct() {
    final r = _room.room;
    final s = _player.state.value;
    if (r == null || r.itemId != _itemId || _loading || !r.running || s.paused || s.buffering) {
      _setSpeed(1);
      return;
    }
    final off = (s.position - r.positionAt(_room.serverNow)).inMilliseconds;
    final seekAt = _player.adjustsSpeed ? 2500 : 1000;
    if (off.abs() > seekAt) {
      if (_ownSeek != null && _now < _ownSeekUntil) return;
      _setSpeed(1);
      _seek(r.positionAt(_room.serverNow));
    } else if (!_player.adjustsSpeed) {
      return;
    } else if (off.abs() > 200) {
      _setSpeed(off > 0 ? 0.95 : 1.05);
    } else if (off.abs() < 60) {
      _setSpeed(1);
    }
  }

  void _onState() {
    if (_loading) return;
    final s = _player.state.value;
    final now = _now;

    if (s.paused != _lastPaused && !s.ended) {
      if (_ownPause == s.paused && now < _ownPauseUntil) {
        _ownPause = null;
      } else {
        _room.action(s.paused ? 'pause' : 'play', s.position);
      }
    }

    final moved = (s.position - _lastPosition).inMilliseconds;
    final expected = _lastMoving ? ((now - _lastAt) * _speed).round() : 0;
    if (moved < -1000 || moved > expected + 1500) {
      final own = _ownSeek;
      if (own != null && now < _ownSeekUntil && (s.position - own).inMilliseconds.abs() < 3000) {
        _ownSeek = null;
      } else {
        _room.action('seek', s.position);
      }
    }
    if (_ownSeek != null && now >= _ownSeekUntil) _ownSeek = null;

    _remember(s);
    _updateReady(s);
  }

  void _remember(PlayerState s) {
    _lastPosition = s.position;
    _lastAt = _now;
    _lastPaused = s.paused;
    _lastMoving = !s.paused && !s.buffering;
  }

  void _updateReady(PlayerState s) {
    if (!s.buffering) {
      _notReady?.cancel();
      _notReady = null;
      _room.ready(true);
    } else {
      _notReady ??= Timer(const Duration(milliseconds: 800), () {
        if (_player.state.value.buffering) _room.ready(false);
      });
    }
  }

  static String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}
