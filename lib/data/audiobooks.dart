import '../core/emby/models/emby_item.dart';

typedef ResumePoint = ({int index, Duration start});

abstract final class Audiobooks {
  static const types = ['MusicAlbum', 'AudioBook'];

  static const finishedAt = 0.97;

  static List<EmbyItem> chapters(Iterable<EmbyItem> tracks) => [...tracks]..sort(_compare);

  static bool finished(EmbyItem track) => track.isPlayed || (track.progress ?? 0) >= finishedAt;

  static ResumePoint? resumePoint(List<EmbyItem> chapters) {
    final at = chapters.indexWhere((c) => !finished(c));
    if (at < 0) return null;
    final start = chapters[at].resumePosition;
    if (at == 0 && start == null) return null;
    return (index: at, start: start ?? Duration.zero);
  }

  static int _compare(EmbyItem a, EmbyItem b) {
    final disc = _number(a.parentIndexNumber, b.parentIndexNumber);
    if (disc != 0) return disc;
    final index = _number(a.indexNumber, b.indexNumber);
    return index != 0 ? index : _natural(a.name, b.name);
  }

  static int _number(int? a, int? b) {
    if (a == null || b == null) return a == b ? 0 : (a == null ? 1 : -1);
    return a.compareTo(b);
  }

  static final _parts = RegExp(r'\d+|\D+');

  static int _natural(String a, String b) {
    final left = _parts.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
    final right = _parts.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
    for (var i = 0; i < left.length && i < right.length; i++) {
      final x = left[i], y = right[i];
      final nx = int.tryParse(x), ny = int.tryParse(y);
      final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
      if (c != 0) return c;
    }
    return left.length.compareTo(right.length);
  }
}
