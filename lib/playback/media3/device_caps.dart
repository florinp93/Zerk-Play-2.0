import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class AndroidDeviceCaps {
  static const _channel = MethodChannel('zerk/player');
  static Map<String, Object?>? _cached;

  static Future<Map<String, Object?>?> get() async {
    if (_cached != null) return _cached;
    try {
      _cached = await _channel.invokeMapMethod<String, Object?>('capabilities');
      debugPrint('[caps] $_cached');
    } catch (e) {
      debugPrint('[caps] $e');
    }
    return _cached;
  }
}
