import 'package:flutter/widgets.dart';

import '../player_settings.dart';
import '../player_smoke.dart';
import 'media3_backend.dart';

Future<void> runMedia3Smoke(NavigatorState navigator, {bool subtitleBackground = false}) => runPlayerSmoke(
    Media3Backend(navigator: navigator, settings: PlayerSettings(subtitleBackground: subtitleBackground)));
