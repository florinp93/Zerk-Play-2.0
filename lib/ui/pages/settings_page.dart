import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../app/release.dart';
import '../../core/host.dart';
import '../../core/log/app_log.dart';
import '../../core/windows/native_window.dart';
import '../../data/xtream/live_catalog.dart';
import '../../data/xtream/xtream.dart';
import '../../data/metadata_localizer.dart';
import '../../l10n/l10n.dart';
import '../../playback/language.dart';
import '../../playback/mpv_conf.dart';
import '../../playback/player_settings.dart';
import '../../playback/subtitle_style.dart';
import '../../playback/trailer/trailer_player.dart';
import '../core/navigation.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/exit_app.dart';
import '../widgets/media_row.dart';
import '../widgets/remote_setup_panel.dart';
import '../widgets/setting_rows.dart';
import '../widgets/subtitle_preview.dart';
import '../widgets/update_dialog.dart';
import '../widgets/value_slider.dart';
import 'home_collections_page.dart';

enum _Section {
  playback(Icons.play_circle_outline_rounded),
  picture(Icons.hd_outlined),
  audio(Icons.graphic_eq_rounded),
  subtitles(Icons.subtitles_outlined),
  languages(Icons.translate_rounded),
  interface(Icons.tune_rounded),
  content(Icons.movie_filter_outlined),
  services(Icons.hub_outlined),
  liveTv(Icons.sports_soccer_rounded),
  account(Icons.person_outline_rounded),
  diagnostics(Icons.bug_report_outlined);

  const _Section(this.icon);

  final IconData icon;

  bool get shown => true;

  String label(L10n l10n) => switch (this) {
        playback => l10n.sectionPlayback,
        picture => l10n.settingsGroupPicture,
        audio => l10n.audio,
        subtitles => l10n.subtitles,
        languages => l10n.sectionLanguagesOnly,
        interface => l10n.sectionInterface,
        content => l10n.sectionContent,
        services => l10n.sectionServices,
        liveTv => l10n.sectionLiveTv,
        account => l10n.sectionAccount,
        diagnostics => l10n.sectionDiagnostics,
      };
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Section _section = _Section.playback;
  PlayerSettings? _player;
  DisplayHdrStatus? _display;

  @override
  void initState() {
    super.initState();
    PlayerSettings.load().then((p) => mounted ? setState(() => _player = p) : null);
    if (Host.isWindows) NativeWindow.hdrStatus().then((d) => mounted ? setState(() => _display = d) : null);
  }

  Future<void> _savePlayer(PlayerSettings next) async {
    setState(() => _player = next);
    await next.save();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: contentLeft, top: 90, right: 120),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 420,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.settings, style: Zt.headline),
            const SizedBox(height: 30),
            Expanded(
              child: FocusZone(
                debugLabel: 'settings-sections',
                child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
                  for (final s in _Section.values.where((s) => s.shown))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TvFocusable(
                        selectSound: null,
                        onFocusChange: (f) => f ? setState(() => _section = s) : null,
                        onSelect: () => ZoneNavigator.move(TraversalDirection.right),
                        builder: (context, focused) => AnimatedContainer(
                          duration: Zm.fast,
                          height: 62,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: focused ? Colors.white : (s == _section ? Colors.white.withValues(alpha: 0.10) : Colors.transparent),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(children: [
                            Icon(s.icon, color: focused ? Zc.background : Zc.textMuted, size: 28),
                            const SizedBox(width: 18),
                            Flexible(
                              child: Text(s.label(context.l10n),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Zt.label.copyWith(fontSize: 22, color: focused ? Zc.background : Zc.text)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 70),
        Expanded(
          child: AnimatedSwitcher(
            duration: Zm.normal,
            child: KeyedSubtree(
              key: ValueKey(_section),
              child: FocusZone(
                debugLabel: 'settings-${_section.name}',
                child: ListView(
                  padding: const EdgeInsets.only(top: 100, bottom: 120),
                  children: _player == null ? const [] : _items(_section, _player!),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _intro(String text) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Text(text, style: Zt.body));

  List<Widget> _items(_Section section, PlayerSettings p) {
    final services = AppServicesScope.of(context);
    final app = services.settings;
    final l10n = context.l10n;
    final languages = {'': l10n.languageFromFile, ...languageNames};
    switch (section) {
      case _Section.playback:
        return [
          SettingChoiceRow<int>(
            title: l10n.streamingQuality,
            subtitle: l10n.streamingQualityHint,
            value: p.maxStreamingBitrate,
            options: {0: l10n.qualityOriginal, 120000000: '120 Mbps', 60000000: '60 Mbps (4K)', 20000000: '20 Mbps (1080p)', 8000000: '8 Mbps (720p)', 3000000: '3 Mbps'},
            onChanged: (v) => _savePlayer(p.copyWith(maxStreamingBitrate: v)),
          ),
          SettingToggleRow(title: l10n.autoPlayNext, value: p.autoPlayNextEpisode,
              onChanged: (v) => _savePlayer(p.copyWith(autoPlayNextEpisode: v))),
          SettingToggleRow(title: l10n.autoSkipIntro, value: p.skipIntroAutomatically,
              onChanged: (v) => _savePlayer(p.copyWith(skipIntroAutomatically: v))),
          SettingHeader(l10n.settingsGroupSeeking),
          SettingChoiceRow<int>(
            title: l10n.seekForwardStep,
            value: p.seekForwardSeconds,
            options: {for (final s in const [5, 10, 15, 20, 30, 45, 60, 90, 120]) s: l10n.secondsCount(s)},
            onChanged: (v) => _savePlayer(p.copyWith(seekForwardSeconds: v)),
          ),
          SettingChoiceRow<int>(
            title: l10n.seekBackStep,
            value: p.seekBackSeconds,
            options: {for (final s in const [5, 10, 15, 20, 30, 45, 60, 90, 120]) s: l10n.secondsCount(s)},
            onChanged: (v) => _savePlayer(p.copyWith(seekBackSeconds: v)),
          ),
        ];
      case _Section.picture:
        return [
          _intro(l10n.videoIntro),
          SettingHeader(l10n.settingsGroupDisplay, first: true),
          if (Host.isWindows) ...[
            SettingToggleRow(title: l10n.hdrPassthrough, subtitle: l10n.hdrPassthroughHint,
                value: p.hdrPassthrough, onChanged: (v) => _savePlayer(p.copyWith(hdrPassthrough: v))),
            SettingToggleRow(
              title: l10n.autoHdr,
              subtitle: switch (_display) {
                null => l10n.autoHdrChecking,
                DisplayHdrStatus(supported: false) => l10n.autoHdrUnsupported,
                DisplayHdrStatus(enabled: true) => l10n.autoHdrAlreadyOn,
                _ => l10n.autoHdrSupported,
              },
              value: p.autoHdr && (_display?.supported ?? false),
              enabled: (_display?.supported ?? false) && p.hdrPassthrough,
              onChanged: (v) => _savePlayer(p.copyWith(autoHdr: v)),
            ),
            SettingToggleRow(
              title: l10n.keepHdr,
              subtitle: l10n.keepHdrHint,
              value: p.keepHdr,
              enabled: p.autoHdr && (_display?.supported ?? false),
              onChanged: (v) => _savePlayer(p.copyWith(keepHdr: v)),
            ),
          ],
          SettingToggleRow(title: l10n.matchRefreshRate, subtitle: l10n.matchRefreshRateHint,
              value: p.matchRefreshRate, onChanged: (v) => _savePlayer(p.copyWith(matchRefreshRate: v))),
          SettingToggleRow(
            title: l10n.keepRefreshRate,
            subtitle: l10n.keepRefreshRateHint,
            value: p.keepRefreshRate,
            enabled: p.matchRefreshRate,
            onChanged: (v) => _savePlayer(p.copyWith(keepRefreshRate: v)),
          ),
          SettingHeader(l10n.settingsGroupScreen),
          SettingChoiceRow<String>(
            title: l10n.defaultAspect,
            subtitle: l10n.defaultAspectHint,
            value: p.defaultAspect,
            options: {'auto': l10n.aspectOriginal, 'zoom': l10n.aspectZoom, 'stretch': l10n.aspectStretch},
            onChanged: (v) => _savePlayer(p.copyWith(defaultAspect: v)),
          ),
          SettingToggleRow(title: l10n.autoCrop, subtitle: l10n.autoCropHint,
              value: p.autoCrop, onChanged: (v) => _savePlayer(p.copyWith(autoCrop: v))),
          SettingChoiceRow<double>(
            title: l10n.screenShape,
            subtitle: l10n.screenShapeHint,
            value: p.scopeScreen,
            options: {0.0: l10n.screenShapeNormal, 2.35: l10n.screenShapeScope('2.35:1'), 2.37: l10n.screenShapeScope('2.37:1'), 2.40: l10n.screenShapeScope('2.40:1')},
            onChanged: (v) => _savePlayer(p.copyWith(scopeScreen: v)),
          ),
          SettingChoiceRow<double>(
            title: l10n.anamorphicLens,
            subtitle: l10n.anamorphicLensHint,
            value: p.anamorphic,
            options: {1.0: l10n.anamorphicNone, 1.25: '1.25×', 1.33: '1.33×', 1.5: '1.5×'},
            onChanged: (v) => _savePlayer(p.copyWith(anamorphic: v)),
          ),
          if (Host.isWindows) ...[
            SettingHeader(l10n.settingsGroupDecoding),
            SettingChoiceRow<VideoQuality>(
              title: l10n.videoQuality,
              subtitle: l10n.videoQualityHint,
              value: p.videoQuality,
              options: {
                VideoQuality.fast: l10n.videoQualityFast,
                VideoQuality.balanced: l10n.videoQualityBalanced,
                VideoQuality.high: l10n.videoQualityHigh,
              },
              onChanged: (v) => _savePlayer(p.copyWith(videoQuality: v)),
            ),
            SettingChoiceRow<String>(
              title: l10n.hardwareDecoding,
              subtitle: l10n.hardwareDecodingHint,
              value: p.hwdec,
              options: {
                'auto-safe': l10n.hwdecAuto,
                'd3d11va': l10n.hwdecD3d11,
                'nvdec': l10n.hwdecNvdec,
                'd3d11va-copy': l10n.hwdecCopy,
                'no': l10n.hwdecOff,
              },
              onChanged: (v) => _savePlayer(p.copyWith(hwdec: v)),
            ),
            const SizedBox(height: 16),
            SettingActionRow(
              title: l10n.advancedVideo,
              subtitle: l10n.advancedVideoHint,
              icon: Icons.chevron_right_rounded,
              onSelect: () async {
                await Navigator.of(context).push(tvRoute<void>(_AdvancedVideoPage(initial: p), name: 'settings/advanced-video'));
                final fresh = await PlayerSettings.load();
                if (mounted) setState(() => _player = fresh);
              },
            ),
          ],
        ];
      case _Section.audio:
        return [
          _intro(Host.isAndroid ? l10n.audioOutputIntroAndroid : l10n.audioPassthroughIntro),
          for (final c in PassthroughCodec.values)
            SettingToggleRow(
              title: switch (c) {
                PassthroughCodec.ac3 => 'Dolby Digital (AC-3)',
                PassthroughCodec.eac3 => 'Dolby Digital Plus (E-AC-3, Atmos)',
                PassthroughCodec.dts => 'DTS',
                PassthroughCodec.dtshd => 'DTS-HD MA / DTS:X',
                PassthroughCodec.truehd => 'Dolby TrueHD (Atmos)',
              },
              value: p.passthrough.contains(c),
              onChanged: (v) => _savePlayer(p.copyWith(passthrough: v ? {...p.passthrough, c} : ({...p.passthrough}..remove(c)))),
            ),
          if (Host.isWindows)
            SettingToggleRow(title: l10n.exclusiveAudio, subtitle: l10n.exclusiveAudioHint,
                value: p.audioExclusive, onChanged: (v) => _savePlayer(p.copyWith(audioExclusive: v))),
        ];
      case _Section.subtitles:
        return [
          SettingChoiceRow<SubtitleMode>(
            title: l10n.subtitles,
            subtitle: l10n.subtitleModeHint,
            value: p.subtitleMode,
            options: {SubtitleMode.smart: l10n.subtitleSmart, SubtitleMode.always: l10n.subtitleAlways, SubtitleMode.off: l10n.subtitleOff},
            onChanged: (v) => _savePlayer(p.copyWith(subtitleMode: v)),
          ),
          SettingHeader(l10n.settingsGroupSubtitleLook),
          SettingSliderRow(
            title: l10n.subtitleSize,
            subtitle: l10n.subtitleSizeHint,
            value: p.subtitleScale,
            min: SubtitleStyle.minScale,
            max: SubtitleStyle.maxScale,
            step: SubtitleStyle.scaleStep,
            marks: SubtitleStyle.marks,
            format: SubtitleStyle.percent,
            onChanged: (v) => _savePlayer(p.copyWith(subtitleScale: v)),
          ),
          SubtitlePreview(settings: p),
          SettingChoiceRow<int>(
            title: l10n.subtitlePosition,
            subtitle: l10n.subtitlePositionHint,
            value: p.subtitleBottomMargin,
            options: {60: l10n.subtitlePositionHigher, 40: l10n.subtitlePositionNormal, 20: l10n.subtitlePositionLow, 4: l10n.subtitlePositionBottom},
            onChanged: (v) => _savePlayer(p.copyWith(subtitleBottomMargin: v)),
          ),
          SettingToggleRow(
            title: l10n.subtitleBackground,
            subtitle: l10n.subtitleBackgroundHint,
            value: p.subtitleBackground,
            onChanged: (v) => _savePlayer(p.copyWith(subtitleBackground: v)),
          ),
          SettingChoiceRow<double>(
            title: l10n.backgroundOpacity,
            subtitle: p.subtitleBackground ? null : l10n.backgroundOpacityHint,
            value: p.subtitleBackgroundOpacity,
            options: {0.25: l10n.opacityLight(25), 0.4: '40%', 0.6: l10n.opacityMedium(60), 0.75: '75%', 0.9: l10n.opacityDark(90)},
            onChanged: (v) => _savePlayer(p.copyWith(subtitleBackgroundOpacity: v)),
          ),
          SettingToggleRow(title: l10n.restyleAss, subtitle: l10n.restyleAssHint,
              value: p.overrideAssStyles, onChanged: (v) => _savePlayer(p.copyWith(overrideAssStyles: v))),
        ];
      case _Section.languages:
        return [
          SettingChoiceRow<String>(
            title: l10n.appLanguage,
            value: app.uiLanguage,
            options: {'': l10n.systemLanguage, ...uiLanguages},
            onChanged: (v) => services.updateSettings(app.copyWith(uiLanguage: v)),
          ),
          SettingHeader(l10n.settingsGroupPlaybackLanguages),
          SettingChoiceRow<String>(
            title: l10n.preferredAudioLanguage,
            value: p.preferredAudioLanguage,
            options: languages,
            onChanged: (v) => _savePlayer(p.copyWith(preferredAudioLanguage: v)),
          ),
          SettingChoiceRow<String>(
            title: l10n.preferredSubtitleLanguage,
            value: p.preferredSubtitleLanguage,
            options: languages,
            onChanged: (v) => _savePlayer(p.copyWith(preferredSubtitleLanguage: v)),
          ),
          SettingHeader(l10n.settingsGroupContentLanguages),
          SettingChoiceRow<String>(
            title: l10n.metadataLanguage,
            subtitle: services.tmdb == null && app.metadataLanguage.isNotEmpty
                ? l10n.metadataLanguageNeedsKey
                : l10n.metadataLanguageHint,
            value: app.metadataLanguage,
            options: {...metadataLanguages, '': l10n.metadataFromServer},
            onChanged: (v) => services.updateSettings(app.copyWith(metadataLanguage: v)),
          ),
          if (TrailerPlayer.supported)
            SettingChoiceRow<String>(
              title: l10n.trailerLanguage,
              subtitle: l10n.trailerLanguageHint,
              value: app.trailerLanguage,
              options: {
                '': l10n.trailerLanguageOriginal,
                for (final e in metadataLanguages.entries)
                  if (e.key.isNotEmpty && e.key != 'en-US') e.key: e.value,
              },
              onChanged: (v) => services.updateSettings(app.copyWith(trailerLanguage: v)),
            ),
        ];
      case _Section.interface:
        return [
          if (Host.isWindows)
            SettingToggleRow(
              title: l10n.startFullScreen,
              value: app.startFullScreen,
              onChanged: (v) => services.updateSettings(app.copyWith(startFullScreen: v)),
            ),
          SettingToggleRow(title: l10n.navigationSounds, value: app.sounds, onChanged: (v) => services.updateSettings(app.copyWith(sounds: v))),
          SettingHeader(l10n.settingsGroupLayout),
          SettingChoiceRow<LibraryView>(
            title: l10n.libraryViewSetting,
            value: app.libraryView,
            options: {LibraryView.posters: l10n.viewPosters, LibraryView.cards: l10n.viewCards, LibraryView.list: l10n.viewList},
            onChanged: (v) => services.updateSettings(app.copyWith(libraryView: v)),
          ),
          SettingChoiceRow<PosterSize>(
            title: l10n.posterSize,
            subtitle: l10n.posterSizeHint,
            value: app.posterSize,
            options: {PosterSize.small: l10n.sizeSmall, PosterSize.medium: l10n.sizeNormal, PosterSize.large: l10n.sizeLarge},
            onChanged: (v) => services.updateSettings(app.copyWith(posterSize: v)),
          ),
          SettingChoiceRow<CollectionsView>(
            title: l10n.collectionsViewSetting,
            value: app.collectionsView,
            options: {CollectionsView.covers: l10n.viewCovers, CollectionsView.wide: l10n.viewWide},
            onChanged: (v) => services.updateSettings(app.copyWith(collectionsView: v)),
          ),
        ];
      case _Section.content:
        return [
          ValueListenableBuilder<bool>(
            valueListenable: MetadataLocalizer.keyRejected,
            builder: (context, rejected, _) => !rejected
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, color: Zc.danger, size: 28),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l10n.tmdbKeyRejected, style: Zt.body.copyWith(color: Zc.danger))),
                    ]),
                  ),
          ),
          SettingHeader(l10n.sectionHome, first: true),
          if (services.isSignedIn)
            SettingActionRow(
              title: l10n.homeCollections,
              subtitle: l10n.homeCollectionsCount(app.homeCollectionsOf(services.janus.session.userId).length),
              icon: Icons.chevron_right_rounded,
              onSelect: () => Navigator.of(context).push(tvRoute<void>(const HomeCollectionsPage(), name: 'settings/home-collections')),
            ),
          SettingToggleRow(
            title: l10n.hideAnimation,
            subtitle: l10n.hideAnimationHint,
            value: app.hideAnimation,
            onChanged: (v) => services.updateSettings(app.copyWith(hideAnimation: v)),
          ),
          if (TrailerPlayer.supported) ...[
            SettingHeader(l10n.trailers),
            SettingChoiceRow<TrailerMode>(
              title: l10n.trailers,
              subtitle: l10n.trailersHint,
              value: app.trailers,
              options: {
                TrailerMode.autoplay: l10n.trailersAutoplay,
                TrailerMode.onRequest: l10n.trailersOnRequest,
                TrailerMode.off: l10n.trailersOff,
              },
              onChanged: (v) => services.updateSettings(app.copyWith(trailers: v)),
            ),
            SettingToggleRow(
              title: l10n.trailerSound,
              subtitle: l10n.trailerSoundHint,
              value: app.trailerSound,
              onChanged: (v) => services.updateSettings(app.copyWith(trailerSound: v)),
            ),
            SettingToggleRow(
              title: l10n.cardTrailers,
              subtitle: l10n.cardTrailersHint,
              value: app.cardTrailers,
              onChanged: (v) => services.updateSettings(app.copyWith(cardTrailers: v)),
            ),
          ],
          SettingHeader(l10n.sectionMetadata),
          SettingActionRow(
            title: l10n.refreshMetadata,
            icon: Icons.refresh_rounded,
            onSelect: () async {
              await MetadataLocalizer.clearCache();
              services.markLibraryChanged();
              if (mounted) _toast(l10n.metadataCleared);
            },
          ),
        ];
      case _Section.services:
        return [
          _intro(l10n.servicesIntro),
          SettingActionRow(
            title: l10n.phoneSetupTitle,
            icon: Icons.qr_code_2_rounded,
            onSelect: () => showRemoteSetupDialog(context),
          ),
          const SettingHeader('TMDB'),
          _intro(l10n.metadataIntro),
          SettingTextRow(
            title: l10n.tmdbApiKey,
            value: app.tmdbApiKey,
            obscure: true,
            hint: l10n.tmdbApiKeyHint,
            onChanged: (v) => services.updateSettings(app.copyWith(tmdbApiKey: v)),
          ),
          SettingActionRow(
            title: l10n.testTmdbKey,
            icon: Icons.wifi_tethering_rounded,
            onSelect: () async {
              final tmdb = services.tmdb;
              final problem = tmdb == null ? l10n.tmdbKeyFirst : await tmdb.check().then((p) => p == null ? null : l10n.tmdbProblem(p));
              if (!mounted) return;
              UiSounds.play(problem == null ? UiSound.select : UiSound.error);
              _toast(problem ?? l10n.tmdbKeyWorks);
            },
          ),
          SettingHeader(l10n.ratingsHeader),
          _intro(l10n.ratingsIntro),
          SettingTextRow(
            title: l10n.mdblistApiKey,
            value: app.mdblistApiKey,
            obscure: true,
            hint: l10n.mdblistApiKeyHint,
            onChanged: (v) => services.updateSettings(app.copyWith(mdblistApiKey: v)),
          ),
          SettingActionRow(
            title: l10n.testMdblistKey,
            icon: Icons.wifi_tethering_rounded,
            onSelect: () async {
              final mdblist = services.mdblist;
              final problem = mdblist == null ? l10n.mdblistKeyFirst : await mdblist.check();
              if (!mounted) return;
              UiSounds.play(problem == null ? UiSound.select : UiSound.error);
              _toast(problem ?? l10n.mdblistKeyWorks);
            },
          ),
          SettingHeader(l10n.sectionRequests),
          _intro(l10n.requestsIntro),
          SettingTextRow(
            title: l10n.seerrAddress,
            value: app.seerrUrl,
            hint: l10n.seerrAddressHint,
            onChanged: (v) => services.updateSettings(app.copyWith(seerrUrl: v)),
          ),
          SettingTextRow(
            title: l10n.seerrApiKey,
            value: app.seerrApiKey,
            obscure: true,
            hint: l10n.seerrApiKeyHint,
            onChanged: (v) => services.updateSettings(app.copyWith(seerrApiKey: v)),
          ),
          SettingActionRow(
            title: l10n.testConnection,
            icon: Icons.wifi_tethering_rounded,
            onSelect: () async {
              final problem = await services.checkSeerr();
              if (!mounted) return;
              UiSounds.play(problem == null ? UiSound.select : UiSound.error);
              _toast(problem == null ? l10n.connected : l10n.seerrProblem(problem));
            },
          ),
          SettingHeader(l10n.automationHeader),
          _intro(l10n.webhookIntro),
          SettingTextRow(
            title: l10n.webhookUrl,
            value: p.webhookUrl,
            hint: 'http://homeassistant.local:8123/api/webhook/zerk_play',
            onChanged: (v) => _savePlayer(p.copyWith(webhookUrl: v.trim())),
          ),
        ];
      case _Section.liveTv:
        return [
          _intro(l10n.liveTvIntro),
          SettingTextRow(
            title: l10n.xtreamServer,
            value: app.xtreamUrl,
            hint: 'http://provider.example:8080',
            onChanged: (v) => services.updateSettings(app.copyWith(xtreamUrl: v)),
          ),
          for (var i = 0; i <= app.xtreamAccounts.length; i++) ...[
            SettingTextRow(
              title: l10n.xtreamAccountUser(i + 1),
              value: i < app.xtreamAccounts.length ? app.xtreamAccounts[i].$1 : '',
              onChanged: (v) => _setXtreamAccount(services, i, user: v),
            ),
            if (i < app.xtreamAccounts.length)
              SettingTextRow(
                title: l10n.xtreamAccountPassword(i + 1),
                value: app.xtreamAccounts[i].$2,
                obscure: true,
                onChanged: (v) => _setXtreamAccount(services, i, password: v),
              ),
          ],
          SettingActionRow(
            title: l10n.testConnection,
            icon: Icons.wifi_tethering_rounded,
            onSelect: () async {
              final server = XtreamServer(app.xtreamUrl, [for (final (u, p) in app.xtreamAccounts) XtreamAccount(u, p)]);
              final statuses = await server.statuses();
              if (!mounted) return;
              UiSounds.play(statuses.isNotEmpty && statuses.every((s) => s.usable) ? UiSound.select : UiSound.error);
              showToast(
                context,
                [
                  for (final s in statuses)
                    s.problem != null
                        ? l10n.xtreamAccountProblem(s.number, s.problem!)
                        : s.free
                            ? l10n.xtreamAccountFree(s.number, s.active, s.max)
                            : l10n.xtreamAccountBusy(s.number, s.active, s.max),
                ].join('\n'),
                duration: const Duration(seconds: 6),
              );
            },
          ),
          SettingHeader(l10n.livePlaylist),
          _intro(l10n.livePlaylistIntro),
          SettingTextRow(
            title: l10n.livePlaylistUrl,
            value: app.playlistUrl,
            hint: 'http://192.168.1.10:8000/api/channels.m3u',
            onChanged: (v) => services.updateSettings(app.copyWith(playlistUrl: v)),
          ),
          SettingTextRow(
            title: l10n.livePlaylistGuide,
            value: app.playlistGuideUrl,
            hint: 'http://192.168.1.10:8000/api/xmltv.xml',
            onChanged: (v) => services.updateSettings(app.copyWith(playlistGuideUrl: v)),
          ),
          SettingActionRow(
            title: l10n.testConnection,
            icon: Icons.wifi_tethering_rounded,
            onSelect: () async {
              String message;
              try {
                final res = await http.get(Uri.parse(app.playlistUrl.trim())).timeout(const Duration(seconds: 12));
                if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
                final found = parseM3u(utf8.decode(res.bodyBytes, allowMalformed: true), res.request!.url);
                message = l10n.livePlaylistFound(found.channels.length);
              } catch (e) {
                message = l10n.livePlaylistProblem('$e');
              }
              if (!mounted) return;
              UiSounds.play(UiSound.select);
              _toast(message);
            },
          ),
        ];
      case _Section.diagnostics:
        return [
          _intro(l10n.logsIntro),
          if (Host.isWindows)
            SettingToggleRow(
              title: l10n.detailedLog,
              subtitle: l10n.detailedLogHint,
              value: p.detailedLog,
              onChanged: (v) => _savePlayer(p.copyWith(detailedLog: v)),
            ),
          SettingActionRow(title: l10n.openLogsFolder, icon: Icons.folder_open_rounded, onSelect: AppLog.openFolder),
          SettingActionRow(
            title: l10n.checkForUpdates,
            icon: Icons.system_update_rounded,
            onSelect: () => checkForUpdate(context, quiet: false),
          ),
          const SizedBox(height: 20),
          Text(l10n.appVersionLabel(Release.name), style: Zt.title),
          const SizedBox(height: 8),
          Text(AppLog.appVersion, style: Zt.caption),
          if (AppLog.file != null) ...[
            const SizedBox(height: 8),
            Text(AppLog.file!, style: Zt.caption),
          ],
        ];
      case _Section.account:
        final session = services.janus.session;
        return [
          Text(session.serverUrl.toString(), style: Zt.title),
          const SizedBox(height: 8),
          Text(l10n.signedInOnDevice, style: Zt.body),
          const SizedBox(height: 30),
          SettingToggleRow(
            title: l10n.allowSelfSigned,
            subtitle: l10n.allowSelfSignedHint,
            value: app.acceptInvalidCertificates,
            onChanged: (v) => services.updateSettings(app.copyWith(acceptInvalidCertificates: v)),
          ),
          SettingActionRow(title: l10n.signOut, icon: Icons.logout_rounded, onSelect: () => services.signOut()),
          SettingActionRow(title: l10n.exitApp, icon: Icons.power_settings_new_rounded, onSelect: () => confirmExit(context)),
        ];
    }
  }

  void _toast(String text) => showToast(context, text);

  void _setXtreamAccount(AppServices services, int i, {String? user, String? password}) {
    final list = [...services.settings.xtreamAccounts];
    final current = i < list.length ? list[i] : ('', '');
    final next = (user ?? current.$1, password ?? current.$2);
    if (i < list.length) {
      list[i] = next;
    } else {
      list.add(next);
    }
    list.removeWhere((a) => a.$1.trim().isEmpty && a.$2.isEmpty);
    services.updateSettings(services.settings.copyWith(xtreamAccounts: list));
  }
}

class _AdvancedIntro extends StatelessWidget {
  const _AdvancedIntro(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Text(text, style: Zt.body));
}

class _AdvancedVideoPage extends StatefulWidget {
  const _AdvancedVideoPage({required this.initial});

  final PlayerSettings initial;

  @override
  State<_AdvancedVideoPage> createState() => _AdvancedVideoPageState();
}

class _AdvancedVideoPageState extends State<_AdvancedVideoPage> {
  late PlayerSettings _p = widget.initial;

  Future<void> _save(PlayerSettings next) async {
    setState(() => _p = next);
    await next.save();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = _p;
    return Padding(
      padding: const EdgeInsets.only(left: contentLeft, top: 90, right: 120),
      child: SizedBox(
        width: 1100,
        child: FocusZone(
          debugLabel: 'settings-advanced-video',
          autofocus: true,
          child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
            Text(l10n.advancedVideo, style: Zt.headline),
            const SizedBox(height: 12),
            Text(l10n.videoIntro, style: Zt.body),
            const SizedBox(height: 30),
            SettingChoiceRow<String>(
              title: l10n.toneMapping,
              subtitle: l10n.toneMappingHint,
              value: p.toneMapping,
              options: {
                'auto': l10n.toneMappingAuto,
                'bt.2390': 'BT.2390',
                'spline': 'Spline',
                'st2094-40': 'ST 2094-40',
                'hable': 'Hable',
                'mobius': 'Mobius',
                'reinhard': 'Reinhard',
                'clip': 'Clip',
              },
              onChanged: (v) => _save(p.copyWith(toneMapping: v)),
            ),
            SettingToggleRow(title: l10n.deband, subtitle: l10n.debandHint,
                value: p.deband, onChanged: (v) => _save(p.copyWith(deband: v))),
            SettingToggleRow(title: l10n.smoothMotion, subtitle: l10n.smoothMotionHint,
                value: p.smoothMotion, onChanged: (v) => _save(p.copyWith(smoothMotion: v))),
            SettingChoiceRow<String>(
              title: l10n.videoRenderer,
              value: p.videoOutput,
              options: {'gpu-next': l10n.videoRendererNext, 'gpu': l10n.videoRendererOld},
              onChanged: (v) => _save(p.copyWith(videoOutput: v)),
            ),
            if (Host.isWindows) ...[
              SettingHeader(l10n.displayTarget),
              _AdvancedIntro(l10n.displayTargetHint),
              SettingChoiceRow<String>(
                title: l10n.targetPrimaries,
                value: p.targetPrim,
                options: {
                  'auto': l10n.targetAuto,
                  'bt.709': 'BT.709 / sRGB',
                  'dci-p3': 'DCI-P3',
                  'display-p3': 'Display P3',
                  'bt.2020': 'BT.2020',
                  'adobe': 'Adobe RGB',
                },
                onChanged: (v) => _save(p.copyWith(targetPrim: v)),
              ),
              SettingChoiceRow<String>(
                title: l10n.targetTransfer,
                value: p.targetTrc,
                options: {
                  'auto': l10n.targetAuto,
                  'bt.1886': 'BT.1886',
                  'srgb': 'sRGB',
                  'gamma2.2': 'Gamma 2.2',
                  'gamma2.4': 'Gamma 2.4',
                  'pq': 'PQ (HDR10)',
                  'hlg': 'HLG',
                },
                onChanged: (v) => _save(p.copyWith(targetTrc: v)),
              ),
              SettingChoiceRow<int>(
                title: l10n.targetPeak,
                subtitle: l10n.targetPeakHint,
                value: p.targetPeak,
                options: {0: l10n.targetAuto, for (final n in const [48, 100, 120, 150, 200, 300, 400, 600, 800, 1000, 1500, 2000, 4000]) n: '$n nits'},
                onChanged: (v) => _save(p.copyWith(targetPeak: v)),
              ),
            ],
            if (MpvConf.supported) ...[
              const SettingHeader('mpv.conf'),
              SettingActionRow(
                title: l10n.editMpvConf,
                icon: Icons.edit_note_rounded,
                onSelect: () async {
                  await MpvConf.edit();
                  if (context.mounted) showToast(context, l10n.mpvConfOpened);
                },
              ),
              SettingActionRow(title: l10n.openSettingsFolder, icon: Icons.folder_open_rounded, onSelect: MpvConf.openFolder),
              SettingToggleRow(title: l10n.mpvConfOnly, subtitle: l10n.mpvConfOnlyHint,
                  value: p.mpvConfOnly, onChanged: (v) => _save(p.copyWith(mpvConfOnly: v))),
            ],
          ]),
        ),
      ),
    );
  }
}
