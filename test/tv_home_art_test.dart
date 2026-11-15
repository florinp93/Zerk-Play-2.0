import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zerk_play/app/app_settings.dart';
import 'package:zerk_play/core/emby/models/emby_item.dart';
import 'package:zerk_play/ui/core/tv_home.dart';

EmbyItem _episode(Map<String, dynamic> extra) =>
    EmbyItem.fromJson({'Id': 'e1', 'Name': 'Pilot', 'Type': 'Episode', 'SeriesId': 's1', ...extra});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('series artwork prefers landscape series art and falls back to the series poster', () {
    expect(
      TvHome.seriesArtSource(_episode({
        'ParentThumbItemId': 's1',
        'ParentThumbImageTag': 't',
        'ParentBackdropItemId': 's1',
        'ParentBackdropImageTags': ['b'],
        'ImageTags': {'Primary': 'still'},
      })),
      SeriesArtSource.thumb,
    );
    expect(
      TvHome.seriesArtSource(_episode({'ParentBackdropItemId': 's1', 'ParentBackdropImageTags': ['b']})),
      SeriesArtSource.backdrop,
    );
    expect(TvHome.seriesArtSource(_episode({'SeriesPrimaryImageTag': 'p'})), SeriesArtSource.poster);
    expect(TvHome.seriesArtSource(_episode({'ImageTags': {'Primary': 'still'}})), SeriesArtSource.none);
  });

  test('launcher episode art is saved and defaults to series artwork', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await AppSettings.load()).launcherEpisodeArt, LauncherEpisodeArt.series);
    await const AppSettings(launcherEpisodeArt: LauncherEpisodeArt.episode).save();
    expect((await AppSettings.load()).launcherEpisodeArt, LauncherEpisodeArt.episode);
  });
}
