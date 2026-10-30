import 'package:flutter/widgets.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../../playback/live_session.dart';
import '../../playback/platform_player.dart';
import '../../playback/playback_session.dart';
import '../../playback/player_settings.dart';
import '../../playback/trailer/trailer_player.dart';
import '../widgets/trailer.dart';
import 'artwork.dart';

final class PlaybackOutcome {
  const PlaybackOutcome(this.reason, this.lastItem);

  final PlaybackEndReason reason;
  final EmbyItem? lastItem;
}

bool _playing = false;

bool get playbackActive => _playing;

void _setPlaying(bool v) => _playing = v;

Future<PlaybackOutcome?> playItem(
  BuildContext context,
  EmbyItem item, {
  Duration? start,
  String? mediaSourceId,
  int? audioIndex,
  int? subtitleIndex,
}) async {
  if (_playing) return null;
  _setPlaying(true);
  try {
    final services = AppServicesScope.read(context);
    final l10n = context.l10n;
    final navigator = Navigator.of(context, rootNavigator: true);
    TrailerController.suspendAll();
    await TrailerPlayer.stopAll();
    final target = item.isSeries || item.isSeason ? await services.catalog.episodeToPlay(item) : item;
    if (target == null) return null;
    final full = target.mediaSources.isNotEmpty || target.isChannel ? target : await services.catalog.item(target.id);
    final settings = await PlayerSettings.load();
    final acceptBadCerts = services.settings.acceptInvalidCertificates;
    final session = PlaybackSession(
      player: createPlayer(
        navigator: navigator,
        settings: settings,
        acceptInvalidCertificates: acceptBadCerts,
        l10n: l10n,
      ),
      api: services.playback,
      artwork: (item) => (
        backdrop: services.catalog.backdrop(item),
        logo: services.catalog.logo(item),
        still: services.catalog.landscape(item, width: 640),
      ),
      localize: services.catalog.localize,
      settings: settings,
      l10n: l10n,
      acceptInvalidCertificates: acceptBadCerts,
      versionPreferences: services.settings.versionPreferences,
      onVersionChosen: (scope, key) {
        final prefs = Map<String, String>.from(services.settings.versionPreferences)..[scope] = key;
        services.updateSettings(services.settings.copyWith(versionPreferences: prefs));
      },
    );
    final reason = await session.run(PlaybackRequest(
      full,
      start: start,
      mediaSourceId: mediaSourceId,
      audioIndex: audioIndex,
      subtitleIndex: subtitleIndex,
    ));
    services.markLibraryChanged();
    return PlaybackOutcome(reason, session.lastItem ?? full);
  } finally {
    _setPlaying(false);
  }
}

Future<void> playChannel(BuildContext context, ZapList zap, int index) async {
  final c = zap.channels[index];
  final sources = ZapList.sourcesOf(c);
  if (sources.isEmpty) return;
  if (_playing) return;
  _setPlaying(true);
  try {
    final services = AppServicesScope.read(context);
    final l10n = context.l10n;
    final navigator = Navigator.of(context, rootNavigator: true);
    TrailerController.suspendAll();
    await TrailerPlayer.stopAll();
    final settings = await PlayerSettings.load();
    final session = LiveSession(
      player: createPlayer(
        navigator: navigator,
        settings: settings,
        acceptInvalidCertificates: services.settings.acceptInvalidCertificates,
        l10n: l10n,
      ),
      server: services.xtream,
      title: c.name,
      sources: sources,
      settings: settings,
      l10n: l10n,
      zap: zap,
      channel: index,
    );
    await session.run(0);
  } finally {
    _setPlaying(false);
  }
}

