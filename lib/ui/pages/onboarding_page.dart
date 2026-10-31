import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../data/tmdb_api.dart';
import '../../l10n/l10n.dart';
import '../../playback/language.dart';
import '../../playback/player_settings.dart';
import '../core/navigation.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/remote_setup_panel.dart';
import '../widgets/setting_rows.dart';
import '../widgets/zerk_logo.dart';

enum _Step { language, metadata, requests }

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  static const _steps = [_Step.language, _Step.metadata, _Step.requests];

  static int get stepCount => _steps.length;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _steps = OnboardingPage._steps;
  int _index = 0;
  PlayerSettings? _player;

  bool _subsFollowUi = false;

  bool _useTmdb = true;
  String _tmdbKey = '';
  String _seerrUrl = '';
  String _seerrKey = '';
  String? _error;
  bool _busy = false;

  _Step get _step => _steps[_index];
  bool get _last => _index == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    final app = AppServicesScope.read(context).settings;
    _tmdbKey = app.tmdbApiKey;
    _seerrUrl = app.seerrUrl;
    _seerrKey = app.seerrApiKey;
    PlayerSettings.load().then((p) {
      if (!mounted) return;
      setState(() {
        _subsFollowUi = p.preferredSubtitleLanguage.isEmpty;
        _player = _subsFollowUi ? p.copyWith(preferredSubtitleLanguage: app.resolvedUiLanguage) : p;
      });
    });
  }

  AppServices get _services => AppServicesScope.read(context);

  Future<void> _setUiLanguage(String language) async {
    final player = _player;
    if (_subsFollowUi && player != null) setState(() => _player = player.copyWith(preferredSubtitleLanguage: language));
    await _services.updateSettings(_services.settings.copyWith(uiLanguage: language));
  }

  Future<void> _phoneSetup() async {
    await showRemoteSetupDialog(context);
    final player = await PlayerSettings.load();
    if (!mounted) return;
    final app = _services.settings;
    setState(() {
      _player = player;
      _subsFollowUi = false;
      _useTmdb = app.tmdbMetadataEnabled;
      _tmdbKey = app.tmdbApiKey;
      _seerrUrl = app.seerrUrl;
      _seerrKey = app.seerrApiKey;
    });
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final problem = await _apply(_step);
      if (!mounted) return;
      if (problem != null) {
        UiSounds.play(UiSound.error);
        setState(() => _error = problem);
        return;
      }
      await _next();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _apply(_Step step) async {
    final l10n = context.l10n;
    final app = _services.settings;
    switch (step) {
      case _Step.language:
        await _player?.save();
        return null;
      case _Step.metadata:
        final key = _tmdbKey.trim();
        if (key.isEmpty) {
          if (_useTmdb) return l10n.tmdbKeyMissing;
          await _services.updateSettings(app.copyWith(metadataLanguage: ''));
          return null;
        }
        final problem = await TmdbApi(apiKey: key).check();
        if (problem != null) return l10n.tmdbProblem(problem);
        await _services.updateSettings(
            app.copyWith(tmdbApiKey: key, metadataLanguage: _useTmdb ? app.uiMetadataLanguage : ''));
        return null;
      case _Step.requests:
        final url = _seerrUrl.trim(), key = _seerrKey.trim();
        if (url.isEmpty && key.isEmpty) return null;
        if (url.isEmpty || key.isEmpty) return l10n.seerrIncomplete;
        await _services.updateSettings(app.copyWith(seerrUrl: url, seerrApiKey: key));
        final problem = await _services.checkSeerr();
        return problem == null ? null : l10n.seerrProblem(problem);
    }
  }

  Future<void> _skip() async {
    if (_step == _Step.metadata) await _services.updateSettings(_services.settings.copyWith(metadataLanguage: ''));
    await _next();
  }

  Future<void> _next() async {
    if (_last) {
      UiSounds.play(UiSound.select);
      await _services.updateSettings(_services.settings.copyWith(onboarded: true));
      return;
    }
    setState(() {
      _index++;
      _error = null;
    });
  }

  bool _back() {
    if (_index == 0) return false;
    UiSounds.play(UiSound.back);
    setState(() {
      _index--;
      _error = null;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final app = AppServicesScope.of(context).settings;
    final (title, body) = switch (_step) {
      _Step.language => (l10n.obLanguageTitle, l10n.obLanguageBody),
      _Step.metadata => (l10n.obMetadataTitle, l10n.obMetadataBody(_languageName(l10n, app))),
      _Step.requests => (l10n.obRequestsTitle, l10n.obRequestsBody),
    };
    return Scaffold(
      body: BackHandler(
        onBack: _back,
        child: Stack(children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment(-0.6, -0.6), radius: 1.4, colors: [Color(0xFF221E4A), Zc.background]),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: 1000,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const ZerkLogo(size: 72),
                const SizedBox(height: 30),
                Text(l10n.stepOf(_index + 2, _steps.length + 1), style: Zt.caption.copyWith(color: Zc.accentSoft)),
                const SizedBox(height: 10),
                Text(title, style: Zt.display.copyWith(fontSize: 52)),
                const SizedBox(height: 12),
                Text(body, style: Zt.body),
                const SizedBox(height: 36),
                KeyedSubtree(
                  key: ValueKey(_step),
                  child: FocusZone(
                    debugLabel: 'onboarding-${_step.name}',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _rows(l10n, app)),
                  ),
                ),
                const SizedBox(height: 26),
                FocusZone(
                  debugLabel: 'onboarding-buttons',
                  child: Row(children: [
                    TvButton(
                      label: _busy ? l10n.checking : (_last ? l10n.finish : l10n.continueAction),
                      icon: _last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                      primary: true,
                      onSelect: _continue,
                    ),
                    if (_step != _Step.language) ...[
                      const SizedBox(width: 16),
                      TvButton(label: l10n.skip, onSelect: _skip),
                    ],
                    if (_index > 0) ...[
                      const SizedBox(width: 16),
                      TvButton(label: l10n.back, icon: Icons.arrow_back_rounded, onSelect: _back),
                    ],
                  ]),
                ),
                AnimatedSize(
                  duration: Zm.normal,
                  child: _error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(_error!, style: Zt.body.copyWith(color: Zc.danger)),
                        ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _rows(L10n l10n, AppSettings app) {
    final phone = SettingActionRow(title: l10n.phoneSetupTitle, icon: Icons.qr_code_2_rounded, onSelect: _phoneSetup);
    switch (_step) {
      case _Step.language:
        final player = _player;
        return [
          SettingChoiceRow<String>(
            title: l10n.appLanguage,
            value: app.resolvedUiLanguage,
            options: uiLanguages,
            onChanged: _setUiLanguage,
          ),
          if (player != null)
            SettingChoiceRow<String>(
              title: l10n.preferredSubtitles,
              subtitle: l10n.preferredSubtitlesHint,
              value: player.preferredSubtitleLanguage,
              options: {'': l10n.languageFromFile, ...languageNames},
              onChanged: (v) => setState(() {
                _subsFollowUi = false;
                _player = player.copyWith(preferredSubtitleLanguage: v);
              }),
            ),
        ];
      case _Step.metadata:
        return [
          SettingChoiceRow<bool>(
            title: l10n.metadataSource,
            subtitle: _useTmdb ? l10n.metadataSourceTmdbHint : l10n.metadataSourceEmbyHint,
            value: _useTmdb,
            options: {true: l10n.metadataSourceTmdb(_languageName(l10n, app)), false: l10n.metadataSourceEmby},
            onChanged: (v) => setState(() {
              _useTmdb = v;
              _error = null;
            }),
          ),
          SettingTextRow(
            title: l10n.tmdbApiKey,
            value: _tmdbKey,
            hint: l10n.tmdbApiKeyHint,
            obscure: true,
            onChanged: (v) => setState(() => _tmdbKey = v),
          ),
          phone,
        ];
      case _Step.requests:
        return [
          SettingTextRow(
            title: l10n.seerrAddress,
            value: _seerrUrl,
            hint: l10n.seerrAddressHint,
            onChanged: (v) => setState(() => _seerrUrl = v),
          ),
          SettingTextRow(
            title: l10n.seerrApiKey,
            value: _seerrKey,
            hint: l10n.seerrApiKeyHint,
            obscure: true,
            onChanged: (v) => setState(() => _seerrKey = v),
          ),
          phone,
        ];
    }
  }

  static String _languageName(L10n l10n, AppSettings app) =>
      uiLanguages[app.resolvedUiLanguage] ?? l10n.langEnglish;
}
