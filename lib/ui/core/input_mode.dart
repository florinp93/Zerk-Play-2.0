import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/host.dart';
import '../focus/focus_zone.dart';
import 'navigation.dart';
import 'text_focus.dart';

abstract final class InputMode {
  static final pointer = ValueNotifier<bool>(false);

  static bool get isPointer => pointer.value;

  static void usePointer() => pointer.value = true;

  static bool useDpad() {
    if (!pointer.value) return false;
    pointer.value = false;
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (focus == null || context == null || !context.mounted || focus is FocusScopeNode) return false;
    final view = View.maybeOf(context);
    if (view == null) return false;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final r = focus.rect;
    final visible = r.top >= screen.top && r.bottom <= screen.bottom && r.left >= screen.left && r.right <= screen.right;
    if (visible) return false;
    revealFocused(context);
    return true;
  }
}

class InputModeDetector extends StatefulWidget {
  const InputModeDetector({super.key, required this.child});

  final Widget child;

  @override
  State<InputModeDetector> createState() => _InputModeDetectorState();
}

class _InputModeDetectorState extends State<InputModeDetector> {
  static final _navKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
  };

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !_navKeys.contains(event.logicalKey)) return false;
    if (focusedTextField() != null) {
      InputMode.pointer.value = false;
      return false;
    }
    return InputMode.useDpad();
  }

  bool _isMouse(PointerEvent e) => e.kind == PointerDeviceKind.mouse || e.kind == PointerDeviceKind.trackpad;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (e) {
        if (_isMouse(e) && e.delta.distanceSquared > 4) InputMode.usePointer();
      },
      onPointerDown: (e) {
        if (!_isMouse(e)) return;
        InputMode.usePointer();
        if (e.buttons & kBackMouseButton != 0) {
          final ctx = FocusManager.instance.primaryFocus?.context;
          if (ctx != null) Actions.maybeInvoke(ctx, const BackIntent());
        }
      },
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) InputMode.usePointer();
      },
      onPointerPanZoomStart: (_) => InputMode.usePointer(),
      child: Host.isAndroid
          ? widget.child
          : Stack(
              textDirection: TextDirection.ltr,
              children: [
                widget.child,
                ValueListenableBuilder<bool>(
                  valueListenable: InputMode.pointer,
                  builder: (context, pointer, _) => pointer
                      ? const SizedBox.shrink()
                      : const Positioned.fill(
                          child: MouseRegion(cursor: SystemMouseCursors.none, hitTestBehavior: HitTestBehavior.translucent),
                        ),
                ),
              ],
            ),
    );
  }
}
