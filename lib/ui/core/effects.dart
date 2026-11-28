import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../app/app_settings.dart';
import '../../core/host.dart';

abstract final class Effects {
  static bool reduced = false;

  static const _lowMemoryMb = 3000;
  static const _defaultCacheBytes = 100 << 20;
  static const _reducedCacheBytes = 40 << 20;

  static int? _ramMb;
  static bool _ramRead = false;

  static int? get ramMb {
    if (!_ramRead) {
      _ramRead = true;
      _ramMb = _readRam();
    }
    return _ramMb;
  }

  static bool get lowMemory {
    final ram = ramMb;
    return ram != null && ram < _lowMemoryMb;
  }

  static void apply(ReduceEffects mode) {
    final next = switch (mode) {
      ReduceEffects.on => true,
      ReduceEffects.off => false,
      ReduceEffects.auto => Host.isAndroid && lowMemory,
    };
    PaintingBinding.instance.imageCache.maximumSizeBytes = next ? _reducedCacheBytes : _defaultCacheBytes;
    if (next != reduced || !_logged) {
      _logged = true;
      debugPrint('[effects] ${next ? 'reduced' : 'full'} (${mode.name}, ram ${ramMb ?? '?'} MB)');
    }
    reduced = next;
  }

  static bool _logged = false;

  static int? _readRam() {
    if (!Host.isAndroid && !Host.isLinux) return null;
    try {
      final info = File('/proc/meminfo').readAsStringSync();
      final kb = int.tryParse(RegExp(r'MemTotal:\s+(\d+)').firstMatch(info)?.group(1) ?? '');
      return kb == null ? null : kb ~/ 1024;
    } catch (_) {
      return null;
    }
  }
}
