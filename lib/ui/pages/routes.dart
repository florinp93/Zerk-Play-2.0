import 'package:flutter/material.dart';

import '../../core/emby/models/emby_item.dart';
import '../../data/seerr_api.dart';
import '../core/navigation.dart';
import 'collection_page.dart';
import 'details_page.dart';
import 'person_page.dart';
import 'request_page.dart';
import 'series_page.dart';

Route<void> detailsRoute(EmbyItem item) =>
    tvRoute(DetailsPage(itemId: item.id, initial: item), name: 'details:${item.id}');

Route<void> itemRoute(EmbyItem item) {
  if (item.isSeries) return tvRoute(SeriesPage(seriesId: item.id), name: 'series:${item.id}');
  if (item.isSeason && item.seriesId != null) {
    return tvRoute(SeriesPage(seriesId: item.seriesId!, initialSeasonId: item.id), name: 'series:${item.seriesId}');
  }
  if (item.isCollection) {
    final key = item.id.isEmpty ? 'tmdb${item.tmdbId}' : item.id;
    return tvRoute(CollectionPage(collection: item), name: 'collection:$key');
  }
  return detailsRoute(item);
}

void openItem(BuildContext context, EmbyItem item) => Navigator.of(context).push(itemRoute(item));

void openSeries(BuildContext context, String seriesId, {String? focusEpisodeId}) {
  Navigator.of(context).push(
    tvRoute(SeriesPage(seriesId: seriesId, focusEpisodeId: focusEpisodeId), name: 'series:$seriesId'),
  );
}

void openRequest(BuildContext context, SeerrMedia media) {
  Navigator.of(context).push(tvRoute(RequestPage(media: media), name: 'request:${media.key}'));
}

void openPerson(BuildContext context, Person person) {
  Navigator.of(context).push(tvRoute(PersonPage(person: person), name: 'person:${person.id}'));
}
