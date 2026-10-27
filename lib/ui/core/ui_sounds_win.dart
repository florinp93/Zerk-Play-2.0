import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import 'ui_sounds.dart';

final _buffers = <UiSound, Pointer<Uint8>>{};

Future<void> load() async {
  if (!Platform.isWindows) return;
  for (final s in UiSound.values) {
    try {
      final data = await rootBundle.load('assets/sounds/${s.name}.wav');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final ptr = malloc<Uint8>(bytes.length);
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      _buffers[s] = ptr;
    } catch (e) {
      debugPrint('[sounds] ${s.name}: $e');
    }
  }
}

void play(UiSound sound) {
  final buf = _buffers[sound];
  if (buf == null) return;
  PlaySound(buf.cast(), NULL, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
}
