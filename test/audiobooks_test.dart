import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/core/emby/models/emby_item.dart';
import 'package:zerk_play/data/audiobooks.dart';

void main() {
  EmbyItem track(String name, {int? disc, int? number, bool played = false, int? position, int? runtime}) => EmbyItem(
        id: name,
        name: name,
        type: 'Audio',
        parentIndexNumber: disc,
        indexNumber: number,
        isPlayed: played,
        playbackPositionTicks: position,
        runTimeTicks: runtime,
      );

  List<String> names(List<EmbyItem> items) => [for (final i in items) i.name];

  group('Audiobooks.chapters', () {
    test('orders by disc, then number', () {
      final sorted = Audiobooks.chapters([
        track('c', disc: 2, number: 1),
        track('b', disc: 1, number: 2),
        track('a', disc: 1, number: 1),
      ]);
      expect(names(sorted), ['a', 'b', 'c']);
    });

    test('falls back to natural name order', () {
      final sorted = Audiobooks.chapters([
        track('Chapter 10'),
        track('Chapter 2'),
        track('chapter 1'),
      ]);
      expect(names(sorted), ['chapter 1', 'Chapter 2', 'Chapter 10']);
    });

    test('numbered chapters come before unnumbered ones', () {
      final sorted = Audiobooks.chapters([track('Epilogue'), track('Intro', number: 1)]);
      expect(names(sorted), ['Intro', 'Epilogue']);
    });
  });

  group('Audiobooks.resumePoint', () {
    const minute = 600000000;

    test('a book that was never started has no resume point', () {
      expect(Audiobooks.resumePoint([track('a'), track('b')]), isNull);
    });

    test('resumes at the saved position of the first unfinished chapter', () {
      final point = Audiobooks.resumePoint([
        track('a', played: true),
        track('b', position: 5 * minute, runtime: 20 * minute),
        track('c'),
      ]);
      expect(point?.index, 1);
      expect(point?.start, const Duration(minutes: 5));
    });

    test('moves on to the next chapter once one is played', () {
      final point = Audiobooks.resumePoint([track('a', played: true), track('b'), track('c')]);
      expect(point?.index, 1);
      expect(point?.start, Duration.zero);
    });

    test('a chapter that was almost finished counts as finished', () {
      final point = Audiobooks.resumePoint([track('a', position: 99 * minute, runtime: 100 * minute), track('b')]);
      expect(point?.index, 1);
    });

    test('a finished book starts over', () {
      expect(Audiobooks.resumePoint([track('a', played: true), track('b', played: true)]), isNull);
    });
  });
}
