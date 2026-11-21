import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../../playback/live_session.dart';
import '../../playback/platform_player.dart';
import '../../playback/playback_session.dart';
import '../../playback/player_settings.dart';
import '../../playback/trailer/trailer_player.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/trailer.dart';
import 'artwork.dart';

final class PlaybackOutcome {
  const PlaybackOutcome(this.reason, this.lastItem);

  final PlaybackEndReason reason;
  final EmbyItem? lastItem;
}

bool _playing = false;

bool get playbackActive => _playing;

final playbackActiveNotifier = ValueNotifier(false);

bool get liveActive => _live;
bool _live = false;

final class _Active {
  const _Active(this.stop, {this.itemId, this.resume});

  final Future<void> Function() stop;
  final String? Function()? itemId;
  final VoidCallback? resume;
}

_Active? _active;
Completer<void>? _ended;

void _setPlaying(bool v) {
  _playing = v;
  if (v) {
    _ended = Completer<void>();
  } else {
    _active = null;
    _ended?.complete();
    _ended = null;
  }
  playbackActiveNotifier.value = v;
}

String? get playingItemId => _active?.itemId?.call();

bool resumePlayback() {
  final resume = _active?.resume;
  if (resume == null) return false;
  resume();
  return true;
}

Future<bool> stopPlayback() async {
  if (!_playing) return true;
  final active = _active;
  final ended = _ended;
  if (active == null || ended == null) return false;
  await active.stop();
  await ended.future;
  return true;
}

Future<PlaybackOutcome?> playItem(
  BuildContext context,
  EmbyItem item, {
  Duration? start,
  String? mediaSourceId,
  int? audioIndex,
  int? subtitleIndex,
  List<EmbyItem> queue = const [],
}) async {
  if (_playing) return null;
  _setPlaying(true);
  try {
    final services = AppServicesScope.read(context);
    final l10n = context.l10n;
    final navigator = Navigator.of(context, rootNavigator: true);
    TrailerController.suspendAll();
    await TrailerPlayer.stopAll();
    final resent = await services.playback.flushPendingStops().timeout(const Duration(seconds: 3), onTimeout: () => {});
    final target = item.isSeries || item.isSeason ? await services.catalog.episodeToPlay(item) : item;
    if (target == null) return null;
    final stale = resent.contains(target.id) && start == null;
    final full = (target.mediaSources.isNotEmpty || target.isChannel) && !stale ? target : await services.catalog.item(target.id);
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
      cover: (item) => services.catalog.albumCover(item, width: 800),
      localize: services.catalog.localize,
      together: services.together,
      avatarOf: (member) => memberAvatar(services, member),
      fetchItem: services.catalog.item,
      settings: settings,
      l10n: l10n,
      acceptInvalidCertificates: acceptBadCerts,
      versionPreferences: services.settings.versionPreferences,
      onVersionChosen: (scope, key) {
        final prefs = Map<String, String>.from(services.settings.versionPreferences)..[scope] = key;
        services.updateSettings(services.settings.copyWith(versionPreferences: prefs));
      },
    );
    _active = _Active(session.stop, itemId: () => session.lastItem?.id ?? full.id, resume: session.resume);
    final reason = await session.run(PlaybackRequest(
      full,
      start: start,
      mediaSourceId: mediaSourceId,
      audioIndex: audioIndex,
      subtitleIndex: subtitleIndex,
      queue: queue,
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
  await playShared(context, LiveShare(key: LiveShare.keyOf(sources.first), title: c.name, sources: sources),
      zap: zap, channel: index);
}

Future<void> playShared(BuildContext context, LiveShare share, {ZapList? zap, int channel = 0}) async {
  if (_playing) return;
  _setPlaying(true);
  _live = true;
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
      title: share.title,
      sources: share.sources,
      settings: settings,
      l10n: l10n,
      together: services.together,
      share: share,
      zap: zap,
      channel: channel,
    );
    _active = _Active(session.stop);
    await session.run(share.first);
  } finally {
    _live = false;
    _setPlaying(false);
  }
}

