import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class PendingStop {
  const PendingStop({required this.owner, required this.body, required this.at});

  final String owner;
  final Map<String, Object?> body;
  final DateTime at;

  String get itemId => body['ItemId'] as String? ?? '';

  Map<String, Object?> toJson() => {'owner': owner, 'at': at.toUtc().toIso8601String(), 'body': body};

  static PendingStop? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final owner = raw['owner'], at = DateTime.tryParse('${raw['at']}'), body = raw['body'];
    if (owner is! String || at == null || body is! Map) return null;
    return PendingStop(owner: owner, body: body.cast<String, Object?>(), at: at);
  }
}

abstract final class PendingStops {
  static const _key = 'playback.pendingStops.v1';
  static const maxAge = Duration(days: 7);
  static const _maxEntries = 20;

  static List<PendingStop> merge(List<PendingStop> list, PendingStop entry, {required DateTime now}) {
    final kept = [
      ...list.where((s) => !(s.owner == entry.owner && s.itemId == entry.itemId) && now.difference(s.at) < maxAge),
      entry,
    ];
    return kept.length > _maxEntries ? kept.sublist(kept.length - _maxEntries) : kept;
  }

  static List<PendingStop> without(List<PendingStop> list, PendingStop entry) =>
      list.where((s) => !(s.owner == entry.owner && s.itemId == entry.itemId && !s.at.isAfter(entry.at))).toList();

  static Future<List<PendingStop>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map(PendingStop.fromJson).nonNulls.toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<PendingStop> list) async {
    final prefs = await SharedPreferences.getInstance();
    if (list.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode([for (final s in list) s.toJson()]));
    }
  }

  static Future<void> _queue = Future.value();

  static Future<void> _serial(Future<void> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.catchError((_) {});
    return next;
  }

  static Future<void> put(PendingStop entry) => _serial(() async => _save(merge(await load(), entry, now: DateTime.now())));

  static Future<void> remove(PendingStop entry) => _serial(() async => _save(without(await load(), entry)));
}
