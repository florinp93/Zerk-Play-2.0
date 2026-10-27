import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'libmpv.dart';

@immutable
final class MpvTrack {
  const MpvTrack({
    required this.id,
    required this.type,
    this.ffIndex,
    this.title,
    this.lang,
    this.codec,
    this.external = false,
    this.externalFilename,
    this.selected = false,
    this.isDefault = false,
    this.forced = false,
    this.channels,
  });

  final int id;

  final String type;

  final int? ffIndex;
  final String? title;
  final String? lang;
  final String? codec;
  final bool external;
  final String? externalFilename;
  final bool selected;
  final bool isDefault;
  final bool forced;
  final int? channels;

  static MpvTrack? fromNode(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final type = raw['type'];
    if (id is! int || type is! String) return null;
    return MpvTrack(
      id: id,
      type: type,
      ffIndex: raw['ff-index'] as int?,
      title: raw['title'] as String?,
      lang: raw['lang'] as String?,
      codec: raw['codec'] as String?,
      external: raw['external'] == true,
      externalFilename: raw['external-filename'] as String?,
      selected: raw['selected'] == true,
      isDefault: raw['default'] == true,
      forced: raw['forced'] == true,
      channels: raw['demux-channel-count'] as int?,
    );
  }
}

@immutable
final class MpvState {
  const MpvState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.paused = false,
    this.buffering = false,
    this.seeking = false,
    this.cacheBufferingPercent = 0,
    this.cacheAhead = Duration.zero,
    this.eofReached = false,
    this.idle = true,
    this.tracks = const [],
    this.volume = 100,
    this.muted = false,
    this.videoParams = const {},
    this.hwdec = '',
    this.containerFps,
  });

  final Duration position;
  final Duration duration;
  final bool paused;

  final bool buffering;
  final bool seeking;
  final int cacheBufferingPercent;
  final Duration cacheAhead;
  final bool eofReached;
  final bool idle;
  final List<MpvTrack> tracks;
  final double volume;
  final bool muted;
  final Map<String, Object?> videoParams;
  final String hwdec;
  final double? containerFps;

  MpvTrack? selected(String type) {
    for (final t in tracks) {
      if (t.type == type && t.selected) return t;
    }
    return null;
  }

  MpvState copyWith({
    Duration? position,
    Duration? duration,
    bool? paused,
    bool? buffering,
    bool? seeking,
    int? cacheBufferingPercent,
    Duration? cacheAhead,
    bool? eofReached,
    bool? idle,
    List<MpvTrack>? tracks,
    double? volume,
    bool? muted,
    Map<String, Object?>? videoParams,
    String? hwdec,
    double? containerFps,
  }) {
    return MpvState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      paused: paused ?? this.paused,
      buffering: buffering ?? this.buffering,
      seeking: seeking ?? this.seeking,
      cacheBufferingPercent: cacheBufferingPercent ?? this.cacheBufferingPercent,
      cacheAhead: cacheAhead ?? this.cacheAhead,
      eofReached: eofReached ?? this.eofReached,
      idle: idle ?? this.idle,
      tracks: tracks ?? this.tracks,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      videoParams: videoParams ?? this.videoParams,
      hwdec: hwdec ?? this.hwdec,
      containerFps: containerFps ?? this.containerFps,
    );
  }
}

sealed class MpvEvent {
  const MpvEvent();
}

final class MpvFileLoaded extends MpvEvent {
  const MpvFileLoaded();
}

final class MpvPlaybackRestart extends MpvEvent {
  const MpvPlaybackRestart();
}

final class MpvEndFile extends MpvEvent {
  const MpvEndFile(this.reason, this.error);

  final int reason;
  final String? error;
}

final class MpvClientMessage extends MpvEvent {
  const MpvClientMessage(this.args);

  final List<String> args;
}

final class MpvLog extends MpvEvent {
  const MpvLog(this.prefix, this.level, this.text);

  final String prefix;
  final String level;
  final String text;
}

final class MpvShutdown extends MpvEvent {
  const MpvShutdown();
}

final class MpvPlayer {
  MpvPlayer._(this._mpv, this._handle);

  final LibMpv _mpv;
  final MpvHandle _handle;
  NativeCallable<MpvWakeupNative>? _wakeup;
  bool _disposed = false;

  final ValueNotifier<MpvState> state = ValueNotifier(const MpvState());
  final StreamController<MpvEvent> _events = StreamController.broadcast(sync: true);

  Stream<MpvEvent> get events => _events.stream;

  int get address => _handle.address;

  static MpvPlayer create({required Map<String, String> options, String logLevel = 'warn'}) {
    final mpv = LibMpv.instance;
    final handle = mpv.create();
    if (handle == nullptr) throw StateError('mpv_create failed');
    final player = MpvPlayer._(mpv, handle);
    options.forEach(player._setOption);
    final rc = mpv.initialize(handle);
    if (rc < 0) {
      mpv.terminateDestroy(handle);
      throw StateError('mpv_initialize failed: ${player._err(rc)}');
    }
    using((arena) => mpv.requestLogMessages(handle, logLevel.toNativeUtf8(allocator: arena)));
    player._observeAll();
    player._wakeup = NativeCallable<MpvWakeupNative>.listener((Pointer<Void> _) => player._drain());
    mpv.setWakeupCallback(handle, player._wakeup!.nativeFunction, nullptr);
    return player;
  }

  void command(List<String> args) {
    if (_disposed) return;
    final rc = _withArgv(args, (argv) => _mpv.command(_handle, argv));
    if (rc < 0) debugPrint('[mpv] command ${args.first} failed: ${_err(rc)}');
  }

  void commandAsync(List<String> args) {
    if (_disposed) return;
    _withArgv(args, (argv) => _mpv.commandAsync(_handle, 0, argv));
  }

  void setProperty(String name, String value) {
    if (_disposed) return;
    final rc = using((a) => _mpv.setPropertyString(
        _handle, name.toNativeUtf8(allocator: a), value.toNativeUtf8(allocator: a)));
    if (rc < 0) debugPrint('[mpv] set $name=$value failed: ${_err(rc)}');
  }

  String? getString(String name) {
    if (_disposed) return null;
    return using((a) {
      final p = _mpv.getPropertyString(_handle, name.toNativeUtf8(allocator: a));
      if (p == nullptr) return null;
      final s = p.toDartString();
      _mpv.free(p.cast());
      return s;
    });
  }

  void scriptMessage(String script, List<String> args) =>
      commandAsync(['script-message-to', script, ...args]);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _mpv.setWakeupCallback(_handle, nullptr, nullptr);
    _wakeup?.close();
    _wakeup = null;
    _mpv.terminateDestroy(_handle);
    _events.close();
    state.dispose();
  }

  static const _observed = <(String, int)>[
    ('time-pos', MpvFormat.double_),
    ('duration', MpvFormat.double_),
    ('pause', MpvFormat.flag),
    ('paused-for-cache', MpvFormat.flag),
    ('seeking', MpvFormat.flag),
    ('cache-buffering-state', MpvFormat.int64),
    ('demuxer-cache-time', MpvFormat.double_),
    ('eof-reached', MpvFormat.flag),
    ('idle-active', MpvFormat.flag),
    ('track-list', MpvFormat.node),
    ('volume', MpvFormat.double_),
    ('mute', MpvFormat.flag),
    ('video-params', MpvFormat.node),
    ('hwdec-current', MpvFormat.string),
    ('container-fps', MpvFormat.double_),
  ];

  void _observeAll() {
    for (var i = 0; i < _observed.length; i++) {
      final (name, format) = _observed[i];
      using((a) => _mpv.observeProperty(_handle, i, name.toNativeUtf8(allocator: a), format));
    }
  }

  void _setOption(String name, String value) {
    final rc = using((a) => _mpv.setOptionString(
        _handle, name.toNativeUtf8(allocator: a), value.toNativeUtf8(allocator: a)));
    if (rc < 0) debugPrint('[mpv] option $name=$value rejected: ${_err(rc)}');
  }

  void _drain() {
    while (!_disposed) {
      final ev = _mpv.waitEvent(_handle, 0);
      final id = ev.ref.eventId;
      if (id == MpvEventId.none) break;
      switch (id) {
        case MpvEventId.propertyChange:
          _onProperty(ev.ref.data.cast<MpvEventProperty>().ref);
        case MpvEventId.fileLoaded:
          _events.add(const MpvFileLoaded());
        case MpvEventId.playbackRestart:
          _events.add(const MpvPlaybackRestart());
        case MpvEventId.endFile:
          final end = ev.ref.data.cast<MpvEventEndFile>().ref;
          _events.add(MpvEndFile(end.reason, end.error < 0 ? _err(end.error) : null));
        case MpvEventId.clientMessage:
          final msg = ev.ref.data.cast<MpvEventClientMessage>().ref;
          _events.add(MpvClientMessage([
            for (var i = 0; i < msg.numArgs; i++) (msg.args + i).value.toDartString(),
          ]));
        case MpvEventId.logMessage:
          final log = ev.ref.data.cast<MpvEventLogMessage>().ref;
          final text = log.text.toDartString().trimRight();
          final prefix = log.prefix.toDartString();
          final level = log.level.toDartString();
          debugPrint('[mpv/$prefix] $level: $text');
          _events.add(MpvLog(prefix, level, text));
        case MpvEventId.shutdown:
          _events.add(const MpvShutdown());
          return;
      }
    }
  }

  void _onProperty(MpvEventProperty p) {
    final name = p.name.toDartString();
    final data = p.data;
    final hasData = data != nullptr && p.format != MpvFormat.none;
    double dbl() => hasData ? data.cast<Double>().value : 0;
    bool flag() => hasData && data.cast<Int32>().value != 0;
    Duration secs(double s) => Duration(microseconds: (s * 1e6).round());

    final s = state.value;
    state.value = switch (name) {
      'time-pos' => s.copyWith(position: secs(dbl())),
      'duration' => s.copyWith(duration: secs(dbl())),
      'pause' => s.copyWith(paused: flag()),
      'paused-for-cache' => s.copyWith(buffering: flag()),
      'seeking' => s.copyWith(seeking: flag()),
      'cache-buffering-state' =>
        s.copyWith(cacheBufferingPercent: hasData ? data.cast<Int64>().value : 0),
      'demuxer-cache-time' => s.copyWith(cacheAhead: secs(dbl())),
      'eof-reached' => s.copyWith(eofReached: flag()),
      'idle-active' => s.copyWith(idle: flag()),
      'track-list' => s.copyWith(tracks: _parseTracks(hasData ? data.cast<MpvNode>() : null)),
      'volume' => s.copyWith(volume: dbl()),
      'mute' => s.copyWith(muted: flag()),
      'video-params' => s.copyWith(
          videoParams: hasData
              ? (mpvNodeToDart(data.cast<MpvNode>()) as Map?)?.cast<String, Object?>() ?? const {}
              : const {}),
      'hwdec-current' =>
        s.copyWith(hwdec: hasData ? data.cast<Pointer<Utf8>>().value.toDartString() : ''),
      'container-fps' => s.copyWith(containerFps: hasData ? dbl() : null),
      _ => s,
    };
  }

  static List<MpvTrack> _parseTracks(Pointer<MpvNode>? node) {
    if (node == null) return const [];
    final raw = mpvNodeToDart(node);
    if (raw is! List) return const [];
    return [for (final t in raw) ?MpvTrack.fromNode(t)];
  }

  T _withArgv<T>(List<String> args, T Function(Pointer<Pointer<Utf8>>) fn) {
    return using((a) {
      final argv = a<Pointer<Utf8>>(args.length + 1);
      for (var i = 0; i < args.length; i++) {
        argv[i] = args[i].toNativeUtf8(allocator: a);
      }
      argv[args.length] = nullptr;
      return fn(argv);
    });
  }

  String _err(int code) => _mpv.errorString(code).toDartString();
}
