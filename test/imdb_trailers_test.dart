import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/playback/trailer/imdb_trailers.dart';

const _trailer = 'amzn1.imdb.video.contenttype.trailer';
const _clip = 'amzn1.imdb.video.contenttype.clip';

Map<String, dynamic> _node(String id, String name, int seconds, String type, [List<Map<String, String>>? urls]) => {
      'id': id,
      'name': {'value': name},
      'runtime': {'value': seconds},
      'contentType': {'id': type},
      'playbackURLs': ?urls,
    };

Map<String, dynamic> _title(List<Map<String, dynamic>> nodes) => {
      'data': {
        'title': {
          'primaryVideos': {
            'edges': [
              for (final n in nodes) {'node': n},
            ],
          },
        },
      },
    };

Map<String, String> _url(String mime, String definition, [String expires = '1795856823']) => {
      'url': 'https://imdb-video.media-imdb.com/vi1/$definition.${mime.toLowerCase()}?Expires=$expires&Signature=x',
      'videoMimeType': mime,
      'videoDefinition': definition,
    };

void main() {
  group('parsing', () {
    test('reads ids, names, runtimes and content types', () {
      final json = jsonDecode(jsonEncode(_title([
        _node('vi1', 'Official Trailer', 150, _trailer),
        _node('vi2', 'Behind the scenes', 240, _clip),
      ]))) as Map<String, dynamic>;
      final videos = Imdb.parseTitle(json);
      expect(videos.map((v) => v.id), ['vi1', 'vi2']);
      expect(videos.first.name, 'Official Trailer');
      expect(videos.first.seconds, 150);
      expect(videos.first.isTrailer, isTrue);
      expect(videos.last.isTrailer, isFalse);
    });

    test('a title without videos or with a null title gives nothing', () {
      expect(Imdb.parseTitle(_title([])), isEmpty);
      expect(Imdb.parseTitle({'data': {'title': null}}), isEmpty);
    });

    test('reads playback urls and the signed expiry', () {
      final videos = Imdb.parseTitle(_title([
        _node('vi1', 'Trailer', 120, _trailer, [_url('MP4', 'DEF_720p'), _url('M3U8', 'DEF_AUTO')]),
      ]));
      final playbacks = videos.single.playbacks;
      expect(playbacks, hasLength(2));
      expect(playbacks.first.height, 720);
      expect(playbacks.first.expires, DateTime.fromMillisecondsSinceEpoch(1795856823 * 1000));
    });
  });

  group('ranking', () {
    List<String> ranked(List<Map<String, dynamic>> nodes) => Imdb.rank(Imdb.parseTitle(_title(nodes))).map((v) => v.id).toList();

    test('trailers come before other content and clips are left out', () {
      expect(ranked([_node('clip', 'Interview', 300, _clip), _node('t', 'Trailer', 120, _trailer)]), ['t']);
    });

    test('a short spot is skipped when a longer trailer exists', () {
      expect(ranked([_node('spot', 'TV Spot', 30, _trailer), _node('long', 'Trailer', 140, _trailer)]), ['long']);
    });

    test('a short trailer is kept when it is the only one', () {
      expect(ranked([_node('spot', 'Teaser', 30, _trailer)]), ['spot']);
    });

    test('official trailers win, then trailers, then the longest', () {
      expect(
        ranked([
          _node('a', 'Behind the Story', 200, _trailer),
          _node('b', 'Trailer #1', 90, _trailer),
          _node('c', 'Trailer #2', 145, _trailer),
          _node('d', 'Official Trailer', 80, _trailer),
        ]),
        ['d', 'c', 'b', 'a'],
      );
    });
  });

  group('stream choice', () {
    ImdbVideo video(List<Map<String, String>> urls) =>
        Imdb.parseTitle(_title([_node('vi1', 'Trailer', 120, _trailer, urls)])).single;

    test('picks the highest MP4 definition', () {
      final best = Imdb.bestPlayback(video([
        _url('MP4', 'DEF_480p'),
        _url('M3U8', 'DEF_AUTO'),
        _url('MP4', 'DEF_1080p'),
        _url('MP4', 'DEF_SD'),
        _url('MP4', 'DEF_720p'),
      ]));
      expect(best!.definition, 'DEF_1080p');
      expect(best.mime, 'MP4');
    });

    test('an SD MP4 beats the HLS playlist', () {
      final best = Imdb.bestPlayback(video([_url('M3U8', 'DEF_AUTO'), _url('MP4', 'DEF_SD')]));
      expect(best!.mime, 'MP4');
    });

    test('falls back to HLS when there is no MP4', () {
      final best = Imdb.bestPlayback(video([_url('WEBM', 'DEF_SD'), _url('M3U8', 'DEF_AUTO')]));
      expect(best!.mime, 'M3U8');
    });

    test('returns nothing when no format is playable', () {
      expect(Imdb.bestPlayback(video([_url('WEBM', 'DEF_SD')])), isNull);
      expect(Imdb.bestPlayback(video([])), isNull);
    });
  });
}
