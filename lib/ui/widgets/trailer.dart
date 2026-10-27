import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../l10n/l10n.dart';
import '../../playback/trailer/trailer_player.dart';
import '../../playback/trailer/trailers.dart';
import '../core/navigation.dart';
import '../core/ui_sounds.dart';
import '../theme/tokens.dart';
import 'common.dart';

class TrailerController extends ChangeNotifier {
  TrailerController(this._services) {
    _services.addListener(_onSettings);
  }

  final AppServices _services;

  List<TrailerRef> _refs = const [];
  String? _key;
  TrailerPlayer? _player;
  Future<TrailerPlayer?>? _creating;
  Timer? _autoplay;
  bool _onstage = true;
  bool _watching = false;
  bool _playing = false;

  bool _done = false;
  bool _disposed = false;
  Size _renderSize = const Size(1920, 1080);

  static const autoplayDelay = Duration(milliseconds: 2500);

  AppSettings get _settings => _services.settings;

  bool get available => TrailerPlayer.supported && _settings.trailers != TrailerMode.off && _refs.isNotEmpty;

  bool get playing => _playing;

  bool get sound => _settings.trailerSound;

  TrailerPlayer? get player => _player;

  Size get renderSize => _renderSize;

  void load(String key, Future<List<TrailerRef>> Function() find) {
    if (key == _key || !TrailerPlayer.supported || _settings.trailers == TrailerMode.off) return;
    _key = key;
    _done = false;
    _refs = const [];
    _autoplay?.cancel();
    unawaited(_player?.stop());
    notifyListeners();
    find().then((refs) {
      if (_disposed || key != _key) return;
      _refs = refs;
      debugPrint('[trailer] $key: ${refs.isEmpty ? 'none' : refs.join(', ')}');
      notifyListeners();
      _scheduleAutoplay();
    }).catchError((Object e) {
      debugPrint('[trailer] lookup $key: $e');
    });
  }

  void toggleSound() {
    UiSounds.play(UiSound.select);
    _services.updateSettings(_settings.copyWith(trailerSound: !sound));
  }

  Future<void> watch(BuildContext context, {required String title}) async {
    if (!available || _watching) return;
    _autoplay?.cancel();
    _watching = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    final player = await _ensurePlayer();
    if (player == null || _disposed) {
      _watching = false;
      UiSounds.play(UiSound.error);
      return;
    }
    player.setCover(false);
    final s = player.state.value;
    if (s.ready && !s.failed) {
      if (s.ended) player.restart();
      player.setPaused(false);
    } else {
      unawaited(_start());
    }
    await navigator.push(_TheatreRoute(trailer: this, player: player, title: title));
    _watching = false;
    if (_disposed) return;
    final now = player.state.value;
    if (now.ended || now.failed || !_onstage) {
      _done = _done || now.ended;
      await player.stop();
    } else {
      player.setCover(true);
    }
  }

  void setOnstage(bool onstage) {
    if (onstage == _onstage) return;
    _onstage = onstage;
    if (onstage) {
      _scheduleAutoplay();
    } else {
      _autoplay?.cancel();
      if (!_watching) unawaited(_player?.stop());
    }
  }

  void setRenderSize(Size size) {
    if (size.isEmpty || size == _renderSize) return;
    _renderSize = size;
    _player?.setRenderSize(size);
  }

  void _onSettings() {
    final p = _player;
    if (p != null && p.state.value.muted == sound) p.setMuted(!sound);
    if (_settings.trailers == TrailerMode.off && p != null) unawaited(p.stop());
    notifyListeners();
  }

  void _scheduleAutoplay() {
    _autoplay?.cancel();
    if (_done || !_onstage || _watching || _refs.isEmpty || _settings.trailers != TrailerMode.autoplay) return;
    unawaited(_refs.first.resolve().then((_) {}, onError: (_) {}));
    _autoplay = Timer(autoplayDelay, _start);
  }

  Future<TrailerPlayer?> _ensurePlayer() {
    if (_player != null) return Future.value(_player);
    return _creating ??= TrailerPlayer.create(
      renderSize: _renderSize,
      acceptInvalidCertificates: _settings.acceptInvalidCertificates,
    ).then((p) {
      _creating = null;
      if (_disposed) {
        p?.dispose();
        return null;
      }
      _player = p;
      p?.state.addListener(_onPlayerState);
      notifyListeners();
      return p;
    });
  }

  Future<void> _start() async {
    final key = _key;
    final player = await _ensurePlayer();
    if (player == null) return;
    player.setCover(!_watching);
    for (final ref in _refs) {
      if (_disposed || key != _key || (!_onstage && !_watching)) return;
      try {
        final stream = await ref.resolve();
        if (_disposed || key != _key) return;
        if (await player.open(stream, muted: !sound)) return;
      } catch (e) {
        debugPrint('[trailer] $ref: $e');
      }
    }
    _done = true;
  }

  void _onPlayerState() {
    final s = _player?.state.value;
    if (s == null) return;
    if (s.ended) _done = true;
    final playing = s.ready && !s.ended && !s.failed;
    if (playing != _playing) {
      _playing = playing;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _services.removeListener(_onSettings);
    _autoplay?.cancel();
    _player?.state.removeListener(_onPlayerState);
    unawaited(_player?.dispose());
    _player = null;
    super.dispose();
  }
}

class TrailerButtons extends StatelessWidget {
  const TrailerButtons(
      {super.key, required this.controller, required this.title, required this.focusNode, this.collapsed = false});

  final TrailerController controller;
  final String title;
  final FocusNode focusNode;

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.available) return const SizedBox.shrink();
        final watch = TvButton(
          focusNode: focusNode,
          label: controller.playing ? l10n.trailerFullScreen : l10n.trailer,
          icon: controller.playing ? Icons.fullscreen_rounded : Icons.theaters_rounded,
          collapsed: collapsed,
          onSelect: () => controller.watch(context, title: title),
        );
        if (!controller.playing) return watch;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          TvButton(
            label: controller.sound ? l10n.trailerMute : l10n.trailerUnmute,
            icon: controller.sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            compact: !collapsed,
            collapsed: collapsed,
            onSelect: controller.toggleSound,
          ),
          const SizedBox(width: 18),
          watch,
        ]);
      },
    );
  }
}

class TrailerVideo extends StatefulWidget {
  const TrailerVideo({super.key, required this.controller});

  final TrailerController controller;

  @override
  State<TrailerVideo> createState() => _TrailerVideoState();
}

class _TrailerVideoState extends State<TrailerVideo> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onstage = TickerMode.valuesOf(context).enabled;
    final size = MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.setOnstage(onstage);
      widget.controller.setRenderSize(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final player = widget.controller.player;
        if (player == null) return const SizedBox.shrink();
        return ValueListenableBuilder<TrailerState>(
          valueListenable: player.state,
          builder: (context, s, _) {
            final visible = s.ready && !s.ended && !s.failed && s.hasSurface;
            return IgnorePointer(
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: visible ? const Duration(milliseconds: 1600) : const Duration(milliseconds: 1800),
                curve: Curves.easeInOutSine,
                child: !s.hasSurface ? const SizedBox.expand() : _Frame(state: s, size: widget.controller.renderSize),
              ),
            );
          },
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.state, required this.size});

  final TrailerState state;
  final Size size;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Texture(textureId: state.textureId!, filterQuality: FilterQuality.medium),
          ),
        ),
      );
}

class _TheatreRoute extends PageRoute<void> {
  _TheatreRoute({required this.trailer, required this.player, required this.title});

  final TrailerController trailer;
  final TrailerPlayer player;
  final String title;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 480);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 360);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      Material(type: MaterialType.transparency, child: _Theatre(controller: trailer, player: player, title: title));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) =>
      FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child);
}

class _Theatre extends StatefulWidget {
  const _Theatre({required this.controller, required this.player, required this.title});

  final TrailerController controller;
  final TrailerPlayer player;
  final String title;

  @override
  State<_Theatre> createState() => _TheatreState();
}

class _TheatreState extends State<_Theatre> {
  final _focus = FocusNode(debugLabel: 'trailer');
  final _backFocus = FocusNode(debugLabel: 'trailer-back', canRequestFocus: false, skipTraversal: true);
  Timer? _hide;
  bool _chrome = true;
  bool _closing = false;

  TrailerPlayer get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _player.state.addListener(_onState);
    _poke();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _player.state.removeListener(_onState);
    _focus.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  void _onState() {
    final s = _player.state.value;
    if ((s.ended || s.failed) && !_closing) {
      if (s.failed) UiSounds.play(UiSound.error);
      _close();
    }
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _poke() {
    _hide?.cancel();
    if (!_chrome) setState(() => _chrome = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && !_player.state.value.paused) setState(() => _chrome = false);
    });
  }

  void _togglePause() {
    final paused = !_player.state.value.paused;
    _player.setPaused(paused);
    UiSounds.play(UiSound.select);
    _poke();
  }

  void _toggleSound() {
    widget.controller.toggleSound();
    _poke();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _player.seekBy(const Duration(seconds: -10));
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _player.seekBy(const Duration(seconds: 10));
      _poke();
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyM || k == LogicalKeyboardKey.audioVolumeMute) {
      _toggleSound();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaStop) {
      _close();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _poke();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      onBack: () {
        UiSounds.play(UiSound.back);
        _close();
        return true;
      },
      child: Actions(
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _togglePause())},
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: MouseRegion(
            onHover: (_) => _poke(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePause,
              onSecondaryTap: _close,
              child: ColoredBox(
                color: Colors.black,
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => ValueListenableBuilder<TrailerState>(
                    valueListenable: _player.state,
                    builder: (context, s, _) => Stack(fit: StackFit.expand, children: [
                      if (s.hasSurface)
                        AnimatedOpacity(
                          opacity: s.ready ? 1 : 0,
                          duration: Zm.slow,
                          child: _Frame(state: s, size: widget.controller.renderSize),
                        ),
                      if (!s.ready) const Center(child: _Spinner()),
                      AnimatedOpacity(
                        opacity: _chrome || s.paused ? 1 : 0,
                        duration: Zm.slow,
                        child: _Chrome(
                          title: widget.title,
                          state: s,
                          sound: widget.controller.sound,
                          onSound: _toggleSound,
                        ),
                      ),
                      Positioned(
                        left: Zs.pageInset,
                        top: 64,
                        child: AnimatedOpacity(
                          opacity: _chrome || s.paused ? 1 : 0,
                          duration: Zm.slow,
                          child: TvButton(
                            label: context.l10n.back,
                            icon: Icons.arrow_back_rounded,
                            compact: true,
                            focusNode: _backFocus,
                            onSelect: () {
                              UiSounds.play(UiSound.back);
                              _close();
                            },
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 4, color: Zc.accent));
}

class _Chrome extends StatelessWidget {
  const _Chrome({required this.title, required this.state, required this.sound, required this.onSound});

  final String title;
  final TrailerState state;
  final bool sound;
  final VoidCallback onSound;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = state.duration.inMilliseconds;
    final progress = d <= 0 ? 0.0 : state.position.inMilliseconds / d;
    String clock(Duration t) => '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: [0, 0.32],
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Zs.pageInset, 0, Zs.pageInset, 56),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IgnorePointer(child: Pill(l10n.trailerBadge, color: Zc.accent, textColor: Zc.text)),
            const SizedBox(width: 16),
            Expanded(
              child: IgnorePointer(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.title)),
            ),
            if (state.paused) const Icon(Icons.pause_rounded, size: 40, color: Zc.text),
            const SizedBox(width: 20),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onSound,
                child: Icon(sound ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 40, color: Zc.text),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          IgnorePointer(child: ClipRRect(borderRadius: BorderRadius.circular(3), child: ProgressStrip(progress, height: 6))),
          const SizedBox(height: 14),
          IgnorePointer(
            child: Row(children: [
              Text('${clock(state.position)} / ${clock(state.duration)}', style: Zt.caption),
              const Spacer(),
              Text(l10n.trailerHints, style: Zt.caption),
            ]),
          ),
        ]),
      ),
    );
  }
}
