import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'subtitle_style.dart';

enum SubtitleMode {
  off,

  smart,

  forced,

  always,
}

enum PassthroughCodec { ac3, eac3, dts, dtshd, truehd }

enum VideoQuality {
  fast,

  balanced,

  high,
}

final class PlayerSettings {
  const PlayerSettings({
    this.preferredAudioLanguage = '',
    this.preferredSubtitleLanguage = '',
    this.subtitleMode = SubtitleMode.smart,
    this.maxStreamingBitrate = 0,
    this.passthrough = const {},
    this.audioExclusive = false,
    this.hdrPassthrough = true,
    this.autoHdr = true,
    this.matchRefreshRate = false,
    this.smoothMotion = false,
    this.subtitleScale = 1.0,
    this.subtitleBottomMargin = 40,
    this.overrideAssStyles = false,
    this.subtitleBackground = false,
    this.subtitleBackgroundOpacity = 0.6,
    this.volume = 100,
    this.skipIntroAutomatically = false,
    this.autoPlayNextEpisode = true,
    this.seekForwardSeconds = 10,
    this.seekBackSeconds = 10,
    this.keepRefreshRate = false,
    this.keepHdr = false,
    this.hwdec = 'auto-safe',
    this.videoQuality = VideoQuality.balanced,
    this.toneMapping = 'auto',
    this.deband = false,
    this.videoOutput = 'gpu-next',
    this.detailedLog = true,
    this.scopeScreen = 0,
    this.autoCrop = false,
    this.defaultAspect = 'auto',
    this.anamorphic = 1.0,
    this.targetPrim = 'auto',
    this.targetTrc = 'auto',
    this.targetPeak = 0,
    this.webhookUrl = '',
    this.mpvConfOnly = false,
  });

  final String preferredAudioLanguage;
  final String preferredSubtitleLanguage;
  final SubtitleMode subtitleMode;

  final int maxStreamingBitrate;
  final Set<PassthroughCodec> passthrough;

  final bool audioExclusive;

  final bool hdrPassthrough;

  final bool autoHdr;

  final bool matchRefreshRate;

  final bool smoothMotion;
  final double subtitleScale;
  final int subtitleBottomMargin;

  final bool overrideAssStyles;

  final bool subtitleBackground;

  final double subtitleBackgroundOpacity;
  final double volume;
  final bool skipIntroAutomatically;
  final bool autoPlayNextEpisode;
  final int seekForwardSeconds;
  final int seekBackSeconds;

  final bool keepRefreshRate;

  final bool keepHdr;

  final String hwdec;
  final VideoQuality videoQuality;

  final String toneMapping;
  final bool deband;

  final String videoOutput;

  final bool detailedLog;

  final double scopeScreen;

  final bool autoCrop;

  final String defaultAspect;

  final double anamorphic;

  final String targetPrim;
  final String targetTrc;
  final int targetPeak;

  final String webhookUrl;

  final bool mpvConfOnly;

  String get mpvSpdif => [
        if (passthrough.contains(PassthroughCodec.ac3)) 'ac3',
        if (passthrough.contains(PassthroughCodec.eac3)) 'eac3',
        if (passthrough.contains(PassthroughCodec.dts)) 'dts',
        if (passthrough.contains(PassthroughCodec.dtshd)) 'dts-hd',
        if (passthrough.contains(PassthroughCodec.truehd)) 'truehd',
      ].join(',');

  PlayerSettings copyWith({
    String? preferredAudioLanguage,
    String? preferredSubtitleLanguage,
    SubtitleMode? subtitleMode,
    int? maxStreamingBitrate,
    Set<PassthroughCodec>? passthrough,
    bool? audioExclusive,
    bool? hdrPassthrough,
    bool? autoHdr,
    bool? matchRefreshRate,
    bool? smoothMotion,
    double? subtitleScale,
    int? subtitleBottomMargin,
    bool? overrideAssStyles,
    bool? subtitleBackground,
    double? subtitleBackgroundOpacity,
    double? volume,
    bool? skipIntroAutomatically,
    bool? autoPlayNextEpisode,
    int? seekForwardSeconds,
    int? seekBackSeconds,
    bool? keepRefreshRate,
    bool? keepHdr,
    String? hwdec,
    VideoQuality? videoQuality,
    String? toneMapping,
    bool? deband,
    String? videoOutput,
    bool? detailedLog,
    double? scopeScreen,
    bool? autoCrop,
    String? defaultAspect,
    double? anamorphic,
    String? targetPrim,
    String? targetTrc,
    int? targetPeak,
    String? webhookUrl,
    bool? mpvConfOnly,
  }) {
    return PlayerSettings(
      preferredAudioLanguage: preferredAudioLanguage ?? this.preferredAudioLanguage,
      preferredSubtitleLanguage: preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      subtitleMode: subtitleMode ?? this.subtitleMode,
      maxStreamingBitrate: maxStreamingBitrate ?? this.maxStreamingBitrate,
      passthrough: passthrough ?? this.passthrough,
      audioExclusive: audioExclusive ?? this.audioExclusive,
      hdrPassthrough: hdrPassthrough ?? this.hdrPassthrough,
      autoHdr: autoHdr ?? this.autoHdr,
      matchRefreshRate: matchRefreshRate ?? this.matchRefreshRate,
      smoothMotion: smoothMotion ?? this.smoothMotion,
      subtitleScale: subtitleScale ?? this.subtitleScale,
      subtitleBottomMargin: subtitleBottomMargin ?? this.subtitleBottomMargin,
      overrideAssStyles: overrideAssStyles ?? this.overrideAssStyles,
      subtitleBackground: subtitleBackground ?? this.subtitleBackground,
      subtitleBackgroundOpacity: subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
      volume: volume ?? this.volume,
      skipIntroAutomatically: skipIntroAutomatically ?? this.skipIntroAutomatically,
      autoPlayNextEpisode: autoPlayNextEpisode ?? this.autoPlayNextEpisode,
      seekForwardSeconds: seekForwardSeconds ?? this.seekForwardSeconds,
      seekBackSeconds: seekBackSeconds ?? this.seekBackSeconds,
      keepRefreshRate: keepRefreshRate ?? this.keepRefreshRate,
      keepHdr: keepHdr ?? this.keepHdr,
      hwdec: hwdec ?? this.hwdec,
      videoQuality: videoQuality ?? this.videoQuality,
      toneMapping: toneMapping ?? this.toneMapping,
      deband: deband ?? this.deband,
      videoOutput: videoOutput ?? this.videoOutput,
      detailedLog: detailedLog ?? this.detailedLog,
      scopeScreen: scopeScreen ?? this.scopeScreen,
      autoCrop: autoCrop ?? this.autoCrop,
      defaultAspect: defaultAspect ?? this.defaultAspect,
      anamorphic: anamorphic ?? this.anamorphic,
      targetPrim: targetPrim ?? this.targetPrim,
      targetTrc: targetTrc ?? this.targetTrc,
      targetPeak: targetPeak ?? this.targetPeak,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      mpvConfOnly: mpvConfOnly ?? this.mpvConfOnly,
    );
  }

  Map<String, Object?> toJson() => {
        'audioLang': preferredAudioLanguage,
        'subLang': preferredSubtitleLanguage,
        'subMode': subtitleMode.name,
        'maxBitrate': maxStreamingBitrate,
        'passthrough': passthrough.map((c) => c.name).toList(),
        'exclusive': audioExclusive,
        'hdr': hdrPassthrough,
        'autoHdr': autoHdr,
        'matchHz': matchRefreshRate,
        'smooth': smoothMotion,
        'subScale': subtitleScale,
        'subMargin': subtitleBottomMargin,
        'assOverride': overrideAssStyles,
        'subBg': subtitleBackground,
        'subBgOpacity': subtitleBackgroundOpacity,
        'volume': volume,
        'autoSkipIntro': skipIntroAutomatically,
        'autoNext': autoPlayNextEpisode,
        'seekForward': seekForwardSeconds,
        'seekBack': seekBackSeconds,
        'keepHz': keepRefreshRate,
        'keepHdr': keepHdr,
        'hwdec': hwdec,
        'quality': videoQuality.name,
        'toneMapping': toneMapping,
        'deband': deband,
        'vo': videoOutput,
        'detailedLog': detailedLog,
        'scope': scopeScreen,
        'autoCrop': autoCrop,
        'aspect': defaultAspect,
        'anamorphic': anamorphic,
        'targetPrim': targetPrim,
        'targetTrc': targetTrc,
        'targetPeak': targetPeak,
        'webhook': webhookUrl,
        'mpvConfOnly': mpvConfOnly,
      };

  factory PlayerSettings.fromJson(Map<String, dynamic> j) {
    const d = PlayerSettings();
    T pick<T>(String key, T fallback) {
      final v = j[key];
      if (v is T) return v;
      if (T == double && v is num) return v.toDouble() as T;
      if (T == int && v is num) return v.toInt() as T;
      return fallback;
    }

    final rawPass = j['passthrough'];
    return PlayerSettings(
      preferredAudioLanguage: pick('audioLang', d.preferredAudioLanguage),
      preferredSubtitleLanguage: pick('subLang', d.preferredSubtitleLanguage),
      subtitleMode: SubtitleMode.values.asNameMap()[j['subMode']] ?? d.subtitleMode,
      maxStreamingBitrate: pick('maxBitrate', d.maxStreamingBitrate),
      passthrough: rawPass is List
          ? {for (final n in rawPass) ?PassthroughCodec.values.asNameMap()[n]}
          : d.passthrough,
      audioExclusive: pick('exclusive', d.audioExclusive),
      hdrPassthrough: pick('hdr', d.hdrPassthrough),
      autoHdr: pick('autoHdr', d.autoHdr),
      matchRefreshRate: pick('matchHz', d.matchRefreshRate),
      smoothMotion: pick('smooth', d.smoothMotion),
      subtitleScale: pick('subScale', d.subtitleScale).clamp(SubtitleStyle.minScale, SubtitleStyle.maxScale),
      subtitleBottomMargin: pick('subMargin', d.subtitleBottomMargin),
      overrideAssStyles: pick('assOverride', d.overrideAssStyles),
      subtitleBackground: pick('subBg', d.subtitleBackground),
      subtitleBackgroundOpacity: pick('subBgOpacity', d.subtitleBackgroundOpacity),
      volume: pick('volume', d.volume),
      skipIntroAutomatically: pick('autoSkipIntro', d.skipIntroAutomatically),
      autoPlayNextEpisode: pick('autoNext', d.autoPlayNextEpisode),
      seekForwardSeconds: pick('seekForward', pick('seekStep', d.seekForwardSeconds)),
      seekBackSeconds: pick('seekBack', pick('seekStep', d.seekBackSeconds)),
      keepRefreshRate: pick('keepHz', d.keepRefreshRate),
      keepHdr: pick('keepHdr', d.keepHdr),
      hwdec: pick('hwdec', d.hwdec),
      videoQuality: VideoQuality.values.asNameMap()[j['quality']] ?? d.videoQuality,
      toneMapping: pick('toneMapping', d.toneMapping),
      deband: pick('deband', d.deband),
      videoOutput: pick('vo', d.videoOutput),
      detailedLog: pick('detailedLog', d.detailedLog),
      scopeScreen: pick('scope', d.scopeScreen),
      autoCrop: pick('autoCrop', d.autoCrop),
      defaultAspect: pick('aspect', d.defaultAspect),
      anamorphic: pick('anamorphic', d.anamorphic),
      targetPrim: pick('targetPrim', d.targetPrim),
      targetTrc: pick('targetTrc', d.targetTrc),
      targetPeak: pick('targetPeak', d.targetPeak),
      webhookUrl: pick('webhook', d.webhookUrl),
      mpvConfOnly: pick('mpvConfOnly', d.mpvConfOnly),
    );
  }

  static const _key = 'player.settings.v2';

  static Future<PlayerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const PlayerSettings();
    try {
      return PlayerSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PlayerSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }
}
