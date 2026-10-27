import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<File> _file(String name) async => File(p.join((await getApplicationSupportDirectory()).path, name));

Future<String?> readBlob(String name) async {
  final file = await _file(name);
  return await file.exists() ? file.readAsString() : null;
}

Future<void> writeBlob(String name, String text) async {
  final file = await _file(name);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(text);
  await tmp.rename(file.path);
}

Future<void> deleteBlob(String name) async {
  final file = await _file(name);
  if (await file.exists()) await file.delete();
}
