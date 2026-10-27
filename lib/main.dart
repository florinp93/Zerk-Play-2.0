import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_services.dart';
import 'core/host.dart';
import 'core/log/app_log.dart';
import 'core/log/perf_bench.dart';
import 'playback/kept_display.dart';
import 'playback/media3/media3_smoke.dart';
import 'core/windows/native_window.dart';
import 'l10n/l10n.dart';
import 'ui/core/gamepad.dart';
import 'ui/core/input_mode.dart';
import 'ui/core/navigation.dart';
import 'ui/core/system_keyboard.dart';
import 'ui/core/tv_scale.dart';
import 'ui/core/ui_sounds.dart';
import 'ui/focus/focus_zone.dart';
import 'ui/pages/onboarding_page.dart';
import 'ui/pages/sign_in_page.dart';
import 'ui/shell/shell.dart';
import 'ui/theme/tokens.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init();
  AppLog.watchFrames();
  WidgetsBinding.instance.addPostFrameCallback((_) => AppLog.mark('first frame'));
  if (Host.isWindows) await _initWindow();
  final services = await AppServices.create();
  if (Host.isWindows && services.settings.startFullScreen) {
    debugPrint('[app] starting in full screen');
    await NativeWindow.setFullScreen(true);
  }
  unawaited(UiSounds.load());
  Gamepad.start();
  SystemBack.install();
  SystemKeyboard.install();
  final tabArg = args.where((a) => a.startsWith('--tab=')).map((a) => a.substring(6)).firstOrNull;
  final initialTab = ShellTab.values.where((t) => t.name == tabArg).firstOrNull ?? ShellTab.home;
  AppLog.mark('services ready');
  runApp(AppServicesScope(services: services, child: ZerkApp(initialTab: initialTab, bench: args.contains('--bench'))));
}

Future<void> _initWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Zerk Play',
      size: Size(1600, 900),
      minimumSize: Size(960, 540),
      center: true,
      backgroundColor: Zc.background,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

class ZerkApp extends StatefulWidget {
  const ZerkApp({super.key, this.initialTab = ShellTab.home, this.bench = false});

  final ShellTab initialTab;

  final bool bench;

  @override
  State<ZerkApp> createState() => _ZerkAppState();
}

class _ZerkAppState extends State<ZerkApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) => debugPrint('[app] lifecycle ${s.name}'),
      onExitRequested: () async {
        debugPrint('[app] exit requested');
        await KeptDisplay.restore();
        await AppLog.flush();
        return AppExitResponse.exit;
      },
    );
    final route = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (Host.isAndroid && route.startsWith('/dev-player')) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => runMedia3Smoke(_navigator.currentState!, subtitleBackground: route == '/dev-player-box'),
      );
    }
    if (widget.bench || route == '/dev-bench') unawaited(PerfBench.run(_navigator));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.of(context);
    final signedIn = services.isSignedIn;
    return MaterialApp(
      title: 'Zerk Play',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: Locale(services.settings.resolvedUiLanguage),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      navigatorKey: _navigator,
      navigatorObservers: [LogNavigatorObserver()],
      builder: (context, child) => InputModeDetector(
        child: TvScale(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f11): () => unawaited(NativeWindow.toggleFullScreen()),
            },
            child: BackKeys(navigatorKey: _navigator, child: ZoneNavigation(child: child!)),
          ),
        ),
      ),
      home: !signedIn
          ? const SignInPage()
          : !services.settings.onboarded
              ? const OnboardingPage(key: ValueKey('onboarding'))
              : Shell(key: const ValueKey('shell'), initialTab: widget.initialTab),
    );
  }
}
