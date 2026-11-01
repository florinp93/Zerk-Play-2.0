import 'package:flutter/foundation.dart';

abstract final class Host {
  static bool get isWindows => defaultTargetPlatform == TargetPlatform.windows;
  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
  static bool get isLinux => defaultTargetPlatform == TargetPlatform.linux;
  static bool get isDesktop => isWindows || isLinux;
}
