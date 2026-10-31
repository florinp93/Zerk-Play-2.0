import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';

double _snap(double v, double min, double max, double step) =>
    ((((v - min) / step).round() * step + min).clamp(min, max) * 1000).roundToDouble() / 1000;

KeyEventResult _stepKey(KeyEvent event, double value, double min, double max, double step, ValueChanged<double> onChanged) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;
  final dir = switch (event.logicalKey) {
    LogicalKeyboardKey.arrowLeft => -1,
    LogicalKeyboardKey.arrowRight => 1,
    _ => 0,
  };
  if (dir == 0) return KeyEventResult.ignored;
  final next = _snap(value + dir * step, min, max, step);
  UiSounds.play(next == value ? UiSound.bump : UiSound.move);
  if (next != value) onChanged(next);
  return KeyEventResult.handled;
}

class ValueSlider extends StatelessWidget {
  const ValueSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.marks,
    required this.format,
    required this.onChanged,
    this.focused = false,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final List<double> marks;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final ink = focused ? Zc.background : Zc.text;
    final faint = focused ? Colors.black38 : Colors.white24;
    return LayoutBuilder(builder: (context, box) {
      const thumb = 30.0;
      final width = box.maxWidth - thumb;
      double fraction(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);
      void pick(double dx) => onChanged(_snap(min + ((dx - thumb / 2) / width).clamp(0.0, 1.0) * (max - min), min, max, step));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => pick(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
        child: SizedBox(
          height: 74,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: thumb / 2,
              right: thumb / 2,
              top: 13,
              child: Container(height: 6, decoration: BoxDecoration(color: faint, borderRadius: BorderRadius.circular(3))),
            ),
            Positioned(
              left: thumb / 2,
              top: 13,
              child: Container(
                width: width * fraction(value),
                height: 6,
                decoration: BoxDecoration(color: Zc.accent, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            for (var v = min; v <= max + 1e-9; v += step)
              Positioned(
                left: thumb / 2 + width * fraction(v) - 1,
                top: marks.any((m) => (m - v).abs() < 1e-6) ? 8 : 11,
                child: Container(
                  width: 2,
                  height: marks.any((m) => (m - v).abs() < 1e-6) ? 16 : 10,
                  color: v <= value + 1e-9 ? Zc.accent : faint,
                ),
              ),
            for (final m in marks)
              Positioned(
                left: thumb / 2 + width * fraction(m) - 40,
                width: 80,
                top: 40,
                child: Text(
                  format(m),
                  textAlign: TextAlign.center,
                  style: Zt.caption.copyWith(
                    fontSize: 17,
                    color: (m - value).abs() < 1e-6 ? ink : (focused ? Colors.black54 : Zc.textFaint),
                    fontWeight: (m - value).abs() < 1e-6 ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            Positioned(
              left: width * fraction(value),
              top: 1,
              child: Container(
                width: thumb,
                height: thumb,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Zc.accent, width: 4),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class SettingSliderRow extends StatefulWidget {
  const SettingSliderRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.marks,
    required this.format,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final double step;
  final List<double> marks;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  State<SettingSliderRow> createState() => _SettingSliderRowState();
}

class _SettingSliderRowState extends State<SettingSliderRow> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(SettingSliderRow old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) _value = widget.value;
  }

  void _set(double v) {
    setState(() => _value = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) => _stepKey(e, _value, widget.min, widget.max, widget.step, _set),
        child: TvFocusable(
          selectSound: null,
          builder: (context, focused) => AnimatedContainer(
            duration: Zm.fast,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
            decoration: BoxDecoration(color: focused ? Colors.white : Zc.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(widget.title, style: Zt.label.copyWith(fontSize: 23, color: focused ? Zc.background : Zc.text))),
                Text(widget.format(_value), style: Zt.label.copyWith(fontSize: 23, color: focused ? Zc.background : Zc.text)),
              ]),
              if (widget.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(widget.subtitle!, style: Zt.caption.copyWith(color: focused ? Colors.black54 : Zc.textFaint)),
                ),
              const SizedBox(height: 14),
              ValueSlider(
                value: _value,
                min: widget.min,
                max: widget.max,
                step: widget.step,
                marks: widget.marks,
                format: widget.format,
                focused: focused,
                onChanged: _set,
              ),
            ]),
          ),
        ),
      );
}

Future<double?> showSliderPanel(
  BuildContext context, {
  required String title,
  String? hint,
  required double value,
  required double min,
  required double max,
  required double step,
  required List<double> marks,
  required String Function(double) format,
  ValueChanged<double>? onChanged,
}) {
  return Navigator.of(context).push<double>(PageRouteBuilder<double>(
    opaque: false,
    barrierColor: Colors.black26,
    barrierDismissible: true,
    transitionDuration: Zm.normal,
    reverseTransitionDuration: Zm.fast,
    pageBuilder: (_, _, _) => _SliderPanel(
      title: title,
      hint: hint,
      initial: value,
      min: min,
      max: max,
      step: step,
      marks: marks,
      format: format,
      onChanged: onChanged,
    ),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Zm.curve)),
      child: FadeTransition(opacity: anim, child: child),
    ),
  ));
}

class _SliderPanel extends StatefulWidget {
  const _SliderPanel({
    required this.title,
    this.hint,
    required this.initial,
    required this.min,
    required this.max,
    required this.step,
    required this.marks,
    required this.format,
    this.onChanged,
  });

  final String title;
  final String? hint;
  final double initial;
  final double min;
  final double max;
  final double step;
  final List<double> marks;
  final String Function(double) format;
  final ValueChanged<double>? onChanged;

  @override
  State<_SliderPanel> createState() => _SliderPanelState();
}

class _SliderPanelState extends State<_SliderPanel> {
  late double _value = widget.initial;

  void _set(double v) {
    setState(() => _value = v);
    widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 64),
          child: Material(
            color: Zc.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(Zs.radiusLarge),
            child: SizedBox(
              width: 1100,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 36, 48, 28),
                child: FocusZone(
                  child: Focus(
                    onKeyEvent: (_, e) => _stepKey(e, _value, widget.min, widget.max, widget.step, _set),
                    child: TvFocusable(
                      autofocus: true,
                      onSelect: () => Navigator.of(context).pop(_value),
                      builder: (context, focused) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(widget.title, style: Zt.headline)),
                          Text(widget.format(_value), style: Zt.headline.copyWith(color: Zc.accentSoft)),
                        ]),
                        if (widget.hint != null) ...[
                          const SizedBox(height: 8),
                          Text(widget.hint!, style: Zt.caption),
                        ],
                        const SizedBox(height: 28),
                        ValueSlider(
                          value: _value,
                          min: widget.min,
                          max: widget.max,
                          step: widget.step,
                          marks: widget.marks,
                          format: widget.format,
                          onChanged: _set,
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
