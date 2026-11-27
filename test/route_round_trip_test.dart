import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/ui/focus/focus_zone.dart';
import 'package:zerk_play/ui/focus/tv_focusable.dart';
import 'package:zerk_play/ui/widgets/media_row.dart';

class _Harness extends StatelessWidget {
  const _Harness({required this.ids, required this.focused});

  final ValueNotifier<List<String>> ids;
  final ValueNotifier<String?> focused;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ZoneNavigation(
        child: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: ids,
            builder: (context, list, _) => MediaRow(
              title: 'row',
              itemCount: list.length,
              height: 200,
              idOf: (i) => list[i],
              itemBuilder: (context, i) => TvFocusable(
                autofocus: i == 0,
                onFocusChange: (f) => f ? focused.value = list[i] : null,
                onSelect: () => Navigator.of(context).push(PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => Material(
                    child: TvFocusable(autofocus: true, builder: (_, _) => const SizedBox(width: 50, height: 50)),
                  ),
                )),
                builder: (_, _) => SizedBox(width: 150, height: 100, child: Text(list[i])),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<String> _names(int count) => [for (var i = 0; i < count; i++) 'item$i'];

Future<void> _walkRight(WidgetTester tester, int steps) async {
  for (var i = 0; i < steps; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
  }
}

double _offset(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

void main() {
  testWidgets('a row keeps its focus and scroll offset across a pushed page', (tester) async {
    final focused = ValueNotifier<String?>(null);
    await tester.pumpWidget(_Harness(ids: ValueNotifier(_names(40)), focused: focused));
    await tester.pumpAndSettle();
    await _walkRight(tester, 12);
    expect(focused.value, 'item12');
    final offset = _offset(tester);
    expect(offset, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(MediaRow), findsNothing);

    Navigator.of(tester.element(find.byType(Material).last)).pop();
    await tester.pumpAndSettle();
    focused.value = null;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focused.value, 'item11');
    expect(_offset(tester), closeTo(offset, 200));
  });

  testWidgets('focus follows an item that moves when the list reloads', (tester) async {
    final focused = ValueNotifier<String?>(null);
    final ids = ValueNotifier(_names(6));
    await tester.pumpWidget(_Harness(ids: ids, focused: focused));
    await tester.pumpAndSettle();
    await _walkRight(tester, 2);
    expect(focused.value, 'item2');

    ids.value = ['item2', 'item0', 'item1', 'item3', 'item4', 'item5'];
    await tester.pumpAndSettle();
    focused.value = null;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused.value, 'item0');
  });

  testWidgets('a card built under a covered page does not take focus from the page on top', (tester) async {
    final ids = ValueNotifier<List<String>>([]);
    await tester.pumpWidget(_Harness(ids: ids, focused: ValueNotifier(null)));
    await tester.pumpAndSettle();
    unawaited(Navigator.of(tester.element(find.byType(Scaffold))).push(PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => Material(
        child: TvFocusable(autofocus: true, builder: (_, _) => const SizedBox(width: 50, height: 50)),
      ),
    )));
    await tester.pumpAndSettle();
    final top = FocusManager.instance.primaryFocus;

    ids.value = _names(3);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(top));
  });
}
