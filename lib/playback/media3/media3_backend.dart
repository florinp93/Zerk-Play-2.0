import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/windows/native_window.dart' show DisplayHdrStatus;
import '../../ui/core/tv_scale.dart';
import '../../ui/player/player_osd.dart';
import '../device_profile.dart' show androidEncodesAc3;
import '../player_backend.dart';
import '../player_settings.dart';
import '../subtitle_style.dart';
import 'device_caps.dart';
import 'osd_model.dart';

final class Media3Backend implements PlayerBackend {
  Media3Backend({required this._navigator, required this._settings});

  static const _channel = MethodChannel('zerk/player');
  static const _eventChannel = EventChannel('zerk/player/events');

  final NavigatorState _navigator;
  PlayerSettings _settings;
  final _state = ValueNotifier(const PlayerState());
  final _events = StreamController<PlayerEvent>.broadcast(sync: true);
  late final OsdModel _osd = OsdModel(
    state: _state,
    send: (name, [arg]) => _events.add(PlayerOsdEvent(name, arg)),
    togglePause: () => _call('togglePause'),
    seekTo: (position) => _call('seekTo', {'ms': position.inMilliseconds}),
  )..subtitleScale = _settings.subtitleScale;
  StreamSubscription<Object?>? _sub;
  Route<void>? _route;

  @override
  ValueListenable<PlayerState> get state => _state;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  bool get selectsFileTracks => true;

  @override
  bool get streamSubtitles => true;

  @override
  String? get textSubtitleFormat => null;

  @override
  void setPaused(bool paused) => _call(paused ? 'pause' : 'play');

  @override
  void seek(Duration position) => _call('seekTo', {'ms': position.inMilliseconds});

  @override
  bool get adjustsSpeed => false;

  @override
  void setSpeed(double speed) {}

  @override
  Future<void> open() async {
    _sub = _eventChannel.receiveBroadcastStream().listen(_onNative, onError: (Object e) {
      debugPrint('[media3] event channel: $e');
    });
    final caps = await AndroidDeviceCaps.get();
    await _channel.invokeMethod('open', {
      'subtitleStyle': SubtitleStyle.androidStyle(_settings),
      'passthrough': [for (final c in _settings.passthrough) c.name],
      'encodeAc3': androidEncodesAc3(caps, _settings.passthrough),
    });
    _osd.subtitleLift.addListener(_liftSubtitles);
    TvScale.videoUnderlay.value = true;
    final route = PlayerOsdRoute(model: _osd);
    _route = route;
    unawaited(_navigator.push(route));
  }

  @override
  void load(Uri url, {Duration? start, int? audioOrdinal, int? subtitleOrdinal, String? dolbyVision}) {
    _state.value = const PlayerState();
    _call('load', {
      'url': url.toString(),
      'startMs': start?.inMilliseconds ?? 0,
      'audio': audioOrdinal,
      'sub': subtitleOrdinal,
      'dolbyVision': dolbyVision,
    });
  }

  @override
  void selectTrack(String type, String? id) => _call('selectTrack', {'type': type, 'id': id});

  @override
  void addSubtitle(Uri url, {required String format, required String title, String? language}) =>
      _call('addSubtitle', {'url': url.toString(), 'format': format, 'title': title, 'language': language});

  @override
  void osd(String command, Object? data) => _osd.handle(command, data);

  @override
  void setSubtitleScale(double scale) {
    _settings = _settings.copyWith(subtitleScale: scale);
    _osd.subtitleScale = scale;
    _call('subtitleStyle', {'style': SubtitleStyle.androidStyle(_settings)});
  }

  @override
  double? matchRefreshRate(double fps) => null;

  @override
  Future<DisplayHdrStatus> displayHdr() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('displayHdr');
      return DisplayHdrStatus(supported: m?['supported'] == true, enabled: m?['enabled'] == true);
    } on PlatformException {
      return const DisplayHdrStatus();
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    final route = _route;
    _route = null;
    if (route != null && route.isActive) _navigator.removeRoute(route);
    TvScale.videoUnderlay.value = false;
    _osd.subtitleLift.removeListener(_liftSubtitles);
    await _channel.invokeMethod('close');
    _osd.dispose();
    await _events.close();
  }

  void _liftSubtitles() => _call('subtitleLift', {'fraction': _osd.subtitleLift.value});

  void _call(String method, [Map<String, Object?>? args]) {
    _channel.invokeMethod(method, args).catchError((Object e) {
      debugPrint('[media3] $method failed: $e');
      return null;
    });
  }

  void _onNative(Object? raw) {
    if (raw is! Map || _events.isClosed) return;
    switch (raw['event']) {
      case 'state':
        _state.value = _parseState(raw);
      case 'loaded':
        _events.add(const PlayerLoaded());
      case 'error':
        _events.add(PlayerLoadError(raw['message'] as String?));
    }
  }

  static PlayerState _parseState(Map<Object?, Object?> m) {
    Duration ms(Object? v) => Duration(milliseconds: (v as num?)?.toInt() ?? 0);
    return PlayerState(
      position: ms(m['position']),
      duration: ms(m['duration']),
      paused: m['paused'] == true,
      buffering: m['buffering'] == true,
      ended: m['ended'] == true,
      volume: (m['volume'] as num?)?.toDouble() ?? 100,
      videoTransfer: m['transfer'] as String?,
      dolbyVision: m['dolbyVision'] == true,
      fps: (m['fps'] as num?)?.toDouble(),
      tracks: [
        for (final t in (m['tracks'] as List? ?? const []).cast<Map<Object?, Object?>>())
          PlayerTrack(
            id: t['id'] as String,
            type: t['type'] as String,
            ordinal: t['ordinal'] as int?,
            ffIndex: t['ffIndex'] as int?,
            external: t['external'] == true,
            externalUrl: t['url'] as String?,
            selected: t['selected'] == true,
          ),
      ],
    );
  }
}
