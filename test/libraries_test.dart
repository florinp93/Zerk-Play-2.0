import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/core/emby/models/emby_item.dart';
import 'package:zerk_play/data/catalog_api.dart';
import 'package:zerk_play/data/libraries.dart';

void main() {
  const movies = LibraryView(id: 'm', name: 'Movies', collectionType: 'movies');
  const kids = LibraryView(id: 'k', name: 'Kids Movies', collectionType: 'movies');
  const shows = LibraryView(id: 's', name: 'Shows', collectionType: 'tvshows');
  const anime = LibraryView(id: 'a', name: 'Anime', collectionType: 'tvshows');
  const mixed = LibraryView(id: 'x', name: 'Mixed');
  const home = LibraryView(id: 'h', name: 'Home videos', collectionType: 'homevideos');
  const boxsets = LibraryView(id: 'b', name: 'Collections', collectionType: 'boxsets');
  const music = LibraryView(id: 'u', name: 'Music', collectionType: 'music');
  const tv = LibraryView(id: 't', name: 'Live TV', collectionType: 'livetv');
  const all = [movies, kids, shows, anime, mixed, home, boxsets, music, tv];

  List<String> ids(List<ServerLibrary> list) => [for (final l in list) l.id];

  group('Libraries', () {
    test('music, books and live TV are left out', () {
      expect(ids(Libraries.visible(all, const {})), ['m', 'k', 's', 'a', 'x', 'h', 'b']);
    });

    test('hidden libraries are left out', () {
      expect(ids(Libraries.visible(all, {'k', 'x'})), ['m', 's', 'a', 'h', 'b']);
    });

    test('pickers list only libraries of their kind that are shown', () {
      expect(ids(Libraries.ofKind(all, const {}, shows: false)), ['m', 'k']);
      expect(ids(Libraries.ofKind(all, {'a'}, shows: true)), ['s']);
    });

    test('a remembered pick is dropped once its library is gone or hidden', () {
      final choices = Libraries.ofKind(all, {'k'}, shows: false);
      expect(Libraries.pickOrNull('m', choices), 'm');
      expect(Libraries.pickOrNull('k', choices), isNull);
      expect(Libraries.pickOrNull('gone', choices), isNull);
      expect(Libraries.pickOrNull(null, choices), isNull);
    });

    test('other libraries are the browsable ones that are not movies or shows', () {
      expect([for (final l in all) if (Libraries.isOther(l)) l.id], ['x', 'h', 'b']);
      expect([for (final l in all) if (Libraries.hasLatest(l)) l.id], ['m', 'k', 's', 'a', 'x', 'h']);
    });
  });

  group('HiddenContent', () {
    EmbyItem item(String id, {String type = 'Movie', String? seriesId, String? seasonId}) =>
        EmbyItem(id: id, name: id, type: type, seriesId: seriesId, seasonId: seasonId);

    test('drops hidden titles and the episodes of hidden shows', () {
      const hidden = HiddenContent({'m1', 'show1'});
      final items = [
        item('m1'),
        item('m2'),
        item('show1', type: 'Series'),
        item('e1', type: 'Episode', seriesId: 'show1'),
        item('e2', type: 'Episode', seriesId: 'show2'),
      ];
      expect([for (final i in hidden.filter(items)) i.id], ['m2', 'e2']);
    });

    test('nothing hidden keeps the same list', () {
      final items = [item('a'), item('b')];
      expect(HiddenContent.none.filter(items), same(items));
    });
  });

  test('ItemPage counts what the server sent, not what was kept', () {
    final page = ItemPage([EmbyItem(id: 'a', name: 'a', type: 'Movie')], 10, scanned: 3);
    expect(page.fetched, 3);
    expect(const ItemPage([], 0).fetched, 0);
  });
}
