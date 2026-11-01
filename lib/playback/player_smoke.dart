import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'player_backend.dart';
import 'trailer/trailer_player_native.dart';
import 'trailer/trailers.dart';

Future<void> runPlayerSmoke(PlayerBackend backend) async {
  if (kReleaseMode) return;
  backend.events.listen((e) => debugPrint('[smoke] event $e'));
  await backend.open();
  backend.osd('state', {'phase': 'loading', 'title': 'Smoke test', 'subtitle': 'Big Buck Bunny'});
  backend.load(Uri.parse('https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4'));
  await Future<void>.delayed(const Duration(seconds: 2));
  backend.osd('state', {'phase': 'playing', 'title': 'Smoke test', 'subtitle': 'Big Buck Bunny'});
  const srt = '1\n00:00:00,000 --> 00:10:00,000\nNu știu ce s-a întâmplat aseară,\ndar trebuie să aflăm.\n';
  backend.addSubtitle(
    Uri.dataFromString(srt, mimeType: 'application/x-subrip', encoding: utf8, base64: true),
    format: 'srt',
    title: 'Română',
    language: 'ro',
  );
}

Future<void> runTrailerSmoke(NavigatorState navigator) async {
  if (kReleaseMode) return;
  final player = await createTrailerPlayer(renderSize: const Size(1280, 720), acceptInvalidCertificates: false);
  if (player == null) {
    debugPrint('[smoke] no trailer player');
    return;
  }
  unawaited(navigator.push(PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => ColoredBox(
      color: const Color(0xFF000000),
      child: Center(
        child: ValueListenableBuilder(
          valueListenable: player.state,
          builder: (_, s, _) => s.textureId == null
              ? const SizedBox()
              : SizedBox(width: 960, height: 540, child: Texture(textureId: s.textureId!)),
        ),
      ),
    ),
  )));
  final ok = await player.open(
    TrailerStream(Uri.parse('https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4')),
    muted: true,
  );
  debugPrint('[smoke] trailer opened: $ok');
}
