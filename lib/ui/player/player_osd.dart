import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../playback/media3/osd_model.dart';
import '../../playback/player_backend.dart';
import '../../playback/subtitle_style.dart';
import '../core/navigation.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/net_image.dart';
import '../widgets/side_panel.dart';
import '../widgets/value_slider.dart';
import 'player_loading.dart';

class _ScreenBand extends StatelessWidget {
  const _ScreenBand({required this.model, required this.child});

  final OsdModel model;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: model,
        child: child,
        builder: (context, child) => LayoutBuilder(builder: (context, box) {
          final scope = model.scope;
          if (scope <= 0 || !box.hasBoundedHeight || box.maxHeight == 0 || scope <= box.maxWidth / box.maxHeight + 0.01) return child!;
          return Center(child: SizedBox(width: box.maxWidth, height: box.maxWidth / scope, child: child));
        }),
      );
}

class PlayerOsdRoute extends PageRoute<void> {
  PlayerOsdRoute({required this.model, this.controls = true, this.background});

  final OsdModel model;
  final bool controls;

  final Widget? background;

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Zm.normal;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => didPop ? null : model.send('back'),
        child: Material(
          type: MaterialType.transparency,
          child: background == null
              ? _ScreenBand(model: model, child: PlayerOsd(model: model, controls: controls))
              : Stack(fit: StackFit.expand, children: [background!, _ScreenBand(model: model, child: PlayerOsd(model: model, controls: controls))]),
        ),
      );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: animation, child: child);
}

class PlayerOsd extends StatefulWidget {
  const PlayerOsd({super.key, required this.model, this.controls = true});

  final OsdModel model;

  final bool controls;

  @override
  State<PlayerOsd> createState() => _PlayerOsdState();
}

class _PlayerOsdState extends State<PlayerOsd> with SingleTickerProviderStateMixin {
  static const _autoHide = Duration(seconds: 5);

  final _root = FocusNode(debugLabel: 'osd-root');
  final _playButton = FocusNode(debugLabel: 'osd-play');
  bool _visible = false;
  bool _panelOpen = false;
  Timer? _hideTimer;

  Duration? _seekTarget;
  Timer? _seekCommit;
  DateTime _miniUntil = DateTime(0);

  DateTime _volumeUntil = DateTime(0);

  String _digits = '';
  Timer? _digitsCommit;

  bool _introSkipped = false;
  bool _nextCancelled = false;
  String _lastPhase = '';

  late final _countdown = AnimationController(vsync: this)
    ..addStatusListener((s) => s == AnimationStatus.completed ? _playNext() : null);
  bool _countdownStarted = false;

  int _nextChoice = 0;
  bool _nextHover = false;
  bool _introHover = false;

  ({bool spinner, bool intro, bool next})? _hiddenShown;

  OsdModel get model => widget.model;
  PlayerState get state => model.state.value;

  @override
  void initState() {
    super.initState();
    model.addListener(_onModel);
    model.state.addListener(_onState);
    model.onToast = (text) {
      if (mounted) showToast(context, text);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _root.requestFocus());
  }

  @override
  void dispose() {
    model.removeListener(_onModel);
    model.state.removeListener(_onState);
    model.onToast = null;
    _hideTimer?.cancel();
    _seekCommit?.cancel();
    _digitsCommit?.cancel();
    _countdown.dispose();
    _root.dispose();
    _playButton.dispose();
    super.dispose();
  }

  void _onModel() {
    if (model.phase == 'loading' && _lastPhase != 'loading') {
      _introSkipped = false;
      _nextCancelled = false;
      _nextChoice = 0;
      _nextHover = _introHover = false;
      _stopCountdown();
    }
    _lastPhase = model.phase;
    setState(() {});
  }

  void _onState() {
    if (!widget.controls) return;
    final s = state;
    if (model.autoSkipIntro && _inIntro(s.position) && !_introSkipped) _skipIntro();
    final nextUp = _nextVisible(s);
    if (nextUp && model.next!.autoplay && !_countdownStarted) _startCountdown(model.next!.countdown);
    if (!nextUp && _countdownStarted) _stopCountdown();
    if (_countdownStarted && _countdown.value < 1) {
      if (s.paused && _countdown.isAnimating) _countdown.stop();
      if (!s.paused && !_countdown.isAnimating) _countdown.forward();
    }
    final shown = (spinner: s.buffering && !s.paused, intro: _introVisible(s), next: nextUp);
    final tracking = DateTime.now().isBefore(_miniUntil) || shown.intro || shown.next;
    if (!_visible && !tracking && shown == _hiddenShown) return;
    _hiddenShown = shown;
    setState(() {});
  }

  void _show({bool focusPlay = true}) {
    if (!_visible) {
      setState(() => _visible = true);
      if (focusPlay) WidgetsBinding.instance.addPostFrameCallback((_) => _playButton.requestFocus());
    }
    _armHide();
  }

  void _hide() {
    _hideTimer?.cancel();
    setState(() => _visible = false);
    _root.requestFocus();
  }

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHide, () {
      if (!mounted || _panelOpen || state.paused || model.phase != 'playing') return _armHide();
      _hide();
    });
  }

  void _seekBy(int seconds) {
    final s = state;
    final base = _seekTarget ?? s.position;
    var target = base + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (s.duration > Duration.zero && target > s.duration) target = s.duration - const Duration(seconds: 1);
    setState(() {
      _seekTarget = target;
      _miniUntil = DateTime.now().add(const Duration(seconds: 2));
    });
    _seekCommit?.cancel();
    _seekCommit = Timer(const Duration(milliseconds: 450), () {
      final t = _seekTarget;
      if (t != null) model.seekTo(t);
      Timer(const Duration(milliseconds: 700), () => mounted ? setState(() => _seekTarget = null) : null);
    });
  }

  void _scrubTo(Duration target) {
    _seekCommit?.cancel();
    _armHide();
    setState(() => _seekTarget = target);
  }

  void _commitScrub() {
    final t = _seekTarget;
    if (t == null) return;
    model.seekTo(t);
    Timer(const Duration(milliseconds: 700), () => mounted ? setState(() => _seekTarget = null) : null);
  }

  bool _inIntro(Duration p) {
    final start = model.introStart, end = model.introEnd;
    return start != null && end != null && p >= start && p < end - const Duration(seconds: 1);
  }

  void _skipIntro() {
    final end = model.introEnd;
    if (end == null) return;
    _introSkipped = true;
    _introHover = false;
    model.seekTo(end);
  }

  bool _introVisible(PlayerState s) => model.phase == 'playing' && _inIntro(s.position) && !_introSkipped;

  bool _nextVisible(PlayerState s) {
    if (model.next == null || _nextCancelled || model.phase != 'playing' || s.duration <= Duration.zero) return false;
    if (_introVisible(s)) return false;
    final from = model.creditsStart ?? s.duration - const Duration(seconds: 30);
    return s.position >= from;
  }

  void _startCountdown(int seconds) {
    _countdownStarted = true;
    _nextChoice = 0;
    _countdown.duration = Duration(seconds: seconds);
    _countdown.forward(from: 0);
  }

  void _stopCountdown() {
    _countdownStarted = false;
    _countdown.stop();
    _countdown.value = 0;
  }

  void _playNext() {
    _stopCountdown();
    UiSounds.play(UiSound.select);
    model.send('next');
  }

  void _cancelNext() {
    _stopCountdown();
    setState(() => _nextCancelled = true);
    model.send('next-cancel');
  }

  Future<void> _choose(String title, List<OsdChoice> choices, String event) async {
    _panelOpen = true;
    final chosen = await showSidePanel<String>(context, title: title, options: [
      for (final c in choices) PanelOption(value: c.id, title: c.label, subtitle: c.detail, selected: c.selected),
    ]);
    _panelOpen = false;
    _armHide();
    if (chosen != null) model.send(event, chosen);
  }

  Future<void> _chooseSubtitles() async {
    final l10n = context.l10n;
    _panelOpen = true;
    final chosen = await showSidePanel<String>(context, title: l10n.subtitles, options: [
      if (model.subtitleSearch) PanelOption(value: 'search', title: l10n.searchSubtitles, icon: Icons.search_rounded),
      PanelOption(value: 'size', title: l10n.subtitleSize, subtitle: SubtitleStyle.percent(model.subtitleScale), icon: Icons.format_size_rounded),
      PanelOption(value: '-1', title: l10n.subtitleOff, selected: !model.subs.any((c) => c.selected)),
      for (final c in model.subs) PanelOption(value: c.id, title: c.label, subtitle: c.detail, selected: c.selected),
    ]);
    _panelOpen = false;
    _armHide();
    if (chosen == 'size') return _chooseSubtitleSize();
    if (chosen == 'search') return _searchSubtitles();
    if (chosen != null) model.send('sub', chosen);
  }

  Future<void> _searchSubtitles() async {
    final l10n = context.l10n;
    _panelOpen = true;
    final language = await showSidePanel<String>(context, title: l10n.searchSubtitles, options: [
      for (final c in model.subtitleLanguages) PanelOption(value: c.id, title: c.label),
    ]);
    if (language == null || !mounted) {
      _panelOpen = false;
      _armHide();
      return;
    }
    model.onToast?.call(l10n.subtitleSearching);
    final found = await model.searchSubtitles(language);
    if (!mounted) return;
    if (found.error != null || found.results.isEmpty) {
      _panelOpen = false;
      _armHide();
      model.onToast?.call(found.error ?? l10n.subtitleSearchEmpty);
      return;
    }
    final chosen = await showSidePanel<String>(context, title: l10n.searchSubtitles, options: [
      for (final c in found.results) PanelOption(value: c.id, title: c.label, subtitle: c.detail),
    ]);
    _panelOpen = false;
    _armHide();
    if (chosen != null) model.send('subdownload', chosen);
  }

  Future<void> _chooseSubtitleSize() async {
    final original = model.subtitleScale;
    _panelOpen = true;
    final chosen = await showSliderPanel(
      context,
      title: context.l10n.subtitleSize,
      hint: context.l10n.sliderHint,
      value: original,
      min: SubtitleStyle.minScale,
      max: SubtitleStyle.maxScale,
      step: SubtitleStyle.scaleStep,
      marks: SubtitleStyle.marks,
      format: SubtitleStyle.percent,
      onChanged: (s) {
        model.subtitleScale = s;
        model.send('subscale-preview', s.toStringAsFixed(2));
      },
    );
    _panelOpen = false;
    _armHide();
    model.subtitleScale = chosen ?? original;
    model.send(chosen == null ? 'subscale-preview' : 'subscale', (chosen ?? original).toStringAsFixed(2));
  }

  Future<void> _chooseSettings() async {
    final l10n = context.l10n;
    _panelOpen = true;
    final chosen = await showSidePanel<String>(context, title: l10n.settings, options: [
      PanelOption(value: 'aspect', title: l10n.aspectRatio, subtitle: _aspectLabel(l10n, model.aspect), icon: Icons.aspect_ratio_rounded),
      PanelOption(value: 'speed', title: l10n.playbackSpeed, subtitle: _speedLabel(model.speed), icon: Icons.speed_rounded),
      if (model.stats != null)
        PanelOption(value: 'info', title: l10n.playbackInfo, subtitle: l10n.playbackInfoDetail, icon: Icons.info_outline_rounded),
    ]);
    _panelOpen = false;
    _armHide();
    if (chosen == 'aspect') return _chooseAspect();
    if (chosen == 'speed') return _chooseSpeed();
    if (chosen == 'info') return _showInfo();
  }

  static String _aspectLabel(L10n l10n, String mode) => switch (mode) {
        'zoom' => l10n.aspectZoom,
        'fill' => l10n.aspectStretch,
        _ => l10n.aspectOriginal,
      };

  static String _speedLabel(double speed) => '${speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : '$speed'}x';

  Future<void> _chooseAspect() async {
    final l10n = context.l10n;
    _panelOpen = true;
    final chosen = await showSidePanel<String>(context, title: l10n.aspectRatio, options: [
      for (final (mode, detail) in [('fit', l10n.aspectOriginalDetail), ('zoom', l10n.aspectZoomDetail), ('fill', l10n.aspectStretchDetail)])
        PanelOption(value: mode, title: _aspectLabel(l10n, mode), subtitle: detail, selected: model.aspect == mode),
    ]);
    _panelOpen = false;
    _armHide();
    if (chosen == null) return;
    model.aspect = chosen;
    model.setAspect?.call(chosen);
  }

  Future<void> _chooseSpeed() async {
    _panelOpen = true;
    final chosen = await showSidePanel<double>(context, title: context.l10n.playbackSpeed, options: [
      for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
        PanelOption(value: s, title: _speedLabel(s), selected: s == model.speed),
    ]);
    _panelOpen = false;
    _armHide();
    if (chosen == null) return;
    model.speed = chosen;
    model.setSpeed?.call(chosen);
  }

  Future<void> _showInfo() async {
    final l10n = context.l10n;
    final s = await model.stats!();
    if (!mounted) return;
    String? join(List<String?> parts) {
      final shown = parts.whereType<String>().where((p) => p.isNotEmpty).toList();
      return shown.isEmpty ? null : shown.join('  ·  ');
    }

    String? mbps(Object? bits) => bits is num ? '${(bits / 1e6).toStringAsFixed(1)} Mbps' : null;
    final fps = s['fps'];
    final rows = [
      (l10n.infoVideo, join([
        _codecName(s['videoMime']),
        if (s['width'] case final num w when w > 0) '$w×${s['height']}',
        if (fps is num) '${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 3)} fps',
        mbps(s['videoBitrate']),
      ])),
      (l10n.infoVideoDecoder, s['videoDecoder'] as String?),
      (l10n.audio, join([
        _codecName(s['audioMime']),
        if (s['channels'] case final num c) '$c ch',
        if (s['sampleRate'] case final num r) '${(r / 1000).toStringAsFixed(r % 1000 == 0 ? 0 : 1)} kHz',
        mbps(s['audioBitrate']),
      ])),
      (l10n.infoAudioDecoder, s['audioDecoder'] as String?),
      (l10n.infoDropped, s['dropped']?.toString()),
      (l10n.playbackSpeed, s['speed'] is num ? _speedLabel((s['speed'] as num).toDouble()) : null),
    ];
    _panelOpen = true;
    await showSidePanel<void>(context, title: l10n.playbackInfo, options: [
      for (final (label, value) in rows)
        if (value != null) PanelOption(value: null, title: label, subtitle: value),
    ]);
    _panelOpen = false;
    _armHide();
  }

  static String? _codecName(Object? mime) => switch (mime) {
        null => null,
        'video/hevc' => 'HEVC',
        'video/avc' => 'H.264',
        'video/dolby-vision' => 'Dolby Vision',
        'video/av01' => 'AV1',
        'video/x-vnd.on2.vp9' => 'VP9',
        'video/mpeg2' => 'MPEG-2',
        'audio/eac3-joc' => 'E-AC-3 Atmos',
        'audio/eac3' => 'E-AC-3',
        'audio/ac3' => 'AC-3',
        'audio/true-hd' => 'TrueHD',
        'audio/vnd.dts' => 'DTS',
        'audio/vnd.dts.hd' => 'DTS-HD',
        'audio/mp4a-latm' => 'AAC',
        'audio/opus' => 'Opus',
        'audio/flac' => 'FLAC',
        'audio/raw' => 'PCM',
        final m => '$m'.split('/').last.toUpperCase(),
      };

  Future<void> _chooseChapter() async {
    final chapters = model.chapters;
    final position = model.state.value.position;
    final current = chapters.lastIndexWhere((c) => c.start <= position + const Duration(milliseconds: 500));
    _panelOpen = true;
    final chosen = await showSidePanel<Duration>(context, title: context.l10n.chapters, options: [
      for (final (i, c) in chapters.indexed)
        PanelOption(
          value: c.start,
          title: c.title ?? context.l10n.chapterNumber('${i + 1}'),
          subtitle: _fmt(c.start),
          image: c.image,
          selected: i == current,
        ),
    ]);
    _panelOpen = false;
    _armHide();
    if (chosen != null) model.seekTo(chosen);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    final repeat = e is KeyRepeatEvent;

    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause || key == LogicalKeyboardKey.space) {
      if (!repeat) model.togglePause();
      _show(focusPlay: !_visible);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward || key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(key == LogicalKeyboardKey.mediaFastForward ? model.seekForward : -model.seekBack);
      return KeyEventResult.handled;
    }
    if (model.zap && widget.controls) {
      final up = key == LogicalKeyboardKey.channelUp || key == LogicalKeyboardKey.pageUp ||
          (!_visible && key == LogicalKeyboardKey.arrowUp);
      final down = key == LogicalKeyboardKey.channelDown || key == LogicalKeyboardKey.pageDown ||
          (!_visible && key == LogicalKeyboardKey.arrowDown);
      if (up || down) {
        model.send('channel', up ? '+1' : '-1');
        return KeyEventResult.handled;
      }
      final digit = _digitOf(key);
      if (digit != null) {
        if (!repeat) _typeDigit(digit);
        return KeyEventResult.handled;
      }
    }
    if (_visible) {
      _armHide();
      return KeyEventResult.ignored;
    }
    if (model.phase != 'playing' || !widget.controls) return KeyEventResult.ignored;
    if (_nextVisible(state) && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight)) {
      final choice = key == LogicalKeyboardKey.arrowRight ? 1 : 0;
      if (choice != _nextChoice) {
        UiSounds.play(UiSound.move);
        setState(() => _nextChoice = choice);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      _seekBy(key == LogicalKeyboardKey.arrowRight ? model.seekForward : -model.seekBack);
      return KeyEventResult.handled;
    }
    if (repeat) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
      if (_introVisible(state)) {
        UiSounds.play(UiSound.select);
        _skipIntro();
      } else if (_nextVisible(state)) {
        _nextChoice == 0 ? _playNext() : _cancelNext();
      } else if (model.zap) {
        _choose(model.versionsTitle ?? context.l10n.liveChannels, model.versions, 'version');
      } else {
        model.togglePause();
        setState(() => _miniUntil = DateTime.now().add(const Duration(seconds: 2)));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _show();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static int? _digitOf(LogicalKeyboardKey key) {
    for (var d = 0; d <= 9; d++) {
      if (key == _digitKeys[d] || key == _numpadKeys[d]) return d;
    }
    return null;
  }

  static final _digitKeys = [
    LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
  ];
  static final _numpadKeys = [
    LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
  ];

  void _typeDigit(int d) {
    _digitsCommit?.cancel();
    setState(() => _digits += '$d');
    void commit() {
      if (!mounted || _digits.isEmpty) return;
      model.send('channel', 'n:$_digits');
      setState(() => _digits = '');
    }

    if (_digits.length >= 4) {
      commit();
    } else {
      _digitsCommit = Timer(const Duration(milliseconds: 1500), commit);
    }
  }

  bool _onBack() {
    if (!widget.controls) {
      model.send('back');
    } else if (_visible) {
      UiSounds.play(UiSound.back);
      _hide();
    } else if (_nextVisible(state)) {
      UiSounds.play(UiSound.back);
      _cancelNext();
    } else {
      model.send('back');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final loading = model.phase == 'loading';
    final error = model.phase == 'error';
    if (!widget.controls) {
      return BackHandler(
        onBack: _onBack,
        child: Focus(
          focusNode: _root,
          child: error
              ? PlayerErrorView(title: model.title, message: model.message ?? context.l10n.playbackFailed, onBack: () => model.send('back'))
              : model.phase == 'playing'
                  ? const ColoredBox(color: Colors.black)
                  : PlayerLoadingView(title: model.title, subtitle: model.subtitle, backdrop: model.backdrop, logo: model.logo),
        ),
      );
    }
    final miniVisible = !_visible && DateTime.now().isBefore(_miniUntil);
    if (miniVisible) {
      Timer(_miniUntil.difference(DateTime.now()), () => mounted ? setState(() {}) : null);
    }
    final lift = _visible ? 0.27 : (miniVisible ? 0.12 : 0.0);
    if (model.subtitleLift.value != lift) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? model.subtitleLift.value = lift : null);
    }
    return BackHandler(
      onBack: _onBack,
      child: Focus(
        focusNode: _root,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: (_) => _onPointerMove(),
          cursor: _visible || loading || error ? MouseCursor.defer : SystemMouseCursors.none,
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: Stack(fit: StackFit.expand, children: [
          if (loading) PlayerLoadingView(title: model.title, subtitle: model.subtitle, backdrop: model.backdrop, logo: model.logo),
          if (error) PlayerErrorView(title: model.title, message: model.message ?? context.l10n.playbackFailed, onBack: () => model.send('back')),
          if (!loading && !error)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onSurfaceTap,
              ),
            ),
          if (!loading && !error && s.buffering && !s.paused)
            const Center(child: SizedBox(width: 72, height: 72, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 5))),
          if (!loading && !error)
            AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: Zm.normal,
              child: ExcludeFocus(excluding: !_visible, child: IgnorePointer(ignoring: !_visible, child: _controls(s))),
            ),
          if (DateTime.now().isBefore(_volumeUntil))
            Positioned(top: _visible ? 180 : 64, right: 96, child: _VolumeBadge(volume: s.muted ? 0 : s.volume)),
          if (miniVisible) ...[
            const Positioned(top: 64, right: 96, child: _Clock(shadow: true)),
            Positioned(left: 96, right: 96, bottom: 70, child: _ProgressBar(position: _seekTarget ?? s.position, duration: s.duration)),
          ],
          if (!loading && !error && _introVisible(s))
            Positioned(
              right: 96,
              bottom: 300,
              child: MouseRegion(
                onEnter: (_) => setState(() => _introHover = true),
                onExit: (_) => setState(() => _introHover = false),
                child: _SkipIntroPill(
                  start: model.introStart!,
                  end: model.introEnd!,
                  position: s.position,
                  lit: !_visible || _introHover,
                  onTap: () {
                    UiSounds.play(UiSound.select);
                    _skipIntro();
                  },
                ),
              ),
            ),
          if (_nextVisible(s))
            Positioned(
              right: 96,
              bottom: 300,
              child: MouseRegion(
                onEnter: (_) => setState(() => _nextHover = true),
                onExit: (_) => setState(() => _nextHover = false),
                child: _NextCard(
                  next: model.next!,
                  countdown: _countdown,
                  choice: !_visible || _nextHover ? _nextChoice : null,
                  onHover: (i) => setState(() => _nextChoice = i),
                  onPlay: _playNext,
                  onKeepWatching: _cancelNext,
                ),
              ),
            ),
          if (_digits.isNotEmpty)
            Positioned(
              top: 56,
              right: 72,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
                child: Text(_digits,
                    style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w700, letterSpacing: 4)),
              ),
            ),
          ]),
          ),
        ),
      ),
    );
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || model.setVolume == null || model.phase != 'playing') return;
    final s = state;
    final current = s.muted ? 0.0 : s.volume;
    model.setVolume!((current + (e.scrollDelta.dy < 0 ? 5 : -5)).clamp(0, 100).toDouble());
    const shown = Duration(milliseconds: 1500);
    setState(() => _volumeUntil = DateTime.now().add(shown));
    Timer(shown, () => mounted ? setState(() {}) : null);
  }

  void _onPointerMove() {
    if (model.phase != 'playing' || !widget.controls) return;
    _visible ? _armHide() : _show(focusPlay: false);
  }

  void _onSurfaceTap() {
    model.togglePause();
    _show(focusPlay: false);
  }

  Widget _controls(PlayerState s) {
    final l10n = context.l10n;
    final position = _seekTarget ?? s.position;
    return Stack(fit: StackFit.expand, children: [
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000), Color(0x00000000), Color(0xE6000000)],
              stops: [0, 0.28, 0.55, 1],
            ),
          ),
        ),
      ),
      Positioned(
        left: 96,
        right: 96,
        top: 64,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FocusZone(
            debugLabel: 'osd-top',
            child: TvButton(label: l10n.back, icon: Icons.arrow_back_rounded, compact: true, onSelect: () => model.send('back')),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(model.title, style: Zt.display.copyWith(fontSize: 46), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (model.subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(model.subtitle, style: Zt.title.copyWith(color: Zc.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          if (model.videoFormat != null) _Badge(text: model.videoFormat!),
          const SizedBox(width: 28),
          const _Clock(),
        ]),
      ),
      Positioned(
        left: 96,
        right: 96,
        bottom: 64,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          FocusZone(
            debugLabel: 'osd-seek',
            child: _SeekBar(
              position: position,
              duration: s.duration,
              onSeek: (secs) => _seekBy(secs),
              onScrub: _scrubTo,
              onScrubEnd: _commitScrub,
              forwardStep: model.seekForward,
              backStep: model.seekBack,
              marks: [for (final c in model.chapters) c.start],
            ),
          ),
          const SizedBox(height: 34),
          FocusZone(
            debugLabel: 'osd-buttons',
            child: Row(children: [
              TvButton(
                label: s.paused ? l10n.play : l10n.pause,
                icon: s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                compact: true,
                primary: true,
                focusNode: _playButton,
                onSelect: model.togglePause,
              ),
              const SizedBox(width: 18),
              TvButton(label: l10n.seekBack('${model.seekBack}'), icon: Icons.replay_rounded, compact: true, onSelect: () => _seekBy(-model.seekBack)),
              const SizedBox(width: 18),
              TvButton(label: l10n.seekForward('${model.seekForward}'), icon: Icons.forward_rounded, compact: true, onSelect: () => _seekBy(model.seekForward)),
              const Spacer(),
              if (model.setVolume != null) ...[
                _VolumeControl(
                  volume: s.muted ? 0 : s.volume,
                  onToggleMute: model.toggleMute,
                  onChanged: (v) {
                    _armHide();
                    model.setVolume!(v);
                  },
                ),
                const SizedBox(width: 30),
              ],
              if (model.audio.isNotEmpty) ...[
                TvButton(label: l10n.audio, icon: Icons.graphic_eq_rounded, onSelect: () => _choose(l10n.audio, model.audio, 'audio')),
                const SizedBox(width: 18),
              ],
              if (model.subs.isNotEmpty || model.subtitleSearch) ...[
                TvButton(label: l10n.subtitles, icon: Icons.subtitles_outlined, onSelect: _chooseSubtitles),
                const SizedBox(width: 18),
              ],
              if (model.chapters.length > 1) ...[
                TvButton(label: l10n.chapters, icon: Icons.list_rounded, onSelect: _chooseChapter),
                const SizedBox(width: 18),
              ],
              if (model.versions.length > 1) ...[
                TvButton(
                  label: model.versionsTitle ?? l10n.version,
                  icon: model.versionsTitle != null ? Icons.live_tv_rounded : Icons.high_quality_outlined,
                  onSelect: () => _choose(model.versionsTitle ?? l10n.version, model.versions, 'version'),
                ),
                const SizedBox(width: 18),
              ],
              if (model.setAspect != null) ...[
                TvButton(label: l10n.settings, icon: Icons.tune_rounded, onSelect: _chooseSettings),
                const SizedBox(width: 18),
              ],
              if (model.next != null) TvButton(label: l10n.nextEpisode, icon: Icons.skip_next_rounded, onSelect: _playNext),
            ]),
          ),
        ]),
        ),
      ),
    ]);
  }
}

String _fmt(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.position,
    required this.duration,
    this.focused = false,
    this.hover,
    this.onHover,
    this.onScrub,
    this.onScrubEnd,
    this.marks = const [],
  });

  final Duration position;
  final Duration duration;
  final bool focused;
  final List<Duration> marks;

  final double? hover;
  final ValueChanged<double?>? onHover;

  final ValueChanged<double>? onScrub;
  final VoidCallback? onScrubEnd;

  @override
  Widget build(BuildContext context) {
    final frac = duration > Duration.zero ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    return Row(children: [
      SizedBox(width: 130, child: Text(_fmt(position), style: Zt.label)),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) {
            double at(Offset local) => box.maxWidth == 0 ? 0 : (local.dx / box.maxWidth).clamp(0.0, 1.0);
            final bar = SizedBox(
            height: 28,
            child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: Zm.fast,
                height: focused ? 10 : 6,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(5)),
              ),
              AnimatedContainer(
                duration: Zm.fast,
                width: box.maxWidth * frac,
                height: focused ? 10 : 6,
                decoration: BoxDecoration(color: Zc.accent, borderRadius: BorderRadius.circular(5)),
              ),
              if (duration > Duration.zero)
                for (final m in marks)
                  if (m > const Duration(seconds: 1) && m < duration - const Duration(seconds: 1))
                    Positioned(
                      left: box.maxWidth * m.inMilliseconds / duration.inMilliseconds - 1,
                      child: Container(width: 2, height: focused ? 10 : 6, color: Colors.black54),
                    ),
              if (focused)
                Positioned(
                  left: (box.maxWidth * frac - 14).clamp(0, box.maxWidth - 28),
                  child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                ),
              if (hover != null && duration > Duration.zero)
                Positioned(
                  left: (box.maxWidth * hover! - 60).clamp(0, box.maxWidth - 120),
                  bottom: 40,
                  child: Container(
                    width: 120,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(12)),
                    child: Text(_fmt(duration * hover!), style: Zt.label, textAlign: TextAlign.center),
                  ),
                ),
            ]),
          );
            if (onScrub == null) return bar;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (e) => onHover?.call(at(e.localPosition)),
              onExit: (_) => onHover?.call(null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => onScrub!(at(d.localPosition)),
                onTapUp: (_) => onScrubEnd?.call(),
                onHorizontalDragStart: (d) => onScrub!(at(d.localPosition)),
                onHorizontalDragUpdate: (d) {
                  onHover?.call(at(d.localPosition));
                  onScrub!(at(d.localPosition));
                },
                onHorizontalDragEnd: (_) => onScrubEnd?.call(),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 22), child: bar),
              ),
            );
          },
        ),
      ),
      SizedBox(width: 130, child: Text(_fmt(duration), style: Zt.label, textAlign: TextAlign.right)),
    ]);
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onScrub,
    required this.onScrubEnd,
    required this.forwardStep,
    required this.backStep,
    this.marks = const [],
  });

  final Duration position;
  final Duration duration;
  final void Function(int seconds) onSeek;
  final void Function(Duration target) onScrub;
  final VoidCallback onScrubEnd;
  final int forwardStep;
  final int backStep;
  final List<Duration> marks;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  final _node = FocusNode(debugLabel: 'osd-seekbar');

  double? _hover;

  Duration _at(double frac) => widget.duration * frac.clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      onKeyEvent: (node, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.onSeek(-widget.backStep);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
          widget.onSeek(widget.forwardStep);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _ProgressBar(
        position: widget.position,
        duration: widget.duration,
        focused: _node.hasFocus || _hover != null,
        marks: widget.marks,
        hover: _hover,
        onHover: (frac) => setState(() => _hover = frac),
        onScrub: widget.duration > Duration.zero ? (frac) => widget.onScrub(_at(frac)) : null,
        onScrubEnd: widget.onScrubEnd,
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock({this.shadow = false});

  final bool shadow;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() {});
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        DateFormat.Hm(context.l10n.localeName).format(DateTime.now()),
        style: Zt.title.copyWith(
          fontSize: 34,
          shadows: widget.shadow ? const [Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 2))] : null,
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: Zt.label.copyWith(fontSize: 20)),
      );
}

class _SkipIntroPill extends StatelessWidget {
  const _SkipIntroPill({required this.start, required this.end, required this.position, required this.lit, required this.onTap});

  final Duration start;
  final Duration end;
  final Duration position;
  final bool lit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final span = (end - start).inMilliseconds;
    final played = span <= 0 ? 0.0 : ((position - start).inMilliseconds / span).clamp(0.0, 1.0);
    final left = end - position;
    final fg = lit ? Zc.background : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: lit ? 1.04 : 1,
          duration: Zm.fast,
          curve: Zm.curve,
          child: AnimatedContainer(
            duration: Zm.fast,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: lit ? Colors.white : Zc.surfaceHigh.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: lit ? Colors.white : Colors.white24, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10))],
            ),
            child: Stack(alignment: Alignment.centerLeft, children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerRight,
                  widthFactor: 1 - played,
                  child: ColoredBox(color: lit ? const Color(0x1A6C63FF) : const Color(0x336C63FF)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 26, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.fast_forward_rounded, color: lit ? Zc.accent : Colors.white, size: 30),
                  const SizedBox(width: 12),
                  Text(context.l10n.skipIntro, style: Zt.label.copyWith(color: fg, fontSize: 22)),
                  const SizedBox(width: 16),
                  Text(
                    _fmt(left.isNegative ? Duration.zero : left),
                    style: Zt.label.copyWith(color: fg.withValues(alpha: 0.55), fontSize: 20, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.next,
    required this.countdown,
    required this.choice,
    required this.onHover,
    required this.onPlay,
    required this.onKeepWatching,
  });

  static const _width = 400.0;
  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  final NextUp next;
  final Animation<double> countdown;

  final int? choice;
  final ValueChanged<int> onHover;
  final VoidCallback onPlay;
  final VoidCallback onKeepWatching;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final image = next.image;
    return Container(
      width: _width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Zc.surfaceHigh.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 32, offset: Offset(0, 10))],
      ),
      child: AnimatedBuilder(
        animation: countdown,
        builder: (context, _) {
          final fill = next.autoplay ? countdown.value : 1.0;
          final left = (next.countdown * (1 - countdown.value)).ceil();
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (image != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  ColorFiltered(colorFilter: _grey, child: _still(image)),
                  ClipRect(clipper: _LeftPart(fill), child: _still(image)),
                  if (fill > 0 && fill < 1)
                    Positioned(
                      left: _width * fill - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        decoration: const BoxDecoration(
                          color: Color(0xCCFFFFFF),
                          boxShadow: [BoxShadow(color: Color(0x80FFFFFF), blurRadius: 10)],
                        ),
                      ),
                    ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  next.autoplay && left > 0 ? l10n.upNextIn(left) : l10n.upNext,
                  style: Zt.caption.copyWith(fontSize: 16, color: Zc.accentSoft, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(next.title, style: Zt.title.copyWith(fontSize: 22), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (next.subtitle != null)
                  Text(next.subtitle!, style: Zt.body.copyWith(fontSize: 17, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 14),
                Row(children: [
                  _CardButton(
                    label: l10n.playNow,
                    icon: Icons.play_arrow_rounded,
                    lit: choice == 0,
                    primary: true,
                    onHover: () => onHover(0),
                    onTap: onPlay,
                  ),
                  const SizedBox(width: 10),
                  _CardButton(
                    label: l10n.keepWatching,
                    lit: choice == 1,
                    onHover: () => onHover(1),
                    onTap: onKeepWatching,
                  ),
                ]),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _still(Uri url) => Image(
        image: NetImageProvider(url, decodeWidth: 800),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const ColoredBox(color: Zc.surfaceTop),
      );
}

class _LeftPart extends CustomClipper<Rect> {
  const _LeftPart(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftPart old) => old.fraction != fraction;
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.lit,
    required this.onHover,
    required this.onTap,
    this.icon,
    this.primary = false,
  });

  final String label;
  final IconData? icon;
  final bool lit;
  final bool primary;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = lit ? Colors.white : (primary ? Zc.accent : Colors.white.withValues(alpha: 0.12));
    final fg = lit ? Zc.background : Colors.white;
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: Zm.fast,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, color: fg, size: 22), const SizedBox(width: 6)],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: Zt.label.copyWith(color: fg, fontSize: 18)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.volume, required this.onChanged, this.onToggleMute});

  final double volume;
  final ValueChanged<double> onChanged;
  final VoidCallback? onToggleMute;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      TvButton(
        label: volume == 0 ? l10n.unmute : l10n.mute,
        icon: _volumeIcon(volume),
        compact: true,
        onSelect: onToggleMute,
      ),
      const SizedBox(width: 10),
      ExcludeFocus(
        child: SizedBox(
          width: 200,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(value: volume.clamp(0, 100).toDouble(), max: 100, onChanged: onChanged),
          ),
        ),
      ),
    ]);
  }
}

class _VolumeBadge extends StatelessWidget {
  const _VolumeBadge({required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(28)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_volumeIcon(volume), color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Text(volume == 0 ? context.l10n.muted : context.l10n.volumeLevel(volume.round()), style: Zt.label.copyWith(fontSize: 22)),
        ]),
      );
}

IconData _volumeIcon(double volume) =>
    volume == 0 ? Icons.volume_off_rounded : (volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
