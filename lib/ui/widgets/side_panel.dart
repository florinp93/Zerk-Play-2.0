import 'package:flutter/material.dart';

import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import 'net_image.dart';

class PanelOption<T> {
  const PanelOption({required this.value, required this.title, this.subtitle, this.selected = false, this.icon, this.image});

  final T value;
  final String title;
  final String? subtitle;
  final bool selected;
  final IconData? icon;
  final Uri? image;
}

Future<T?> showSidePanel<T>(BuildContext context, {required String title, required List<PanelOption<T>> options}) {
  return Navigator.of(context).push<T>(PageRouteBuilder<T>(
    opaque: false,
    barrierColor: Colors.black54,
    barrierDismissible: true,
    transitionDuration: Zm.normal,
    reverseTransitionDuration: Zm.fast,
    pageBuilder: (_, _, _) => _SidePanel<T>(title: title, options: options),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Zm.curve)),
      child: FadeTransition(opacity: anim, child: child),
    ),
  ));
}

class _SidePanel<T> extends StatelessWidget {
  const _SidePanel({required this.title, required this.options});

  final String title;
  final List<PanelOption<T>> options;

  @override
  Widget build(BuildContext context) {
    final initial = options.indexWhere((o) => o.selected);
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Zc.surface,
        child: SizedBox(
          width: 680,
          height: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 72, 56, 28),
              child: Text(title, style: Zt.headline),
            ),
            Expanded(
              child: FocusZone(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 60),
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final o = options[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TvFocusable(
                        autofocus: i == (initial < 0 ? 0 : initial),
                        onSelect: () => Navigator.of(context).pop(o.value),
                        builder: (context, focused) => AnimatedContainer(
                          duration: Zm.fast,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                          decoration: BoxDecoration(
                            color: focused ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(children: [
                            if (o.icon != null) ...[
                              Icon(o.icon, color: focused ? Zc.background : Zc.textMuted, size: 30),
                              const SizedBox(width: 18),
                            ],
                            if (o.image != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: NetImage(url: o.image, width: 160, height: 90),
                              ),
                              const SizedBox(width: 22),
                            ],
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(o.title, style: Zt.label.copyWith(fontSize: 24, color: focused ? Zc.background : Zc.text)),
                                if (o.subtitle != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(o.subtitle!, style: Zt.caption.copyWith(color: focused ? Colors.black54 : Zc.textFaint)),
                                  ),
                              ]),
                            ),
                            if (o.selected) Icon(Icons.check_rounded, color: focused ? Zc.accent : Zc.accentSoft, size: 30),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
