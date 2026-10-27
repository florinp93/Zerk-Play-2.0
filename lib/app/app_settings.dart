import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';


const uiLanguages = {'en': 'English', 'ro': 'Română'};

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

enum CollectionsView {
  covers,

  wide,
}

final class AppSettings {
  const AppSettings({
    this.seerrUrl = '',
    this.seerrApiKey = '',
    this.tmdbApiKey = '',
    this.metadataLanguage = '',
    this.sounds = true,
    this.hideAnimation = true,
    this.acceptInvalidCertificates = false,
    this.versionPreferences = const {},
    this.uiLanguage = '',
    this.onboarded = false,
    this.trailers = TrailerMode.autoplay,
    this.trailerSound = false,
    this.trailerLanguage = '',
    this.xtreamUrl = '',
    this.xtreamAccounts = const [],
    this.startFullScreen = false,
    this.posterSize = PosterSize.medium,
    this.collectionsView = CollectionsView.covers,
  });

  final String seerrUrl;
  final String seerrApiKey;

  final String tmdbApiKey;

  final String metadataLanguage;
  final bool sounds;

  final bool hideAnimation;
  final bool acceptInvalidCertificates;

  final Map<String, String> versionPreferences;

  final String uiLanguage;

  final bool onboarded;

  final TrailerMode trailers;

  final bool trailerSound;

  final String trailerLanguage;

  final String xtreamUrl;
  final List<(String, String)> xtreamAccounts;

  final bool startFullScreen;
  final PosterSize posterSize;
  final CollectionsView collectionsView;

  String get resolvedUiLanguage {
    if (uiLanguages.containsKey(uiLanguage)) return uiLanguage;
    final system = PlatformDispatcher.instance.locale.languageCode;
    return uiLanguages.containsKey(system) ? system : 'en';
  }

  String get uiMetadataLanguage => resolvedUiLanguage == 'ro' ? 'ro-RO' : 'en-US';

  String get tmdbLanguage => metadataLanguage.isEmpty ? 'en-US' : metadataLanguage;

  bool get tmdbMetadataEnabled => tmdbApiKey.trim().isNotEmpty && metadataLanguage.isNotEmpty;

  bool get xtreamConfigured => xtreamUrl.trim().isNotEmpty && xtreamAccounts.isNotEmpty;

  bool get seerrConfigured => seerrUrl.trim().isNotEmpty && seerrApiKey.trim().isNotEmpty;

  AppSettings copyWith({
    String? seerrUrl,
    String? seerrApiKey,
    String? tmdbApiKey,
    String? metadataLanguage,
    bool? sounds,
    bool? hideAnimation,
    bool? acceptInvalidCertificates,
    Map<String, String>? versionPreferences,
    String? uiLanguage,
    bool? onboarded,
    TrailerMode? trailers,
    bool? trailerSound,
    String? trailerLanguage,
    String? xtreamUrl,
    List<(String, String)>? xtreamAccounts,
    bool? startFullScreen,
    PosterSize? posterSize,
    CollectionsView? collectionsView,
  }) =>
      AppSettings(
        seerrUrl: seerrUrl ?? this.seerrUrl,
        seerrApiKey: seerrApiKey ?? this.seerrApiKey,
        tmdbApiKey: tmdbApiKey ?? this.tmdbApiKey,
        metadataLanguage: metadataLanguage ?? this.metadataLanguage,
        sounds: sounds ?? this.sounds,
        hideAnimation: hideAnimation ?? this.hideAnimation,
        acceptInvalidCertificates: acceptInvalidCertificates ?? this.acceptInvalidCertificates,
        versionPreferences: versionPreferences ?? this.versionPreferences,
        uiLanguage: uiLanguage ?? this.uiLanguage,
        onboarded: onboarded ?? this.onboarded,
        trailers: trailers ?? this.trailers,
        trailerSound: trailerSound ?? this.trailerSound,
        trailerLanguage: trailerLanguage ?? this.trailerLanguage,
        xtreamUrl: xtreamUrl ?? this.xtreamUrl,
        xtreamAccounts: xtreamAccounts ?? this.xtreamAccounts,
        startFullScreen: startFullScreen ?? this.startFullScreen,
        posterSize: posterSize ?? this.posterSize,
        collectionsView: collectionsView ?? this.collectionsView,
      );

  static Future<bool> exist() async => (await SharedPreferences.getInstance()).containsKey(_key);

  static const _key = 'app.settings.v2';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings(
        seerrUrl: j['seerrUrl'] as String? ?? '',
        seerrApiKey: j['seerrApiKey'] as String? ?? '',
        tmdbApiKey: j['tmdbApiKey'] as String? ?? '',
        metadataLanguage: j['metadataLanguage'] as String? ?? '',
        sounds: j['sounds'] as bool? ?? true,
        hideAnimation: j['hideAnimation'] as bool? ?? true,
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
        trailerLanguage: j['trailerLanguage'] as String? ?? '',
        xtreamUrl: j['xtreamUrl'] as String? ?? '',
        xtreamAccounts: [
          for (final a in j['xtreamAccounts'] as List? ?? const []) (a[0] as String, a[1] as String),
          if (j['xtreamAccounts'] == null && (j['xtreamUser'] as String? ?? '').isNotEmpty)
            (j['xtreamUser'] as String, j['xtreamPassword'] as String? ?? ''),
        ],
        startFullScreen: j['startFullScreen'] as bool? ?? false,
        posterSize: PosterSize.values.asNameMap()[j['posterSize']] ?? PosterSize.medium,
        collectionsView: CollectionsView.values.asNameMap()[j['collectionsView']] ?? CollectionsView.covers,
      );
    } catch (_) {
      return const AppSettings();
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
        'metadataLanguage': metadataLanguage,
        'sounds': sounds,
        'hideAnimation': hideAnimation,
        'badCerts': acceptInvalidCertificates,
        'versions': versionPreferences,
        'uiLanguage': uiLanguage,
        'onboarded': onboarded,
        'trailers': trailers.name,
        'trailerSound': trailerSound,
        'trailerLanguage': trailerLanguage,
        'xtreamUrl': xtreamUrl,
        'xtreamAccounts': [for (final (u, p) in xtreamAccounts) [u, p]],
        'startFullScreen': startFullScreen,
        'posterSize': posterSize.name,
        'collectionsView': collectionsView.name,
      }),
    );
  }
}
