import '../core/emby/models/media_source.dart';
import '../l10n/app_localizations.dart';
import 'emby_playback_api.dart';
import 'media3/osd_model.dart';
import 'track_labels.dart';
import 'versions.dart';

abstract final class PlaybackInfo {
  static List<OsdChoice> rows(
    L10n l10n, {
    required MediaSourceInfo source,
    required PlayMethod method,
    String? transcodeReasons,
    MediaStream? audio,
    MediaStream? subtitle,
  }) {
    final video = source.video;
    final reasons = method == PlayMethod.transcode ? reasonLabels(l10n, transcodeReasons) : const <String>[];
    final fps = frameRate(video?.frameRate);
    final range = dynamicRange(source, l10n.infoProfile);
    final audioTrack = audio == null
        ? null
        : join([
            audio.displayLanguage != null || audio.language != null ? TrackLabels.title(audio, l10n) : null,
            sampleRate(audio.sampleRate),
            bitrate(audio.bitRate),
          ]);
    final rows = <(String, String?)>[
      (l10n.infoPlayback, switch (method) {
        PlayMethod.directPlay => l10n.infoDirectPlay,
        PlayMethod.directStream => l10n.infoDirectStream,
        PlayMethod.transcode => l10n.infoTranscoding,
      }),
      (l10n.infoTranscodeReason, join(reasons, separator: ', ')),
      (l10n.infoContainer, source.container?.toUpperCase().replaceAll(',', ' / ')),
      (l10n.infoFile, source.path?.split(RegExp(r'[\\/]')).last),
      if (video != null) ...[
        (l10n.infoVideo, join([VersionInfo(source).codec, video.profile, level(video.codecLower, video.level)])),
        (l10n.infoResolution, join([
          if (video.width != null && video.height != null) '${video.width}×${video.height}',
          if (fps != null) '$fps fps',
          if (video.bitDepth != null) '${video.bitDepth}-bit',
          if (video.isInterlaced) l10n.infoInterlaced,
        ])),
        (l10n.infoDynamicRange, range ?? 'SDR'),
        (l10n.infoVideoBitrate, bitrate(video.bitRate)),
      ],
      if (audio != null) ...[
        (l10n.audio, join([TrackLabels.audioCodec(audio), channelLayout(audio)])),
        (l10n.infoAudioTrack, audioTrack),
      ],
      (l10n.subtitles, subtitle == null
          ? l10n.subtitleOff
          : join([
              TrackLabels.subtitleCodec(subtitle, l10n),
              subtitle.displayLanguage != null || subtitle.language != null ? TrackLabels.title(subtitle, l10n) : null,
              if (subtitle.deliveryMethod == SubtitleDeliveryMethod.encode)
                l10n.infoBurnedIn
              else if (subtitle.isExternal)
                l10n.trackExternal,
            ])),
    ];
    return [
      for (final (label, value) in rows)
        if (value != null && value.isNotEmpty) OsdChoice(id: label, label: label, detail: value),
    ];
  }

  static String? join(List<String?> parts, {String separator = '  ·  '}) {
    final shown = parts.whereType<String>().where((p) => p.isNotEmpty).toList();
    return shown.isEmpty ? null : shown.join(separator);
  }

  static String? bitrate(int? bitsPerSecond) {
    if (bitsPerSecond == null || bitsPerSecond <= 0) return null;
    if (bitsPerSecond < 1000000) return '${(bitsPerSecond / 1000).round()} kbps';
    final mbps = bitsPerSecond / 1e6;
    return '${mbps.toStringAsFixed(mbps >= 20 ? 0 : 1)} Mbps';
  }

  static String? sampleRate(int? hertz) {
    if (hertz == null || hertz <= 0) return null;
    final khz = hertz / 1000;
    return '${khz.toStringAsFixed(hertz % 1000 == 0 ? 0 : 1)} kHz';
  }

  static String? frameRate(double? fps) {
    if (fps == null || fps <= 0) return null;
    final text = fps.toStringAsFixed(3);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  static String? level(String codec, double? level) {
    if (level == null || level <= 0) return null;
    final divisor = switch (codec) {
      'h264' || 'avc' => 10,
      'hevc' || 'h265' => 30,
      _ => 0,
    };
    if (divisor == 0) return null;
    return 'L${(level / divisor).toStringAsFixed(1)}';
  }

  static String? channelLayout(MediaStream s) {
    final layout = s.channelLayout?.toLowerCase().replaceAll(RegExp(r'\(.*\)'), '').trim();
    if (layout != null && RegExp(r'^\d(\.\d)?$').hasMatch(layout)) return layout.contains('.') ? layout : '$layout.0';
    return switch (layout) {
      'mono' => 'Mono',
      'stereo' => 'Stereo',
      _ => TrackLabels.channels(s),
    };
  }

  static String? dolbyVisionProfile(MediaStream v) {
    final digits = RegExp(r'DoviProfile(\d+)').firstMatch(v.extendedVideoSubType ?? '')?.group(1);
    if (digits == null) return null;
    if (digits.length < 2) return digits;
    final compatibility = digits.substring(digits.length - 1);
    final profile = digits.substring(0, digits.length - 1);
    return compatibility == '0' ? profile : '$profile.$compatibility';
  }

  static String? dynamicRange(MediaSourceInfo source, String profileWord) {
    final hdr = VersionInfo(source).hdr;
    final video = source.video;
    if (hdr == null || video == null) return null;
    final profile = hdr == 'Dolby Vision' ? dolbyVisionProfile(video) : null;
    return profile == null ? hdr : '$hdr  ·  $profileWord $profile';
  }

  static List<String> reasonLabels(L10n l10n, String? raw) {
    final labels = <String>[];
    for (final reason in (raw ?? '').split(',')) {
      final label = reasonLabel(l10n, reason.trim());
      if (label != null && !labels.contains(label)) labels.add(label);
    }
    return labels;
  }

  static String? reasonLabel(L10n l10n, String reason) {
    if (reason.isEmpty) return null;
    return switch (reason) {
      'ContainerNotSupported' => l10n.reasonContainer,
      'VideoResolutionNotSupported' => l10n.reasonVideoResolution,
      'ContainerBitrateExceedsLimit' || 'VideoBitrateNotSupported' || 'AudioBitrateNotSupported' => l10n.reasonBitrate,
      'DirectPlayError' => l10n.reasonDirectPlayError,
      'SecondaryAudioNotSupported' || 'AudioIsExternal' => l10n.reasonAudioTracks,
      _ when reason.contains('Video') || reason == 'RefFramesNotSupported' => l10n.reasonVideoCodec,
      _ when reason.contains('Audio') => l10n.reasonAudioCodec,
      _ when reason.contains('Subtitle') => l10n.reasonSubtitle,
      _ => reason.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' '),
    };
  }
}
