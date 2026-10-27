import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/host.dart';
import 'text_focus.dart';

abstract final class SystemKeyboard {
  static const _channel = MethodChannel('zerk/ime');
  static bool _editing = false;

  static void install() {
    if (Host.isAndroid) FocusManager.instance.addListener(_onFocus);
  }

  static void _onFocus() {
    final editing = _keyboardField() != null;
    if (editing == _editing) return;
    _editing = editing;
    _channel.invokeMethod<void>('editing', editing).catchError((Object e) => debugPrint('[ime] $e'));
  }

  static EditableTextState? _keyboardField() {
    final field = focusedTextField();
    if (field == null || field.widget.readOnly || field.widget.keyboardType == TextInputType.none) return null;
    return field;
  }

  static KeyEventResult? handle(KeyEvent event) {
    if (!Host.isAndroid || event.logicalKey != LogicalKeyboardKey.select) return null;
    final field = _keyboardField();
    if (field == null) return null;
    if (event is KeyUpEvent) field.requestKeyboard();
    return KeyEventResult.handled;
  }
}
