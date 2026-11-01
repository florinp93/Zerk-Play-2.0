import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'gamepad.dart';

void startLinuxPolling(void Function(int pad, int? buttons) onButtons) => _Joysticks(onButtons).start();

final class _Pad {
  _Pad(this.subscription);

  final StreamSubscription<List<int>> subscription;
  final pending = BytesBuilder(copy: false);
  int buttons = 0;
  final axes = <int, int>{};
}

final class _Joysticks {
  _Joysticks(this._onButtons);

  final void Function(int pad, int? buttons) _onButtons;
  final _pads = <int, _Pad>{};
  Timer? _poll;

  static const _maxPads = 4;
  static const _dead = 20000;

  static const _buttonMap = {
    0: PadButton.ok,
    1: PadButton.back,
    2: PadButton.info,
    3: PadButton.menu,
    4: PadButton.rewind,
    5: PadButton.forward,
    6: PadButton.back,
    7: PadButton.playPause,
  };

  void start() {
    _rescan();
    Timer.periodic(const Duration(seconds: 2), (_) => _rescan());
  }

  void _rescan() {
    for (var i = 0; i < _maxPads; i++) {
      if (_pads.containsKey(i)) continue;
      final file = File('/dev/input/js$i');
      if (!file.existsSync()) continue;
      try {
        late final _Pad pad;
        pad = _Pad(file.openRead().listen(
          (data) => _onData(i, pad, data),
          onError: (Object e) => _drop(i),
          onDone: () => _drop(i),
          cancelOnError: true,
        ));
        _pads[i] = pad;
        debugPrint('[gamepad] opened /dev/input/js$i');
      } catch (e) {
        debugPrint('[gamepad] /dev/input/js$i: $e');
      }
    }
    if (_pads.isNotEmpty) _poll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _drop(int i) {
    final pad = _pads.remove(i);
    if (pad == null) return;
    unawaited(pad.subscription.cancel());
    _onButtons(i, null);
    if (_pads.isEmpty) {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _onData(int i, _Pad pad, List<int> data) {
    pad.pending.add(data);
    final bytes = pad.pending.takeBytes();
    final whole = bytes.length - bytes.length % 8;
    final view = ByteData.sublistView(bytes);
    for (var o = 0; o < whole; o += 8) {
      final value = view.getInt16(o + 4, Endian.little);
      final type = view.getUint8(o + 6) & 0x7f;
      final number = view.getUint8(o + 7);
      if (type == 1) {
        final b = _buttonMap[number];
        if (b != null) {
          pad.buttons = value != 0 ? pad.buttons | Gamepad.mask(b) : pad.buttons & ~Gamepad.mask(b);
        }
      } else if (type == 2) {
        pad.axes[number] = value;
      }
    }
    if (whole < bytes.length) pad.pending.add(bytes.sublist(whole));
  }

  void _tick() {
    for (final MapEntry(key: i, value: pad) in _pads.entries.toList()) {
      _onButtons(i, _buttons(pad));
    }
  }

  static int _buttons(_Pad pad) {
    var buttons = pad.buttons;
    int axis(int n) => pad.axes[n] ?? 0;
    final x = axis(0).abs() > axis(6).abs() ? axis(0) : axis(6);
    final y = axis(1).abs() > axis(7).abs() ? axis(1) : axis(7);
    if (y < -_dead) buttons |= Gamepad.mask(PadButton.up);
    if (y > _dead) buttons |= Gamepad.mask(PadButton.down);
    if (x < -_dead) buttons |= Gamepad.mask(PadButton.left);
    if (x > _dead) buttons |= Gamepad.mask(PadButton.right);
    return buttons;
  }
}
