import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/core/emby/models/emby_item.dart';
import 'package:zerk_play/ui/widgets/item_menu.dart';

EmbyItem item({String type = 'Movie', Map<String, dynamic> userData = const {}, String? location}) => EmbyItem.fromJson({
      'Id': '1',
      'Name': 'Film',
      'Type': type,
      'LocationType': location,
      'UserData': userData,
    });

void main() {
  test('a fresh item offers play, watched, favorite and details', () {
    expect(itemActions(item()), [
      ItemAction.play,
      ItemAction.markWatched,
      ItemAction.favorite,
      ItemAction.details,
    ]);
  });

  test('a saved position offers resume instead of play', () {
    final i = item(userData: {'PlaybackPositionTicks': 36000000000});
    expect(itemActions(i).first, ItemAction.resume);
  });

  test('watched and favorite items offer the opposite action', () {
    final i = item(userData: {'Played': true, 'IsFavorite': true});
    expect(itemActions(i), [
      ItemAction.play,
      ItemAction.markUnwatched,
      ItemAction.unfavorite,
      ItemAction.details,
    ]);
  });

  test('only the Continue watching row offers to remove the item', () {
    expect(itemActions(item()), isNot(contains(ItemAction.hideFromResume)));
    expect(itemActions(item(), continueWatching: true).last, ItemAction.hideFromResume);
  });

  test('movies, series and episodes have a menu, missing episodes and collections do not', () {
    expect(hasItemMenu(item()), isTrue);
    expect(hasItemMenu(item(type: 'Series')), isTrue);
    expect(hasItemMenu(item(type: 'Episode')), isTrue);
    expect(hasItemMenu(item(type: 'Episode', location: 'Virtual')), isFalse);
    expect(hasItemMenu(item(type: 'BoxSet')), isFalse);
  });
}
