import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'side_panel.dart';

Color _trailingColor(bool focused) => focused ? Zc.background : Zc.textMuted;

class _RowShell extends StatelessWidget {
  const _RowShell({required this.focused, required this.title, this.subtitle, required this.trailing});

  final bool focused;
  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Zm.fast,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: focused ? Colors.white : Zc.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Zt.label.copyWith(fontSize: 23, color: focused ? Zc.background : Zc.text)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(subtitle!, style: Zt.caption.copyWith(color: focused ? Colors.black54 : Zc.textFaint)),
              ),
          ]),
        ),
        const SizedBox(width: 24),
        IconTheme.merge(
          data: IconThemeData(color: _trailingColor(focused)),
          child: DefaultTextStyle.merge(style: TextStyle(color: _trailingColor(focused)), child: trailing),
        ),
      ]),
    );
  }
}

class SettingToggleRow extends StatelessWidget {
  const SettingToggleRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.enabled = true});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      selectSound: enabled ? UiSound.select : UiSound.bump,
      onSelect: () => enabled ? onChanged(!value) : null,
      builder: (context, focused) => _RowShell(
        focused: focused,
        title: title,
        subtitle: subtitle,
        trailing: AnimatedContainer(
          duration: Zm.fast,
          width: 64,
          height: 36,
          padding: const EdgeInsets.all(4),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? Zc.accent : (focused ? Colors.black26 : Colors.white24),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        ),
      ),
    );
  }
}

class SettingChoiceRow<T> extends StatelessWidget {
  const SettingChoiceRow({super.key, required this.title, this.subtitle, required this.value, required this.options, required this.onChanged});

  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: () async {
        final chosen = await showSidePanel<T>(
          context,
          title: title,
          options: [for (final e in options.entries) PanelOption(value: e.key, title: e.value, selected: e.key == value)],
        );
        if (chosen != null) onChanged(chosen);
      },
      builder: (context, focused) => _RowShell(
        focused: focused,
        title: title,
        subtitle: subtitle,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(options[value] ?? '$value', style: Zt.label.copyWith(color: _trailingColor(focused))),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 30),
        ]),
      ),
    );
  }
}

class SettingTextRow extends StatelessWidget {
  const SettingTextRow({super.key, required this.title, required this.value, required this.onChanged, this.hint, this.obscure = false});

  final String title;
  final String value;
  final String? hint;
  final bool obscure;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = value.isEmpty ? context.l10n.notSet : (obscure ? '•' * value.length.clamp(0, 16) : value);
    return TvFocusable(
      onSelect: () async {
        final result = await showDialog<String>(context: context, builder: (_) => _TextDialog(title: title, initial: value, hint: hint, obscure: obscure));
        if (result != null) onChanged(result.trim());
      },
      builder: (context, focused) => _RowShell(
        focused: focused,
        title: title,
        subtitle: hint,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.label.copyWith(color: _trailingColor(focused))),
        ),
      ),
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, this.hint, this.obscure = false});

  final String title;
  final String initial;
  final String? hint;
  final bool obscure;


  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Zc.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Zs.radiusLarge)),
      child: SizedBox(
        width: 820,
        child: Padding(
          padding: const EdgeInsets.all(44),
          child: FocusZone(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: Zt.headline),
              const SizedBox(height: 26),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: widget.obscure,
                autocorrect: false,
                enableSuggestions: false,
                style: Zt.label.copyWith(fontSize: 26, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: Zt.caption.copyWith(fontSize: 22),
                  filled: true,
                  fillColor: Zc.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
              const SizedBox(height: 26),
              Row(children: [
                TvButton(label: context.l10n.save, icon: Icons.check_rounded, primary: true, onSelect: () => Navigator.of(context).pop(_controller.text)),
                const SizedBox(width: 16),
                TvButton(label: context.l10n.cancel, onSelect: () => Navigator.of(context).pop()),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class SettingStepperRow extends StatelessWidget {
  const SettingStepperRow({super.key, required this.title, this.subtitle, required this.value, required this.onStep, this.onSelect});

  final String title;
  final String? subtitle;
  final String value;
  final ValueChanged<int> onStep;
  final VoidCallback? onSelect;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    UiSounds.play(UiSound.move);
    onStep(step);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, int step) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onStep(step),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(icon, size: 30)),
        );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: TvFocusable(
        onSelect: onSelect,
        builder: (context, focused) => _RowShell(
          focused: focused,
          title: title,
          subtitle: subtitle,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            button(Icons.remove_rounded, -1),
            SizedBox(
              width: 92,
              child: Text(value, textAlign: TextAlign.center, style: Zt.label.copyWith(color: _trailingColor(focused))),
            ),
            button(Icons.add_rounded, 1),
          ]),
        ),
      ),
    );
  }
}

class SettingActionRow extends StatelessWidget {
  const SettingActionRow({super.key, required this.title, required this.icon, required this.onSelect, this.subtitle});

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onSelect,
      builder: (context, focused) =>
          _RowShell(focused: focused, title: title, subtitle: subtitle, trailing: Icon(icon, size: 30)),
    );
  }
}

class SettingHeader extends StatelessWidget {
  const SettingHeader(this.text, {super.key, this.first = false});

  final String text;

  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: first ? 0 : 26, bottom: 12, left: 6),
        child: Text(text.toUpperCase(), style: Zt.label.copyWith(fontSize: 17, color: Zc.textFaint, letterSpacing: 1.4)),
      );
}
