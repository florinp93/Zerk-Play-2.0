import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/app/home_rows.dart';

List<String> ids(List<HomeRowDef> rows) => [for (final r in rows) r.id];

void main() {
  const a = HomeRowDef('a');
  const b = HomeRowDef('b');
  const c = HomeRowDef('c');
  const d = HomeRowDef('d');
  const off = HomeRowDef('off', defaultOn: false);

  group('HomeRowLayout', () {
    test('an empty layout keeps the default order and visibility', () {
      const layout = HomeRowLayout();
      expect(ids(layout.arrange([a, b, off, c])), ['a', 'b', 'off', 'c']);
      expect(ids(layout.visible([a, b, off, c])), ['a', 'b', 'c']);
      expect(layout.isDefault, isTrue);
    });

    test('a saved order wins over the default order', () {
      const layout = HomeRowLayout(order: ['c', 'a', 'b']);
      expect(ids(layout.arrange([a, b, c])), ['c', 'a', 'b']);
    });

    test('an unknown new row lands at its default position, enabled', () {
      const layout = HomeRowLayout(order: ['c', 'a', 'b'], toggles: {'a': false});
      expect(ids(layout.arrange([a, d, b, c])), ['c', 'a', 'd', 'b']);
      expect(ids(layout.visible([a, d, b, c])), ['c', 'd', 'b']);
    });

    test('a new first row goes to the top', () {
      const layout = HomeRowLayout(order: ['b', 'a']);
      expect(ids(layout.arrange([d, a, b])), ['d', 'b', 'a']);
    });

    test('rows that left the defaults are skipped but keep their saved place', () {
      const layout = HomeRowLayout(order: ['c', 'gone', 'a']);
      expect(ids(layout.arrange([a, c])), ['c', 'a']);
      final moved = layout.moved([a, c], 'a', -1);
      expect(moved.order, ['a', 'c', 'gone']);
      expect(ids(moved.arrange([a, c, const HomeRowDef('gone')])), ['a', 'c', 'gone']);
    });

    test('toggles override the default visibility', () {
      final layout = const HomeRowLayout().toggled('a', false).toggled('off', true);
      expect(ids(layout.visible([a, off, b])), ['off', 'b']);
      expect(layout.enabled(a), isFalse);
      expect(layout.enabled(b), isTrue);
    });

    test('moving clamps at the ends', () {
      const layout = HomeRowLayout();
      expect(layout.moved([a, b, c], 'a', -1), same(layout));
      expect(ids(layout.moved([a, b, c], 'a', 1).arrange([a, b, c])), ['b', 'a', 'c']);
      expect(ids(layout.moved([a, b, c], 'c', -2).arrange([a, b, c])), ['c', 'a', 'b']);
      expect(layout.moved([a, b, c], 'c', 1), same(layout));
    });

    test('duplicate ids in a saved order are ignored', () {
      const layout = HomeRowLayout(order: ['b', 'b', 'a']);
      expect(ids(layout.arrange([a, b])), ['b', 'a']);
    });

    test('survives a JSON round trip', () {
      final layout = const HomeRowLayout(order: ['b', 'a']).toggled('a', false);
      final back = HomeRowLayout.fromJson(layout.toJson());
      expect(back, layout);
      expect(HomeRowLayout.fromJson(null).isDefault, isTrue);
      expect(HomeRowLayout.fromJson({'order': [1, 'x'], 'on': {'y': 'no', 'z': true}}),
          const HomeRowLayout(order: ['x'], toggles: {'z': true}));
    });
  });

  group('HomeRows', () {
    test('defaults include optional rows only when available', () {
      final plain = ids(HomeRows.defaults());
      expect(plain.first, HomeRows.continueWatching);
      expect(plain, isNot(contains(HomeRows.trending)));
      expect(plain, isNot(contains(HomeRows.moods)));
      expect(plain.where((id) => id.startsWith('${HomeRows.tag}.')), isEmpty);
      final full = ids(HomeRows.defaults(seerr: true, moods: true, tags: true));
      expect(full, containsAll([HomeRows.trending, HomeRows.popularToRequest, HomeRows.moods, '${HomeRows.tag}.4']));
      expect(full.toSet().length, full.length);
    });

    test('per-library latest rows are off by default and follow Latest shows', () {
      final rows = HomeRows.defaults(libraries: ['x', 'y']);
      final at = rows.indexWhere((r) => r.id == HomeRows.latestShows);
      expect(ids(rows.sublist(at + 1, at + 3)), [HomeRows.latestIn('x'), HomeRows.latestIn('y')]);
      expect(rows[at + 1].defaultOn, isFalse);
      expect(HomeRows.libraryOf(HomeRows.latestIn('x')), 'x');
      expect(HomeRows.libraryOf(HomeRows.latestMovies), isNull);
    });

    test('Next up is off by default', () {
      final rows = HomeRows.defaults();
      expect(rows.firstWhere((r) => r.id == HomeRows.nextUp).defaultOn, isFalse);
    });

    test('generated ids carry their kind and index', () {
      expect(HomeRows.generated('${HomeRows.starring}.2'), (kind: HomeRows.starring, index: 1));
      expect(HomeRows.generated(HomeRows.latestMovies), isNull);
      expect(HomeRows.generated('x.0'), isNull);
    });
  });
}
