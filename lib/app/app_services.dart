import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/host.dart';
import '../core/http/trust_all_certs.dart';
import '../core/storage/shared_preferences_store.dart';
import '../core/emby/server_kind.dart';
import '../data/catalog_api.dart';
import '../data/collection_index.dart';
import '../data/metadata_localizer.dart';
import '../data/recommendations.dart';
import '../data/seerr_api.dart';
import '../data/title_tags.dart';
import '../data/tmdb_api.dart';
import '../data/emby_live_tv.dart';
import '../data/title_ratings.dart';
import '../data/xtream/live_catalog.dart';
import '../data/xtream/xtream.dart';
import '../playback/emby_playback_api.dart';
import '../services/janus/janus_service.dart';
import '../ui/core/ui_sounds.dart';
import 'app_settings.dart';

final class AppServices extends ChangeNotifier {
  AppServices._({
    required this.janus,
    required this.catalog,
    required this.playback,
    required this._settings,
  }) {
    _rebuildSeerr();
    _rebuildMetadata();
    _warmLiveTv();
    unawaited(_detectEmbyTv());
  }

  final JanusService janus;
  final CatalogApi catalog;
  final EmbyPlaybackApi playback;

  AppSettings _settings;
  AppSettings get settings => _settings;

  SeerrApi? _seerr;

  final libraryChanged = ValueNotifier<int>(0);

  void markLibraryChanged() => libraryChanged.value++;

  SeerrApi? get seerr => _seerr;

  Recommender get recommender => Recommender(
        catalog: catalog,
        seerr: _seerr,
        tmdb: tmdb,
        language: _settings.tmdbLanguage,
      );

  TitleTags? _titleTags;

  TitleTags? get titleTags {
    final t = tmdb;
    if (t == null) return _titleTags = null;
    final language = _settings.tmdbLanguage;
    final cached = _titleTags;
    if (cached != null && cached.tmdb.apiKey == t.apiKey && cached.language == language) return cached;
    return _titleTags = TitleTags(t, language: language);
  }

  bool get isSignedIn => janus.isAuthenticated;

  static Future<AppServices> create() async {
    final store = SharedPreferencesStore();
    await store.init();
    final hadSettings = await AppSettings.exist();
    var settings = await AppSettings.load();
    if (settings.acceptInvalidCertificates) trustAllCertificates();
    UiSounds.enabled = settings.sounds;
    RecommendationFilter.hideAnimation = settings.hideAnimation;

    final janus = JanusService(
      store: store,
      deviceName: Host.isAndroid ? 'Android TV' : 'Windows',
      appVersion: '2.0.0',
    );
    await janus.init();
    await janus.restoreSession();
    if (!hadSettings && janus.isAuthenticated) {
      settings = settings.copyWith(onboarded: true);
      await settings.save();
    }
    final services = AppServices._(
      janus: janus,
      catalog: CatalogApi(janus: janus),
      playback: EmbyPlaybackApi(janus: janus),
      settings: settings,
    );
    if (janus.isAuthenticated) {
      unawaited(services.playback.registerCapabilities().catchError((Object e) {
        debugPrint('[emby] capabilities: $e');
      }));
    }
    return services;
  }

  bool get liveTvAvailable => _settings.xtreamConfigured || playlist.configured;

  late final embyLiveTv = EmbyLiveTv(janus);
  bool _embyTvAvailable = false;

  bool get embyTvAvailable => !liveTvAvailable && _embyTvAvailable;

  Future<void> _detectEmbyTv() async {
    if (!janus.isAuthenticated) return;
    final available = await embyLiveTv.available();
    if (available == _embyTvAvailable) return;
    _embyTvAvailable = available;
    notifyListeners();
  }

  XtreamServer get xtream =>
      XtreamServer(_settings.xtreamUrl, [for (final (u, p) in _settings.xtreamAccounts) XtreamAccount(u, p)]);

  M3uPlaylist get playlist => M3uPlaylist(_settings.playlistUrl, _settings.playlistGuideUrl);

  void _warmLiveTv() => LiveTv(xtream, playlist).warmUp();

  MdbListApi? _mdblist;

  MdbListApi? get mdblist {
    final key = _settings.mdblistApiKey.trim();
    if (key.isEmpty) return null;
    return _mdblist?.apiKey == key ? _mdblist : _mdblist = MdbListApi(key);
  }

  Future<TitleRatings?> titleRatings(int tmdbId, {required bool tv}) async =>
      await mdblist?.ratings(tmdbId, tv: tv) ?? await seerr?.ratings(tmdbId, tv ? SeerrMediaType.tv : SeerrMediaType.movie);

  TmdbApi? get tmdb {
    final key = _settings.tmdbApiKey.trim();
    return key.isEmpty ? null : TmdbApi(apiKey: key);
  }

  Future<void> updateSettings(AppSettings next) async {
    final metadataChanged =
        next.tmdbApiKey != _settings.tmdbApiKey || next.metadataLanguage != _settings.metadataLanguage;
    final recommendationsChanged = next.hideAnimation != _settings.hideAnimation;
    final xtreamChanged = next.xtreamUrl != _settings.xtreamUrl || next.xtreamAccounts.length != _settings.xtreamAccounts.length ||
        next.xtreamAccounts.indexed.any((e) => e.$2 != _settings.xtreamAccounts[e.$1]) ||
        next.playlistUrl != _settings.playlistUrl || next.playlistGuideUrl != _settings.playlistGuideUrl;
    _settings = next;
    UiSounds.enabled = next.sounds;
    RecommendationFilter.hideAnimation = next.hideAnimation;
    _rebuildSeerr();
    if (metadataChanged) _rebuildMetadata();
    if (xtreamChanged) _warmLiveTv();
    await next.save();
    notifyListeners();
    if (xtreamChanged) unawaited(_detectEmbyTv());
    if (metadataChanged || recommendationsChanged) markLibraryChanged();
  }

  Future<void> signIn(
      {required String server, ServerKind kind = ServerKind.emby, required String username, required String password}) async {
    await janus.login(serverUrl: server, kind: kind, username: username, password: password);
    catalog.collections?.invalidate();
    try {
      await playback.registerCapabilities();
    } catch (_) {}
    notifyListeners();
    unawaited(_detectEmbyTv());
  }

  Future<void> signOut() async {
    await janus.logout();
    _embyTvAvailable = false;
    notifyListeners();
  }

  void _rebuildSeerr() {
    final s = _settings;
    if (!s.seerrConfigured) {
      _seerr = null;
      return;
    }
    _seerr = SeerrApi(
      baseUrl: seerrBaseUrl(s.seerrUrl),
      apiKey: s.seerrApiKey.trim(),
      language: s.tmdbMetadataEnabled ? s.metadataLanguage : null,
      embyUserId: () => janus.isAuthenticated ? janus.session.userId : null,
    );
  }

  static Uri seerrBaseUrl(String raw) {
    final url = raw.trim();
    if (url.contains('://')) return Uri.parse(url);
    final host = Uri.parse('http://$url').host.toLowerCase();
    final ip = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');
    final lan = ip ||
        host == 'localhost' ||
        !host.contains('.') ||
        ['.local', '.lan', '.home', '.internal'].any(host.endsWith);
    return Uri.parse('${lan ? 'http' : 'https'}://$url');
  }

  Future<SeerrProblem?> checkSeerr() async {
    final seerr = _seerr;
    if (seerr == null) return const SeerrProblem(SeerrProblemKind.notConfigured);
    final problem = await seerr.check();
    debugPrint('[seerr] check ${seerr.baseUrl}: ${problem ?? 'ok'}');
    final raw = _settings.seerrUrl.trim();
    if (problem == null || raw.contains('://')) return problem;
    final other = seerr.baseUrl.replace(scheme: seerr.baseUrl.scheme == 'http' ? 'https' : 'http');
    final alt = SeerrApi(baseUrl: other, apiKey: seerr.apiKey, language: seerr.language);
    final altProblem = await alt.check();
    debugPrint('[seerr] check $other: ${altProblem ?? 'ok'}');
    if (altProblem != null) return problem;
    await updateSettings(_settings.copyWith(seerrUrl: other.toString()));
    return null;
  }

  void _rebuildMetadata() {
    final s = _settings;
    final localizer = catalog.localizer = s.tmdbMetadataEnabled
        ? MetadataLocalizer(
            tmdb: TmdbApi(apiKey: s.tmdbApiKey),
            language: s.metadataLanguage,
            seriesTmdbIds: catalog.seriesTmdbIds,
          )
        : null;
    final key = s.tmdbApiKey.trim();
    catalog.collections = key.isEmpty
        ? null
        : CollectionIndex(
            movies: catalog.movieRefs,
            tmdb: localizer ??
                MetadataLocalizer(tmdb: TmdbApi(apiKey: key), language: 'en-US', seriesTmdbIds: catalog.seriesTmdbIds),
          );
  }
}

final class AppServicesScope extends InheritedNotifier<AppServices> {
  const AppServicesScope({super.key, required AppServices services, required super.child})
      : super(notifier: services);

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppServicesScope>()!.notifier!;

  static AppServices read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppServicesScope>()!.notifier!;
}
