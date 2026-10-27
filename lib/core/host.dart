import 'package:flutter/foundation.dart';

abstract final class Host {
  static bool get isWindows => defaultTargetPlatform == TargetPlatform.windows;
  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
}
