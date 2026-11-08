import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

final class TrickplayGrid {
  const TrickplayGrid({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.count,
    required this.interval,
  });

  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int count;
  final Duration interval;

  int get perSheet => tileWidth * tileHeight;

  int indexAt(Duration t) {
    final ms = interval.inMilliseconds;
    if (ms <= 0 || t.inMilliseconds <= 0) return 0;
    return math.min(t.inMilliseconds ~/ ms, count - 1);
  }

  ({int sheet, int left, int top}) tileOf(int index) {
    final local = index % perSheet;
    return (sheet: index ~/ perSheet, left: local % tileWidth * width, top: local ~/ tileWidth * height);
  }

  static String _plainId(String id) => id.replaceAll('-', '').toLowerCase();

  static TrickplayGrid? fromJellyfin(Object? trickplay, String mediaSourceId, {int preferredWidth = 320}) {
    if (trickplay is! Map) return null;
    final wanted = _plainId(mediaSourceId);
    final widths = trickplay.entries.where((e) => _plainId('${e.key}') == wanted).firstOrNull?.value;
    if (widths is! Map) return null;
    int distance(TrickplayGrid g) => (g.width - preferredWidth).abs();
    bool closer(TrickplayGrid a, TrickplayGrid b) =>
        distance(a) < distance(b) || distance(a) == distance(b) && a.width > b.width;
    TrickplayGrid? best;
    for (final grid in widths.values.map(_parse).nonNulls) {
      if (best == null || closer(grid, best)) best = grid;
    }
    return best;
  }

  static TrickplayGrid? _parse(Object? raw) {
    if (raw is! Map) return null;
    int v(String key) => (raw[key] as num?)?.toInt() ?? 0;
    final grid = TrickplayGrid(
      width: v('Width'),
      height: v('Height'),
      tileWidth: v('TileWidth'),
      tileHeight: v('TileHeight'),
      count: v('ThumbnailCount'),
      interval: Duration(milliseconds: v('Interval')),
    );
    final ok = grid.width > 0 && grid.height > 0 && grid.tileWidth > 0 && grid.tileHeight > 0 && grid.count > 0 &&
        grid.interval > Duration.zero;
    return ok ? grid : null;
  }
}

final class BifIndex {
  BifIndex._(this._data, this._times, this._offsets);

  static const magic = [0x89, 0x42, 0x49, 0x46, 0x0d, 0x0a, 0x1a, 0x0a];
  static const _headerSize = 64;

  final Uint8List _data;
  final List<int> _times;
  final List<int> _offsets;

  int get count => _times.length;

  Duration get interval => count > 1
      ? Duration(milliseconds: (_times.last - _times.first) ~/ (count - 1))
      : const Duration(seconds: 10);

  static BifIndex? parse(Uint8List data) {
    if (data.length < _headerSize) return null;
    for (var i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) return null;
    }
    final bd = ByteData.sublistView(data);
    final n = bd.getUint32(12, Endian.little);
    var multiplier = bd.getUint32(16, Endian.little);
    if (multiplier == 0) multiplier = 1000;
    if (n == 0 || _headerSize + (n + 1) * 8 > data.length) return null;
    final times = <int>[], offsets = <int>[];
    for (var i = 0; i <= n; i++) {
      final at = _headerSize + i * 8;
      final offset = bd.getUint32(at + 4, Endian.little);
      if (offset > data.length || offsets.isNotEmpty && offset < offsets.last) return null;
      if (i < n) times.add(bd.getUint32(at, Endian.little) * multiplier);
      offsets.add(offset);
    }
    return BifIndex._(data, times, offsets);
  }

  int indexAt(Duration t) {
    final ms = t.inMilliseconds;
    var lo = 0, hi = _times.length - 1, found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] <= ms) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  Uint8List frame(int index) => Uint8List.sublistView(_data, _offsets[index], _offsets[index + 1]);
}

final class TrickplayFrame {
  TrickplayFrame(this.index, this.image, this.source);

  final int index;
  final ui.Image image;
  final ui.Rect source;

  void paint(ui.Canvas canvas, ui.Rect target) =>
      canvas.drawImageRect(image, source, target, ui.Paint()..filterQuality = ui.FilterQuality.medium);

  void dispose() => image.dispose();
}

abstract base class Trickplay {
  Duration get interval;

  int indexAt(Duration t);

  Future<TrickplayFrame?> frame(int index);

  void dispose();

  static Future<ui.Image?> decode(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}

final class _ImageCache {
  _ImageCache(this.capacity);

  final int capacity;
  final _entries = <int, Future<ui.Image?>>{};
  bool disposed = false;

  Future<ui.Image?> get(int key, Future<ui.Image?> Function() load) {
    final hit = _entries.remove(key);
    if (hit != null) return _entries[key] = hit;
    final loading = load();
    _entries[key] = loading;
    while (_entries.length > capacity) {
      _release(_entries.remove(_entries.keys.first)!);
    }
    return loading;
  }

  static void _release(Future<ui.Image?> f) => f.then((image) => image?.dispose(), onError: (Object _) {});

  void dispose() {
    disposed = true;
    _entries.values.forEach(_release);
    _entries.clear();
  }
}

final class SheetTrickplay extends Trickplay {
  SheetTrickplay(this.grid, this._fetch);

  final TrickplayGrid grid;
  final Future<Uint8List?> Function(int sheet) _fetch;
  final _sheets = _ImageCache(3);

  @override
  Duration get interval => grid.interval;

  @override
  int indexAt(Duration t) => grid.indexAt(t);

  @override
  Future<TrickplayFrame?> frame(int index) async {
    if (index < 0 || index >= grid.count || _sheets.disposed) return null;
    final tile = grid.tileOf(index);
    final sheet = await _sheets.get(tile.sheet, () async {
      try {
        return await Trickplay.decode(await _fetch(tile.sheet));
      } catch (_) {
        return null;
      }
    });
    if (sheet == null || _sheets.disposed) return null;
    final w = math.min(grid.width, sheet.width - tile.left), h = math.min(grid.height, sheet.height - tile.top);
    if (w <= 0 || h <= 0) return null;
    return TrickplayFrame(index, sheet.clone(),
        ui.Rect.fromLTWH(tile.left.toDouble(), tile.top.toDouble(), w.toDouble(), h.toDouble()));
  }

  @override
  void dispose() => _sheets.dispose();
}

final class BifTrickplay extends Trickplay {
  BifTrickplay(this.bif);

  final BifIndex bif;
  final _frames = _ImageCache(40);

  @override
  Duration get interval => bif.interval;

  @override
  int indexAt(Duration t) => bif.indexAt(t);

  @override
  Future<TrickplayFrame?> frame(int index) async {
    if (index < 0 || index >= bif.count || _frames.disposed) return null;
    final image = await _frames.get(index, () => Trickplay.decode(bif.frame(index)));
    if (image == null || _frames.disposed) return null;
    return TrickplayFrame(index, image.clone(), ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));
  }

  @override
  void dispose() => _frames.dispose();
}
