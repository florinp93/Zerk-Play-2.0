import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final class ChunkedProxy {
  ChunkedProxy._(this._server) {
    _server.listen(_handle, onError: (Object e) => debugPrint('[trailer] proxy: $e'));
  }

  static Future<ChunkedProxy>? _instance;

  static Future<ChunkedProxy> get instance =>
      _instance ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0).then(ChunkedProxy._);

  static const _piece = 8 * 1024 * 1024;

  final HttpServer _server;
  final _client = http.Client();
  final _streams = <String, ({Uri url, int length})>{};
  var _next = 0;

  Uri wrap(Uri url) {
    final length = int.tryParse(url.queryParameters['clen'] ?? '');
    if (!url.host.endsWith('googlevideo.com') || length == null || length <= 0) return url;
    if (_streams.length > 16) _streams.remove(_streams.keys.first);
    final id = '${_next++}';
    _streams[id] = (url: url, length: length);
    return Uri(scheme: 'http', host: '127.0.0.1', port: _server.port, path: '/s/$id');
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final s = req.uri.pathSegments.length == 2 ? _streams[req.uri.pathSegments[1]] : null;
    if (s == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    var start = 0, end = s.length - 1;
    final range = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range != null) {
      if (range.group(1)!.isNotEmpty) start = int.parse(range.group(1)!);
      if (range.group(2)!.isNotEmpty) end = math.min(end, int.parse(range.group(2)!));
      if (range.group(1)!.isEmpty && range.group(2)!.isNotEmpty) {
        start = math.max(0, s.length - int.parse(range.group(2)!));
        end = s.length - 1;
      }
    }
    if (start > end || start >= s.length) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${s.length}');
      await res.close();
      return;
    }
    res.statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent;
    res.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, s.url.queryParameters['mime'] ?? 'application/octet-stream')
      ..contentLength = end - start + 1;
    if (range != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${s.length}');
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    try {
      for (var at = start; at <= end; at += _piece) {
        final to = math.min(end, at + _piece - 1);
        final piece = await _client
            .send(http.Request('GET', Uri.parse('${s.url}&range=$at-$to')))
            .timeout(const Duration(seconds: 15));
        if (piece.statusCode >= 300) throw HttpException('upstream ${piece.statusCode}', uri: s.url);
        await res.addStream(piece.stream);
      }
      await res.close();
    } catch (e) {
      if (e is! SocketException) debugPrint('[trailer] proxy stream: $e');
      try {
        await res.close();
      } catch (_) {}
    }
  }
}
