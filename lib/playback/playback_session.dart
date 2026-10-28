import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import '../core/windows/native_window.dart';
import '../core/emby/models/media_source.dart';
import '../l10n/app_localizations.dart';
import 'emby_playback_api.dart';
import 'kept_display.dart';
import 'player_backend.dart';
import 'player_settings.dart';
import 'track_labels.dart';
import 'track_policy.dart';
import 'versions.dart';

final class PlaybackRequest {
  const PlaybackRequest(this.item, {this.start, this.audioIndex, this.subtitleIndex, this.mediaSourceId});

  final EmbyItem item;

  final Duration? start;
  final int? audioIndex;

  final int? subtitleIndex;
  final String? mediaSourceId;
}

enum PlaybackEndReason { userExit, finished, error }

final class _Current {
  _Current({
    required this.item,
    required this.stream,
    required this.audioIndex,
    required this.subtitleIndex,
    required this.versions,
  });

  final EmbyItem item;
  final ResolvedStream stream;

  final List<MediaSourceInfo> versions;
  int? audioIndex;
  int? subtitleIndex;
  bool reportedStart = false;
  bool directPlayFailedOver = false;

  MediaSourceInfo get source => stream.source;
}

final class PlaybackSession {
  PlaybackSession({
    required this._player,
    required this._api,
    required this._settings,
    required this.l10n,
    this.acceptInvalidCertificates = false,
    Map<String, String> versionPreferences = const {},
    this.onVersionChosen,
    this.artwork,
    this.localize,
  }) : _versionPrefs = Map.of(versionPreferences);

  final Map<String, String> _versionPrefs;

  final void Function(String scope, String preferenceKey)? onVersionChosen;

  final ({Uri? backdrop, Uri? logo, Uri? still}) Function(EmbyItem item)? artwork;

  final Future<EmbyItem> Function(EmbyItem item)? localize;

  static String _versionScope(EmbyItem item) => item.seriesId ?? item.id;

  final EmbyPlaybackApi _api;
  final PlayerSettings _settings;
  final bool acceptInvalidCertificates;

  final L10n l10n;

  final PlayerBackend _player;
  final _done = Completer<PlaybackEndReason>();
  final _sticky = StickyLanguages();
  StreamSubscription<PlayerEvent>? _eventsSub;
  Timer? _progressTimer;

  _Current? _current;

  EmbyItem? get lastItem => _current?.item;
  EmbyItem? _nextEpisode;
  bool _nextCancelled = false;
  bool _loading = false;
  bool _finishing = false;
  bool _lastPaused = false;

  bool _hdrAutoEnabled = false;

  String? _videoSignature;

  Future<PlaybackEndReason> run(PlaybackRequest request) async {
    _eventsSub = _player.events.listen(_onEvent);
    _player.state.addListener(_onState);
    await _player.open();
    _osd('config', {
      'seekStep': _settings.seekStepSeconds,
      'autoSkipIntro': _settings.skipIntroAutomatically,
    });

    unawaited(_play(request));
    return _done.future;
  }

  Future<void> _play(PlaybackRequest request, {bool forceTranscode = false}) async {
    final item = request.item;
    _loading = true;
    _nextEpisode = null;
    _nextCancelled = false;
    _videoSignature = null;
    _osd('next', null);
    _osd('video', null);
    _osd('chapters', null);
    _osdState('loading', item);

    try {
      final start = request.start ?? _resumePosition(item);
      var info = await _api.getPlaybackInfo(
        item.id,
        mediaSourceId: request.mediaSourceId,
        start: start,
        maxBitrate: _settings.maxStreamingBitrate,
        enableDirectPlay: !forceTranscode,
        enableDirectStream: !forceTranscode,
      );
      final versions = item.mediaSources.length > 1
          ? item.mediaSources
          : request.mediaSourceId == null
              ? info.mediaSources
              : (_current?.item.id == item.id ? _current!.versions : info.mediaSources);
      var source = request.mediaSourceId != null
          ? info.mediaSources.firstWhere((m) => m.id == request.mediaSourceId, orElse: () => info.mediaSources.first)
          : pickVersion(info.mediaSources, preferenceKey: _versionPrefs[_versionScope(item)]);

      debugPrint('[session] playback info for "${item.name}" (${item.id}): ${info.mediaSources.length} source(s), '
          'chosen ${source.id} ${source.container} ${source.bitrate ?? '?'} b/s, direct play ${source.supportsDirectPlay}, '
          'direct stream ${source.supportsDirectStream}, transcode url ${source.transcodingUrl != null}, '
          'remote ${source.isRemote}, start $start, force transcode $forceTranscode');
      final policy = TrackPolicy.choose(source, _settings, sticky: _sticky);
      final audioIndex = request.audioIndex ?? policy.audioIndex;
      final subtitleIndex = switch (request.subtitleIndex) {
        -1 => null,
        null => policy.subtitleIndex,
        final i => i,
      };

      final streamSubs = _player.streamSubtitles;
      var stream = _api.resolve(item.id, info, mediaSourceId: source.id, streamSubtitles: streamSubs);
      final serverTracks = stream.method != PlayMethod.transcode &&
          !_player.selectsFileTracks &&
          _needsServerTracks(source, audioIndex, subtitleIndex, streamSubtitles: streamSubs);
      if (stream.method == PlayMethod.transcode || serverTracks) {
        info = await _api.getPlaybackInfo(
          item.id,
          mediaSourceId: source.id,
          start: start,
          audioStreamIndex: audioIndex,
          subtitleStreamIndex: subtitleIndex ?? -1,
          maxBitrate: _settings.maxStreamingBitrate,
          enableDirectPlay: !forceTranscode && !serverTracks,
          enableDirectStream: !forceTranscode && !serverTracks,
        );
        source = info.mediaSources.firstWhere((m) => m.id == source.id, orElse: () => info.mediaSources.first);
        stream = _api.resolve(item.id, info, mediaSourceId: source.id, streamSubtitles: streamSubs);
      }
      await _prepareHdr(VersionInfo(source).hdr != null);
      if (_finishing) return;

      _current = _Current(
        item: item,
        stream: stream,
        audioIndex: audioIndex,
        subtitleIndex: subtitleIndex,
        versions: versions,
      );
      final v = source.video;
      debugPrint('[session] ${item.name}: ${stream.method.wire} '
          'video=${v?.codec}/${v?.profile} ${v?.width}x${v?.height} ${v?.bitDepth}bit '
          '${v?.videoRange}/${v?.extendedVideoType} '
          'audio=$audioIndex sub=$subtitleIndex start=$start url=${stream.url.path}');

      _player.load(
        stream.url,
        start: start,
        audioOrdinal: _initialAudio(source, stream, audioIndex),
        subtitleOrdinal: _initialSubtitle(source, stream, subtitleIndex),
        dolbyVision: stream.copiedDolbyVision,
      );
      _warmUpSubtitle(item, source, stream, subtitleIndex);
      _prefetchNext(item);
    } catch (e) {
      debugPrint('[session] load failed: $e');
      _loading = false;
      _osdState('error', item, message: _friendlyError(l10n, e));
    }
  }

  static bool _needsServerTracks(MediaSourceInfo source, int? audioIndex, int? subtitleIndex,
      {required bool streamSubtitles}) {
    final firstAudio = source.audioStreams.where((s) => !s.isExternal).firstOrNull;
    if (audioIndex != null && firstAudio != null && audioIndex != firstAudio.index) return true;
    final sub = subtitleIndex == null ? null : source.streamByIndex(subtitleIndex);
    return sub != null && !sub.isExternal && (streamSubtitles || !sub.isTextSubtitleStream);
  }

  int? _initialAudio(MediaSourceInfo source, ResolvedStream stream, int? audioIndex) {
    if (!stream.tracksMatchSource || audioIndex == null) return null;
    return _ordinal(source, 'audio', audioIndex);
  }

  int? _initialSubtitle(MediaSourceInfo source, ResolvedStream stream, int? subtitleIndex) {
    if (subtitleIndex == null || !stream.tracksMatchSource) return null;
    final sub = source.streamByIndex(subtitleIndex);
    if (sub == null || sub.isExternal) return null;
    return _ordinal(source, 'sub', subtitleIndex);
  }

  static int? _ordinal(MediaSourceInfo source, String type, int embyIndex) {
    final streams = (type == 'audio' ? source.audioStreams : source.subtitleStreams).where((s) => !s.isExternal).toList();
    final i = streams.indexWhere((s) => s.index == embyIndex);
    return i < 0 ? null : i + 1;
  }

  Future<void> _onFileLoaded() async {
    final cur = _current;
    if (cur == null) return;
    _loading = false;

    if (cur.stream.tracksMatchSource) {
      final audio = _trackFor(cur, 'audio', cur.audioIndex);
      if (audio != null && !audio.selected) _player.selectTrack('audio', audio.id);
    }
    await _applySubtitle(cur, cur.subtitleIndex, initial: true);

    final ps = _player.state.value;
    debugPrint('[session] playing "${cur.item.name}": ${cur.stream.method.wire}, duration ${ps.duration}, '
        'fps ${ps.fps}, ${ps.tracks.length} tracks, audio ${cur.audioIndex} sub ${cur.subtitleIndex}');
    _osdState('playing', cur.item);
    _sendTracks();
    _sendVersions();
    unawaited(_sendSegments(cur));
    unawaited(_sendChapters(cur));
    final hz = _settings.matchRefreshRate ? _matchRefreshRate(cur) : null;
    if (_settings.matchRefreshRate) debugPrint('[session] refresh rate match: ${hz == null ? 'no change' : '$hz Hz'}');
    unawaited(_sendVideo(cur, announce: true, refreshHz: hz));

    if (!cur.reportedStart) {
      cur.reportedStart = true;
      unawaited(_report(_api.reportStart, eventName: null));
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_report(_api.reportProgress, eventName: 'TimeUpdate'));
      });
    }
  }

  PlayerTrack? _trackFor(_Current cur, String type, int? embyIndex) {
    if (embyIndex == null) return null;
    final own = _player.state.value.tracks.where((t) => t.type == type && !t.external).toList();
    if (own.any((t) => t.ffIndex != null)) return own.where((t) => t.ffIndex == embyIndex).firstOrNull;
    final ordinal = _ordinal(cur.source, type, embyIndex);
    return own.where((t) => t.ordinal == ordinal).firstOrNull;
  }

  Future<void> _switchAudio(int index) async {
    final cur = _current;
    if (cur == null || index == cur.audioIndex) return;
    final stream = cur.source.streamByIndex(index);
    _sticky.audio = stream?.language;

    final track = cur.stream.tracksMatchSource ? _trackFor(cur, 'audio', index) : null;
    if (track != null) {
      _player.selectTrack('audio', track.id);
      cur.audioIndex = index;
      _sendTracks();
      _toast(l10n.audioToast(stream == null ? '$index' : TrackLabels.title(stream, l10n)));
      unawaited(_report(_api.reportProgress, eventName: 'AudioTrackChange'));
      return;
    }
    await _renegotiate(audioIndex: index, subtitleIndex: cur.subtitleIndex);
  }

  Future<void> _switchSubtitle(int index) async {
    final cur = _current;
    if (cur == null) return;
    final target = index < 0 ? null : index;
    if (target == null) {
      _sticky.subtitlesOff = true;
      _sticky.subtitle = null;
    } else {
      _sticky.subtitlesOff = false;
      _sticky.subtitle = cur.source.streamByIndex(target)?.language;
    }
    final ok = await _applySubtitle(cur, target);
    if (!ok) {
      await _renegotiate(audioIndex: cur.audioIndex, subtitleIndex: target);
      return;
    }
    cur.subtitleIndex = target;
    _sendTracks();
    unawaited(_report(_api.reportProgress, eventName: 'SubtitleTrackChange'));
  }

  Future<bool> _applySubtitle(_Current cur, int? index, {bool initial = false}) async {
    if (index == null) {
      _player.selectTrack('sub', null);
      return true;
    }
    final stream = cur.source.streamByIndex(index);
    if (stream == null) return true;

    final embeddedTrack = cur.stream.tracksMatchSource && !stream.isExternal
        ? _trackFor(cur, 'sub', index)
        : null;
    if (embeddedTrack != null) {
      if (!embeddedTrack.selected) _player.selectTrack('sub', embeddedTrack.id);
      return true;
    }

    if (_player.streamSubtitles && !stream.isExternal && stream.isTextSubtitleStream) {
      final track = _trackFor(cur, 'sub', index);
      if (track != null) {
        if (!track.selected) _player.selectTrack('sub', track.id);
        return true;
      }
      if (!initial) return false;
    }

    if (stream.deliveryMethod == SubtitleDeliveryMethod.encode && !cur.stream.tracksMatchSource) {
      return initial;
    }

    if (stream.isExternal || stream.isTextSubtitleStream) {
      final format = _subtitleFormat(stream);
      final url = _api.subtitleUrl(cur.item.id, cur.source, stream, format: format);
      final existing = _player.state.value.tracks
          .where((t) => t.type == 'sub' && t.externalUrl == url.toString())
          .firstOrNull;
      if (existing != null) {
        _player.selectTrack('sub', existing.id);
      } else {
        _player.addSubtitle(url, format: format, title: TrackLabels.title(stream, l10n), language: stream.language);
      }
      return true;
    }
    return false;
  }

  void _warmUpSubtitle(EmbyItem item, MediaSourceInfo source, ResolvedStream stream, int? index) {
    if (_player.selectsFileTracks || index == null) return;
    final sub = source.streamByIndex(index);
    if (sub == null || !(sub.isExternal || sub.isTextSubtitleStream)) return;
    if (_player.streamSubtitles && !sub.isExternal) return;
    if (sub.deliveryMethod == SubtitleDeliveryMethod.encode && !stream.tracksMatchSource) return;
    _api.warmUpSubtitle(_api.subtitleUrl(item.id, source, sub, format: _subtitleFormat(sub)));
  }

  String _subtitleFormat(MediaStream s) =>
      _player.textSubtitleFormat ?? (s.codecLower == 'ass' || s.codecLower == 'ssa' ? 'ass' : 'srt');

  Future<void> _renegotiate({int? audioIndex, int? subtitleIndex}) async {
    final cur = _current;
    if (cur == null) return;
    final position = _player.state.value.position;
    await _report(_api.reportStopped, eventName: null);
    _progressTimer?.cancel();
    if (cur.stream.method == PlayMethod.transcode) {
      unawaited(_api.stopTranscode(cur.stream.playSessionId));
    }
    await _play(PlaybackRequest(
      cur.item,
      start: position,
      audioIndex: audioIndex,
      subtitleIndex: subtitleIndex ?? -1,
      mediaSourceId: cur.source.id,
    ));
  }

  void _sendVersions() {
    final cur = _current;
    if (cur == null) return;
    _osd('versions', [
      if (cur.versions.length > 1)
        for (final v in cur.versions)
          {
            'id': v.id,
            'label': VersionInfo(v).label,
            'detail': VersionInfo(v).summary,
            'selected': v.id == cur.source.id,
          },
    ]);
  }

  Future<void> _switchVersion(String mediaSourceId) async {
    final cur = _current;
    if (cur == null || cur.source.id == mediaSourceId || _loading) return;
    final target = cur.versions.where((v) => v.id == mediaSourceId).firstOrNull;
    if (target == null) return;

    final oldAudio = cur.audioIndex == null ? null : cur.source.streamByIndex(cur.audioIndex!);
    final oldSub = cur.subtitleIndex == null ? null : cur.source.streamByIndex(cur.subtitleIndex!);
    final policy = TrackPolicy.choose(target, _settings, sticky: _sticky);
    final audio = TrackMatcher.match(oldAudio, target.audioStreams)?.index ?? policy.audioIndex;
    final sub = oldSub == null ? null : (TrackMatcher.match(oldSub, target.subtitleStreams)?.index ?? policy.subtitleIndex);

    final scope = _versionScope(cur.item);
    final key = VersionInfo(target).preferenceKey;
    _versionPrefs[scope] = key;
    onVersionChosen?.call(scope, key);
    _toast(l10n.versionToast(VersionInfo(target).label));

    final position = _player.state.value.position;
    await _report(_api.reportStopped, eventName: null);
    _progressTimer?.cancel();
    if (cur.stream.method == PlayMethod.transcode) unawaited(_api.stopTranscode(cur.stream.playSessionId));
    await _play(PlaybackRequest(
      cur.item,
      start: position,
      mediaSourceId: target.id,
      audioIndex: audio,
      subtitleIndex: sub ?? -1,
    ));
  }

  void _prefetchNext(EmbyItem item) {
    if (!item.isEpisode) return;
    _api.nextEpisode(item).then((next) async {
      if (next == null) return null;
      return await localize?.call(next) ?? next;
    }).then((next) {
      if (_current?.item.id != item.id || next == null) return;
      _nextEpisode = next;
      _osd('next', {
        'title': [next.episodeCode, next.name].whereType<String>().join('  '),
        'subtitle': next.seriesName,
        'image': ?artwork?.call(next).still?.toString(),
        'autoplay': _settings.autoPlayNextEpisode,
        'countdown': 10,
      });
    }).catchError((Object e) {
      debugPrint('[session] next episode lookup failed: $e');
    });
  }

  Future<void> _playNext() async {
    final next = _nextEpisode;
    final cur = _current;
    if (next == null || cur == null || _loading) return;
    final pos = _player.state.value.position;
    final dur = _player.state.value.duration;
    await _report(_api.reportStopped, eventName: null);
    _progressTimer?.cancel();
    if (dur > Duration.zero && pos.inMilliseconds > dur.inMilliseconds * 0.8) {
      unawaited(_api.markPlayed(cur.item.id).catchError((_) {}));
    }
    if (cur.stream.method == PlayMethod.transcode) {
      unawaited(_api.stopTranscode(cur.stream.playSessionId));
    }
    await _play(PlaybackRequest(next, start: Duration.zero));
  }

  void _onEvent(PlayerEvent e) {
    switch (e) {
      case PlayerLoaded():
        unawaited(_onFileLoaded());
      case PlayerLoadError(:final message):
        _onLoadError(message);
      case PlayerOsdEvent(:final name, :final arg):
        _onOsdEvent(name, arg);
      case PlayerShutdown():
        unawaited(_finish(PlaybackEndReason.error));
    }
  }

  void _onLoadError(String? error) {
    final cur = _current;
    if (cur == null) return;
    debugPrint('[session] player could not open stream: $error');
    if (cur.stream.method != PlayMethod.transcode && !cur.directPlayFailedOver) {
      cur.directPlayFailedOver = true;
      unawaited(_play(
        PlaybackRequest(cur.item,
            start: _player.state.value.position,
            audioIndex: cur.audioIndex,
            subtitleIndex: cur.subtitleIndex ?? -1),
        forceTranscode: true,
      ));
      return;
    }
    _loading = false;
    _osdState('error', cur.item, message: l10n.couldNotPlayVideo(error ?? l10n.unknownError));
  }

  void _onOsdEvent(String name, String? arg) {
    switch (name) {
      case 'back':
        unawaited(_finish(PlaybackEndReason.userExit));
      case 'audio':
        final i = int.tryParse(arg ?? '');
        if (i != null) unawaited(_switchAudio(i));
      case 'sub':
        final i = int.tryParse(arg ?? '');
        if (i != null) unawaited(_switchSubtitle(i));
      case 'version':
        if (arg != null) unawaited(_switchVersion(arg));
      case 'next':
        unawaited(_playNext());
      case 'next-cancel':
        _nextCancelled = true;
    }
  }

  void _onState() {
    final s = _player.state.value;
    if (_current == null || _loading) return;
    final signature = '${s.videoTransfer}|${s.dolbyVision}';
    if (s.videoTransfer != null && signature != _videoSignature) {
      _videoSignature = signature;
      unawaited(_sendVideo(_current!));
    }
    if (s.paused != _lastPaused) {
      _lastPaused = s.paused;
      unawaited(_report(_api.reportProgress, eventName: s.paused ? 'Pause' : 'Unpause'));
    }
    if (s.ended && !_finishing) {
      if (_nextEpisode != null && !_nextCancelled && _settings.autoPlayNextEpisode) {
        unawaited(_playNext());
      } else {
        unawaited(_finish(PlaybackEndReason.finished));
      }
    }
  }

  void _osd(String command, Object? data) => _player.osd(command, data);

  void _osdState(String phase, EmbyItem item, {String? message}) {
    final (title, subtitle) = _titles(item);
    final art = phase == 'loading' ? artwork?.call(item) : null;
    _osd('state', {
      'phase': phase,
      'title': title,
      'subtitle': subtitle,
      'message': ?message,
      'backdrop': ?art?.backdrop?.toString(),
      'logo': ?art?.logo?.toString(),
    });
  }

  (String, String) _titles(EmbyItem item) {
    if (item.isChannel) return (item.name, item.overview ?? '');
    if (item.isEpisode) {
      final code = item.episodeCode;
      return (item.seriesName ?? item.name, [code, item.name].whereType<String>().join('  '));
    }
    return (item.name, item.productionYear?.toString() ?? '');
  }

  void _sendTracks() {
    final cur = _current;
    if (cur == null) return;
    Map<String, Object?> entry(MediaStream s, bool selected) => {
          'id': s.index,
          'label': TrackLabels.title(s, l10n),
          'detail': TrackLabels.detail(s, l10n),
          'selected': selected,
        };
    _osd('tracks', {
      'audio': [for (final s in cur.source.audioStreams) entry(s, s.index == cur.audioIndex)],
      'subs': [for (final s in cur.source.subtitleStreams) entry(s, s.index == cur.subtitleIndex)],
    });
  }

  Future<void> _sendSegments(_Current cur) async {
    double? secs(int? ticks) => ticks == null ? null : ticks / 1e7;
    final segments = await _api.segments(cur.item.id).catchError((Object e) {
      debugPrint('[session] media segments: $e');
      return null;
    });
    if (!identical(_current, cur)) return;
    int? marker(String type) =>
        switch (type) {
          'IntroStart' => segments?.introStart,
          'IntroEnd' => segments?.introEnd,
          'CreditsStart' => segments?.creditsStart,
          _ => null,
        } ??
        cur.source.chapters.where((c) => c.markerType == type).firstOrNull?.startTicks;
    final runtime = cur.source.runTimeTicks ?? cur.item.runTimeTicks;
    final fallback = runtime != null && runtime > 120 * 10000000 ? runtime - 30 * 10000000 : null;
    var credits = cur.item.creditsStartTicks ?? marker('CreditsStart');
    if (credits != null && runtime != null && credits < runtime ~/ 2) credits = null;
    _osd('segments', {
      'introStart': ?secs(cur.item.introStartTicks ?? marker('IntroStart')),
      'introEnd': ?secs(cur.item.introEndTicks ?? marker('IntroEnd')),
      'creditsStart': ?secs(credits ?? fallback),
    });
  }

  Future<void> _sendChapters(_Current cur) async {
    final chapters = await _api.chapters(cur.item).catchError((Object e) {
      debugPrint('[session] chapters: $e');
      return const <ChapterInfo>[];
    });
    if (!identical(_current, cur) || chapters.length < 2) return;
    _osd('chapters', [
      for (final c in chapters)
        {'time': c.startTicks / 1e7, 'title': ?c.name, 'image': ?_api.chapterImage(cur.item.id, c, width: 320)?.toString()},
    ]);
  }

  void _toast(String text) => _player.osd('toast', text);

  double? _matchRefreshRate(_Current cur) {
    final fps = _player.state.value.fps ?? cur.source.video?.frameRate;
    if (fps == null) return null;
    return _player.matchRefreshRate(fps);
  }

  Future<void> _prepareHdr(bool hdrContent) async {
    if (!hdrContent || !_settings.autoHdr || !_settings.hdrPassthrough || _hdrAutoEnabled) return;
    final status = await NativeWindow.hdrStatus();
    debugPrint('[session] HDR video; display HDR supported ${status.supported}, on ${status.enabled}');
    if (!status.supported || status.enabled) return;
    debugPrint('[session] turning Windows HDR on');
    if (!await NativeWindow.setHdr(true)) {
      debugPrint('[session] could not turn on Windows HDR');
      return;
    }
    _hdrAutoEnabled = true;
    await NativeWindow.waitForHdr(true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  String? _videoFormat(_Current cur) {
    final s = _player.state.value;
    final gamma = s.videoTransfer;
    if (s.dolbyVision) return 'Dolby Vision';
    final declared = VersionInfo(cur.source).hdr;
    if (gamma == null) return declared;
    if (gamma != 'pq' && gamma != 'hlg') return null;
    return declared ?? (gamma == 'hlg' ? 'HLG' : 'HDR10');
  }

  Future<void> _sendVideo(_Current cur, {bool announce = false, double? refreshHz}) async {
    final display = await _player.displayHdr();
    if (_current != cur || _finishing) return;
    final format = _videoFormat(cur);
    final hdrOutput = format != null && _settings.hdrPassthrough && display.enabled;
    _osd('video', {
      'format': ?format,
      'output': format == null ? null : (hdrOutput ? 'HDR' : 'SDR'),
      'displayHdr': display.enabled,
    });
    if (!announce) return;
    final parts = [
      ?format,
      if (format != null) hdrOutput ? l10n.hdrOn : (display.supported ? l10n.toneMappedHdrOff : l10n.toneMappedSdr),
      if (refreshHz != null) l10n.displayHz(refreshHz.toStringAsFixed(refreshHz % 1 == 0 ? 0 : 3)),
    ];
    if (parts.isNotEmpty) _toast(parts.join('  ·  '));
  }

  Future<void> _report(Future<void> Function(PlaybackReport) send, {required String? eventName}) async {
    final report = _snapshot(eventName);
    if (report != null) await _send(send, report);
  }

  PlaybackReport? _snapshot(String? eventName) {
    final cur = _current;
    if (cur == null) return null;
    final s = _player.state.value;
    return PlaybackReport(
      itemId: cur.item.id,
      stream: cur.stream,
      position: s.position,
      isPaused: s.paused,
      isMuted: s.muted,
      volume: s.volume.round(),
      audioStreamIndex: cur.audioIndex,
      subtitleStreamIndex: cur.subtitleIndex,
      eventName: eventName,
    );
  }

  Future<void> _send(Future<void> Function(PlaybackReport) send, PlaybackReport report) async {
    try {
      await send(report);
    } catch (e) {
      debugPrint('[session] report failed: $e');
    }
  }

  Future<void> _finish(PlaybackEndReason reason) async {
    if (_finishing) return;
    _finishing = true;
    debugPrint('[session] finishing (${reason.name}) at ${_player.state.value.position}');
    _progressTimer?.cancel();
    final cur = _current;
    final stopped = cur != null && cur.reportedStart ? _snapshot(null) : null;
    final volume = _player.state.value.volume;
    if (volume != _settings.volume) unawaited(PlayerSettings.load().then((p) => p.copyWith(volume: volume).save()));

    await _eventsSub?.cancel();
    _player.state.removeListener(_onState);
    await _player.close();
    if (_hdrAutoEnabled) {
      if (_settings.keepHdr) {
        debugPrint('[session] leaving Windows HDR on (keep after playback)');
        KeptDisplay.hdrOn = true;
      } else {
        debugPrint('[session] turning Windows HDR back off');
        unawaited(NativeWindow.setHdr(false));
      }
    }

    if (stopped != null) {
      await _send(_api.reportStopped, stopped).timeout(const Duration(seconds: 4), onTimeout: () {});
    }
    if (cur != null && cur.stream.method == PlayMethod.transcode) {
      unawaited(_api.stopTranscode(cur.stream.playSessionId));
    }
    if (!_done.isCompleted) _done.complete(reason);
  }

  Duration? _resumePosition(EmbyItem item) {
    final ticks = item.playbackPositionTicks;
    if (ticks == null || ticks <= 0 || item.isPlayed) return null;
    return Duration(microseconds: ticks ~/ 10);
  }

  static String _friendlyError(L10n l10n, Object e) {
    if (e is PlaybackRefusedException) {
      return switch (e.code) {
        'NotAllowed' => l10n.playbackNotAllowed,
        'NoCompatibleStream' => l10n.playbackNoStream,
        'RateLimitExceeded' => l10n.playbackRateLimited,
        _ => l10n.playbackRefused(e.code),
      };
    }
    if (e is SocketException || e is TimeoutException) return l10n.serverUnreachable;
    return l10n.playbackFailedWith('$e');
  }
}
