import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/log/app_log.dart';
import '../../core/windows/native_window.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/core/gamepad.dart';
import '../../ui/player/player_osd.dart';
import '../../ui/widgets/net_image.dart';
import '../display_refresh.dart';
import '../media3/osd_model.dart';
import '../player_backend.dart';
import '../player_settings.dart';
import 'libmpv.dart' show MpvEndFileReason;
import 'mpv_options.dart';
import 'mpv_player.dart';
import 'video_host.dart';

final class MpvBackend implements PlayerBackend {
  MpvBackend({
    required this._navigator,
    required this._settings,
    required this.l10n,
    this.acceptInvalidCertificates = false,
  });

  final NavigatorState _navigator;
  final PlayerSettings _settings;

  final L10n l10n;
  final bool acceptInvalidCertificates;

  late final MpvPlayer _mpv;
  final _state = ValueNotifier(const PlayerState());
  final _events = StreamController<PlayerEvent>.broadcast(sync: true);
  final _osdReady = Completer<void>();
  final _refresh = DisplayRefreshMatcher();
  StreamSubscription<MpvEvent>? _sub;
  late final OsdModel _curtain = OsdModel(
    state: _state,
    send: (name, [arg]) => _events.add(PlayerOsdEvent(name, arg)),
    togglePause: () {},
    seekTo: (_) {},
  );
  Route<void>? _route;
  bool _videoShown = false;

  bool _framed = false;

  @override
  ValueListenable<PlayerState> get state => _state;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  bool get selectsFileTracks => true;

  @override
  bool get streamSubtitles => false;

  @override
  String? get textSubtitleFormat => null;

  @override
  Future<void> open() async {
    final wid = await VideoHost.create();
    final logFile = _settings.detailedLog ? AppLog.sidePath('mpv') : null;
    final options = buildMpvOptions(
      wid: wid,
      settings: _settings,
      acceptInvalidCertificates: acceptInvalidCertificates,
      logFile: logFile,
    );
    debugPrint('[mpv] options: ${[for (final e in options.entries) if (e.key != 'wid') '${e.key}=${e.value}'].join(' ')}');
    if (logFile != null) debugPrint('[mpv] detailed log: $logFile');
    _mpv = MpvPlayer.create(options: options, logLevel: _settings.detailedLog ? 'info' : 'warn');
    _sub = _mpv.events.listen(_onEvent);
    VideoHost.onInput = _mpv.commandAsync;
    _mpv.state.addListener(_onState);

    final route = PlayerOsdRoute(model: _curtain, controls: false);
    _route = route;
    unawaited(_navigator.push(route));

    await _loadUserConfig();
    final script = _osdScriptPath();
    debugPrint('[mpv] loading the OSD ${File(script).existsSync() ? '' : '(MISSING!) '}$script');
    _mpv.command(['load-script', script]);
    _mpv.setProperty('user-data/zerk/fullscreen', (await NativeWindow.isFullScreen()) ? 'yes' : 'no');
    await _osdReady.future.timeout(const Duration(seconds: 3), onTimeout: () {
      debugPrint('[mpv] the OSD script did not report ready within 3 s: the player UI will be missing');
    });
    osd('strings', _osdStrings(l10n));
  }

  static Map<String, String> _osdStrings(L10n l) => {
        'back': l.back,
        'seek_back': l.seekBack('{n}'),
        'seek_forward': l.seekForward('{n}'),
        'mute': l.mute,
        'unmute': l.unmute,
        'play': l.play,
        'pause': l.pause,
        'audio': l.audio,
        'subtitles': l.subtitles,
        'chapters': l.chapters,
        'next_episode': l.nextEpisode,
        'settings': l.settings,
        'full_screen': l.fullScreen,
        'off': l.subtitleOff,
        'chapter': l.chapterNumber('{n}'),
        'version': l.version,
        'aspect_original': l.aspectOriginal,
        'aspect_original_detail': l.aspectOriginalDetail,
        'aspect_flat': l.aspectFlat,
        'aspect_scope': l.aspectScope,
        'aspect_zoom': l.aspectZoom,
        'aspect_zoom_detail': l.aspectZoomDetail,
        'aspect_stretch': l.aspectStretch,
        'aspect_stretch_detail': l.aspectStretchDetail,
        'aspect_ratio': l.aspectRatio,
        'aspect_toast': l.aspectToast('{n}'),
        'playback_speed': l.playbackSpeed,
        'subtitle_delay': l.subtitleDelay,
        'audio_delay': l.audioDelay,
        'subtitle_size': l.subtitleSize,
        'search_subtitles': l.searchSubtitles,
        'searching': l.subtitleSearching,
        'no_subtitles_found': l.subtitleSearchEmpty,
        'playback_info': l.playbackInfo,
        'playback_info_detail': l.playbackInfoDetail,
        'hdr_on': l.badgeHdrOn,
        'tone_mapped': l.badgeToneMapped,
        'muted': l.muted,
        'press_back': l.pressBackToReturn,
        'skip_intro': l.skipIntro,
        'up_next': l.upNext,
        'starts_in': l.startsIn('{n}'),
        'intro_skipped': l.introSkipped,
        'play_now': l.playNow,
        'keep_watching': l.keepWatching,
      };

  Future<void> _showVideo(bool show) async {
    if (show == _videoShown) return;
    _videoShown = show;
    debugPrint('[mpv] video window ${show ? 'shown' : 'hidden'}');
    Gamepad.playerSink = show ? (key) => _mpv.commandAsync(['keypress', key]) : null;
    await (show ? VideoHost.show() : VideoHost.hide());
  }

  @override
  void load(Uri url, {Duration? start, int? audioOrdinal, int? subtitleOrdinal, String? dolbyVision}) {
    final opts = <String>[
      if (start != null && start > Duration.zero) 'start=${start.inMilliseconds / 1000}',
      'aid=${audioOrdinal ?? 'auto'}',
      'sid=${subtitleOrdinal ?? 'no'}',
    ];
    _mpv.command(['loadfile', url.toString(), 'replace', '-1', opts.join(',')]);
  }

  @override
  void selectTrack(String type, String? id) => _mpv.setProperty(type == 'audio' ? 'aid' : 'sid', id ?? 'no');

  @override
  void addSubtitle(Uri url, {required String format, required String title, String? language}) =>
      _mpv.commandAsync(['sub-add', url.toString(), 'select', title, language ?? '']);

  @override
  void osd(String command, Object? data) {
    final payload = data is String ? data : jsonEncode(data);
    if (command != 'strings') {
      debugPrint('[osd] -> $command ${payload.length > 300 ? '${payload.substring(0, 300)}...' : payload}');
    }
    _mpv.scriptMessage('zerk_osd', [command, payload]);
    if (command == 'next') unawaited(_sendNextImage(data is Map ? data['image'] as String? : null));
    if (command != 'state') return;
    _curtain.handle(command, data);
    if (_curtain.phase == 'loading') _framed = false;
    unawaited(_showVideo(_curtain.phase == 'playing' && _framed));
  }

  @override
  void setPaused(bool paused) => _mpv.setProperty('pause', paused ? 'yes' : 'no');

  @override
  void seek(Duration position) => _mpv.commandAsync(['seek', '${position.inMilliseconds / 1000}', 'absolute']);

  @override
  bool get adjustsSpeed => true;

  @override
  void setSpeed(double speed) => _mpv.setProperty('speed', '$speed');

  @override
  void setSubtitleScale(double scale) => _mpv.setProperty('sub-scale', scale.toStringAsFixed(2));

  @override
  Future<double?> matchRefreshRate(double fps) async => _refresh.matchFrameRate(fps);

  @override
  Future<DisplayHdrStatus> displayHdr() => NativeWindow.hdrStatus();

  @override
  Future<void> close() async {
    if (_settings.keepRefreshRate) {
      _refresh.keep();
    } else {
      _refresh.restore();
    }
    await _sub?.cancel();
    _mpv.state.removeListener(_onState);
    VideoHost.onInput = null;
    Gamepad.playerSink = null;
    await VideoHost.hide();
    _mpv.dispose();
    final route = _route;
    _route = null;
    if (route != null && route.isActive) _navigator.removeRoute(route);
    _curtain.dispose();
    await _events.close();
  }

  void _onEvent(MpvEvent e) {
    switch (e) {
      case MpvFileLoaded():
        final s = _mpv.state.value;
        debugPrint('[mpv] file loaded: hwdec=${s.hwdec} video=${s.videoParams} fps=${s.containerFps}');
        _events.add(const PlayerLoaded());
      case MpvPlaybackRestart():
        if (!_framed) debugPrint('[mpv] first frame (hwdec ${_mpv.state.value.hwdec})');
        _framed = true;
        if (_curtain.phase == 'playing') unawaited(_showVideo(true));
      case MpvEndFile(:final reason, :final error) when reason == MpvEndFileReason.error:
        debugPrint('[mpv] end of file: ERROR $error');
        _events.add(PlayerLoadError(error));
      case MpvEndFile(:final reason):
        debugPrint('[mpv] end of file (reason $reason)');
      case MpvClientMessage(:final args) when args.firstOrNull == 'zerk-event':
        final name = args.elementAtOrNull(1);
        debugPrint('[osd] event $name${args.length > 2 ? ' ${args[2]}' : ''}');
        switch (name) {
          case null:
            break;
          case 'ready':
            if (!_osdReady.isCompleted) _osdReady.complete();
          case 'fullscreen':
            unawaited(_toggleFullscreen());
          default:
            _events.add(PlayerOsdEvent(name, args.elementAtOrNull(2)));
        }
      case MpvShutdown():
        _events.add(const PlayerShutdown());
      default:
        break;
    }
  }

  void _onState() {
    final s = _mpv.state.value;
    _state.value = PlayerState(
      position: s.position,
      duration: s.duration,
      paused: s.paused,
      buffering: s.buffering,
      ended: s.eofReached,
      muted: s.muted,
      volume: s.volume,
      videoTransfer: s.videoParams['gamma'] as String?,
      dolbyVision: s.videoParams['colormatrix'] == 'dolbyvision',
      fps: s.containerFps,
      tracks: [
        for (final t in s.tracks)
          if (t.type == 'audio' || t.type == 'sub')
            PlayerTrack(
              id: '${t.id}',
              type: t.type,
              ordinal: t.external ? null : t.id,
              ffIndex: t.ffIndex,
              external: t.external,
              externalUrl: t.externalFilename,
              selected: t.selected,
            ),
      ],
    );
  }

  int _nextImageSerial = 0;

  Future<void> _sendNextImage(String? url) async {
    final serial = ++_nextImageSerial;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) return;
    try {
      final image = await _resolve(NetImageProvider(uri, decodeWidth: _nextImageWidth));
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'zerk_play_osd'));
      await dir.create(recursive: true);
      for (final f in dir.listSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
      final files = <String, String>{};
      for (final grey in [true, false]) {
        final bytes = await _cardStill(image, grey: grey);
        final file = File(p.join(dir.path, 'next-$serial-${grey ? 'grey' : 'colour'}.bgra'));
        await file.writeAsBytes(bytes, flush: true);
        files[grey ? 'grey' : 'colour'] = file.path;
      }
      image.dispose();
      if (serial != _nextImageSerial) return;
      _mpv.scriptMessage('zerk_osd', ['next-image', jsonEncode({
        'url': url,
        ...files,
        'w': _nextImageWidth,
        'h': _nextImageWidth * 9 ~/ 16,
      })]);
    } catch (e) {
      debugPrint('[mpv] up-next still failed: $e');
    }
  }

  static const _nextImageWidth = 800;

  static Future<ui.Image> _resolve(ImageProvider provider) {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      done.complete(info.image.clone());
      info.dispose();
    }, onError: (e, _) {
      stream.removeListener(listener);
      done.completeError(e);
    });
    stream.addListener(listener);
    return done.future;
  }

  static Future<Uint8List> _cardStill(ui.Image image, {required bool grey}) async {
    const w = _nextImageWidth, h = _nextImageWidth * 9 ~/ 16;
    const r = Radius.circular(36);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRRect(RRect.fromLTRBAndCorners(0, 0, w.toDouble(), h.toDouble(), topLeft: r, topRight: r));
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (grey) {
      paint.colorFilter = const ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    }
    final src = Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
    final fit = applyBoxFit(BoxFit.cover, src.size, const Size(w + 0.0, h + 0.0));
    canvas.drawImageRect(image, Alignment.center.inscribe(fit.source, src), Offset.zero & const Size(w + 0.0, h + 0.0), paint);
    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    picture.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    out.dispose();
    final px = data!.buffer.asUint8List();
    for (var i = 0; i < px.length; i += 4) {
      final red = px[i];
      px[i] = px[i + 2];
      px[i + 2] = red;
    }
    return px;
  }

  Future<void> _toggleFullscreen() async {
    final fs = await NativeWindow.toggleFullScreen();
    _mpv.setProperty('user-data/zerk/fullscreen', fs ? 'yes' : 'no');
    await VideoHost.focus();
  }

  Future<void> _loadUserConfig() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'mpv.conf'));
      if (await file.exists()) {
        debugPrint('[mpv] loading the user mpv.conf: ${file.path}');
        _mpv.command(['load-config-file', file.path]);
      }
    } catch (e) {
      debugPrint('[mpv] mpv.conf: $e');
    }
  }

  static String _osdScriptPath() => p.join(
        p.dirname(Platform.resolvedExecutable),
        'data', 'flutter_assets', 'assets', 'mpv', 'zerk_osd.lua',
      );
}
