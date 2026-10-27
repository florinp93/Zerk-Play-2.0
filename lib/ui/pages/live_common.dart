import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/xtream/live_catalog.dart';
import '../../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/net_image.dart';

class LiveCatalogView extends StatefulWidget {
  const LiveCatalogView({super.key, required this.builder, required this.loader});

  final Widget Function(BuildContext context, LiveCatalog catalog, DateTime now) builder;

  final Widget loader;

  @override
  State<LiveCatalogView> createState() => _LiveCatalogViewState();
}

class _LiveCatalogViewState extends State<LiveCatalogView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder(
      valueListenable: LiveTv.latest,
      builder: (context, catalog, _) {
        if (catalog != null) return widget.builder(context, catalog, DateTime.now());
        return ValueListenableBuilder(
          valueListenable: LiveTv.error,
          builder: (context, error, _) => error == null
              ? widget.loader
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Zs.pageInset),
                    child: Text(l10n.liveLoadFailed(error), style: Zt.body, textAlign: TextAlign.center),
                  ),
                ),
        );
      },
    );
  }
}

class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.name, this.logo, this.width = 96, this.height = 64});

  final String name;
  final String? logo;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = logo == null ? null : Uri.tryParse(logo!);
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Zc.surfaceTop, borderRadius: BorderRadius.circular(10)),
      child: NetImage(
        url: url,
        width: width,
        fit: BoxFit.contain,
        fallback: Center(child: Text(_initials(name), style: Zt.label.copyWith(color: Zc.textMuted))),
      ),
    );
  }
}

class Crest extends StatelessWidget {
  const Crest({super.key, required this.name, this.url, this.size = 72});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Zc.surfaceTop, shape: BoxShape.circle),
      child: Text(_initials(name), style: Zt.label.copyWith(fontSize: size * 0.3, color: Zc.textMuted)),
    );
    final u = url == null ? null : Uri.tryParse(url!);
    if (u == null) return fallback;
    return SizedBox(width: size, height: size, child: NetImage(url: u, width: size, fit: BoxFit.contain, fallback: fallback));
  }
}

String _initials(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w[0]));
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}
