import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../app/release.dart';
import '../host.dart';
import 'app_log.dart';

final class LogUploadException implements Exception {
  const LogUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class LogUpload {
  static const _perFile = 700 * 1024;

  static bool get available => Release.hub.isNotEmpty && AppLog.directory != null;

  static Future<String> send({String? note}) async {
    await AppLog.flush();
    final dir = AppLog.directory;
    if (dir == null) throw const LogUploadException('No log file is open.');
    final files = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('zerkplay-'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    final parts = <String>[];
    for (final f in files.take(2).toList().reversed) {
      final bytes = await f.readAsBytes();
      final tail = bytes.length > _perFile ? bytes.sublist(bytes.length - _perFile) : bytes;
      parts.add('===== ${p.basename(f.path)} (${bytes.length} bytes${bytes.length > _perFile ? ', last $_perFile' : ''}) =====\n'
          '${utf8.decode(tail, allowMalformed: true)}');
    }
    final hub = Uri.parse(Release.hub.contains('://') ? Release.hub : 'https://${Release.hub}');
    final http.Response res;
    try {
      res = await http
          .post(
            hub.replace(path: '/api/app/logs'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'device': {
                'platform': Host.isAndroid ? 'androidtv' : Host.isLinux ? 'linux' : 'windows',
                'version': '${Release.name} (${AppLog.appVersion})',
              },
              'note': ?note,
              'text': parts.join('\n\n'),
            }),
          )
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      throw const LogUploadException('Could not reach the server. Check the connection and try again.');
    }
    final json = res.statusCode == 200 ? jsonDecode(res.body) : null;
    if (json is! Map || json['id'] is! String) {
      throw LogUploadException('The upload failed (HTTP ${res.statusCode}).');
    }
    AppLog.write('[log] sent to the developer as ${json['id']}');
    return json['id'] as String;
  }
}
