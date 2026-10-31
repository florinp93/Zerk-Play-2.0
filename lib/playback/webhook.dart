import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/emby/models/emby_item.dart';

final class PlaybackWebhook {
  PlaybackWebhook(String url) : _url = Uri.tryParse(url.trim());

  final Uri? _url;

  bool get enabled => _url != null && _url.hasScheme;

  void send(String event, EmbyItem? item, {Duration? position, Map<String, Object?> extra = const {}}) {
    final url = _url;
    if (url == null || !url.hasScheme) return;
    final body = jsonEncode({
      'event': event,
      'app': 'Zerk Play',
      if (item != null) ...{
        'id': item.id,
        'type': item.type,
        'title': item.name,
        'series': ?item.seriesName,
        'year': ?item.productionYear,
      },
      if (position != null) 'position': position.inSeconds,
      ...extra,
    });
    unawaited(http
        .post(url, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 5))
        .then((r) => debugPrint('[webhook] $event -> ${r.statusCode}'), onError: (Object e) => debugPrint('[webhook] $event failed: $e')));
  }
}
