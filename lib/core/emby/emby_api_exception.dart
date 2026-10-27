final class EmbyApiException implements Exception {
  EmbyApiException({
    required this.statusCode,
    required this.reasonPhrase,
    required this.body,
    this.uri,
  });

  final int statusCode;
  final String? reasonPhrase;
  final Object? body;
  final Uri? uri;

  @override
  String toString() {
    return 'EmbyApiException(statusCode: $statusCode, reasonPhrase: $reasonPhrase, body: $body, uri: $uri)';
  }
}
