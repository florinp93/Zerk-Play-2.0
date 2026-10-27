import 'package:flutter/material.dart';

import '../core/input_mode.dart';
import '../core/ui_sounds.dart';
import '../theme/tokens.dart';

class PointerScrollArrows extends StatefulWidget {
  const PointerScrollArrows({
    super.key,
    required this.controller,
    required this.child,
    this.leftInset = 0,
  });

  final ScrollController controller;
  final Widget child;

  final double leftInset;

  @override
  State<PointerScrollArrows> createState() => _PointerScrollArrowsState();
}

class _PointerScrollArrowsState extends State<PointerScrollArrows> {
  static const _width = 64.0;
  bool _hovered = false;

  void _page(int dir) {
    final c = widget.controller;
    if (!c.hasClients) return;
    final p = c.position;
    final step = (p.viewportDimension - widget.leftInset - _width).clamp(200.0, double.infinity);
    final to = (p.pixels + dir * step).clamp(p.minScrollExtent, p.maxScrollExtent);
    UiSounds.play(UiSound.move);
    p.animateTo(to, duration: const Duration(milliseconds: 420), curve: Zm.curve);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: widget.child),
        ListenableBuilder(
          listenable: Listenable.merge([widget.controller, InputMode.pointer]),
          builder: (context, _) {
            final c = widget.controller;
            final ready = c.hasClients && c.position.hasContentDimensions;
            final show = _hovered && InputMode.isPointer && ready;
            final canLeft = show && c.position.pixels > c.position.minScrollExtent + 1;
            final canRight = show && c.position.pixels < c.position.maxScrollExtent - 1;
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: (widget.leftInset - _width).clamp(0.0, double.infinity),
                top: 0,
                bottom: 0,
                width: _width,
                child: _Arrow(visible: canLeft, icon: Icons.chevron_left_rounded, onTap: () => _page(-1)),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _width,
                child: _Arrow(visible: canRight, icon: Icons.chevron_right_rounded, onTap: () => _page(1)),
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _Arrow extends StatefulWidget {
  const _Arrow({required this.visible, required this.icon, required this.onTap});

  final bool visible;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_Arrow> createState() => _ArrowState();
}

class _ArrowState extends State<_Arrow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: Zm.fast,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Center(
              child: AnimatedContainer(
                duration: Zm.fast,
                curve: Zm.curve,
                width: _hover ? 64 : 56,
                height: _hover ? 64 : 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hover ? Colors.white : Zc.background.withValues(alpha: 0.78),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
                ),
                child: Icon(widget.icon, size: 40, color: _hover ? Zc.background : Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
