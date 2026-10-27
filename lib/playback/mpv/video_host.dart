import 'package:flutter/services.dart';

abstract final class VideoHost {
  static const _channel = MethodChannel('zerk/video_host');

  static set onInput(void Function(List<String> command)? handler) {
    _channel.setMethodCallHandler(handler == null
        ? null
        : (call) async {
            if (call.method != 'input') return;
            final args = (call.arguments as List).cast<String>();
            if (args.isNotEmpty && (args.first == 'keypress' || args.first == 'mouse')) handler(args);
          });
  }

  static Future<int> create() async => (await _channel.invokeMethod<int>('create'))!;

  static Future<void> show() => _channel.invokeMethod('show');

  static Future<void> hide() => _channel.invokeMethod('hide');

  static Future<void> focus() => _channel.invokeMethod('focus');
}
