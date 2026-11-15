import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/core/emby/models/emby_item.dart';
import 'package:zerk_play/data/catalog_api.dart';

EmbyItem episode(String id, {bool played = false, int ticks = 0, String? lastPlayed}) => EmbyItem.fromJson({
      'Id': id,
      'Name': id,
      'Type': 'Episode',
      'SeriesId': 's',
      'RunTimeTicks': 27000000000,
      'UserData': {
        'Played': played,
        'PlaybackPositionTicks': ticks,
        'LastPlayedDate': ?lastPlayed,
      },
    });

void main() {
  final nextUp = episode('e5');

  test('a rewatched episode stopped part way wins when it was played last', () {
    final e2 = episode('e2', played: true, ticks: 9000000000, lastPlayed: '2026-11-14T20:00:00Z');
    expect(CatalogApi.pickNextEpisode(nextUp, [e2])?.id, 'e2');
  });

  test('an old abandoned episode loses to later watching', () {
    final e2 = episode('e2', ticks: 9000000000, lastPlayed: '2026-10-01T20:00:00Z');
    final e4 = episode('e4', played: true, lastPlayed: '2026-11-14T20:00:00Z');
    expect(CatalogApi.pickNextEpisode(nextUp, [e2, e4])?.id, 'e5');
    expect(CatalogApi.pickNextEpisode(nextUp, [e4])?.id, 'e5');
  });

  test('nothing in progress keeps next up', () {
    expect(CatalogApi.pickNextEpisode(nextUp, const [])?.id, 'e5');
    expect(CatalogApi.pickNextEpisode(nextUp, [episode('e4', played: true, lastPlayed: '2026-11-14T20:00:00Z')])?.id, 'e5');
    expect(CatalogApi.pickNextEpisode(nextUp, [episode('e1')])?.id, 'e5');
  });

  test('no next up but an episode in progress resumes it', () {
    final e9 = episode('e9', played: true, ticks: 9000000000, lastPlayed: '2026-11-14T20:00:00Z');
    expect(CatalogApi.pickNextEpisode(null, [e9])?.id, 'e9');
    expect(CatalogApi.pickNextEpisode(null, const []), isNull);
  });
}
