import 'package:flutter/foundation.dart';

import '../core/windows/native_window.dart' show DisplayHdrStatus;

final class PlayerTrack {
  const PlayerTrack({
    required this.id,
    required this.type,
    this.ordinal,
    this.ffIndex,
    this.external = false,
    this.externalUrl,
    this.selected = false,
  });

  final String id;

  final String type;

  final int? ordinal;

  final int? ffIndex;
  final bool external;
  final String? externalUrl;
  final bool selected;
}

final class PlayerState {
  const PlayerState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.paused = false,
    this.buffering = false,
    this.ended = false,
    this.muted = false,
    this.volume = 100,
    this.tracks = const [],
    this.videoTransfer,
    this.dolbyVision = false,
    this.fps,
  });

  final Duration position;
  final Duration duration;
  final bool paused;
  final bool buffering;

  final bool ended;
  final bool muted;
  final double volume;
  final List<PlayerTrack> tracks;

  final String? videoTransfer;
  final bool dolbyVision;

  final double? fps;
}

sealed class PlayerEvent {
  const PlayerEvent();
}

final class PlayerLoaded extends PlayerEvent {
  const PlayerLoaded();
}

final class PlayerLoadError extends PlayerEvent {
  const PlayerLoadError(this.message);

  final String? message;
}

final class PlayerOsdEvent extends PlayerEvent {
  const PlayerOsdEvent(this.name, [this.arg]);

  final String name;
  final String? arg;
}

final class PlayerShutdown extends PlayerEvent {
  const PlayerShutdown();
}

abstract interface class PlayerBackend {
  ValueListenable<PlayerState> get state;
  Stream<PlayerEvent> get events;

  bool get selectsFileTracks;

  bool get streamSubtitles;

  String? get textSubtitleFormat;

  Future<void> open();

  void load(Uri url, {Duration? start, int? audioOrdinal, int? subtitleOrdinal, String? dolbyVision});

  void selectTrack(String type, String? id);

  void addSubtitle(Uri url, {required String format, required String title, String? language});

  void osd(String command, Object? data);

  void setPaused(bool paused);
  void seek(Duration position);

  bool get adjustsSpeed;
  void setSpeed(double speed);

  void setSubtitleScale(double scale);

  double? matchRefreshRate(double fps);

  Future<DisplayHdrStatus> displayHdr();

  Future<void> close();
}
