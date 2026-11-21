import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zerk_play/playback/pending_stops.dart';

PendingStop stop(String item, int minutes, DateTime at, {String owner = 'srv|u1'}) => PendingStop(
      owner: owner,
      body: {'ItemId': item, 'PositionTicks': minutes * 60 * 10000000},
      at: at,
    );

void main() {
  final now = DateTime.utc(2026, 11, 22, 20);

  test('a newer position for the same item replaces the older one', () {
    final list = PendingStops.merge([stop('a', 10, now)], stop('a', 45, now.add(const Duration(seconds: 10))), now: now);
    expect(list, hasLength(1));
    expect(list.single.body['PositionTicks'], 45 * 60 * 10000000);
  });

  test('other items and other accounts are kept', () {
    final list = PendingStops.merge([stop('a', 10, now), stop('a', 5, now, owner: 'srv|u2')], stop('b', 3, now), now: now);
    expect(list.map((s) => '${s.owner}/${s.itemId}'), ['srv|u1/a', 'srv|u2/a', 'srv|u1/b']);
  });

  test('entries older than a week are dropped', () {
    final old = stop('a', 10, now.subtract(const Duration(days: 8)));
    expect(PendingStops.merge([old], stop('b', 1, now), now: now).map((s) => s.itemId), ['b']);
  });

  test('a confirmed stop does not clear a newer position', () {
    final newer = stop('a', 50, now.add(const Duration(minutes: 1)));
    expect(PendingStops.without([newer], stop('a', 45, now)), [newer]);
    expect(PendingStops.without([stop('a', 45, now)], stop('a', 45, now)), isEmpty);
  });

  test('put and remove round trip through storage', () async {
    SharedPreferences.setMockInitialValues({});
    final s = stop('a', 45, DateTime.now());
    await Future.wait([PendingStops.put(s), PendingStops.remove(s)]);
    expect(await PendingStops.load(), isEmpty);
    await PendingStops.put(s);
    final loaded = await PendingStops.load();
    expect(loaded.single.itemId, 'a');
    expect(loaded.single.body['PositionTicks'], 45 * 60 * 10000000);
  });
}
