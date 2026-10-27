import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../app/app_services.dart';
import '../../l10n/l10n.dart';
import '../../services/remote_setup/remote_setup_server.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import 'common.dart';

class RemoteSetupPanel extends StatefulWidget {
  const RemoteSetupPanel({super.key});

  @override
  State<RemoteSetupPanel> createState() => _RemoteSetupPanelState();
}

class _RemoteSetupPanelState extends State<RemoteSetupPanel> {
  late final RemoteSetupServer _server;
  bool _ready = false;
  bool _noNetwork = false;

  @override
  void initState() {
    super.initState();
    _server = RemoteSetupServer(AppServicesScope.read(context));
    _server.event.addListener(_onEvent);
    _server.start().then(
      (_) {
        if (mounted) setState(() => _ready = true);
      },
      onError: (Object e) {
        if (mounted) setState(() => _noNetwork = true);
      },
    );
  }

  @override
  void dispose() {
    _server.event.removeListener(_onEvent);
    unawaited(_server.stop());
    super.dispose();
  }

  void _onEvent() {
    if (!mounted) return;
    setState(() {});
    switch (_server.event.value) {
      case RemoteSetupEvent.applied:
        UiSounds.play(UiSound.select);
        showToast(context, context.l10n.phoneSetupReceived);
      case RemoteSetupEvent.failed:
        UiSounds.play(UiSound.error);
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _server.url;
    final base = _server.baseUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.phoneSetupTitle, style: Zt.title.copyWith(fontSize: 30)),
        const SizedBox(height: 10),
        Text(context.l10n.phoneSetupBody, style: Zt.body),
        const SizedBox(height: 28),
        if (_noNetwork)
          Text(context.l10n.phoneSetupNoNetwork, style: Zt.body.copyWith(color: Zc.danger))
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 280,
                height: 280,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Zs.radiusLarge)),
                child: _ready && url != null ? _QrView(data: url.toString()) : const Center(child: CircularProgressIndicator(color: Zc.accent)),
              ),
              const SizedBox(width: 36),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.setupAddress, style: Zt.caption),
                    const SizedBox(height: 4),
                    Text(base == null ? '…' : '${base.host}:${base.port}', style: Zt.label.copyWith(fontSize: 28)),
                    const SizedBox(height: 22),
                    Text(context.l10n.setupCode, style: Zt.caption),
                    const SizedBox(height: 4),
                    Text(_server.code, style: Zt.label.copyWith(fontSize: 40, letterSpacing: 6)),
                    const SizedBox(height: 22),
                    _Status(event: _server.event.value),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.event});

  final RemoteSetupEvent? event;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (text, color) = switch (event) {
      null => (l10n.phoneWaiting, Zc.textFaint),
      RemoteSetupEvent.phoneConnected => (l10n.phoneConnected, Zc.accentSoft),
      RemoteSetupEvent.applying => (l10n.phoneApplying, Zc.accentSoft),
      RemoteSetupEvent.applied => (l10n.phoneApplied, Zc.success),
      RemoteSetupEvent.failed => (l10n.phoneFailed, Zc.danger),
    };
    return AnimatedSwitcher(
      duration: Zm.fast,
      child: Text(
        text,
        key: ValueKey(text),
        style: Zt.body.copyWith(color: color),
      ),
    );
  }
}

class _QrView extends StatelessWidget {
  const _QrView({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    return CustomPaint(painter: _QrPainter(image), size: Size.infinite);
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.shortestSide / n;
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (image.isDark(r, c)) canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + 0.5, cell + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

Future<void> showRemoteSetupDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    backgroundColor: Zc.surfaceHigh,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Zs.radiusLarge)),
    child: SizedBox(
      width: 900,
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: FocusZone(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RemoteSetupPanel(),
              const SizedBox(height: 36),
              TvButton(label: context.l10n.done, icon: Icons.check_rounded, primary: true, autofocus: true, onSelect: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    ),
  ),
);
