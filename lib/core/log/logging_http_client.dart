import 'package:http/http.dart' as http;

import 'app_log.dart';

final class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient({http.Client? inner, this.tag = 'http', this.quiet = false}) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final String tag;
  final bool quiet;

  static const _slow = Duration(seconds: 3);
  static final _secret = RegExp(r'(api_key|apikey|api-key|token|password|pw|X-Emby-Token|access_token)=[^&]*', caseSensitive: false);

  static const _noise = {'Fields', 'EnableImageTypes', 'ImageTypeLimit', 'EnableUserData', 'EnableTotalRecordCount', 'EnableImages'};

  static String describe(Uri uri) {
    final query = uri.query
        .split('&')
        .where((p) => p.isNotEmpty && !_noise.contains(p.split('=').first))
        .join('&')
        .replaceAllMapped(_secret, (m) => '${m[1]}=***');
    final shown = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}${query.isEmpty ? '' : '?$query'}';
    return shown.length > 300 ? '${shown.substring(0, 300)}...' : shown;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final watch = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      final ms = watch.elapsedMilliseconds;
      final failed = response.statusCode >= 400;
      if (!quiet || failed || watch.elapsed > _slow) {
        AppLog.write('[$tag] ${request.method} ${describe(request.url)} -> ${response.statusCode} in $ms ms'
            '${response.contentLength != null ? ', ${response.contentLength} B' : ''}${watch.elapsed > _slow ? '  (SLOW)' : ''}');
      }
      return response;
    } catch (e) {
      AppLog.write('[$tag] ${request.method} ${describe(request.url)} FAILED after ${watch.elapsedMilliseconds} ms: $e');
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
