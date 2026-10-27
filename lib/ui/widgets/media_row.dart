import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'scroll_arrows.dart';

const double contentLeft = Zs.railCollapsed + 56;

double posterGridCardWidth(double width, int columns) =>
    ((width - contentLeft - 120 - Zs.cardGap * (columns - 1)) / columns).clamp(100.0, 600.0);

class MediaRow extends StatefulWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.height,
    this.trailingTitle,
    this.gap = Zs.cardGap,
    this.left = contentLeft,
  });

  final double left;

  final String title;
  final Widget? trailingTitle;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  final double height;
  final double gap;

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  late final _controller = RevealController(mode: RevealMode.anchored, anchor: widget.left);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: EdgeInsets.only(left: widget.left, bottom: 18),
        child: Row(children: [
          Text(widget.title, style: Zt.rowTitle),
          if (widget.trailingTitle != null) ...[const SizedBox(width: 16), widget.trailingTitle!],
        ]),
      ),
      SizedBox(
        height: widget.height,
        child: PointerScrollArrows(
          controller: _controller,
          leftInset: widget.left,
          child: FocusZone(
            debugLabel: 'row:${widget.title}',
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
              padding: EdgeInsets.symmetric(horizontal: widget.left),
              itemCount: widget.itemCount,
              separatorBuilder: (_, _) => SizedBox(width: widget.gap),
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ),
      ),
    ]);
  }
}

class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, required this.cardWidth, required this.cardHeight, this.count = 8});

  final double cardWidth;
  final double cardHeight;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: contentLeft, bottom: 18),
        child: SkeletonBox(width: 240, height: 28, radius: 6),
      ),
      SizedBox(
        height: cardHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: contentLeft),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(width: Zs.cardGap),
          itemBuilder: (_, _) => SkeletonBox(width: cardWidth, height: cardHeight),
        ),
      ),
    ]);
  }
}
