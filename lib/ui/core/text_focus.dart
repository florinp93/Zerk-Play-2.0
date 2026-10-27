import 'package:flutter/widgets.dart';

EditableTextState? focusedTextField() {
  final focus = FocusManager.instance.primaryFocus;
  final context = focus?.context;
  if (context == null || !context.mounted) return null;
  final field = context.findAncestorStateOfType<EditableTextState>();
  return field != null && field.widget.focusNode == focus ? field : null;
}
