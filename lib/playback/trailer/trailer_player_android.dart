import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chunked_proxy.dart';
import 'trailer_player.dart';
import 'trailers.dart';

const _channel = MethodChannel('zerk/trailer');

final _players = <int, _AndroidTrailerPlayer>{};

Future<TrailerPlayer> createAndroidTrailerPlayer({required Size renderSize}) async {
  _channel.setMethodCallHandler(_onNative);
  final size = renderSize.isEmpty ? const Size(1280, 720) : renderSize;
  final id = await _channel.invokeMethod<int>('create', {'width': size.width.round(), 'height': size.height.round()});
  return _players[id!] = _AndroidTrailerPlayer._(id);
}

Future<void> _onNative(MethodCall call) async {
  if (call.method != 'state') return;
  final m = (call.arguments as Map).cast<String, Object?>();
  _players[(m['id'] as num).toInt()]?._onState(m);
}

final class _AndroidTrailerPlayer extends TrailerPlayer {
  _AndroidTrailerPlayer._(this._id) {
    _state.value = TrailerState(textureId: _id);
  }

  final int _id;
  final _state = ValueNotifier(const TrailerState());
  Completer<bool>? _opening;
  bool _disposed = false;

  @override
  ValueListenable<TrailerState> get state => _state;

  Future<void> _call(String method, [Map<String, Object?> args = const {}]) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod(method, {'id': _id, ...args});
    } catch (e) {
      debugPrint('[trailer] $method: $e');
    }
  }

  @override
  Future<bool> open(TrailerStream trailer, {required bool muted}) async {
    if (_disposed) return false;
    _opening?.complete(false);
    final opening = _opening = Completer<bool>();
    final proxy = await ChunkedProxy.instance;
    if (_disposed || !identical(_opening, opening)) return false;
    _state.value = TrailerState(textureId: _id, muted: muted);
    await _call('open', {
      'video': proxy.wrap(trailer.video).toString(),
      'audio': trailer.audio == null ? null : proxy.wrap(trailer.audio!).toString(),
      'muted': muted,
    });
    return opening.future.timeout(const Duration(seconds: 20), onTimeout: () {
      if (identical(_opening, opening)) _opening = null;
      _state.value = _state.value.copyWith(failed: true);
      unawaited(_call('stop'));
      return false;
    });
  }

  void _onState(Map<String, Object?> m) {
    if (_disposed) return;
    final ready = m['ready'] == true;
    final failed = m['failed'] == true;
    _state.value = _state.value.copyWith(
      ready: ready,
      failed: failed || _state.value.failed,
      ended: m['ended'] == true && ready,
      paused: m['paused'] == true,
      position: Duration(milliseconds: (m['position'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0),
    );
    if (ready || failed) {
      _opening?.complete(ready);
      _opening = null;
    }
  }

  @override
  void setMuted(bool muted) {
    unawaited(_call('muted', {'muted': muted}));
    _state.value = _state.value.copyWith(muted: muted);
  }

  @override
  void setPaused(bool paused) => unawaited(_call('paused', {'paused': paused}));

  @override
  void seekBy(Duration offset) => unawaited(_call('seekBy', {'ms': offset.inMilliseconds}));

  @override
  void restart() {
    unawaited(_call('restart'));
    _state.value = _state.value.copyWith(ended: false);
  }

  @override
  void setCover(bool cover) {}

  @override
  void setRenderSize(Size size) {}

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _opening?.complete(false);
    _opening = null;
    _state.value = TrailerState(textureId: _id, muted: _state.value.muted);
    await _call('stop');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await super.dispose();
    _opening?.complete(false);
    _opening = null;
    await _call('dispose');
    _disposed = true;
    _players.remove(_id);
    _state.dispose();
  }
}
