import 'package:flutter/services.dart';

import '../host.dart';

final class DisplayHdrStatus {
  const DisplayHdrStatus({this.supported = false, this.enabled = false});

  final bool supported;

  final bool enabled;
}

abstract final class NativeWindow {
  static const _channel = MethodChannel('zerk/window');

  static Future<bool> isFullScreen() async {
    return Host.isWindows && (await _channel.invokeMethod<bool>('isFullScreen') ?? false);
  }

  static Future<void> setFullScreen(bool fullscreen) async {
    if (Host.isWindows) await _channel.invokeMethod('setFullScreen', fullscreen);
  }

  static Future<bool> toggleFullScreen() async {
    final fs = !(await isFullScreen());
    await setFullScreen(fs);
    return fs;
  }

  static Future<DisplayHdrStatus> hdrStatus() async {
    if (!Host.isWindows) return const DisplayHdrStatus();
    try {
      final m = await _channel.invokeMapMethod<String, bool>('hdrStatus');
      return DisplayHdrStatus(supported: m?['supported'] ?? false, enabled: m?['enabled'] ?? false);
    } on PlatformException {
      return const DisplayHdrStatus();
    }
  }

  static Future<bool> setHdr(bool enabled) async {
    if (!Host.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('setHdr', enabled) ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> waitForHdr(bool enabled, {Duration timeout = const Duration(seconds: 4)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if ((await hdrStatus()).enabled == enabled) return true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }
}
