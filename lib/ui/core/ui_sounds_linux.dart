import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../playback/mpv/mpv_player.dart';
import 'ui_sounds.dart';

MpvPlayer? _mpv;

Future<void> loadLinux() async {
  try {
    _mpv = MpvPlayer.create(options: {
      'config': 'no',
      'load-scripts': 'no',
      'osc': 'no',
      'ytdl': 'no',
      'vo': 'null',
      'video': 'no',
      'idle': 'yes',
      'cache': 'no',
      'audio-buffer': '0.05',
      'input-default-bindings': 'no',
      'msg-level': 'all=error',
    }, logLevel: 'error');
  } catch (e) {
    debugPrint('[sounds] mpv: $e');
  }
}

void playLinux(UiSound sound) {
  final mpv = _mpv;
  if (mpv == null) return;
  mpv.commandAsync([
    'loadfile',
    p.join(p.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', 'assets', 'sounds', '${sound.name}.wav'),
    'replace',
  ]);
}
