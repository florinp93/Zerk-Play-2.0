import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/host.dart';
import '../data/catalog_api.dart';
import 'home_rows.dart';


const uiLanguages = {'en': 'English', 'ro': 'Română', 'fr': 'Français', 'de': 'Deutsch', 'es': 'Español', 'pl': 'Polski'};

const metadataLanguages = {
  '': 'From the server (Emby)',
  'en-US': 'English',
  'ro-RO': 'Română',
  'fr-FR': 'Français',
  'de-DE': 'Deutsch',
  'es-ES': 'Español',
  'it-IT': 'Italiano',
  'pt-PT': 'Português',
  'pt-BR': 'Português (Brasil)',
  'pl-PL': 'Polski',
  'hu-HU': 'Magyar',
  'ja-JP': '日本語',
  'ko-KR': '한국어',
};

enum TrailerMode {
  autoplay,

  onRequest,

  off,
}

enum PosterSize {
  small(9),
  medium(7),
  large(5);

  const PosterSize(this.columns);

  final int columns;
}

enum LibraryView {
  posters,

  cards,

  list,
}

enum TextSize {
  small(0.88),
  medium(1.0),
  large(1.2);

  const TextSize(this.scale);

  final double scale;
}

enum ReduceEffects { auto, on, off }

enum ContinueWatchingAction { details, play }

enum CollectionsView {
  covers,

  wide,
}

enum LauncherEpisodeArt {
  series,

  episode,
}

enum TechInfoPlacement { bottom, underButtons }

final class AppSettings {
  const AppSettings({
    this.seerrUrl = '',
    this.seerrApiKey = '',
    this.tmdbApiKey = '',
    this.mdblistApiKey = '',
    this.metadataLanguage = '',
    this.sounds = true,
    this.hideAnimation = true,
    this.groupCollections = false,
    this.homeClock = false,
    this.launcherEpisodeArt = LauncherEpisodeArt.series,
    this.techInfoPlacement = TechInfoPlacement.bottom,
    this.acceptInvalidCertificates = false,
    this.versionPreferences = const {},
    this.uiLanguage = '',
    this.onboarded = false,
    this.trailers = TrailerMode.autoplay,
    this.trailerSound = false,
    this.xtreamUrl = '',
    this.xtreamAccounts = const [],
    this.playlistUrl = '',
    this.playlistGuideUrl = '',
    this.startFullScreen = false,
    this.posterSize = PosterSize.medium,
    this.collectionsView = CollectionsView.covers,
    this.reduceEffects = ReduceEffects.auto,
    this.collectionsSource = CollectionsSource.both,
    this.continueWatchingAction = ContinueWatchingAction.details,
    this.libraryView = LibraryView.posters,
    this.homeCollections = const {},
    this.cardTrailers = true,
    this.textSize = TextSize.medium,
    this.interfaceScale = 1,
    this.homeRows = const {},
    this.hiddenLibraries = const {},
    this.libraryPicks = const {},
  });

  final String seerrUrl;
  final String seerrApiKey;

  final String tmdbApiKey;

  final String mdblistApiKey;

  final String metadataLanguage;
  final bool sounds;

  final bool hideAnimation;
  final bool groupCollections;
  final bool homeClock;
  final LauncherEpisodeArt launcherEpisodeArt;
  final TechInfoPlacement techInfoPlacement;
  final bool acceptInvalidCertificates;

  final Map<String, String> versionPreferences;

  final String uiLanguage;

  final bool onboarded;

  final TrailerMode trailers;

  final bool trailerSound;


  final String xtreamUrl;
  final List<(String, String)> xtreamAccounts;

  final String playlistUrl;
  final String playlistGuideUrl;

  final bool startFullScreen;
  final PosterSize posterSize;
  final CollectionsView collectionsView;
  final ReduceEffects reduceEffects;
  final CollectionsSource collectionsSource;
  final ContinueWatchingAction continueWatchingAction;
  final LibraryView libraryView;

  final Map<String, List<(String, String)>> homeCollections;

  final bool cardTrailers;

  final TextSize textSize;

  final double interfaceScale;

  final Map<String, HomeRowLayout> homeRows;

  final Map<String, List<String>> hiddenLibraries;

  final Map<String, String> libraryPicks;

  HomeRowLayout homeRowsOf(String userId) => homeRows[userId] ?? const HomeRowLayout();

  AppSettings withHomeRows(String userId, HomeRowLayout layout) =>
      copyWith(homeRows: {...homeRows, userId: layout}..removeWhere((_, v) => v.isDefault));

  Set<String> hiddenLibrariesOf(String userId) => {...?hiddenLibraries[userId]};

  AppSettings withHiddenLibraries(String userId, Set<String> ids) =>
      copyWith(hiddenLibraries: {...hiddenLibraries, userId: ids.toList()..sort()}..removeWhere((_, v) => v.isEmpty));

  String? libraryPickOf(String userId, String page) => libraryPicks['$userId/$page'];

  AppSettings withLibraryPick(String userId, String page, String? libraryId) => copyWith(
      libraryPicks: {...libraryPicks, '$userId/$page': libraryId ?? ''}..removeWhere((_, v) => v.isEmpty));

  List<(String, String)> homeCollectionsOf(String userId) => homeCollections[userId] ?? const [];

  AppSettings withHomeCollections(String userId, List<(String, String)> picked) =>
      copyWith(homeCollections: {...homeCollections, userId: picked});

  String get resolvedUiLanguage {
    if (uiLanguages.containsKey(uiLanguage)) return uiLanguage;
    final system = PlatformDispatcher.instance.locale.languageCode;
    return uiLanguages.containsKey(system) ? system : 'en';
  }

  String get uiMetadataLanguage =>
      const {'ro': 'ro-RO', 'fr': 'fr-FR', 'de': 'de-DE', 'es': 'es-ES', 'pl': 'pl-PL'}[resolvedUiLanguage] ?? 'en-US';

  String get tmdbLanguage => metadataLanguage.isEmpty ? 'en-US' : metadataLanguage;

  bool get tmdbMetadataEnabled => tmdbApiKey.trim().isNotEmpty && metadataLanguage.isNotEmpty;

  bool get xtreamConfigured => xtreamUrl.trim().isNotEmpty && xtreamAccounts.isNotEmpty;

  bool get seerrConfigured => seerrUrl.trim().isNotEmpty && seerrApiKey.trim().isNotEmpty;

  AppSettings copyWith({
    String? seerrUrl,
    String? seerrApiKey,
    String? tmdbApiKey,
    String? mdblistApiKey,
    String? metadataLanguage,
    bool? sounds,
    bool? hideAnimation,
    bool? groupCollections,
    bool? homeClock,
    LauncherEpisodeArt? launcherEpisodeArt,
    TechInfoPlacement? techInfoPlacement,
    bool? acceptInvalidCertificates,
    Map<String, String>? versionPreferences,
    String? uiLanguage,
    bool? onboarded,
    TrailerMode? trailers,
    bool? trailerSound,
    String? xtreamUrl,
    List<(String, String)>? xtreamAccounts,
    String? playlistUrl,
    String? playlistGuideUrl,
    bool? startFullScreen,
    PosterSize? posterSize,
    CollectionsView? collectionsView,
    ReduceEffects? reduceEffects,
    CollectionsSource? collectionsSource,
    ContinueWatchingAction? continueWatchingAction,
    LibraryView? libraryView,
    Map<String, List<(String, String)>>? homeCollections,
    bool? cardTrailers,
    TextSize? textSize,
    double? interfaceScale,
    Map<String, HomeRowLayout>? homeRows,
    Map<String, List<String>>? hiddenLibraries,
    Map<String, String>? libraryPicks,
  }) =>
      AppSettings(
        seerrUrl: seerrUrl ?? this.seerrUrl,
        seerrApiKey: seerrApiKey ?? this.seerrApiKey,
        tmdbApiKey: tmdbApiKey ?? this.tmdbApiKey,
        mdblistApiKey: mdblistApiKey ?? this.mdblistApiKey,
        metadataLanguage: metadataLanguage ?? this.metadataLanguage,
        sounds: sounds ?? this.sounds,
        hideAnimation: hideAnimation ?? this.hideAnimation,
        groupCollections: groupCollections ?? this.groupCollections,
        homeClock: homeClock ?? this.homeClock,
        launcherEpisodeArt: launcherEpisodeArt ?? this.launcherEpisodeArt,
        techInfoPlacement: techInfoPlacement ?? this.techInfoPlacement,
        acceptInvalidCertificates: acceptInvalidCertificates ?? this.acceptInvalidCertificates,
        versionPreferences: versionPreferences ?? this.versionPreferences,
        uiLanguage: uiLanguage ?? this.uiLanguage,
        onboarded: onboarded ?? this.onboarded,
        trailers: trailers ?? this.trailers,
        trailerSound: trailerSound ?? this.trailerSound,
        xtreamUrl: xtreamUrl ?? this.xtreamUrl,
        xtreamAccounts: xtreamAccounts ?? this.xtreamAccounts,
        playlistUrl: playlistUrl ?? this.playlistUrl,
        playlistGuideUrl: playlistGuideUrl ?? this.playlistGuideUrl,
        startFullScreen: startFullScreen ?? this.startFullScreen,
        posterSize: posterSize ?? this.posterSize,
        collectionsView: collectionsView ?? this.collectionsView,
        reduceEffects: reduceEffects ?? this.reduceEffects,
        collectionsSource: collectionsSource ?? this.collectionsSource,
        continueWatchingAction: continueWatchingAction ?? this.continueWatchingAction,
        libraryView: libraryView ?? this.libraryView,
        homeCollections: homeCollections ?? this.homeCollections,
        cardTrailers: cardTrailers ?? this.cardTrailers,
        textSize: textSize ?? this.textSize,
        interfaceScale: interfaceScale ?? this.interfaceScale,
        homeRows: homeRows ?? this.homeRows,
        hiddenLibraries: hiddenLibraries ?? this.hiddenLibraries,
        libraryPicks: libraryPicks ?? this.libraryPicks,
      );

  static Future<bool> exist() async => (await SharedPreferences.getInstance()).containsKey(_key);

  static const _key = 'app.settings.v2';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return AppSettings(cardTrailers: !Host.isAndroid);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings(
        seerrUrl: j['seerrUrl'] as String? ?? '',
        seerrApiKey: j['seerrApiKey'] as String? ?? '',
        tmdbApiKey: j['tmdbApiKey'] as String? ?? '',
        mdblistApiKey: j['mdblistApiKey'] as String? ?? '',
        metadataLanguage: j['metadataLanguage'] as String? ?? '',
        sounds: j['sounds'] as bool? ?? true,
        hideAnimation: j['hideAnimation'] as bool? ?? true,
        groupCollections: j['groupCollections'] as bool? ?? false,
        homeClock: j['homeClock'] as bool? ?? false,
        launcherEpisodeArt:
            LauncherEpisodeArt.values.asNameMap()[j['launcherEpisodeArt']] ?? LauncherEpisodeArt.series,
        techInfoPlacement: TechInfoPlacement.values.asNameMap()[j['techInfoPlacement']] ?? TechInfoPlacement.bottom,
        acceptInvalidCertificates: j['badCerts'] as bool? ?? false,
        versionPreferences: (j['versions'] as Map?)?.cast<String, String>() ?? const {},
        uiLanguage: j['uiLanguage'] as String? ?? '',
        onboarded: j['onboarded'] as bool? ?? true,
        trailers: switch (j['trailers']) {
          'onRequest' => TrailerMode.onRequest,
          'off' => TrailerMode.off,
          _ => TrailerMode.autoplay,
        },
        trailerSound: j['trailerSound'] as bool? ?? j['trailers'] == 'autoplaySound',
        xtreamUrl: j['xtreamUrl'] as String? ?? '',
        xtreamAccounts: [
          for (final a in j['xtreamAccounts'] as List? ?? const []) (a[0] as String, a[1] as String),
          if (j['xtreamAccounts'] == null && (j['xtreamUser'] as String? ?? '').isNotEmpty)
            (j['xtreamUser'] as String, j['xtreamPassword'] as String? ?? ''),
        ],
        playlistUrl: j['playlistUrl'] as String? ?? '',
        playlistGuideUrl: j['playlistGuideUrl'] as String? ?? '',
        startFullScreen: j['startFullScreen'] as bool? ?? false,
        posterSize: PosterSize.values.asNameMap()[j['posterSize']] ?? PosterSize.medium,
        collectionsView: CollectionsView.values.asNameMap()[j['collectionsView']] ?? CollectionsView.covers,
        reduceEffects: ReduceEffects.values.asNameMap()[j['reduceEffects']] ?? ReduceEffects.auto,
        collectionsSource: CollectionsSource.values.asNameMap()[j['collectionsSource']] ?? CollectionsSource.both,
        continueWatchingAction:
            ContinueWatchingAction.values.asNameMap()[j['continueWatchingAction']] ?? ContinueWatchingAction.details,
        libraryView: LibraryView.values.asNameMap()[j['libraryView']] ?? LibraryView.posters,
        homeCollections: {
          for (final MapEntry(:key, :value) in ((j['homeCollections'] as Map?) ?? const {}).entries)
            '$key': [for (final c in value as List) (c[0] as String, c[1] as String)],
        },
        cardTrailers: Host.isAndroid && j['cardTrailersV'] != 2 ? false : j['cardTrailers'] as bool? ?? !Host.isAndroid,
        textSize: TextSize.values.asNameMap()[j['textSize']] ?? TextSize.medium,
        interfaceScale: ((j['interfaceScale'] as num?) ?? 1).toDouble().clamp(0.7, 1),
        homeRows: {
          for (final MapEntry(:key, :value) in ((j['homeRows'] as Map?) ?? const {}).entries)
            '$key': HomeRowLayout.fromJson(value),
        },
        hiddenLibraries: {
          for (final MapEntry(:key, :value) in ((j['hiddenLibraries'] as Map?) ?? const {}).entries)
            '$key': [for (final id in value as List) if (id is String) id],
        },
        libraryPicks: {
          for (final MapEntry(:key, :value) in ((j['libraryPicks'] as Map?) ?? const {}).entries)
            if (value is String) '$key': value,
        },
      );
    } catch (_) {
      return AppSettings(cardTrailers: !Host.isAndroid);
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'seerrUrl': seerrUrl,
        'seerrApiKey': seerrApiKey,
        'tmdbApiKey': tmdbApiKey,
        'mdblistApiKey': mdblistApiKey,
        'metadataLanguage': metadataLanguage,
        'sounds': sounds,
        'hideAnimation': hideAnimation,
        'groupCollections': groupCollections,
        'homeClock': homeClock,
        'launcherEpisodeArt': launcherEpisodeArt.name,
        'techInfoPlacement': techInfoPlacement.name,
        'badCerts': acceptInvalidCertificates,
        'versions': versionPreferences,
        'uiLanguage': uiLanguage,
        'onboarded': onboarded,
        'trailers': trailers.name,
        'trailerSound': trailerSound,
        'xtreamUrl': xtreamUrl,
        'xtreamAccounts': [for (final (u, p) in xtreamAccounts) [u, p]],
        'playlistUrl': playlistUrl,
        'playlistGuideUrl': playlistGuideUrl,
        'startFullScreen': startFullScreen,
        'posterSize': posterSize.name,
        'collectionsView': collectionsView.name,
        'reduceEffects': reduceEffects.name,
        'collectionsSource': collectionsSource.name,
        'continueWatchingAction': continueWatchingAction.name,
        'libraryView': libraryView.name,
        'homeCollections': {
          for (final MapEntry(:key, :value) in homeCollections.entries) key: [for (final (id, name) in value) [id, name]],
        },
        'cardTrailers': cardTrailers,
        'cardTrailersV': 2,
        'textSize': textSize.name,
        'interfaceScale': interfaceScale,
        'homeRows': {for (final MapEntry(:key, :value) in homeRows.entries) key: value.toJson()},
        'hiddenLibraries': hiddenLibraries,
        'libraryPicks': libraryPicks,
      }),
    );
  }
}
