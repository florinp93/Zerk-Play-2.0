import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../host.dart';
import 'log_sink.dart';

abstract final class AppLog {
  static const appVersion = '2.0.0+12';

  static LogSink? _sink;
  static DebugPrintCallback? _console;

  static final _sinceStart = Stopwatch()..start();
  static final _marked = <String>{};

  static void mark(String step) {
    if (_marked.add(step)) write('[startup] $step after ${_sinceStart.elapsedMilliseconds} ms');
  }

  static String? get directory => _sink?.directory;

  static String? get file => _sink?.file;

  static Future<void> init() async {
    _sinceStart.elapsed;
    _console = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) write(message);
      if (!kReleaseMode) _console!(message, wrapWidth: wrapWidth);
    };
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      write('[error] Flutter: ${details.exceptionAsString()}\n'
          '  context: ${details.context?.toDescription() ?? '-'}  library: ${details.library ?? '-'}\n${details.stack ?? ''}');
      previousFlutterError?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      write('[error] uncaught: $error\n$stack');
      return true;
    };
    try {
      _sink = await LogSink.open();
    } catch (e) {
      _console?.call('[log] could not open the log file: $e');
    }
    write('[app] Zerk Play $appVersion (${kReleaseMode ? 'release' : kProfileMode ? 'profile' : 'debug'})');
    if (_sink != null) write('[log] writing to ${_sink!.file}');
    unawaited(LogSink.systemInfo().then((lines) {
      for (final line in lines) {
        write('[system] $line');
      }
    }));
  }

  static void write(String message) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';
    final sink = _sink;
    if (sink == null) {
      if (kReleaseMode) _console?.call('$stamp $message');
      return;
    }
    sink.add('$stamp $message');
    if (Host.isAndroid && kReleaseMode) _console?.call(message);
  }

  static Future<void> flush() async => _sink?.flush();

  static Future<void> openFolder() async => _sink?.reveal();

  static String? sidePath(String prefix) => _sink?.sidePath(prefix);

  static String _where = 'start';
  static int _slowFrames = 0, _frames = 0;
  static Duration _worst = Duration.zero;
  static Timer? _frameReport;

  static set where(String value) {
    _where = value;
    write('[nav] now on $value');
  }

  static String get where => _where;

  static void watchFrames() {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        _frames++;
        final total = t.totalSpan;
        if (total > const Duration(milliseconds: 17)) _slowFrames++;
        if (total > _worst) _worst = total;
        if (total > const Duration(milliseconds: 34)) {
          write('[jank] ${total.inMilliseconds} ms frame on $_where '
              '(build ${t.buildDuration.inMilliseconds} ms, raster ${t.rasterDuration.inMilliseconds} ms, '
              'vsync wait ${t.vsyncOverhead.inMilliseconds} ms)');
        }
      }
    });
    _frameReport = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_frames > 0) {
        write('[frames] last 10 s: $_frames frames, $_slowFrames over 16 ms, worst ${_worst.inMilliseconds} ms ($_where)');
      }
      _frames = _slowFrames = 0;
      _worst = Duration.zero;
    });
  }

  @visibleForTesting
  static void stopWatchingFrames() => _frameReport?.cancel();
}

class LogNavigatorObserver extends NavigatorObserver {
  static String _name(Route<dynamic>? r) => r == null ? '-' : (r.settings.name ?? r.runtimeType.toString());

  void _shown(String what, Route<dynamic>? route) {
    final watch = Stopwatch()..start();
    AppLog.where = _name(route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLog.write('[nav] $what ${_name(route)}: first frame after ${watch.elapsedMilliseconds} ms');
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _shown('push', route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.write('[nav] pop ${_name(route)}');
    _shown('back to', previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _shown('replace ${_name(oldRoute)} with', newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => AppLog.write('[nav] removed ${_name(route)}');
}
