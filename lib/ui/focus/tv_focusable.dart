import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/gamepad.dart';
import '../core/input_mode.dart';
import '../core/ui_sounds.dart';
import 'focus_zone.dart';

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.onSelect,
    this.onMenu,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.reveal = true,
    this.selectSound = UiSound.select,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onMenu;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool reveal;
  final UiSound? selectSound;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());
  bool _focused = false;
  DateTime? _okDown;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  void _activate() {
    if (widget.onSelect == null) return;
    if (widget.selectSound != null) UiSounds.play(widget.selectSound!);
    widget.onSelect!();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isOk = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space;
    if (isOk) {
      if (event is KeyDownEvent) {
        _okDown = DateTime.now();
      } else if (event is KeyRepeatEvent) {
        if (widget.onMenu != null && _okDown != null &&
            DateTime.now().difference(_okDown!) > const Duration(milliseconds: 600)) {
          _okDown = null;
          widget.onMenu!();
        }
      } else if (event is KeyUpEvent) {
        if (_okDown != null) _activate();
        _okDown = null;
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && key == LogicalKeyboardKey.contextMenu && widget.onMenu != null) {
      widget.onMenu!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onFocus(bool focused) {
    setState(() => _focused = focused);
    if (focused && widget.reveal && !InputMode.isPointer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _node.hasPrimaryFocus && !InputMode.isPointer) revealFocused(context);
      });
    }
    widget.onFocusChange?.call(focused);
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          _activate();
          return null;
        }),
        MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) {
          widget.onMenu?.call();
          return null;
        }),
      },
      child: _buildFocus(context),
    );
  }

  Widget _buildFocus(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: _onFocus,
      child: MouseRegion(
        cursor: widget.onSelect == null ? MouseCursor.defer : SystemMouseCursors.click,
        onHover: (event) {
          if (InputMode.isPointer && event.kind == PointerDeviceKind.mouse && event.delta != Offset.zero && !_node.hasFocus) {
            _node.requestFocus();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect == null
              ? null
              : () {
                  _node.requestFocus();
                  _activate();
                },
          onSecondaryTap: widget.onMenu,
          onLongPress: widget.onMenu,
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}
