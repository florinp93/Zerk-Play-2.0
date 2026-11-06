import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../theme/tokens.dart';

class WallClock extends StatefulWidget {
  const WallClock({super.key, this.shadow = false, this.size = 34});

  final bool shadow;
  final double size;

  @override
  State<WallClock> createState() => _WallClockState();
}

class _WallClockState extends State<WallClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() {});
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        DateFormat.Hm(context.l10n.localeName).format(DateTime.now()),
        style: Zt.title.copyWith(
          fontSize: widget.size,
          shadows: widget.shadow ? const [Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 2))] : null,
        ),
      );
}
