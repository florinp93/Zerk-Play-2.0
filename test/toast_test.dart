import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/ui/widgets/common.dart';

void main() {
  testWidgets('a toast shows when given the navigator overlay context', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const SizedBox()));
    showToast(navigator.currentState!.overlay!.context, 'Performance test finished', duration: const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Performance test finished'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Performance test finished'), findsNothing);
  });
}
