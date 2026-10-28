import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/recommendations.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/media_row.dart';
import '../widgets/rows_scroll_view.dart';
import '../widgets/mixed_cards.dart';
import '../widgets/trailer.dart';
import 'hero.dart';

final class MixedRowSpec {
  const MixedRowSpec(this.title, this.items, {this.style = CardStyle.poster});

  final String Function(L10n) title;
  final Future<MixedItems> items;
  final CardStyle style;
}

class MixedRowsView extends StatefulWidget {
  const MixedRowsView({super.key, required this.rows, this.left = contentLeft, this.header});

  final List<MixedRowSpec> rows;

  final double left;

  final Widget? header;

  @override
  State<MixedRowsView> createState() => _MixedRowsViewState();
}

class _MixedRowsViewState extends State<MixedRowsView> {
  final _hero = Debounced<HeroInfo?>(null);
  final _scroll = RevealController(mode: RevealMode.anchored, anchor: 64);

  late final Future<int> _firstNonEmpty = Future.wait(
          widget.rows.map((r) => r.items.then((v) => v.isNotEmpty, onError: (Object _) => false)))
      .then((nonEmpty) => nonEmpty.indexOf(true));

  @override
  void dispose() {
    _hero.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _focus(Object data) {
    final l10n = context.l10n;
    _hero.set(data is EmbyItem
        ? HeroInfo.fromItem(l10n, AppServicesScope.read(context), data)
        : HeroInfo.fromRequest(l10n, data as SeerrMedia));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final heroHeight = height * 0.42;
    return Stack(children: [
      Positioned.fill(
        child: ValueListenableBuilder(valueListenable: _hero, builder: (_, info, _) => Backdrop(url: info?.backdrop)),
      ),
      if (widget.header != null) Positioned(left: widget.left, top: 56, child: widget.header!),
      Positioned(
        left: widget.left,
        right: 600,
        top: 0,
        height: heroHeight,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: ValueListenableBuilder(valueListenable: _hero, builder: (_, info, _) => HeroPanel(info: info)),
          ),
        ),
      ),
      Positioned.fill(
        top: heroHeight,
        child: CardTrailers(
          child: FutureBuilder<int>(
            future: _firstNonEmpty,
            builder: (context, first) => RowsScrollView(
              key: ValueKey(first.data),
              controller: _scroll,
              children: [
                for (final (i, row) in widget.rows.indexed) _row(row, autofocus: first.data == i),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _row(MixedRowSpec row, {required bool autofocus}) {
    return FutureBuilder<MixedItems>(
      future: row.items,
      builder: (context, snap) {
        if (snap.hasError) debugPrint('[rows] ${row.title(context.l10n)}: ${snap.error}');
        final items = snap.data;
        if (items == null && !snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Zs.rowGap),
            child: SkeletonRow(cardWidth: cardWidth(row.style), cardHeight: cardAreaHeight(row.style) - 100),
          );
        }
        if (items == null || items.isEmpty) return const SizedBox.shrink();
        if (autofocus && _hero.value == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _hero.value == null) _focus(items.first);
          });
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: Zs.rowGap),
          child: MediaRow(
            left: widget.left,
            title: row.title(context.l10n),
            height: cardAreaHeight(row.style),
            gap: row.style == CardStyle.ranked ? 8 : Zs.cardGap,
            itemCount: items.length,
            itemBuilder: (context, j) => Padding(
              padding: const EdgeInsets.only(top: 14),
              child: mixedCard(context, items[j],
                  style: row.style, rank: j + 1, autofocus: autofocus && j == 0, onFocus: () => _focus(items[j])),
            ),
          ),
        );
      },
    );
  }
}
