import 'package:flutter/material.dart';

import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';

class FocusFrame extends StatelessWidget {
  const FocusFrame({
    super.key,
    required this.focused,
    required this.child,
    this.radius = Zs.radius,
    this.scale = 1.08,
    this.ringColor = Colors.white,
    this.glowColor = Zc.accent,
  });

  final bool focused;
  final Widget child;
  final double radius;
  final double scale;
  final Color ringColor;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused ? scale : 1,
      duration: Zm.normal,
      curve: focused ? Curves.easeOutBack : Zm.curve,
      child: AnimatedContainer(
        duration: Zm.normal,
        curve: Zm.curve,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: focused ? [BoxShadow(color: glowColor.withValues(alpha: 0.45), blurRadius: 36, spreadRadius: 2)] : null,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: focused ? Border.all(color: ringColor, width: 3) : null,
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Zc.surfaceTop, this.textColor = Zc.text, this.icon, this.outlined = false});

  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color,
        borderRadius: BorderRadius.circular(8),
        border: outlined ? Border.all(color: textColor.withValues(alpha: 0.6), width: 1.5) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 18, color: textColor), const SizedBox(width: 5)],
        Text(text, style: Zt.caption.copyWith(color: textColor, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.4)),
      ]),
    );
  }
}

class RatingPill extends StatelessWidget {
  const RatingPill(this.value, {super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, color: Zc.rating, size: 24),
      const SizedBox(width: 4),
      Text(value.toStringAsFixed(1), style: Zt.meta.copyWith(color: Zc.text)),
    ]);
  }
}

class ProgressStrip extends StatelessWidget {
  const ProgressStrip(this.value, {super.key, this.height = 5});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.02, 1.0),
        child: Container(color: Zc.accent),
      ),
    );
  }
}

class MetaLine extends StatelessWidget {
  const MetaLine(this.parts, {super.key, this.leading = const [], this.trailing = const [], this.style});

  final List<String?> parts;
  final List<Widget> leading;
  final List<Widget> trailing;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final texts = parts.whereType<String>().where((s) => s.isNotEmpty).toList();
    final children = <Widget>[...leading];
    for (final t in texts) {
      if (children.isNotEmpty) children.add(Text('  ·  ', style: style ?? Zt.meta));
      children.add(Text(t, style: style ?? Zt.meta));
    }
    children.addAll(trailing);
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }
}

class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    this.icon,
    this.onSelect,
    this.primary = false,
    this.accent = Zc.accent,
    this.autofocus = false,
    this.focusNode,
    this.compact = false,
    this.collapsed = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onSelect;
  final bool primary;
  final Color accent;
  final bool autofocus;
  final FocusNode? focusNode;

  final bool compact;

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: onSelect,
      builder: (context, focused) {
        final bg = focused ? Colors.white : (primary ? accent : Colors.white.withValues(alpha: 0.12));
        final fg = focused ? Zc.background : Colors.white;
        if (collapsed && icon != null) {
          return ExpandingPill(focused: focused, primary: primary, accent: accent, leading: Icon(icon, color: fg, size: 30),
              label: Text(label, style: Zt.label.copyWith(color: fg, fontSize: 22)));
        }
        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: Zm.fast,
          curve: Zm.curve,
          child: AnimatedContainer(
            duration: Zm.fast,
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 30),
            width: compact ? 64 : null,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(32),
              boxShadow: focused ? [BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 24)] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) Icon(icon, color: fg, size: 30),
              if (!compact) ...[
                if (icon != null) const SizedBox(width: 10),
                Text(label, style: Zt.label.copyWith(color: fg, fontSize: 22)),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class ExpandingPill extends StatelessWidget {
  const ExpandingPill({
    super.key,
    required this.focused,
    required this.leading,
    required this.label,
    this.primary = false,
    this.accent = Zc.accent,
    this.pad = 17,
  });

  final bool focused;
  final Widget leading;
  final Widget label;
  final bool primary;
  final Color accent;

  final double pad;

  @override
  Widget build(BuildContext context) {
    final bg = focused ? Colors.white : (primary ? accent : Colors.white.withValues(alpha: 0.12));
    return AnimatedScale(
      scale: focused ? 1.06 : 1,
      duration: Zm.fast,
      curve: Zm.curve,
      child: AnimatedContainer(
        duration: Zm.fast,
        height: 64,
        constraints: const BoxConstraints(minWidth: 64),
        padding: EdgeInsets.only(left: pad, right: focused ? 30 : pad),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(32),
          boxShadow: focused ? [BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 24)] : null,
        ),
        child: AnimatedSize(
          duration: Zm.fast,
          curve: Zm.curve,
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            leading,
            if (focused) ...[const SizedBox(width: 12), label],
          ]),
        ),
      ),
    );
  }
}

class TitleArt extends StatelessWidget {
  const TitleArt({super.key, required this.title, this.subtitle, this.icon = Icons.movie_outlined});

  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final hue = (title.hashCode % 360).abs().toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.35, 0.22).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.40, 0.12).toColor();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white38, size: 40),
        const SizedBox(height: 10),
        if (title.isNotEmpty)
          Text(title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: Zt.label.copyWith(color: Colors.white70)),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle!, textAlign: TextAlign.center, maxLines: 1, style: Zt.caption),
          ),
      ]),
    );
  }
}

const requestTint = ColorFilter.matrix(<double>[
  0.55, 0.35, 0.10, 0, 0,
  0.25, 0.65, 0.10, 0, 0,
  0.25, 0.35, 0.40, 0, 0,
  0, 0, 0, 1, 0,
]);

class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = Zs.radius});

  final double? width;
  final double? height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.7).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: Zc.surfaceHigh, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

void showToast(BuildContext context, String text, {Duration duration = const Duration(seconds: 3), Widget? leading}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Zm.normal,
            builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, -16 * (1 - t)), child: child)),
            child: Material(
              color: Zc.surfaceTop,
              borderRadius: BorderRadius.circular(30),
              elevation: 12,
              child: Padding(
                padding: EdgeInsets.fromLTRB(leading == null ? 32 : 10, leading == null ? 16 : 10, 32, leading == null ? 16 : 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (leading != null) ...[leading, const SizedBox(width: 16)],
                  Text(text, style: Zt.label.copyWith(fontSize: 22)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(duration, entry.remove);
}
