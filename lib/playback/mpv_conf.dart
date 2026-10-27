import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract final class MpvConf {
  static bool get supported => Platform.isWindows;

  static Future<String> _path() async => p.join((await getApplicationSupportDirectory()).path, 'mpv.conf');

  static Future<void> edit() async {
    final file = File(await _path());
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString(_template);
    }
    debugPrint('[mpv] editing ${file.path}');
    await Process.start('notepad.exe', [file.path]);
  }

  static Future<void> openFolder() async {
    final dir = p.dirname(await _path());
    await Process.start('explorer.exe', [dir]);
  }

  static const _template = '''# Zerk Play: your own mpv options (https://mpv.io/manual/stable/)
#
# Loaded after the app's settings, so anything here wins over them.
# Applied from the next playback. One option per line, without the leading --.
# Lines starting with # are ignored. Delete this file to go back to the defaults.
#
# Examples:
# profile=high-quality
# scale=ewa_lanczossharp
# cscale=ewa_lanczossharp
# deband=yes
# tone-mapping=bt.2390
# hdr-compute-peak=yes
# hwdec=nvdec
# video-sync=display-resample
# interpolation=yes
# demuxer-max-bytes=1GiB
# audio-device=wasapi/{your-device-id}
''';
}
