import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../player_settings.dart';
import 'media3_backend.dart';

Future<void> runMedia3Smoke(NavigatorState navigator, {bool subtitleBackground = false}) async {
  if (kReleaseMode) return;
  final backend = Media3Backend(navigator: navigator, settings: PlayerSettings(subtitleBackground: subtitleBackground));
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
