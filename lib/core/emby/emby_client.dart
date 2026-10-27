import 'dart:convert';

import 'package:http/http.dart' as http;

import '../log/logging_http_client.dart';
import 'emby_api_exception.dart';
import 'server_kind.dart';

final class EmbyClient {
  EmbyClient({
    required Uri serverUrl,
    required this.clientName,
    required this.deviceName,
    required this.deviceId,
    required this.appVersion,
    this.kind = ServerKind.emby,
    http.Client? httpClient,
    this._accessToken,
  })  : serverUrl = _normalizeServerUrl(serverUrl),
        _http = httpClient ?? LoggingHttpClient(tag: kind.name);

  final Uri serverUrl;
  final String clientName;
  final String deviceName;
  final String deviceId;
  final String appVersion;
  final ServerKind kind;
  final http.Client _http;
  String? _accessToken;

  bool get isJellyfin => kind == ServerKind.jellyfin;

  String get tokenParameter => isJellyfin ? 'ApiKey' : 'api_key';

  void setAccessToken(String? token) => _accessToken = token;

  Uri buildUri(
    String path, {
    Map<String, String?> queryParameters = const {},
  }) {
    final qp = <String, String>{};
    for (final entry in queryParameters.entries) {
      final value = entry.value;
      if (value == null) continue;
      qp[entry.key] = value;
    }

    var normalizedPath = path.startsWith('/') ? path : '/$path';
    if (isJellyfin) normalizedPath = _jellyfinRoute(normalizedPath, qp);
    return serverUrl.replace(
      path: _joinPath(serverUrl.path, normalizedPath),
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  static const _jellyfinFields = {
    'AirTime', 'CanDelete', 'CanDownload', 'ChannelImage', 'ChannelInfo', 'Chapters', 'ChildCount',
    'CumulativeRunTimeTicks', 'CustomRating', 'DateCreated', 'DateLastMediaAdded', 'DateLastRefreshed',
    'DateLastSaved', 'DisplayPreferencesId', 'EnableMediaSourceDisplay', 'Etag', 'ExternalUrls', 'ExtraIds',
    'Genres', 'Height', 'IsHD', 'ItemCounts', 'LocalTrailerCount', 'MediaSourceCount', 'MediaSources',
    'MediaStreams', 'OriginalTitle', 'Overview', 'ParentId', 'Path', 'People', 'PlayAccess',
    'PrimaryImageAspectRatio', 'ProductionLocations', 'ProviderIds', 'RecursiveItemCount', 'RefreshState',
    'RemoteTrailers', 'SeasonUserData', 'SeriesStudio', 'Settings', 'SortName', 'SpecialEpisodeNumbers',
    'SpecialFeatureCount', 'Studios', 'Tags', 'Taglines', 'Trickplay', 'Width',
  };

  static final _userRoute =
      RegExp(r'^/Users/([^/]+)/(Items(?:/Latest)?|Items/[^/]+|Views|PlayedItems/[^/]+|FavoriteItems/[^/]+|Images/Primary)$');

  static String _jellyfinRoute(String path, Map<String, String> qp) {
    final key = qp.remove('api_key');
    if (key != null) qp['ApiKey'] = key;
    final fields = qp['Fields'];
    if (fields != null) {
      final kept = fields.split(',').where(_jellyfinFields.contains).join(',');
      kept.isEmpty ? qp.remove('Fields') : qp['Fields'] = kept;
    }
    final m = _userRoute.firstMatch(path);
    if (m == null) return path;
    final rest = m.group(2)!;
    if (!qp.keys.any((k) => k.toLowerCase() == 'userid')) qp['userId'] = m.group(1)!;
    return switch (rest) {
      'Views' => '/UserViews',
      'Items/Resume' => '/UserItems/Resume',
      'Images/Primary' => '/UserImage',
      _ when rest.startsWith('PlayedItems/') => '/User$rest',
      _ when rest.startsWith('FavoriteItems/') => '/User$rest',
      _ => '/$rest',
    };
  }

  Uri buildPrimaryImageUri(
    String itemId, {
    int maxWidth = 360,
    String? tag,
  }) {
    return buildUri(
      '/Items/$itemId/Images/Primary',
      queryParameters: {
        'maxWidth': '$maxWidth',
        'tag': tag,
      },
    );
  }

  Map<String, String> _headers({
    Map<String, String> extra = const {},
  }) {
    final token = _accessToken;
    final hasToken = token != null && token.isNotEmpty;
    final client = 'MediaBrowser Client="$clientName", Device="$deviceName", DeviceId="$deviceId", Version="$appVersion"';
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (isJellyfin)
        'Authorization': hasToken ? '$client, Token="$token"' : client
      else ...{
        'X-Emby-Authorization': client,
        if (hasToken) 'X-Emby-Token': token,
      },
      ...extra,
    };
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String?> queryParameters = const {},
  }) async {
    final uri = buildUri(path, queryParameters: queryParameters);
    final response = await _http.get(uri, headers: _headers());
    return _decodeJsonResponse(response);
  }

  Future<List<dynamic>> getJsonList(
    String path, {
    Map<String, String?> queryParameters = const {},
  }) async {
    final uri = buildUri(path, queryParameters: queryParameters);
    final response = await _http.get(uri, headers: _headers());
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = response.body;
    }
    if (response.statusCode >= 200 && response.statusCode < 300 && decoded is List) return decoded;
    throw EmbyApiException(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      body: decoded,
      uri: uri,
    );
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, String?> queryParameters = const {},
    Object? body,
  }) async {
    final uri = buildUri(path, queryParameters: queryParameters);
    final response = await _http.post(
      uri,
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeJsonResponse(response);
  }

  Future<void> postNoContent(
    String path, {
    Map<String, String?> queryParameters = const {},
    Object? body,
  }) async {
    final uri = buildUri(path, queryParameters: queryParameters);
    final response = await _http.post(
      uri,
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    Object? decodedBody;
    try {
      decodedBody = jsonDecode(response.body);
    } catch (_) {
      decodedBody = response.body;
    }
    throw EmbyApiException(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      body: decodedBody,
    );
  }

  Future<void> deleteNoContent(
    String path, {
    Map<String, String?> queryParameters = const {},
    Object? body,
  }) async {
    final uri = buildUri(path, queryParameters: queryParameters);
    final response = await _http.delete(
      uri,
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    Object? decodedBody;
    try {
      decodedBody = jsonDecode(response.body);
    } catch (_) {
      decodedBody = response.body;
    }
    throw EmbyApiException(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      body: decodedBody,
      uri: uri,
    );
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    Object? decodedBody;
    try {
      decodedBody = jsonDecode(response.body);
    } catch (_) {
      decodedBody = response.body;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decodedBody is Map<String, dynamic>) return decodedBody;
      throw EmbyApiException(
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        body: decodedBody,
      );
    }

    throw EmbyApiException(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      body: decodedBody,
    );
  }
}

Uri _normalizeServerUrl(Uri uri) {
  final normalized = uri.replace(
    path: uri.path.isEmpty ? '/' : uri.path,
    queryParameters: null,
    fragment: null,
  );

  return normalized;
}

String _joinPath(String base, String add) {
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
  if (!add.startsWith('/')) add = '/$add';
  return '$base$add';
}
