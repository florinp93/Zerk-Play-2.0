import 'package:flutter/foundation.dart';

import '../core/windows/native_window.dart';

abstract final class KeptDisplay {
  static void Function()? restoreRefresh;

  static bool hdrOn = false;

  static Future<void> restore() async {
    final refresh = restoreRefresh;
    restoreRefresh = null;
    if (refresh != null) {
      debugPrint('[display] restoring the desktop refresh rate');
      refresh();
    }
    if (hdrOn) {
      hdrOn = false;
      debugPrint('[display] turning Windows HDR back off');
      await NativeWindow.setHdr(false);
    }
  }
}
