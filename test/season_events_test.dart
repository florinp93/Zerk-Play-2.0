import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/app/home_rows.dart';
import 'package:zerk_play/data/season_events.dart';
import 'package:zerk_play/data/seerr_api.dart';

const doomsday = {
  'id': 'samw3gk46m',
  'name': 'Avengers: Doomsday',
  'start': '2026-11-22',
  'end': '2027-01-08',
  'look': {'accent': '#7b5cff', 'effect': 'none', 'badge': 'star'},
  'spotlight': {
    'title': 'Avengers: Doomsday',
    'text': 'In cinemas soon.',
    'tmdb': {'type': 'movie', 'id': 1003596, 'title': 'Avengers: Doomsday'},
    'countdown': '2026-12-18',
    'image': 'http://insecure.example/a.jpg',
  },
  'rows': [
    {
      'title': 'Catch up before Doomsday',
      'source': 'keyword',
      'media': 'both',
      'ids': [180547],
      'sort': 'release',
      'unwatchedFirst': true,
      'missing': true,
    },
    {'title': 'Broken'},
  ],
};

void main() {
  test('reads an event as the hub sends it', () {
    final e = SeasonEvent.list([doomsday, 'junk', {'id': 'x'}]).single;
    expect(e.accent, 0xff7b5cff);
    expect(e.badge, 'star');
    expect(e.spotlight!.tmdb, (type: SeerrMediaType.movie, id: 1003596));
    expect(e.spotlight!.image, isNull);
    expect(e.rows.single.ids, [180547]);
    expect(e.rows.single.types, [SeerrMediaType.movie, SeerrMediaType.tv]);
    expect(e.rows.single.unwatchedFirst, isTrue);
  });

  test('is active from the first to the last day, whatever the time', () {
    final e = SeasonEvent.fromJson(doomsday)!;
    expect(e.activeOn(DateTime(2026, 11, 21, 23, 59)), isFalse);
    expect(e.activeOn(DateTime(2026, 11, 22)), isTrue);
    expect(e.activeOn(DateTime(2027, 1, 8, 23, 30)), isTrue);
    expect(e.activeOn(DateTime(2027, 1, 9)), isFalse);
  });

  test('counts down whole days to the date', () {
    final s = SeasonEvent.fromJson(doomsday)!.spotlight!;
    expect(s.daysLeft(DateTime(2026, 11, 22, 20)), 26);
    expect(s.daysLeft(DateTime(2026, 12, 17, 23)), 1);
    expect(s.daysLeft(DateTime(2026, 12, 18, 8)), 0);
    expect(s.daysLeft(DateTime(2026, 12, 20)), -2);
  });

  test('home row ids round-trip', () {
    expect(HomeRows.eventOf(HomeRows.event('abc')), 'abc');
    expect(HomeRows.eventOf('event:abc:spot'), isNull);
    expect(HomeRows.eventOf('event:'), isNull);
    expect(HomeRows.eventOf('latest:abc'), isNull);
    expect(HomeRows.generated(HomeRows.event('abc')), isNull);
  });
}
