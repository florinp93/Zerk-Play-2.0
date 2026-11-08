import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/trickplay.dart';

Map<String, Object?> _info(int width, {int height = 0, int count = 250, int interval = 10000}) => {
      'Width': width,
      'Height': height == 0 ? width * 9 ~/ 16 : height,
      'TileWidth': 10,
      'TileHeight': 10,
      'ThumbnailCount': count,
      'Interval': interval,
      'Bandwidth': 12345,
    };

Uint8List _bif(List<int> timestamps, List<List<int>> frames, {int multiplier = 1000}) {
  final indexSize = (frames.length + 1) * 8;
  final total = 64 + indexSize + frames.fold<int>(0, (n, f) => n + f.length);
  final data = Uint8List(total);
  final bd = ByteData.sublistView(data);
  data.setAll(0, BifIndex.magic);
  bd.setUint32(12, frames.length, Endian.little);
  bd.setUint32(16, multiplier, Endian.little);
  var offset = 64 + indexSize;
  for (var i = 0; i < frames.length; i++) {
    bd.setUint32(64 + i * 8, timestamps[i], Endian.little);
    bd.setUint32(68 + i * 8, offset, Endian.little);
    data.setAll(offset, frames[i]);
    offset += frames[i].length;
  }
  bd.setUint32(64 + frames.length * 8, 0xffffffff, Endian.little);
  bd.setUint32(68 + frames.length * 8, offset, Endian.little);
  return data;
}

Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFF336699));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('sheet frames crop the right tile and clip the last sheet', (tester) async {
    await tester.runAsync(() async {
      final full = await _png(40, 20);
      final short = await _png(40, 10);
      final fetched = <int>[];
      final trickplay = SheetTrickplay(
        const TrickplayGrid(width: 20, height: 10, tileWidth: 2, tileHeight: 2, count: 6, interval: Duration(seconds: 5)),
        (sheet) async {
          fetched.add(sheet);
          return sheet == 0 ? full : short;
        },
      );
      final third = await trickplay.frame(trickplay.indexAt(const Duration(seconds: 17)));
      expect(third!.index, 3);
      expect(third.source, const ui.Rect.fromLTWH(20, 10, 20, 10));
      third.dispose();
      final fifth = await trickplay.frame(5);
      expect(fifth!.source, const ui.Rect.fromLTWH(20, 0, 20, 10));
      fifth.dispose();
      expect(await trickplay.frame(6), isNull);
      (await trickplay.frame(0))!.dispose();
      expect(fetched, [0, 1]);
      trickplay.dispose();
      expect(await trickplay.frame(0), isNull);
    });
  });

  group('Jellyfin trickplay grid', () {
    test('picks the media source and the width closest to the preferred one', () {
      final grid = TrickplayGrid.fromJellyfin({
        'other': {'320': _info(320)},
        'abc123': {'160': _info(160), '320': _info(320, count: 600), '640': _info(640)},
      }, 'abc123');
      expect(grid, isNotNull);
      expect(grid!.width, 320);
      expect(grid.height, 180);
      expect(grid.count, 600);
      expect(grid.interval, const Duration(seconds: 10));
      expect(grid.perSheet, 100);
    });

    test('matches media source ids with or without dashes', () {
      final grid = TrickplayGrid.fromJellyfin({
        'a1b2c3d4e5f60718293a4b5c6d7e8f90': {'320': _info(320)},
      }, 'A1B2C3D4-E5F6-0718-293A-4B5C6D7E8F90');
      expect(grid?.width, 320);
    });

    test('reports nothing for another media source or bad data', () {
      expect(TrickplayGrid.fromJellyfin({'x': {'320': _info(320)}}, 'y'), isNull);
      expect(TrickplayGrid.fromJellyfin(null, 'y'), isNull);
      expect(TrickplayGrid.fromJellyfin({'y': {}}, 'y'), isNull);
      expect(TrickplayGrid.fromJellyfin({'y': {'320': _info(320, count: 0)}}, 'y'), isNull);
      expect(TrickplayGrid.fromJellyfin({'y': {'320': _info(320, interval: 0)}}, 'y'), isNull);
    });

    test('falls back to the nearest width when the preferred one is missing', () {
      final grid = TrickplayGrid.fromJellyfin({'s': {'240': _info(240), '480': _info(480)}}, 's');
      expect(grid?.width, 240);
    });

    test('maps a time to a thumbnail and a tile', () {
      final grid = TrickplayGrid.fromJellyfin({'s': {'320': _info(320, count: 250)}}, 's')!;
      expect(grid.indexAt(Duration.zero), 0);
      expect(grid.indexAt(const Duration(seconds: -5)), 0);
      expect(grid.indexAt(const Duration(milliseconds: 9999)), 0);
      expect(grid.indexAt(const Duration(seconds: 10)), 1);
      expect(grid.indexAt(const Duration(seconds: 1234)), 123);
      expect(grid.indexAt(const Duration(hours: 5)), 249);

      expect(grid.tileOf(0), (sheet: 0, left: 0, top: 0));
      expect(grid.tileOf(9), (sheet: 0, left: 9 * 320, top: 0));
      expect(grid.tileOf(10), (sheet: 0, left: 0, top: 180));
      expect(grid.tileOf(99), (sheet: 0, left: 9 * 320, top: 9 * 180));
      expect(grid.tileOf(100), (sheet: 1, left: 0, top: 0));
      expect(grid.tileOf(123), (sheet: 1, left: 3 * 320, top: 2 * 180));
      expect(grid.tileOf(249), (sheet: 2, left: 9 * 320, top: 4 * 180));
    });

    test('handles non-square tile grids', () {
      final grid = TrickplayGrid(
          width: 100, height: 50, tileWidth: 4, tileHeight: 3, count: 30, interval: const Duration(seconds: 2));
      expect(grid.perSheet, 12);
      expect(grid.tileOf(13), (sheet: 1, left: 100, top: 0));
      expect(grid.tileOf(23), (sheet: 1, left: 300, top: 100));
    });
  });

  group('BIF', () {
    test('parses the header and index', () {
      final bif = BifIndex.parse(_bif([0, 10, 20, 30], [
        [1, 2, 3],
        [4],
        [5, 6],
        [7, 8, 9, 10],
      ]))!;
      expect(bif.count, 4);
      expect(bif.interval, const Duration(seconds: 10));
      expect(bif.frame(0), [1, 2, 3]);
      expect(bif.frame(1), [4]);
      expect(bif.frame(2), [5, 6]);
      expect(bif.frame(3), [7, 8, 9, 10]);
      expect(bif.indexAt(const Duration(seconds: 20)), 2);
    });

    test('maps a time to the last frame at or before it', () {
      final bif = BifIndex.parse(_bif([0, 10, 20, 30], [[1], [2], [3], [4]]))!;
      expect(bif.indexAt(Duration.zero), 0);
      expect(bif.indexAt(const Duration(seconds: 9)), 0);
      expect(bif.indexAt(const Duration(seconds: 10)), 1);
      expect(bif.indexAt(const Duration(seconds: 29)), 2);
      expect(bif.indexAt(const Duration(hours: 1)), 3);
      expect(bif.indexAt(const Duration(seconds: -1)), 0);
    });

    test('uses the timestamp multiplier, defaulting to 1000 ms', () {
      final scaled = BifIndex.parse(_bif([0, 5, 10], [[1], [2], [3]], multiplier: 2000))!;
      expect(scaled.indexAt(const Duration(milliseconds: 9999)), 0);
      expect(scaled.indexAt(const Duration(seconds: 10)), 1);
      expect(scaled.interval, const Duration(seconds: 10));
      final unset = BifIndex.parse(_bif([0, 5, 10], [[1], [2], [3]], multiplier: 0))!;
      expect(unset.indexAt(const Duration(seconds: 10)), 2);
      expect(unset.interval, const Duration(seconds: 5));
    });

    test('rejects files that are not BIF or are truncated', () {
      expect(BifIndex.parse(Uint8List(10)), isNull);
      final notBif = _bif([0], [[1]]);
      notBif[1] = 0x41;
      expect(BifIndex.parse(notBif), isNull);
      final truncated = _bif([0, 10], [[1, 2, 3], [4, 5, 6]]);
      expect(BifIndex.parse(Uint8List.sublistView(truncated, 0, truncated.length - 2)), isNull);
      final empty = _bif([], []);
      expect(BifIndex.parse(empty), isNull);
    });
  });
}
