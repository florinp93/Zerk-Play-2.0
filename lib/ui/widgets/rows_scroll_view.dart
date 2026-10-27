import 'package:flutter/widgets.dart';

import '../core/input_mode.dart';
import '../focus/focus_zone.dart';

class RowsScrollView extends StatelessWidget {
  const RowsScrollView({super.key, required this.controller, required this.children, this.top = 20});

  final RevealController controller;
  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return ValueListenableBuilder(
      valueListenable: InputMode.pointer,
      builder: (context, pointer, _) => SingleChildScrollView(
        controller: controller,
        child: Padding(
          padding: EdgeInsets.only(top: top, bottom: pointer ? 60 : height * 0.5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}
