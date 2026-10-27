import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory>? _dir;

Future<Directory> _cacheDir() => _dir ??= () async {
      final base = await getApplicationCacheDirectory();
      final dir = Directory(p.join(base.path, 'images'));
      await dir.create(recursive: true);
      return dir;
    }();

Future<File> _file(Uri url) async => File(p.join((await _cacheDir()).path, _hash(url.toString())));

Future<Uint8List?> readCachedImage(Uri url) async {
  try {
    final file = await _file(url);
    if (await file.exists()) return await file.readAsBytes();
  } catch (_) {}
  return null;
}

void writeCachedImage(Uri url, Uint8List bytes) {
  unawaited(() async {
    try {
      await (await _file(url)).writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }());
}

String _hash(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16);
}
