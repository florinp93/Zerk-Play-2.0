import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'trailer_player_stub.dart'
    if (dart.library.ffi) 'trailer_player_mpv.dart' as impl;
import 'trailers.dart';

@immutable
final class TrailerState {
  const TrailerState({
    this.textureId,
    this.ready = false,
    this.paused = false,
    this.ended = false,
    this.failed = false,
    this.muted = true,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final int? textureId;

  bool get hasSurface => textureId != null;

  final bool ready;
  final bool paused;
  final bool ended;
  final bool failed;
  final bool muted;
  final Duration position;
  final Duration duration;

  TrailerState copyWith({
    int? textureId,
    bool? ready,
    bool? paused,
    bool? ended,
    bool? failed,
    bool? muted,
    Duration? position,
    Duration? duration,
  }) =>
      TrailerState(
        textureId: textureId ?? this.textureId,
        ready: ready ?? this.ready,
        paused: paused ?? this.paused,
        ended: ended ?? this.ended,
        failed: failed ?? this.failed,
        muted: muted ?? this.muted,
        position: position ?? this.position,
        duration: duration ?? this.duration,
      );
}

abstract class TrailerPlayer {
  static bool get supported => impl.trailersSupported;

  static final _live = <TrailerPlayer>{};

  static Future<TrailerPlayer?> create({required Size renderSize, bool acceptInvalidCertificates = false}) async {
    if (!supported) return null;
    final p = await impl.createTrailerPlayer(renderSize: renderSize, acceptInvalidCertificates: acceptInvalidCertificates);
    if (p != null) {
      for (final other in _live.toList()) {
        await other.stop();
      }
      _live.add(p);
    }
    return p;
  }

  static Future<void> stopAll() async {
    for (final p in _live.toList()) {
      await p.stop();
    }
  }

  ValueListenable<TrailerState> get state;

  Future<bool> open(TrailerStream trailer, {required bool muted});

  void setMuted(bool muted);
  void setPaused(bool paused);
  void seekBy(Duration offset);
  void restart();

  void setCover(bool cover);

  void setRenderSize(Size size);

  Future<void> stop();

  @mustCallSuper
  Future<void> dispose() async => _live.remove(this);
}
