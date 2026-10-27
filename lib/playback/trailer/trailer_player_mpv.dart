import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/host.dart';
import '../mpv/mpv_player.dart';
import 'chunked_proxy.dart';
import 'trailer_player.dart';
import 'trailers.dart';

bool get trailersSupported => Host.isWindows;

Future<TrailerPlayer?> createTrailerPlayer({required Size renderSize, required bool acceptInvalidCertificates}) async {
  try {
    return await _MpvTrailerPlayer.create(renderSize, acceptInvalidCertificates);
  } catch (e) {
    debugPrint('[trailer] player: $e');
    return null;
  }
}

const _channel = MethodChannel('zerk/trailer');

final class _MpvTrailerPlayer extends TrailerPlayer {
  _MpvTrailerPlayer._(this._mpv, this._textureId) {
    _state.value = TrailerState(textureId: _textureId);
    _mpv.state.addListener(_onMpvState);
    _events = _mpv.events.listen(_onEvent);
  }

  final MpvPlayer _mpv;
  final int _textureId;
  final _state = ValueNotifier(const TrailerState());
  late final StreamSubscription<MpvEvent> _events;
  Completer<bool>? _opening;
  bool _disposed = false;

  @override
  ValueListenable<TrailerState> get state => _state;

  static Future<_MpvTrailerPlayer> create(Size size, bool acceptInvalidCertificates) async {
    final mpv = MpvPlayer.create(options: {
      'vo': 'libmpv',
      'config': 'no',
      'load-scripts': 'no',
      'osc': 'no',
      'ytdl': 'no',
      'input-default-bindings': 'no',
      'input-builtin-bindings': 'no',
      'osd-level': '0',
      'idle': 'yes',
      'keep-open': 'yes',
      'hwdec': 'auto-copy',
      'panscan': '1.0',
      'sub-auto': 'no',
      'audio-file-auto': 'no',
      'cache': 'yes',
      'demuxer-max-bytes': '64MiB',
      'network-timeout': '15',
      'tls-verify': acceptInvalidCertificates ? 'no' : 'yes',
      'audio-display': 'no',
      'volume': '100',
      'mute': 'yes',
      'msg-level': 'ffmpeg=error',
    });
    try {
      final (w, h) = _pixels(size);
      final id = await _channel.invokeMethod<int>('create', {'handle': mpv.address, 'width': w, 'height': h});
      return _MpvTrailerPlayer._(mpv, id!);
    } catch (_) {
      mpv.dispose();
      rethrow;
    }
  }

  static (int, int) _pixels(Size s) {
    if (s.isEmpty) return (1280, 720);
    final scale = [1.0, 1280 / s.width, 720 / s.height].reduce((a, b) => a < b ? a : b);
    return ((s.width * scale).round(), (s.height * scale).round());
  }

  @override
  Future<bool> open(TrailerStream trailer, {required bool muted}) async {
    if (_disposed) return false;
    _opening?.complete(false);
    final opening = _opening = Completer<bool>();
    final proxy = await ChunkedProxy.instance;
    if (_disposed || !identical(_opening, opening)) return false;
    final video = proxy.wrap(trailer.video);
    final audio = trailer.audio == null ? null : proxy.wrap(trailer.audio!);
    _state.value = TrailerState(textureId: _textureId, muted: muted);
    _mpv.setProperty('mute', muted ? 'yes' : 'no');
    _mpv.setProperty('pause', 'no');
    final opts = [if (audio != null) 'audio-file=${_quoted(audio.toString())}'];
    _mpv.command(['loadfile', video.toString(), 'replace', '-1', opts.join(',')]);
    return opening.future.timeout(const Duration(seconds: 20), onTimeout: () {
      if (identical(_opening, opening)) _opening = null;
      _state.value = _state.value.copyWith(failed: true);
      _mpv.command(['stop']);
      return false;
    });
  }

  static String _quoted(String s) => '%${utf8.encode(s).length}%$s';

  @override
  void setMuted(bool muted) {
    _mpv.setProperty('mute', muted ? 'yes' : 'no');
    _state.value = _state.value.copyWith(muted: muted);
  }

  @override
  void setPaused(bool paused) => _mpv.setProperty('pause', paused ? 'yes' : 'no');

  @override
  void seekBy(Duration offset) => _mpv.commandAsync(['seek', '${offset.inMilliseconds / 1000}', 'relative', 'exact']);

  @override
  void restart() {
    _mpv.commandAsync(['seek', '0', 'absolute']);
    _mpv.setProperty('pause', 'no');
    _state.value = _state.value.copyWith(ended: false);
  }

  @override
  void setCover(bool cover) => _mpv.setProperty('panscan', cover ? '1.0' : '0.0');

  @override
  void setRenderSize(Size size) {
    if (_disposed) return;
    final (w, h) = _pixels(size);
    _channel.invokeMethod('resize', {'id': _textureId, 'width': w, 'height': h});
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _opening?.complete(false);
    _opening = null;
    _mpv.command(['stop']);
    _state.value = TrailerState(textureId: _textureId, muted: _state.value.muted);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await super.dispose();
    _opening?.complete(false);
    _opening = null;
    _mpv.command(['stop']);
    await _events.cancel();
    _mpv.state.removeListener(_onMpvState);
    try {
      await _channel.invokeMethod('dispose', {'id': _textureId});
    } catch (e) {
      debugPrint('[trailer] dispose texture: $e');
    }
    _mpv.dispose();
    _state.dispose();
  }

  void _onEvent(MpvEvent e) {
    switch (e) {
      case MpvPlaybackRestart():
        if (!_state.value.ready) _state.value = _state.value.copyWith(ready: true);
        _opening?.complete(true);
        _opening = null;
      case MpvEndFile(:final error) when error != null:
        debugPrint('[trailer] playback failed: $error');
        _state.value = _state.value.copyWith(failed: true, ready: false);
        _opening?.complete(false);
        _opening = null;
      default:
    }
  }

  void _onMpvState() {
    if (_disposed) return;
    final m = _mpv.state.value;
    _state.value = _state.value.copyWith(
      paused: m.paused,
      ended: m.eofReached && _state.value.ready,
      position: m.position,
      duration: m.duration,
    );
  }
}
