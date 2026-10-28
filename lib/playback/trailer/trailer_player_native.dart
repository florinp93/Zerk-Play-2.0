import 'package:flutter/widgets.dart';

import '../../core/host.dart';
import 'trailer_player.dart';
import 'trailer_player_android.dart';
import 'trailer_player_mpv.dart';

bool get trailersSupported => Host.isWindows || Host.isAndroid;

Future<TrailerPlayer?> createTrailerPlayer({required Size renderSize, required bool acceptInvalidCertificates}) async {
  try {
    if (Host.isAndroid) return await createAndroidTrailerPlayer(renderSize: renderSize);
    return await createMpvTrailerPlayer(renderSize: renderSize, acceptInvalidCertificates: acceptInvalidCertificates);
  } catch (e) {
    debugPrint('[trailer] player: $e');
    return null;
  }
}
