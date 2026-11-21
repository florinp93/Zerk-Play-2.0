import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../ui/core/input_mode.dart';
import '../../ui/focus/focus_zone.dart';
import '../../ui/pages/home_page.dart';
import '../host.dart';

abstract final class PerfBench {
  static final _timings = <FrameTiming>[];
  static bool _recording = false;
  static bool _listening = false;
  static bool running = false;

  static Future<void> run(NavigatorState? Function() navigator, {int settleMs = 10000}) async {
    if (running) return;
    running = true;
    try {
      await _run(navigator, settleMs);
    } finally {
      _recording = false;
      running = false;
    }
  }

  static Future<void> _run(NavigatorState? Function() navigator, int settleMs) async {
    if (!_listening) {
      _listening = true;
      SchedulerBinding.instance.addTimingsCallback((t) {
        if (_recording) _timings.addAll(t);
      });
    }
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    String size(Size s) => '${s.width.round()}x${s.height.round()}';
    final mode = kReleaseMode ? 'release' : kProfileMode ? 'profile' : 'debug';
    debugPrint('[bench] $mode build, view ${size(view.physicalSize)} dpr ${view.devicePixelRatio} '
        'display ${size(view.display.size)}${_memory()}; waiting for Home');
    while (HomePage.firstLoad.value) {
      await _wait(200);
    }
    await _wait(settleMs);
    InputMode.useDpad();

    await _scenario('idle_home', () => _wait(10000));
    await _scenario('row_step', () async {
      for (var i = 0; i < 12; i++) {
        _move(TraversalDirection.right);
        await _wait(350);
      }
      for (var i = 0; i < 12; i++) {
        _move(TraversalDirection.left);
        await _wait(350);
      }
      await _wait(1500);
    });
    await _scenario('row_hold', () async {
      for (var i = 0; i < 20; i++) {
        _move(TraversalDirection.right);
        await _wait(80);
      }
      for (var i = 0; i < 20; i++) {
        _move(TraversalDirection.left);
        await _wait(80);
      }
      await _wait(1500);
    });
    await _scenario('rows_down_up', () async {
      for (var i = 0; i < 6; i++) {
        _move(TraversalDirection.down);
        await _wait(600);
      }
      for (var i = 0; i < 6; i++) {
        _move(TraversalDirection.up);
        await _wait(600);
      }
      await _wait(1500);
    });
    await _scenario('details_open', () async {
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus != null) Actions.maybeInvoke(focus, const ActivateIntent());
      await _wait(12000);
    });
    await _scenario('details_back', () async {
      await navigator()?.maybePop();
      await _wait(4000);
    });
    debugPrint('[bench] done');
  }

  static void _move(TraversalDirection dir) => ZoneNavigator.move(dir);

  static Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

  static Future<void> _scenario(String name, Future<void> Function() body) async {
    _timings.clear();
    final cpu = _cpuMs();
    final clock = Stopwatch()..start();
    _recording = true;
    await body();
    await _wait(300);
    _recording = false;
    final cpuUsed = cpu == null ? null : _cpuMs()! - cpu;
    debugPrint('[bench] $name ${clock.elapsedMilliseconds}ms ${_summary(_timings)}'
        '${cpuUsed == null ? '' : ' cpu=${cpuUsed}ms'}');
  }

  static String _summary(List<FrameTiming> frames) {
    if (frames.isEmpty) return 'frames=0';
    String pct(Iterable<Duration> values) {
      final ms = [for (final v in values) v.inMicroseconds / 1000]..sort();
      double at(double p) => ms[((ms.length - 1) * p).round()];
      return '${at(0.5).toStringAsFixed(1)}/${at(0.9).toStringAsFixed(1)}/${at(0.99).toStringAsFixed(1)}';
    }

    final over16 = frames.where((f) => f.totalSpan > const Duration(microseconds: 16667)).length;
    final over33 = frames.where((f) => f.totalSpan > const Duration(microseconds: 33333)).length;
    return 'frames=${frames.length} build=${pct(frames.map((f) => f.buildDuration))} '
        'raster=${pct(frames.map((f) => f.rasterDuration))} total=${pct(frames.map((f) => f.totalSpan))} '
        'over16=$over16 over33=$over33';
  }

  static String _memory() {
    if (!Host.isAndroid && !Host.isLinux) return '';
    try {
      final info = File('/proc/meminfo').readAsStringSync();
      int? kb(String key) => int.tryParse(RegExp('$key:' r'\s+(\d+)').firstMatch(info)?.group(1) ?? '');
      final total = kb('MemTotal'), available = kb('MemAvailable');
      if (total == null) return '';
      return ', ram ${total ~/ 1024} MB${available == null ? '' : ' (${available ~/ 1024} MB free)'}';
    } catch (_) {
      return '';
    }
  }

  static int? _cpuMs() {
    if (!Host.isAndroid) return null;
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      return (int.parse(fields[11]) + int.parse(fields[12])) * 10;
    } catch (_) {
      return null;
    }
  }
}
