import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../core/host.dart';
import 'media3/media3_backend.dart';
import 'mpv/mpv_backend.dart';
import 'player_backend.dart';
import 'player_settings.dart';

PlayerBackend createPlayer({
  required NavigatorState navigator,
  required PlayerSettings settings,
  required bool acceptInvalidCertificates,
  required L10n l10n,
}) =>
    Host.isAndroid
        ? Media3Backend(navigator: navigator, settings: settings)
        : MpvBackend(navigator: navigator, settings: settings, l10n: l10n, acceptInvalidCertificates: acceptInvalidCertificates);
