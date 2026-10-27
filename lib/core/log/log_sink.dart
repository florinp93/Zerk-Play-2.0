import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final class LogSink {
  LogSink._(this.directory, this.file, this._out);

  static const _keep = 12;

  final String directory;
  final String file;
  final IOSink _out;
  Timer? _flushTimer;
  bool _flushing = false;

  final _held = <String>[];

  static Future<LogSink> open() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'logs'));
    await dir.create(recursive: true);
    _prune(dir);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'zerkplay-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.log';
    final path = p.join(dir.path, name);
    return LogSink._(dir.path, path, File(path).openWrite(mode: FileMode.append));
  }

  static void _prune(Directory dir) {
    try {
      for (final prefix in const ['zerkplay-', 'mpv-']) {
        final files = dir.listSync().whereType<File>().where((f) => p.basename(f.path).startsWith(prefix)).toList()
          ..sort((a, b) => b.path.compareTo(a.path));
        for (final f in files.skip(_keep)) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }

  void add(String line) {
    if (_flushing) {
      _held.add(line);
    } else {
      try {
        _out.writeln(line);
      } catch (_) {}
    }
    _flushTimer ??= Timer(const Duration(milliseconds: 800), () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _out.flush();
    } catch (_) {
    } finally {
      _flushing = false;
    }
    if (_held.isEmpty) return;
    final held = List.of(_held);
    _held.clear();
    for (final line in held) {
      add(line);
    }
  }

  Future<void> reveal() async {
    await flush();
    if (Platform.isWindows) await Process.start('explorer.exe', [directory]);
  }

  String sidePath(String prefix) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return p.join(directory, '$prefix-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.log');
  }

  static Future<List<String>> systemInfo() async {
    final lines = <String>[
      'os: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'cpus: ${Platform.numberOfProcessors}  locale: ${Platform.localeName}  dart: ${Platform.version.split(' ').first}',
      'exe: ${Platform.resolvedExecutable}',
      for (final d in PlatformDispatcher.instance.displays)
        'display ${d.id}: ${d.size.width.round()}x${d.size.height.round()} px, scale ${d.devicePixelRatio}, ${d.refreshRate.toStringAsFixed(2)} Hz',
    ];
    if (!Platform.isWindows) return lines;
    final fonts = p.join(Platform.environment['WINDIR'] ?? r'C:\Windows', 'Fonts');
    lines.add('icon fonts: Segoe Fluent Icons ${File(p.join(fonts, 'SegoeIcons.ttf')).existsSync() ? 'yes' : 'NO'}, '
        'Segoe MDL2 Assets ${File(p.join(fonts, 'segmdl2.ttf')).existsSync() ? 'yes' : 'NO'}');
    final mpv = File(p.join(p.dirname(Platform.resolvedExecutable), 'libmpv-2.dll'));
    lines.add('libmpv-2.dll: ${mpv.existsSync() ? '${mpv.lengthSync()} bytes, ${mpv.lastModifiedSync().toIso8601String()}' : 'MISSING'}');
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Get-CimInstance Win32_VideoController | ForEach-Object { "gpu: $($_.Name), driver $($_.DriverVersion), $($_.VideoModeDescription), $($_.CurrentRefreshRate) Hz" }; '
            r'Get-CimInstance Win32_Processor | ForEach-Object { "cpu: $($_.Name.Trim())" }; '
            r'"ram: {0:N1} GB" -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB); '
            r'$o = Get-CimInstance Win32_OperatingSystem; "windows: $($o.Caption) $($o.Version) build $($o.BuildNumber)"',
      ]).timeout(const Duration(seconds: 8));
      lines.addAll((r.stdout as String).split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty));
    } catch (e) {
      lines.add('hardware query failed: $e');
    }
    return lines;
  }
}
