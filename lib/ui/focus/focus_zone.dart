import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/system_keyboard.dart';
import '../core/text_focus.dart';
import '../core/ui_sounds.dart';

class FocusZone extends StatefulWidget {
  const FocusZone({
    super.key,
    required this.child,
    this.debugLabel,
    this.autofocus = false,
    this.onEnter,
    this.preferredEntry,
  });

  final Widget child;
  final String? debugLabel;
  final bool autofocus;

  final FocusNode? Function()? preferredEntry;

  final VoidCallback? onEnter;

  @override
  State<FocusZone> createState() => _FocusZoneState();

  static ZoneScopeNode? nodeOf(GlobalKey key) {
    final state = key.currentState;
    return state is _FocusZoneState ? state._node : null;
  }
}

class _FocusZoneState extends State<FocusZone> {
  late final ZoneScopeNode _node = ZoneScopeNode(debugLabel: widget.debugLabel ?? 'zone');

  @override
  void initState() {
    super.initState();
    _node.onEnter = widget.onEnter;
    _node.preferredEntry = widget.preferredEntry;
  }

  @override
  void didUpdateWidget(FocusZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    _node.onEnter = widget.onEnter;
    _node.preferredEntry = widget.preferredEntry;
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _node, autofocus: widget.autofocus, child: widget.child);
}

class ZoneScopeNode extends FocusScopeNode {
  ZoneScopeNode({super.debugLabel});

  VoidCallback? onEnter;
  FocusNode? Function()? preferredEntry;

  Iterable<FocusNode> get items => traversalDescendants.where(
        (n) => n is! FocusScopeNode && n.canRequestFocus && _zoneOf(n) == this && n.context != null,
      );

  FocusNode? get remembered {
    final f = focusedChild;
    if (f == null || f is FocusScopeNode || !f.canRequestFocus || f.context == null) return null;
    return f;
  }
}

ZoneScopeNode? _zoneOf(FocusNode node) {
  for (FocusNode? n = node.parent; n != null; n = n.parent) {
    if (n is ZoneScopeNode) return n;
  }
  return null;
}

abstract final class ZoneNavigator {
  static bool move(TraversalDirection dir) {
    final current = FocusManager.instance.primaryFocus;
    if (current == null || current.context == null) return false;
    final zone = current is ZoneScopeNode ? current : _zoneOf(current);
    if (zone == null) return current.focusInDirection(dir);

    final from = current.rect;

    if (current is! ZoneScopeNode) {
      final next = _best(from, zone.items.where((n) => n != current), dir, (n) => n.rect);
      if (next != null) {
        next.requestFocus();
        UiSounds.play(UiSound.move);
        return true;
      }
    }

    final root = _routeScope(zone);
    final zones = <ZoneScopeNode>[
      for (final n in root.descendants)
        if (n is ZoneScopeNode && n != zone && !_isAncestor(n, zone) && !_isAncestor(zone, n) && n.items.isNotEmpty) n,
    ];
    final target = _best(zone.rect, zones, dir, (z) => z.rect, perpendicularFrom: from);
    if (target == null) {
      UiSounds.play(UiSound.bump);
      return false;
    }
    enter(target, from: from);
    UiSounds.play(UiSound.move);
    return true;
  }

  static void enter(ZoneScopeNode zone, {Rect? from}) {
    final preferred = zone.preferredEntry?.call();
    final remembered = preferred != null && preferred.canRequestFocus ? preferred : zone.remembered;
    if (remembered != null) {
      remembered.requestFocus();
    } else {
      final items = zone.items.toList();
      if (items.isEmpty) return;
      final anchor = from?.center ?? items.first.rect.center;
      items.sort((a, b) => (a.rect.center - anchor).distance.compareTo((b.rect.center - anchor).distance));
      items.first.requestFocus();
    }
    zone.onEnter?.call();
  }

  static FocusScopeNode _routeScope(FocusNode node) {
    final context = node.context;
    final subtree = context == null ? null : ModalRoute.of(context)?.subtreeContext;
    return subtree == null ? FocusManager.instance.rootScope : FocusScope.of(subtree);
  }

  static bool _isAncestor(FocusNode a, FocusNode b) {
    for (FocusNode? n = b.parent; n != null; n = n.parent) {
      if (n == a) return true;
    }
    return false;
  }

  static T? _best<T>(Rect from, Iterable<T> candidates, TraversalDirection dir, Rect Function(T) rectOf,
      {Rect? perpendicularFrom}) {
    final across = perpendicularFrom ?? from;
    T? best;
    var bestScore = double.infinity;
    for (final c in candidates) {
      final r = rectOf(c);
      if (r.isEmpty) continue;
      final double gap;
      final double cross;
      final bool overlap;
      switch (dir) {
        case TraversalDirection.left:
          if (r.center.dx >= from.center.dx - 1 || r.right > from.right) continue;
          gap = math.max(0, from.left - r.right);
          cross = (r.center.dy - across.center.dy).abs();
          overlap = r.top < across.bottom && r.bottom > across.top;
        case TraversalDirection.right:
          if (r.center.dx <= from.center.dx + 1 || r.left < from.left) continue;
          gap = math.max(0, r.left - from.right);
          cross = (r.center.dy - across.center.dy).abs();
          overlap = r.top < across.bottom && r.bottom > across.top;
        case TraversalDirection.up:
          if (r.center.dy >= from.center.dy - 1 || r.bottom > from.bottom) continue;
          gap = math.max(0, from.top - r.bottom);
          cross = _horizontalDistance(r, across);
          overlap = r.left < across.right && r.right > across.left;
        case TraversalDirection.down:
          if (r.center.dy <= from.center.dy + 1 || r.top < from.top) continue;
          gap = math.max(0, r.top - from.bottom);
          cross = _horizontalDistance(r, across);
          overlap = r.left < across.right && r.right > across.left;
      }
      final score = gap + cross * (overlap ? 0.1 : 2.5);
      if (score < bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  static double _horizontalDistance(Rect r, Rect from) {
    if (r.left <= from.center.dx && r.right >= from.center.dx) return 0;
    return math.min((r.left - from.center.dx).abs(), (r.right - from.center.dx).abs());
  }
}

class _ZoneMoveIntent extends Intent {
  const _ZoneMoveIntent(this.direction);

  final TraversalDirection direction;
}

class _ZoneMoveAction extends ContextAction<_ZoneMoveIntent> {
  @override
  bool isEnabled(_ZoneMoveIntent intent, [BuildContext? context]) {
    final field = focusedTextField();
    if (field == null) return true;
    final value = field.textEditingValue;
    final sel = value.selection;
    if (!sel.isValid) return true;
    return switch (intent.direction) {
      TraversalDirection.left => sel.isCollapsed && sel.baseOffset <= 0,
      TraversalDirection.right => sel.isCollapsed && sel.baseOffset >= value.text.length,
      _ => true,
    };
  }

  @override
  Object? invoke(_ZoneMoveIntent intent, [BuildContext? context]) {
    ZoneNavigator.move(intent.direction);
    return null;
  }
}

class ZoneNavigation extends StatelessWidget {
  const ZoneNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowUp): _ZoneMoveIntent(TraversalDirection.up),
        SingleActivator(LogicalKeyboardKey.arrowDown): _ZoneMoveIntent(TraversalDirection.down),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _ZoneMoveIntent(TraversalDirection.left),
        SingleActivator(LogicalKeyboardKey.arrowRight): _ZoneMoveIntent(TraversalDirection.right),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      child: Actions(
        actions: {_ZoneMoveIntent: _ZoneMoveAction()},
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) => SystemKeyboard.handle(event) ?? KeyEventResult.ignored,
          child: child,
        ),
      ),
    );
  }
}

enum RevealMode {
  minimal,

  anchored,
}

class RevealController extends ScrollController {
  RevealController({this.mode = RevealMode.minimal, this.anchor = 0, this.margin = 48, super.initialScrollOffset});

  final RevealMode mode;
  final double anchor;
  final double margin;
}

void revealFocused(BuildContext context, {Duration duration = const Duration(milliseconds: 260)}) {
  RenderObject? target = context.findRenderObject();
  var scrollable = Scrollable.maybeOf(context);
  while (scrollable != null && target != null && target.attached) {
    final position = scrollable.position;
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport == null) break;
    final controller = scrollable.widget.controller;
    final policy = controller is RevealController ? controller : RevealController();

    final leading = viewport.getOffsetToReveal(target, 0).offset;
    final trailing = viewport.getOffsetToReveal(target, 1).offset;
    double to;
    if (policy.mode == RevealMode.anchored) {
      to = leading - policy.anchor;
    } else if (trailing + policy.margin <= position.minScrollExtent) {
      to = position.minScrollExtent;
    } else if (position.pixels > leading - policy.margin) {
      to = leading - policy.margin;
    } else if (position.pixels < trailing + policy.margin) {
      to = trailing + policy.margin;
    } else {
      to = position.pixels;
    }
    to = to.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((to - position.pixels).abs() > 0.5) {
      position.animateTo(to, duration: duration, curve: Curves.easeOutCubic);
    }
    target = scrollable.context.findRenderObject();
    scrollable = Scrollable.maybeOf(scrollable.context);
  }
}
