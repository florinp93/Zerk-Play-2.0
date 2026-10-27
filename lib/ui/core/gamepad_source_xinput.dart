import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'gamepad.dart';

void startPolling(void Function(int pad, int? buttons) onButtons) {
  if (!Platform.isWindows) return;
  _XInput(onButtons).start();
}

final class _XInput {
  _XInput(this._onButtons);

  final void Function(int pad, int? buttons) _onButtons;
  final _connected = <int>{};
  final _state = calloc<XINPUT_STATE>();
  Timer? _poll;

  static final _map = [
    (XINPUT_GAMEPAD_DPAD_UP, PadButton.up),
    (XINPUT_GAMEPAD_DPAD_DOWN, PadButton.down),
    (XINPUT_GAMEPAD_DPAD_LEFT, PadButton.left),
    (XINPUT_GAMEPAD_DPAD_RIGHT, PadButton.right),
    (XINPUT_GAMEPAD_A, PadButton.ok),
    (XINPUT_GAMEPAD_B, PadButton.back),
    (XINPUT_GAMEPAD_BACK, PadButton.back),
    (XINPUT_GAMEPAD_Y, PadButton.menu),
    (XINPUT_GAMEPAD_START, PadButton.playPause),
    (XINPUT_GAMEPAD_LEFT_SHOULDER, PadButton.rewind),
    (XINPUT_GAMEPAD_RIGHT_SHOULDER, PadButton.forward),
    (XINPUT_GAMEPAD_X, PadButton.info),
  ];

  void start() {
    _rescan();
    Timer.periodic(const Duration(seconds: 2), (_) => _rescan());
  }

  void _rescan() {
    for (var i = 0; i < XUSER_MAX_COUNT; i++) {
      if (_connected.contains(i)) continue;
      if (XInputGetState(i, _state) == ERROR_SUCCESS) {
        _connected.add(i);
        _onButtons(i, _buttons(_state.ref.Gamepad));
      }
    }
    if (_connected.isNotEmpty) {
      _poll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    }
  }

  void _tick() {
    for (final i in _connected.toList()) {
      if (XInputGetState(i, _state) != ERROR_SUCCESS) {
        _connected.remove(i);
        _onButtons(i, null);
        continue;
      }
      _onButtons(i, _buttons(_state.ref.Gamepad));
    }
    if (_connected.isEmpty) {
      _poll?.cancel();
      _poll = null;
    }
  }

  static int _buttons(XINPUT_GAMEPAD pad) {
    var raw = pad.wButtons;
    const dead = 20000;
    if (pad.sThumbLY > dead) raw |= XINPUT_GAMEPAD_DPAD_UP;
    if (pad.sThumbLY < -dead) raw |= XINPUT_GAMEPAD_DPAD_DOWN;
    if (pad.sThumbLX < -dead) raw |= XINPUT_GAMEPAD_DPAD_LEFT;
    if (pad.sThumbLX > dead) raw |= XINPUT_GAMEPAD_DPAD_RIGHT;
    var buttons = 0;
    for (final (bit, b) in _map) {
      if (raw & bit != 0) buttons |= Gamepad.mask(b);
    }
    return buttons;
  }
}
