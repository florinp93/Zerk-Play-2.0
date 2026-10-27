import 'package:flutter/widgets.dart';

import '../focus/focus_zone.dart';
import 'gamepad_source_stub.dart' if (dart.library.ffi) 'gamepad_source_xinput.dart' as source;
import 'input_mode.dart';
import 'navigation.dart';

class MenuIntent extends Intent {
  const MenuIntent();
}

enum PadButton { up, down, left, right, ok, back, menu, playPause, rewind, forward, info }

abstract final class Gamepad {
  static void Function(String mpvKey)? playerSink;

  static final _previous = <int, int>{};

  static PadButton? _held;
  static DateTime _heldSince = DateTime(0);
  static DateTime _lastRepeat = DateTime(0);
  static const _repeatDelay = Duration(milliseconds: 380);
  static const _repeatEvery = Duration(milliseconds: 85);

  static bool _started = false;

  static void start() {
    if (_started) return;
    _started = true;
    source.startPolling(_onButtons);
  }

  static int mask(PadButton b) => 1 << b.index;

  static void _onButtons(int pad, int? buttons) {
    if (buttons == null) {
      _previous.remove(pad);
      _repeat(0);
      return;
    }
    final before = _previous[pad];
    _previous[pad] = buttons;
    if (before == null) return;
    final pressed = buttons & ~before;
    for (final b in PadButton.values) {
      if (pressed & mask(b) != 0) _press(b);
    }
    _repeat(buttons);
  }

  static void _repeat(int buttons) {
    PadButton? dir;
    for (final b in const [PadButton.up, PadButton.down, PadButton.left, PadButton.right]) {
      if (buttons & mask(b) != 0) dir = b;
    }
    final now = DateTime.now();
    if (dir != _held) {
      _held = dir;
      _heldSince = now;
      _lastRepeat = now;
      return;
    }
    if (dir != null && now.difference(_heldSince) > _repeatDelay && now.difference(_lastRepeat) > _repeatEvery) {
      _lastRepeat = now;
      _press(dir);
    }
  }

  static void _press(PadButton b) {
    final sink = playerSink;
    if (sink != null) {
      final key = switch (b) {
        PadButton.up => 'UP',
        PadButton.down => 'DOWN',
        PadButton.left => 'LEFT',
        PadButton.right => 'RIGHT',
        PadButton.ok => 'ENTER',
        PadButton.back => 'ESC',
        PadButton.menu => 's',
        PadButton.playPause => 'PLAYPAUSE',
        PadButton.rewind => 'REWIND',
        PadButton.forward => 'FORWARD',
        PadButton.info => 'i',
      };
      sink(key);
      return;
    }
    if (InputMode.useDpad()) return;
    final context = FocusManager.instance.primaryFocus?.context;
    switch (b) {
      case PadButton.up:
        ZoneNavigator.move(TraversalDirection.up);
      case PadButton.down:
        ZoneNavigator.move(TraversalDirection.down);
      case PadButton.left:
        ZoneNavigator.move(TraversalDirection.left);
      case PadButton.right:
        ZoneNavigator.move(TraversalDirection.right);
      case PadButton.ok:
        if (context != null) Actions.maybeInvoke(context, const ActivateIntent());
      case PadButton.back:
        if (context != null) Actions.maybeInvoke(context, const BackIntent());
      case PadButton.menu:
        if (context != null) Actions.maybeInvoke(context, const MenuIntent());
      case PadButton.playPause || PadButton.rewind || PadButton.forward || PadButton.info:
        break;
    }
  }
}
