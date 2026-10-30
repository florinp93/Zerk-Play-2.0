import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/widgets.dart' show Locale;

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../core/emby/server_kind.dart';
import '../../l10n/l10n.dart';
import '../../playback/language.dart';
import '../../playback/player_settings.dart';
import 'setup_page.dart';

enum RemoteSetupEvent { phoneConnected, applying, applied, failed }

final class RemoteSetupServer {
  RemoteSetupServer(this._services);

  final AppServices _services;

  static const _preferredPort = 8765;
  static const _maxBody = 64 * 1024;
  static const _maxFailures = 30;

  final code = (Random.secure().nextInt(900000) + 100000).toString();
  final event = ValueNotifier<RemoteSetupEvent?>(null);

  HttpServer? _http;
  InternetAddress? _address;
  int _failures = 0;

  Uri? get baseUrl => _http == null || _address == null ? null : Uri(scheme: 'http', host: _address!.address, port: _http!.port);

  Uri? get url => baseUrl?.replace(path: '/$code');

  Future<void> start() async {
    final address = await _lanAddress();
    if (address == null) throw const SocketException('No local network connection.');
    HttpServer http;
    try {
      http = await HttpServer.bind(InternetAddress.anyIPv4, _preferredPort);
    } on SocketException {
      http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _address = address;
    _http = http;
    http.listen((r) => unawaited(_handle(r)), onError: (_) {});
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    await http?.close();
  }

  void _emit(RemoteSetupEvent e) {
    if (_http != null) event.value = e;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Frame-Options', 'DENY')
      ..set('Referrer-Policy', 'no-referrer');
    try {
      final segments = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (_failures >= _maxFailures) return await _send(res, HttpStatus.tooManyRequests, 'Too many wrong codes. Reopen the setup screen on the TV.');
      if (req.method == 'GET' && segments.isEmpty) {
        final typed = req.uri.queryParameters['code']?.replaceAll(RegExp(r'\D'), '');
        if (typed != null && typed.isNotEmpty) {
          if (!_checkCode(typed)) return await _html(res, setupCodePage(wrongCode: true));
          res.statusCode = HttpStatus.seeOther;
          res.headers.set(HttpHeaders.locationHeader, '/$code');
          return await res.close();
        }
        return await _html(res, setupCodePage());
      }
      if (segments.isEmpty || !_checkCode(segments.first)) {
        return await _send(res, HttpStatus.notFound, 'Not found.');
      }
      if (req.method == 'GET' && segments.length == 1) {
        _emit(RemoteSetupEvent.phoneConnected);
        return await _html(res, setupFormPage(await _currentValues()));
      }
      if (req.method == 'POST' && segments.length == 2 && segments[1] == 'apply') {
        if (req.headers.contentType?.mimeType != 'application/json') return await _send(res, HttpStatus.unsupportedMediaType, 'Expected JSON.');
        final body = await _readBody(req);
        if (body == null) return await _send(res, HttpStatus.requestEntityTooLarge, 'Too large.');
        final Map<String, dynamic> input;
        try {
          input = jsonDecode(body) as Map<String, dynamic>;
        } catch (_) {
          return await _send(res, HttpStatus.badRequest, 'Bad JSON.');
        }
        _emit(RemoteSetupEvent.applying);
        final result = await _apply(input);
        _emit(result.values.every((r) => r['ok'] != false) ? RemoteSetupEvent.applied : RemoteSetupEvent.failed);
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(result));
        return await res.close();
      }
      return await _send(res, HttpStatus.notFound, 'Not found.');
    } catch (e) {
      try {
        await _send(res, HttpStatus.internalServerError, 'Something went wrong on the TV.');
      } catch (_) {}
    }
  }

  bool _checkCode(String candidate) {
    if (!RegExp(r'^\d+$').hasMatch(candidate)) return false;
    var diff = candidate.length ^ code.length;
    for (var i = 0; i < min(candidate.length, code.length); i++) {
      diff |= candidate.codeUnitAt(i) ^ code.codeUnitAt(i);
    }
    if (diff != 0) _failures++;
    return diff == 0;
  }

  Future<Map<String, Object?>> _currentValues() async {
    final s = _services.settings;
    final janus = _services.janus;
    final player = await PlayerSettings.load();
    return {
      'server': janus.isAuthenticated ? janus.session.serverUrl.toString() : await janus.getServerUrl(),
      'serverKind': janus.isAuthenticated ? janus.session.kind.name : (await janus.getServerKind()).name,
      'signedIn': janus.isAuthenticated,
      'uiLanguage': s.resolvedUiLanguage,
      'subtitleLanguage': player.preferredSubtitleLanguage.isEmpty && !s.onboarded
          ? s.resolvedUiLanguage
          : player.preferredSubtitleLanguage,
      'metadataSource': s.tmdbMetadataEnabled || !s.onboarded ? 'tmdb' : 'emby',
      'seerrUrl': s.seerrUrl,
      'playlistUrl': s.playlistUrl,
      'playlistGuideUrl': s.playlistGuideUrl,
      'hasSeerrKey': s.seerrApiKey.trim().isNotEmpty,
      'hasTmdbKey': s.tmdbApiKey.trim().isNotEmpty,
      'hasMdblistKey': s.mdblistApiKey.trim().isNotEmpty,
    };
  }

  Future<Map<String, Map<String, Object?>>> _apply(Map<String, dynamic> input) async {
    String? field(String key) => (input[key] as String?)?.trim();
    final result = <String, Map<String, Object?>>{};
    final l10n = lookupL10n(const Locale('en'));

    var s = _services.settings;
    final uiLanguage = field('uiLanguage');
    if (uiLanguage != null && uiLanguages.containsKey(uiLanguage)) s = s.copyWith(uiLanguage: uiLanguage);

    final subtitles = field('subtitleLanguage');
    if (subtitles != null && (subtitles.isEmpty || languageNames.containsKey(subtitles))) {
      final player = await PlayerSettings.load();
      await player.copyWith(preferredSubtitleLanguage: subtitles).save();
    }

    final mdblistKey = field('mdblistApiKey');
    if (mdblistKey != null && mdblistKey.isNotEmpty) s = s.copyWith(mdblistApiKey: mdblistKey);

    final tmdbKey = field('tmdbApiKey');
    if (tmdbKey != null && tmdbKey.isNotEmpty) s = s.copyWith(tmdbApiKey: tmdbKey);
    final useTmdb = switch (field('metadataSource')) {
      'emby' => false,
      'tmdb' => true,
      _ => s.tmdbMetadataEnabled,
    };
    s = s.copyWith(metadataLanguage: useTmdb ? s.uiMetadataLanguage : '');

    final seerrUrl = field('seerrUrl');
    final seerrKey = field('seerrApiKey');
    s = s.copyWith(seerrUrl: seerrUrl, seerrApiKey: seerrKey == null || seerrKey.isEmpty ? null : seerrKey);
    s = s.copyWith(playlistUrl: field('playlistUrl'), playlistGuideUrl: field('playlistGuideUrl'));
    await _services.updateSettings(s);

    if (_services.seerr != null) {
      final problem = await _services.checkSeerr();
      result['seerr'] = {
        'ok': problem == null,
        'message': problem == null ? 'Connected to ${_services.seerr!.baseUrl}.' : l10n.seerrProblem(problem),
      };
    }
    if (useTmdb || (tmdbKey?.isNotEmpty ?? false)) {
      final tmdb = _services.tmdb;
      final problem = tmdb == null ? null : await tmdb.check();
      final ok = tmdb != null && problem == null;
      result['tmdb'] = {
        'ok': ok,
        'message': tmdb == null ? l10n.tmdbKeyMissing : (problem == null ? l10n.tmdbKeyWorks : l10n.tmdbProblem(problem)),
      };
    }

    if (mdblistKey != null && mdblistKey.isNotEmpty) {
      final problem = await _services.mdblist?.check();
      result['mdblist'] = {'ok': problem == null, 'message': problem ?? l10n.mdblistKeyWorks};
    }

    final settingsOk = result.values.every((r) => r['ok'] != false);
    final username = field('username') ?? '';
    final wasOnboarded = _services.settings.onboarded;
    if (username.isNotEmpty) {
      var server = field('server') ?? '';
      if (server.isNotEmpty && !server.contains('://')) server = 'http://$server';
      if (settingsOk && !wasOnboarded) await _services.updateSettings(_services.settings.copyWith(onboarded: true));
      try {
        final kind = ServerKind.parse(field('serverKind'));
        await _services.signIn(server: server, kind: kind, username: username, password: (input['password'] as String?) ?? '');
        result['emby'] = {'ok': true, 'message': 'Signed in as $username.'};
      } catch (e) {
        if (!wasOnboarded) await _services.updateSettings(_services.settings.copyWith(onboarded: false));
        result['emby'] = {'ok': false, 'message': _describeSignInError(e)};
      }
    } else if (settingsOk && _services.janus.isAuthenticated && !wasOnboarded) {
      await _services.updateSettings(_services.settings.copyWith(onboarded: true));
    }
    return result;
  }

  static String _describeSignInError(Object e) {
    final s = '$e';
    if (s.contains('401')) return 'Wrong username or password.';
    if (s.contains('SocketException') || s.contains('Connection')) return 'The TV could not reach the server. Check the address.';
    return s;
  }

  static Future<String?> _readBody(HttpRequest req) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in req) {
      bytes.add(chunk);
      if (bytes.length > _maxBody) return null;
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  static Future<void> _html(HttpResponse res, String html) {
    res.headers.contentType = ContentType.html;
    res.write(html);
    return res.close();
  }

  static Future<void> _send(HttpResponse res, int status, String text) {
    res.statusCode = status;
    res.headers.contentType = ContentType.text;
    res.write(text);
    return res.close();
  }

  static Future<InternetAddress?> _lanAddress() async {
    const virtual = ['vethernet', 'virtualbox', 'vmware', 'wsl', 'hyper-v', 'loopback', 'docker', 'tailscale', 'zerotier', 'tun', 'tap', 'rmnet'];
    int score(NetworkInterface iface, InternetAddress a) {
      final name = iface.name.toLowerCase();
      if (a.isLoopback || a.isLinkLocal) return -1;
      if (virtual.any(name.contains)) return 0;
      final b = a.rawAddress;
      if (b[0] == 192 && b[1] == 168) return 4;
      if (b[0] == 10) return 3;
      if (b[0] == 172 && b[1] >= 16 && b[1] < 32) return 2;
      return 1;
    }

    final candidates = <(int, InternetAddress)>[
      for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in iface.addresses) (score(iface, a), a),
    ]..sort((x, y) => y.$1.compareTo(x.$1));
    return candidates.where((c) => c.$1 > 0).map((c) => c.$2).firstOrNull;
  }
}
