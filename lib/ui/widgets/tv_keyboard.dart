import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';

class TvKeyboard extends StatelessWidget {
  const TvKeyboard({super.key, required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  static const _rows = ['abcdefghijklm', 'nopqrstuvwxyz', '1234567890'];

  void _set(String text) {
    controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    return FocusZone(
      debugLabel: 'keyboard',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, row) in _rows.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final ch in row.split('')) _Key(label: ch.toUpperCase(), onSelect: () => _set(controller.text + ch)),
              if (i == 2) ...[
                _Key(label: context.l10n.keySpace, width: 150, onSelect: () => _set('${controller.text} ')),
                _Key(
                  icon: Icons.backspace_outlined,
                  width: 100,
                  onSelect: () {
                    final t = controller.text;
                    if (t.isEmpty) {
                      UiSounds.play(UiSound.bump);
                    } else {
                      _set(t.substring(0, t.length - 1));
                    }
                  },
                ),
                _Key(label: context.l10n.keyClear, width: 120, onSelect: () => _set('')),
              ],
            ]),
          ),
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onSelect, this.width = 62});

  final String? label;
  final IconData? icon;
  final VoidCallback onSelect;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: TvFocusable(
        onSelect: onSelect,
        selectSound: UiSound.move,
        reveal: false,
        builder: (context, focused) => AnimatedContainer(
          duration: Zm.fast,
          width: width,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? Colors.white : Zc.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: icon != null
              ? Icon(icon, size: 26, color: focused ? Zc.background : Zc.text)
              : Text(label!, style: Zt.label.copyWith(fontSize: 22, color: focused ? Zc.background : Zc.text)),
        ),
      ),
    );
  }
}
