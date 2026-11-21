import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../playback/player_settings.dart';
import '../../ui/core/input_mode.dart';
import '../../ui/focus/focus_zone.dart';
import '../../ui/pages/home_page.dart';
import '../../ui/shell/shell.dart';

abstract final class DevScript {
  static final boundary = GlobalKey(debugLabel: 'dev-shot');

  static Future<void> run(String scriptPath, NavigatorState? Function() navigator) async {
    final file = File(scriptPath);
    final outDir = file.parent.path;
    final lines = file.readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('#'));
    debugPrint('[script] $scriptPath: waiting for Home');
    while (HomePage.firstLoad.value) {
      await _wait(200);
    }
    await _wait(1500);
    InputMode.useDpad();
    for (final line in lines) {
      final parts = line.split(RegExp(r'\s+'));
      final arg = parts.length > 1 ? parts[1] : '';
      debugPrint('[script] $line');
      switch (parts.first) {
        case 'wait':
          await _wait(int.tryParse(arg) ?? 1000);
        case 'key':
          final times = parts.length > 2 ? int.tryParse(parts[2]) ?? 1 : 1;
          for (var i = 0; i < times; i++) {
            _key(arg, navigator);
            await _wait(250);
          }
        case 'tab':
          final tab = ShellTab.values.where((t) => t.name == arg).firstOrNull;
          if (tab != null) Shell.go(tab);
          await _wait(800);
        case 'screen':
          PlayerSettings.screen.value = (
            scope: double.tryParse(arg) ?? 0,
            anamorphic: parts.length > 2 ? double.tryParse(parts[2]) ?? 1 : 1,
          );
          await _wait(600);
        case 'shot':
          await _shot('$outDir${Platform.pathSeparator}$arg.png');
        case 'quit':
          exit(0);
      }
    }
  }

  static void _key(String name, NavigatorState? Function() navigator) {
    switch (name) {
      case 'right':
        ZoneNavigator.move(TraversalDirection.right);
      case 'left':
        ZoneNavigator.move(TraversalDirection.left);
      case 'up':
        ZoneNavigator.move(TraversalDirection.up);
      case 'down':
        ZoneNavigator.move(TraversalDirection.down);
      case 'ok':
        final focus = FocusManager.instance.primaryFocus?.context;
        if (focus != null) Actions.maybeInvoke(focus, const ActivateIntent());
      case 'back':
        navigator()?.maybePop();
    }
  }

  static Future<void> _shot(String path) async {
    await WidgetsBinding.instance.endOfFrame;
    final render = boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) {
      debugPrint('[script] no boundary to capture');
      return;
    }
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return;
    File(path).writeAsBytesSync(bytes.buffer.asUint8List());
    debugPrint('[script] saved $path');
  }

  static Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));
}
