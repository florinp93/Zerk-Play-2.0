import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/emby/server_kind.dart';
import '../core/host.dart';
import 'app_settings.dart';
import 'release.dart';

final class HubFeatures {
  const HubFeatures({
    this.requests = false,
    this.together = false,
    this.profiles = false,
    this.redownload = false,
  });

  factory HubFeatures.fromJson(Object? raw) {
    final j = raw is Map ? raw : const {};
    return HubFeatures(
      requests: j['requests'] == true,
      together: j['together'] == true,
      profiles: j['profiles'] == true,
      redownload: j['redownload'] == true,
    );
  }

  final bool requests;
  final bool together;
  final bool profiles;
  final bool redownload;
}

final class HubConfig {
  HubConfig(this.json)
      : serverName = (json['server'] as Map?)?['name'] as String? ?? '',
        serverUrl = (json['server'] as Map?)?['url'] as String? ?? '',
        serverKind = ServerKind.parse((json['server'] as Map?)?['kind'] as String?),
        base = Uri.tryParse(json['hub'] as String? ?? ''),
        features = HubFeatures.fromJson(json['features']),
        refreshAfter = Duration(hours: (json['refreshHours'] as num?)?.toInt() ?? 6);

  final Map<String, Object?> json;
  final String serverName;
  final String serverUrl;
  final ServerKind serverKind;
  final Uri? base;
  final HubFeatures features;
  final Duration refreshAfter;

  String _text(String key) => json[key] is String ? json[key] as String : '';

  Map _map(String key) => json[key] is Map ? json[key] as Map : const {};

  AppSettings applyTo(AppSettings s) {
    final seerr = _map('seerr');
    final tv = _map('liveTv');
    final accounts = [
      for (final a in tv['xtreamAccounts'] as List? ?? const [])
        if (a is List && a.length == 2) ('${a[0]}', '${a[1]}'),
    ];
    final language = _text('metadataLanguage');
    return s.copyWith(
      tmdbApiKey: _text('tmdbApiKey'),
      mdblistApiKey: _text('mdblistApiKey'),
      metadataLanguage: s.metadataLanguage.isEmpty && language.isNotEmpty ? language : null,
      seerrUrl: seerr['enabled'] == true ? '${seerr['url']}' : '',
      seerrApiKey: seerr['enabled'] == true ? 'hub' : '',
      xtreamUrl: '${tv['xtreamUrl'] ?? ''}',
      xtreamAccounts: accounts,
      playlistUrl: '${tv['playlistUrl'] ?? ''}',
      playlistGuideUrl: '${tv['playlistGuideUrl'] ?? ''}',
      onboarded: true,
    );
  }
}

final class HubLinkException implements Exception {
  const HubLinkException(this.code, this.message);

  final String code;
  final String message;

  bool get dropsLink => code == 'revoked' || code == 'unknown-code' || code == 'inactive';

  @override
  String toString() => message;
}

abstract final class HubLink {
  static const _key = 'hub.link.v1';

  static String get defaultHub => Release.hub;

  static HubConfig? _config;
  static String? _code;
  static String? _hub;
  static DateTime? _linkedAt;

  static final changed = ValueNotifier<int>(0);

  static String? droppedMessage;

  static HubConfig? get config => _config;

  static bool get linked => _config != null;

  static Uri? get base => _config?.base;

  static HubFeatures get features => _config?.features ?? const HubFeatures();

  static String? get code => _code;

  static String get hub => _hub ?? defaultHub;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      _code = j['code'] as String?;
      _hub = j['hub'] as String?;
      _linkedAt = DateTime.tryParse(j['linkedAt'] as String? ?? '');
      final config = j['config'];
      if (config is Map<String, Object?>) _config = HubConfig(config);
    } catch (e) {
      debugPrint('[hub] stored link unreadable: $e');
    }
  }

  static bool get due {
    final at = _linkedAt;
    final config = _config;
    return config != null && (at == null || DateTime.now().difference(at) > config.refreshAfter);
  }

  static Uri _endpoint(String hub) {
    var h = hub.trim();
    if (!h.contains('://')) h = 'https://$h';
    final uri = Uri.parse(h);
    return uri.replace(path: '/api/app/link', query: null, fragment: null);
  }

  static Future<HubConfig> redeem(String code, {String? hub}) async {
    final prefs = await SharedPreferences.getInstance();
    var device = prefs.getString('hub.deviceId');
    if (device == null) {
      device = const Uuid().v4();
      await prefs.setString('hub.deviceId', device);
    }
    final target = (hub == null || hub.trim().isEmpty) ? defaultHub : hub.trim();
    if (target.isEmpty) throw const HubLinkException('no-hub', 'Enter the hub address your server owner gave you.');
    final http.Response res;
    try {
      res = await http
          .post(
            _endpoint(target),
            headers: {'content-type': 'application/json', 'accept': 'application/json'},
            body: jsonEncode({
              'code': code,
              'device': {
                'id': device,
                'name': Host.isAndroid ? 'Android TV' : Host.isLinux ? 'Linux' : 'Windows',
                'platform': Host.isAndroid ? 'androidtv' : Host.isLinux ? 'linux' : 'windows',
                'version': Release.name,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw HubLinkException('unreachable', 'Could not reach $target. Check your connection and try again.');
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (res.statusCode != 200 || json is! Map<String, Object?>) {
      final map = json is Map ? json : const {};
      throw HubLinkException('${map['code'] ?? 'http-${res.statusCode}'}', '${map['message'] ?? 'The hub answered ${res.statusCode}.'}');
    }
    final config = HubConfig(json);
    if (config.serverUrl.isEmpty || config.base == null) {
      throw const HubLinkException('bad-config', 'The hub sent an incomplete setup.');
    }
    _config = config;
    _code = code;
    _hub = target;
    _linkedAt = DateTime.now();
    await prefs.setString(_key, jsonEncode({
      'code': code,
      'hub': target,
      'linkedAt': _linkedAt!.toIso8601String(),
      'config': json,
    }));
    changed.value++;
    return config;
  }

  static Future<HubConfig?> refresh() async {
    final code = _code;
    if (code == null) return null;
    try {
      return await redeem(code, hub: _hub);
    } on HubLinkException catch (e) {
      debugPrint('[hub] refresh: ${e.code} ${e.message}');
      if (e.dropsLink) await unlink();
      rethrow;
    }
  }

  static Future<void> unlink() async {
    _config = null;
    _code = null;
    _hub = null;
    _linkedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    changed.value++;
  }
}
