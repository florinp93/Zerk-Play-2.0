import 'package:uuid/uuid.dart';

import '../../core/emby/emby_client.dart';
import '../../core/emby/emby_session.dart';
import '../../core/emby/server_kind.dart';
import '../../core/storage/local_store.dart';

final class JanusService {
  JanusService({
    required this._store,
    this._clientName = 'Zerk Play',
    required this._deviceName,
    required this._appVersion,
  });

  static const _kServerUrl = 'emby.serverUrl';
  static const _kServerKind = 'emby.serverKind';
  static const _kAccessToken = 'emby.accessToken';
  static const _kUserId = 'emby.userId';
  static const _kDeviceId = 'emby.deviceId';

  final LocalStore _store;
  final String _clientName;
  final String _deviceName;
  final String _appVersion;

  EmbySession? _session;
  EmbyClient? _client;

  bool get isAuthenticated => _session != null;
  EmbySession get session {
    final session = _session;
    if (session == null) throw StateError('Not authenticated.');
    return session;
  }

  EmbyClient get client {
    final client = _client;
    if (client == null) throw StateError('Not initialized.');
    return client;
  }

  Future<String> getServerUrl() async {
    return (await _store.getString(_kServerUrl)) ?? '';
  }

  Future<ServerKind> getServerKind() async => ServerKind.parse(await _store.getString(_kServerKind));

  Future<void> init() async {
    final deviceId = await _ensureDeviceId();
    final serverUrl = Uri.parse(
      (await _store.getString(_kServerUrl)) ?? '',
    );
    _client = EmbyClient(
      serverUrl: serverUrl,
      kind: await getServerKind(),
      clientName: _clientName,
      deviceName: _deviceName,
      deviceId: deviceId,
      appVersion: _appVersion,
    );
  }

  Future<bool> restoreSession() async {
    final accessToken = await _store.getString(_kAccessToken);
    final userId = await _store.getString(_kUserId);
    if (accessToken == null || accessToken.isEmpty) return false;
    if (userId == null || userId.isEmpty) return false;

    final serverUrl = Uri.parse(
      (await _store.getString(_kServerUrl)) ?? '',
    );
    final deviceId = await _ensureDeviceId();
    final kind = await getServerKind();

    _session = EmbySession(
      serverUrl: serverUrl,
      kind: kind,
      clientName: _clientName,
      deviceName: _deviceName,
      deviceId: deviceId,
      appVersion: _appVersion,
      userId: userId,
      accessToken: accessToken,
    );

    final client = EmbyClient(
      serverUrl: serverUrl,
      kind: kind,
      clientName: _clientName,
      deviceName: _deviceName,
      deviceId: deviceId,
      appVersion: _appVersion,
      accessToken: accessToken,
    );
    _client = client;
    return true;
  }

  Future<EmbySession> login({
    String? serverUrl,
    ServerKind kind = ServerKind.emby,
    required String username,
    required String password,
  }) async {
    final url = Uri.parse(
      serverUrl ??
          (await _store.getString(_kServerUrl)) ??
          '',
    );
    final deviceId = await _ensureDeviceId();

    final client = EmbyClient(
      serverUrl: url,
      kind: kind,
      clientName: _clientName,
      deviceName: _deviceName,
      deviceId: deviceId,
      appVersion: _appVersion,
    );

    final auth = await client.postJson(
      '/Users/AuthenticateByName',
      body: {
        'Username': username,
        'Pw': password,
      },
    );

    final token = (auth['AccessToken'] as String?) ?? '';
    final user = auth['User'];
    final userId =
        user is Map ? (user['Id'] as String?) ?? '' : (auth['UserId'] as String?) ?? '';

    if (token.isEmpty || userId.isEmpty) {
      throw StateError('Login succeeded but token/userId missing.');
    }

    await _store.setString(_kServerUrl, url.toString());
    await _store.setString(_kServerKind, kind.name);
    await _store.setString(_kAccessToken, token);
    await _store.setString(_kUserId, userId);

    _session = EmbySession(
      serverUrl: url,
      kind: kind,
      clientName: _clientName,
      deviceName: _deviceName,
      deviceId: deviceId,
      appVersion: _appVersion,
      userId: userId,
      accessToken: token,
    );

    client.setAccessToken(token);
    _client = client;
    return _session!;
  }

  Future<void> logout() async {
    _session = null;
    _client?.setAccessToken(null);

    await _store.remove(_kAccessToken);
    await _store.remove(_kUserId);
  }

  Future<String> _ensureDeviceId() async {
    final existing = await _store.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await _store.setString(_kDeviceId, id);
    return id;
  }
}
