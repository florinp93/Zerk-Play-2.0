import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/playback_launcher.dart';
import '../core/ui_sounds.dart';
import '../pages/routes.dart';
import 'side_panel.dart';

enum ItemAction { play, resume, markWatched, markUnwatched, favorite, unfavorite, details, hideFromResume }

bool hasItemMenu(EmbyItem item) => (item.isMovie || item.isSeries || item.isEpisode) && !item.isVirtual;

List<ItemAction> itemActions(EmbyItem item, {bool continueWatching = false}) => [
      if (item.resumePosition != null) ItemAction.resume else ItemAction.play,
      if (item.isPlayed) ItemAction.markUnwatched else ItemAction.markWatched,
      if (item.isFavorite) ItemAction.unfavorite else ItemAction.favorite,
      ItemAction.details,
      if (continueWatching) ItemAction.hideFromResume,
    ];

VoidCallback? itemMenuCallback(BuildContext context, EmbyItem item, {bool continueWatching = false}) =>
    hasItemMenu(item) ? () => showItemMenu(context, item, continueWatching: continueWatching) : null;

Future<void> showItemMenu(BuildContext context, EmbyItem item, {bool continueWatching = false}) async {
  final l10n = context.l10n;
  final services = AppServicesScope.read(context);
  final action = await showSidePanel<ItemAction>(
    context,
    title: item.isEpisode ? item.seriesName ?? item.name : item.name,
    header: item.isEpisode ? [item.episodeCode, item.name].whereType<String>().join('  ') : null,
    options: [
      for (final a in itemActions(item, continueWatching: continueWatching))
        PanelOption(
          value: a,
          title: switch (a) {
            ItemAction.play => l10n.play,
            ItemAction.resume => l10n.menuResume,
            ItemAction.markWatched => l10n.markWatched,
            ItemAction.markUnwatched => l10n.markUnwatched,
            ItemAction.favorite => l10n.addToFavorites,
            ItemAction.unfavorite => l10n.removeFromFavorites,
            ItemAction.details => l10n.menuDetails,
            ItemAction.hideFromResume => l10n.removeFromContinueWatching,
          },
          icon: switch (a) {
            ItemAction.play || ItemAction.resume => Icons.play_arrow_rounded,
            ItemAction.markWatched => Icons.check_circle_outline_rounded,
            ItemAction.markUnwatched => Icons.check_circle_rounded,
            ItemAction.favorite => Icons.favorite_border_rounded,
            ItemAction.unfavorite => Icons.favorite_rounded,
            ItemAction.details => Icons.info_outline_rounded,
            ItemAction.hideFromResume => Icons.visibility_off_outlined,
          },
        ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case ItemAction.play || ItemAction.resume:
      await playItem(context, item);
    case ItemAction.details:
      openItem(context, item);
    case ItemAction.markWatched || ItemAction.markUnwatched:
      await _change(services, () => services.catalog.setPlayed(item.id, action == ItemAction.markWatched));
    case ItemAction.favorite || ItemAction.unfavorite:
      await _change(services, () => services.catalog.setFavorite(item.id, action == ItemAction.favorite));
    case ItemAction.hideFromResume:
      await _change(services, () => services.catalog.hideFromResume(item.id));
  }
}

Future<void> _change(AppServices services, Future<void> Function() change) async {
  try {
    await change();
    services.markLibraryChanged();
  } catch (_) {
    UiSounds.play(UiSound.error);
  }
}

Future<void> showRequestMenu(BuildContext context, SeerrMedia media) async {
  final request = await showSidePanel<bool>(
    context,
    title: media.title,
    options: [PanelOption(value: true, title: context.l10n.request, icon: Icons.add_circle_outline_rounded)],
  );
  if (request == true && context.mounted) openRequest(context, media);
}
