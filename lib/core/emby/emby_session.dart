import 'server_kind.dart';

final class EmbySession {
  EmbySession({
    required this.serverUrl,
    required this.kind,
    required this.clientName,
    required this.deviceName,
    required this.deviceId,
    required this.appVersion,
    required this.userId,
    required this.accessToken,
  });

  final Uri serverUrl;
  final ServerKind kind;
  final String clientName;
  final String deviceName;
  final String deviceId;
  final String appVersion;
  final String userId;
  final String accessToken;
}

