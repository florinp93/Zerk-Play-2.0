import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/release.dart';
import '../../core/host.dart';

final class AppUpdate {
  const AppUpdate({required this.tag, required this.name, required this.download, required this.size});

  final String tag;
  final String name;
  final Uri download;
  final int size;
}

final class UpdateNotAllowed implements Exception {
  const UpdateNotAllowed();
}

abstract final class Updater {
  static const _channel = MethodChannel('zerk/updater');

  static String get _assetName => Host.isAndroid ? 'ZerkPlay-Public-Android.apk' : 'ZerkPlay-Public-Windows-setup.exe';

  static bool get supported => Host.isWindows || Host.isAndroid;

  static Future<AppUpdate?> check() async {
    final res = await http.get(
      Uri.https('api.github.com', '/repos/${Release.repository}/releases', {'per_page': '10'}),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
    final releases = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>().where((r) => r['draft'] != true).toList()
      ..sort((a, b) => '${b['published_at']}'.compareTo('${a['published_at']}'));
    final latest = releases.firstOrNull;
    if (latest == null || latest['tag_name'] == Release.tag) return null;
    final asset = (latest['assets'] as List).cast<Map<String, dynamic>>().where((a) => a['name'] == _assetName).firstOrNull;
    if (asset == null) return null;
    final tag = latest['tag_name'] as String;
    final name = (latest['name'] as String?)?.trim() ?? '';
    debugPrint('[update] ${Release.tag} -> $tag');
    return AppUpdate(
      tag: tag,
      name: name.isEmpty ? tag : name,
      download: Uri.parse(asset['browser_download_url'] as String),
      size: (asset['size'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<File> download(AppUpdate update, {void Function(double progress)? onProgress}) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'zerk_play_update'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, _assetName));
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', update.download));
      if (res.statusCode != 200) throw HttpException('Download answered ${res.statusCode}');
      final total = res.contentLength ?? update.size;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) throw const HttpException('The download was cut short');
      debugPrint('[update] downloaded $received bytes to ${file.path}');
      return file;
    } finally {
      client.close();
    }
  }

  static Future<void> install(File file) async {
    if (Host.isAndroid) {
      if (await _channel.invokeMethod<bool>('canInstall') != true) {
        await _channel.invokeMethod('allowInstalls');
        throw const UpdateNotAllowed();
      }
      await _channel.invokeMethod('install', file.path);
      return;
    }
    await Process.start(
      file.path,
      ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  }
}
