import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import 'kept_display.dart';

final class DisplayRefreshMatcher {
  static String? _device;

  double? matchFrameRate(double fps, {int? hwnd}) {
    if (!Platform.isWindows || fps < 10 || fps > 121) return null;
    return using((arena) {
      final device = _monitorDevice(arena, hwnd ?? GetForegroundWindow());
      if (device == null) return null;
      final devName = device.toNativeUtf16(allocator: arena);

      final current = arena<DEVMODE>()..ref.dmSize = sizeOf<DEVMODE>();
      if (EnumDisplaySettings(devName, ENUM_CURRENT_SETTINGS, current) == 0) return null;
      final w = current.ref.dmPelsWidth, h = current.ref.dmPelsHeight;
      final bpp = current.ref.dmBitsPerPel;

      final currentHz = _actualHz(current.ref.dmDisplayFrequency);
      debugPrint('[refresh] ${fps.toStringAsFixed(3)} fps video on $device, now ${w}x$h @ ${currentHz.toStringAsFixed(3)} Hz');
      if (_isMultiple(currentHz, fps)) {
        debugPrint('[refresh] current rate already fits');
        return null;
      }

      final mode = arena<DEVMODE>()..ref.dmSize = sizeOf<DEVMODE>();
      int? best;
      for (var i = 0; EnumDisplaySettings(devName, i, mode) != 0; i++) {
        final m = mode.ref;
        if (m.dmPelsWidth != w || m.dmPelsHeight != h || m.dmBitsPerPel != bpp) continue;
        final hz = m.dmDisplayFrequency;
        if (!_isMultiple(_actualHz(hz), fps)) continue;
        if (best == null || hz < best) best = hz;
      }
      if (best == null) {
        debugPrint('[refresh] no mode matches ${fps.toStringAsFixed(3)} fps at ${w}x$h');
        return null;
      }

      current.ref
        ..dmDisplayFrequency = best
        ..dmFields = DM_DISPLAYFREQUENCY | DM_PELSWIDTH | DM_PELSHEIGHT;
      final rc = ChangeDisplaySettingsEx(devName, current, NULL, CDS_FULLSCREEN, nullptr);
      if (rc != DISP_CHANGE_SUCCESSFUL) {
        debugPrint('[refresh] ChangeDisplaySettingsEx($best Hz) failed: $rc');
        return null;
      }
      debugPrint('[refresh] switched to $best Hz');
      _device = device;
      KeptDisplay.restoreRefresh = null;
      return _actualHz(best);
    });
  }

  void restore() => _restore();

  void keep() {
    if (_device == null) return;
    debugPrint('[refresh] keeping $_device in its playback mode');
    KeptDisplay.restoreRefresh = _restore;
  }

  static void _restore() {
    final device = _device;
    if (device == null) return;
    _device = null;
    KeptDisplay.restoreRefresh = null;
    final rc = using((arena) => ChangeDisplaySettingsEx(device.toNativeUtf16(allocator: arena), nullptr, NULL, 0, nullptr));
    debugPrint('[refresh] restored $device to its desktop mode (rc $rc)');
  }

  static double _actualHz(int hz) =>
      const {23, 29, 47, 59, 71, 119, 143}.contains(hz) ? (hz + 1) * 1000 / 1001 : hz.toDouble();

  static bool _isMultiple(double hz, double fps) {
    for (var k = 1; k <= 6; k++) {
      if ((hz - fps * k).abs() < 0.02 * k) return true;
    }
    return false;
  }

  static String? _monitorDevice(Arena arena, int hwnd) {
    final monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    final info = arena<MONITORINFOEX>()..ref.monitorInfo.cbSize = sizeOf<MONITORINFOEX>();
    if (GetMonitorInfo(monitor, info.cast()) == 0) return null;
    return info.ref.szDevice;
  }
}
