import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/core/emby/models/emby_item.dart';

EmbyItem item(Map<String, dynamic> userData) => EmbyItem.fromJson({
      'Id': '1',
      'Name': 'Film',
      'Type': 'Movie',
      'RunTimeTicks': 72000000000,
      'UserData': userData,
    });

void main() {
  test('an unplayed item stopped half way resumes', () {
    final i = item({'Played': false, 'PlaybackPositionTicks': 36000000000});
    expect(i.resumePosition, const Duration(hours: 1));
    expect(i.progress, 0.5);
  });

  test('a played item watched again and stopped half way still resumes', () {
    final i = item({'Played': true, 'PlaybackPositionTicks': 18000000000, 'PlayedPercentage': 25.0});
    expect(i.resumePosition, const Duration(minutes: 30));
    expect(i.progress, 0.25);
  });

  test('no saved position means play from the start, played or not', () {
    expect(item({'Played': true, 'PlaybackPositionTicks': 0}).resumePosition, isNull);
    expect(item({'Played': true}).resumePosition, isNull);
    expect(item({'Played': false}).resumePosition, isNull);
    expect(item({}).resumePosition, isNull);
  });

  test('marking watched clears the position locally', () {
    final i = item({'Played': false, 'PlaybackPositionTicks': 36000000000}).copyWithUserData(isPlayed: true, playbackPositionTicks: 0);
    expect(i.resumePosition, isNull);
  });
}
