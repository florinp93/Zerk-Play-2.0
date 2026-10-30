import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../widgets/exit_app.dart';
import 'input_mode.dart';
import 'playback_launcher.dart';
import 'text_focus.dart';
import 'ui_sounds.dart';

class BackIntent extends Intent {
  const BackIntent();
}

class _BackAction extends ContextAction<BackIntent> {
  _BackAction(this.onBack, this.parentContext);

  final bool Function() onBack;
  final BuildContext? parentContext;

  @override
  bool isEnabled(BackIntent intent, [BuildContext? context]) {
    if (focusedTextField() != null && HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.backspace)) {
      return false;
    }
    return true;
  }

  @override
  Object? invoke(BackIntent intent, [BuildContext? context]) {
    if (onBack()) return true;
    final parent = parentContext;
    if (parent != null && parent.mounted) return Actions.maybeInvoke(parent, intent) == true;
    return false;
  }
}

class BackHandler extends StatelessWidget {
  const BackHandler({super.key, required this.onBack, required this.child});

  final bool Function() onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(actions: {BackIntent: _BackAction(onBack, context)}, child: child);
  }
}

final class SystemBack with WidgetsBindingObserver {
  SystemBack._();

  static DateTime _lastKey = DateTime(0);
  static DateTime _unhandled = DateTime(0);

  static void markUnhandled() => _unhandled = DateTime.now();

  static void install() {
    WidgetsBinding.instance.addObserver(SystemBack._());
    HardwareKeyboard.instance.addHandler((e) {
      if (e.logicalKey == LogicalKeyboardKey.goBack) _lastKey = DateTime.now();
      return e is KeyDownEvent && _backKeys.contains(e.logicalKey) && focusedTextField() == null && DoubleBack.handle();
    });
  }

  static final _backKeys = {
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.browserBack,
    LogicalKeyboardKey.gameButtonB,
  };

  @override
  Future<bool> didPopRoute() async {
    const window = Duration(milliseconds: 600);
    final now = DateTime.now();
    if (now.difference(_lastKey) < window) return now.difference(_unhandled) >= window;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null || !focus.mounted) return false;
    return Actions.maybeInvoke(focus, const BackIntent()) == true;
  }
}

abstract final class DoubleBack {
  static const _window = Duration(milliseconds: 450);
  static DateTime _last = DateTime(0);
  static GlobalKey<NavigatorState>? navigator;

  static bool handle() {
    final now = DateTime.now();
    final second = now.difference(_last) < _window;
    _last = second ? DateTime(0) : now;
    final context = navigator?.currentState?.overlay?.context;
    if (!second || playbackActive || context == null) return false;
    unawaited(confirmExit(context));
    return true;
  }
}

class BackKeys extends StatelessWidget {
  const BackKeys({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): BackIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): BackIntent(),
        SingleActivator(LogicalKeyboardKey.browserBack): BackIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): BackIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonB): BackIntent(),
      },
      child: BackHandler(
        onBack: () {
          final nav = navigatorKey.currentState;
          if (nav != null && nav.canPop()) {
            UiSounds.play(UiSound.back);
            nav.pop();
            return true;
          }
          SystemBack.markUnhandled();
          return false;
        },
        child: child,
      ),
    );
  }
}

Route<T> tvRoute<T>(Widget page, {String? name}) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: name),
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => Material(
      color: Zc.background,
      child: Stack(children: [Positioned.fill(child: page), const _PointerBackButton()]),
    ),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Zm.curve, reverseCurve: Curves.easeIn);
      final slide = SlideTransition(
        position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
        child: child,
      );
      return AnimatedBuilder(
        animation: curved,
        child: slide,
        builder: (context, child) {
          final leaving = animation.status == AnimationStatus.reverse;
          return Stack(fit: StackFit.passthrough, children: [
            Opacity(opacity: leaving ? curved.value : 1, child: child),
            if (!leaving && curved.value < 1)
              Positioned.fill(
                child: IgnorePointer(child: ColoredBox(color: Zc.background.withValues(alpha: 1 - curved.value))),
              ),
          ]);
        },
      );
    },
  );
}

class _PointerBackButton extends StatefulWidget {
  const _PointerBackButton();

  @override
  State<_PointerBackButton> createState() => _PointerBackButtonState();
}

class _PointerBackButtonState extends State<_PointerBackButton> {
  bool _hover = false;

  void _back() {
    final focus = FocusManager.instance.primaryFocus?.context;
    final ctx = focus != null && focus.mounted ? focus : context;
    Actions.maybeInvoke(ctx, const BackIntent());
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 28,
      top: 28,
      child: ValueListenableBuilder(
        valueListenable: InputMode.pointer,
        builder: (context, pointer, _) => IgnorePointer(
          ignoring: !pointer,
          child: AnimatedOpacity(
            opacity: pointer ? 1 : 0,
            duration: Zm.fast,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                onTap: _back,
                child: AnimatedContainer(
                  duration: Zm.fast,
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hover ? Colors.white : Zc.background.withValues(alpha: 0.7),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                  ),
                  child: Icon(Icons.arrow_back_rounded, size: 32, color: _hover ? Zc.background : Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
