import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app/hub_link.dart';
import '../core/emby/models/emby_item.dart';
import '../services/janus/janus_service.dart';
import 'seerr_api.dart';

final class ListEntry {
  const ListEntry({
    required this.key,
    required this.title,
    this.embyId,
    this.tmdbId,
    this.mediaType,
    this.year,
    this.posterPath,
    this.added = 0,
  });

  final String key;
  final String title;
  final String? embyId;
  final int? tmdbId;

  final String? mediaType;
  final int? year;
  final String? posterPath;
  final int added;

  bool get isLibraryOnly => key.startsWith('emby:');

  SeerrMedia? get media => tmdbId == null
      ? null
      : SeerrMedia(
          tmdbId: tmdbId!,
          type: mediaType == 'tv' ? SeerrMediaType.tv : SeerrMediaType.movie,
          title: title,
          year: year,
          posterPath: posterPath,
        );

  Map<String, Object?> toJson() => {
        'title': title,
        'embyId': ?embyId,
        'tmdbId': ?tmdbId,
        'mediaType': ?mediaType,
        'year': ?year,
        'posterPath': ?posterPath,
      };

  static ListEntry fromJson(Map json) => ListEntry(
        key: json['key'] as String,
        title: json['title'] as String? ?? '',
        embyId: json['embyId'] as String?,
        tmdbId: (json['tmdbId'] as num?)?.toInt(),
        mediaType: json['mediaType'] as String?,
        year: (json['year'] as num?)?.toInt(),
        posterPath: json['posterPath'] as String?,
        added: (json['added'] as num?)?.toInt() ?? 0,
      );

  static ListEntry? of(Object item) {
    if (item is SeerrMedia) {
      return ListEntry(
        key: 'tmdb:${item.isTv ? 'tv' : 'movie'}:${item.tmdbId}',
        title: item.title,
        embyId: item.embyItemId?.replaceAll('-', '').toLowerCase(),
        tmdbId: item.tmdbId,
        mediaType: item.isTv ? 'tv' : 'movie',
        year: item.year,
        posterPath: item.posterPath,
      );
    }
    if (item is! EmbyItem || !(item.isMovie || item.isSeries)) return null;
    final tmdb = item.tmdbId;
    final type = item.isSeries ? 'tv' : 'movie';
    return ListEntry(
      key: tmdb != null ? 'tmdb:$type:$tmdb' : 'emby:${item.id.replaceAll('-', '').toLowerCase()}',
      title: item.name,
      embyId: item.id.replaceAll('-', '').toLowerCase(),
      tmdbId: tmdb,
      mediaType: tmdb != null ? type : null,
      year: item.productionYear,
    );
  }
}

final class UserProfile {
  const UserProfile({required this.id, required this.name, this.avatar, this.avatarUrl, this.list = const []});

  final String id;
  final String name;

  final String? avatar;
  final Uri? avatarUrl;

  final List<ListEntry> list;

  String? get libraryAvatar => avatar != null && avatar!.startsWith('lib:') ? avatar!.substring(4) : null;
}

final class ProfileService extends ChangeNotifier {
  ProfileService({required this.janus});

  final JanusService janus;
  Uri? _base;

  bool get available => _base != null;

  UserProfile? get profile => _profile;
  UserProfile? _profile;

  List<String>? _library;

  Set<String> _keys = const {};

  bool inList(Object item) {
    final key = ListEntry.of(item)?.key;
    return key != null && _keys.contains(key);
  }

  bool canList(Object item) => available && ListEntry.of(item) != null;

  Map<String, String> get _auth {
    if (!janus.isAuthenticated) return const {};
    final session = janus.session;
    return {'X-Emby-Token': session.accessToken, 'X-Emby-User-Id': session.userId};
  }

  Future<void> detect() async {
    final base = HubLink.features.profiles ? HubLink.base : null;
    if (base == null || !janus.isAuthenticated) return _unavailable();
    try {
      final res = await http.get(base.resolve('profile/health'), headers: _auth).timeout(const Duration(seconds: 4));
      final json = res.statusCode == 200 ? jsonDecode(res.body) : null;
      if (json is Map && json['service'] == 'zerk-profile' && json['enabled'] == true) {
        if (_base != base) {
          _base = base;
          _library = null;
          _profile = null;
          _keys = const {};
          notifyListeners();
        }
        await load();
      } else if (res.statusCode == 200) {
        _unavailable();
      }
    } catch (_) {
    }
  }

  void _unavailable() {
    if (_base == null && _profile == null) return;
    _base = null;
    _library = null;
    clear();
  }

  Future<void> load() async {
    if (_base == null || !janus.isAuthenticated) return;
    try {
      final json = await _call('GET', 'profile/me');
      if (json['created'] == true) unawaited(_syncToEmby(onlyIfMissing: true));
    } catch (e) {
      debugPrint('[profile] load: $e');
    }
  }

  void clear() {
    _profile = null;
    _keys = const {};
    notifyListeners();
  }

  Future<List<String>> library() async {
    if (_library != null) return _library!;
    final res = await http.get(_base!.resolve('profile/avatars'), headers: _auth).timeout(const Duration(seconds: 10));
    final json = jsonDecode(res.body);
    return _library = [for (final id in (json is Map ? json['avatars'] as List? : null) ?? const []) if (id is String) id];
  }

  Uri libraryAvatar(String id) => _base!.resolve('profile/avatars/$id.png');

  Uri? avatarOf(String? userId) =>
      _base == null || userId == null || userId.isEmpty ? null : _base!.resolve('profile/avatar/$userId');

  Future<void> rename(String name) => _call('PUT', 'profile/me', body: {'name': name.trim()});

  Future<void> pickAvatar(String libraryId) async {
    await _call('PUT', 'profile/me', body: {'avatar': libraryId});
    unawaited(_syncToEmby());
  }

  Future<void> uploadAvatar(Uint8List bytes) async {
    final png = await squarePng(bytes, 512);
    await _call('PUT', 'profile/me/avatar', raw: png, contentType: 'image/png');
    unawaited(_syncToEmby(bytes: png));
  }

  Future<void> toggle(Object item) async {
    final entry = ListEntry.of(item);
    if (entry == null) return;
    final key = Uri.encodeComponent(entry.key);
    if (_keys.contains(entry.key)) {
      await _call('DELETE', 'profile/list/$key');
    } else {
      await _call('PUT', 'profile/list/$key', body: entry.toJson());
    }
  }

  Future<Map<String, Object?>> _call(String method, String path,
      {Map<String, Object?>? body, Uint8List? raw, String? contentType}) async {
    final request = http.Request(method, _base!.resolve(path))..headers.addAll(_auth);
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    } else if (raw != null) {
      request
        ..headers['Content-Type'] = contentType ?? 'application/octet-stream'
        ..bodyBytes = raw;
    }
    final res = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 20)));
    final json = jsonDecode(res.body);
    if (res.statusCode != 200 || json is! Map<String, Object?>) {
      throw http.ClientException('${res.statusCode} ${json is Map ? json['message'] : ''}', request.url);
    }
    _apply(json);
    return json;
  }

  void _apply(Map<String, Object?> json) {
    final url = json['avatarUrl'] as String?;
    _profile = UserProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      avatar: json['avatar'] as String?,
      avatarUrl: url == null ? null : _base!.resolve(url),
      list: [for (final e in json['list'] as List? ?? const []) if (e is Map) ListEntry.fromJson(e)],
    );
    _keys = {for (final e in _profile!.list) e.key};
    notifyListeners();
  }

  Future<void> _syncToEmby({Uint8List? bytes, bool onlyIfMissing = false}) async {
    try {
      final session = janus.session;
      if (onlyIfMissing) {
        final user = await janus.client.getJson('/Users/${session.userId}');
        if (user['PrimaryImageTag'] != null) return;
      }
      final url = _profile?.avatarUrl;
      final image = bytes ?? (url == null ? null : (await http.get(url, headers: _auth)).bodyBytes);
      if (image == null || image.isEmpty) return;
      final type = image.length > 3 && image[0] == 0xff && image[1] == 0xd8 ? 'image/jpeg' : 'image/png';
      await janus.client.postImage('/Users/${session.userId}/Images/Primary', image, contentType: type);
      debugPrint('[profile] picture copied to the media server');
    } catch (e) {
      debugPrint('[profile] media server picture not changed: $e');
    }
  }
}

Future<Uint8List> squarePng(Uint8List bytes, int size) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final side = image.width < image.height ? image.width : image.height;
  final src = ui.Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side.toDouble(), side.toDouble());
  final out = side < size ? side : size;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(image, src, ui.Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high);
  final scaled = await recorder.endRecording().toImage(out, out);
  final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  scaled.dispose();
  return data!.buffer.asUint8List();
}
