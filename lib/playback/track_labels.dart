import '../core/emby/models/media_source.dart';
import '../l10n/app_localizations.dart';
import 'language.dart';

abstract final class TrackLabels {
  static String title(MediaStream s, L10n l10n) {
    final lang = s.displayLanguage ?? _languageName(s.language);
    if (lang != null && lang.isNotEmpty) return lang;
    if (s.title != null && s.title!.isNotEmpty) return s.title!;
    return l10n.trackNumber(s.index);
  }

  static String detail(MediaStream s, L10n l10n) {
    final parts = <String>[];
    if (s.type == MediaStreamType.audio) {
      parts.add(audioCodec(s));
      final ch = channels(s);
      if (ch != null) parts.add(ch);
    } else {
      parts.add(subtitleCodec(s, l10n));
    }
    final t = s.title;
    if (t != null && t.isNotEmpty && t != title(s, l10n) && !_isRedundant(t, s)) parts.add(t);
    if (s.isForced) parts.add(l10n.trackForced);
    if (s.isDefault) parts.add(l10n.trackDefault);
    if (s.isExternal) parts.add(l10n.trackExternal);
    return parts.join('  ·  ');
  }

  static String audioCodec(MediaStream s) {
    final c = s.codecLower;
    final hint = '${s.profile ?? ''} ${s.title ?? ''} ${s.displayTitle ?? ''}'.toLowerCase();
    final atmos = hint.contains('atmos');
    return switch (c) {
      'truehd' => atmos ? 'TrueHD Atmos' : 'Dolby TrueHD',
      'eac3' => atmos ? 'Dolby Digital+ Atmos' : 'Dolby Digital+',
      'ac3' => 'Dolby Digital',
      'dts' || 'dca' => hint.contains('dts:x') || hint.contains('dts-x')
          ? 'DTS:X'
          : hint.contains('ma')
              ? 'DTS-HD MA'
              : hint.contains('hra') || hint.contains('hi res')
                  ? 'DTS-HD HRA'
                  : 'DTS',
      'aac' => 'AAC',
      'flac' => 'FLAC',
      'opus' => 'Opus',
      'vorbis' => 'Vorbis',
      'mp3' => 'MP3',
      'mp2' => 'MP2',
      'alac' => 'ALAC',
      _ when c.startsWith('pcm') => 'PCM',
      _ => c.toUpperCase(),
    };
  }

  static String? channels(MediaStream s) {
    final n = s.channels;
    if (n == null || n <= 0) return null;
    return switch (n) {
      1 => 'Mono',
      2 => 'Stereo',
      3 => '2.1',
      6 => '5.1',
      7 => '6.1',
      8 => '7.1',
      _ => '$n ch',
    };
  }

  static String subtitleCodec(MediaStream s, L10n l10n) => switch (s.codecLower) {
        'subrip' || 'srt' => 'SRT',
        'ass' || 'ssa' => 'ASS',
        'pgssub' || 'pgs' => 'PGS',
        'dvdsub' || 'vobsub' => 'VobSub',
        'dvbsub' => 'DVB',
        'webvtt' || 'vtt' => 'WebVTT',
        'mov_text' => l10n.trackText,
        '' => l10n.subtitles,
        final c => c.toUpperCase(),
      };

  static bool _isRedundant(String title, MediaStream s) {
    final t = title.toLowerCase();
    return t == (s.language ?? '').toLowerCase() || t == (s.displayLanguage ?? '').toLowerCase();
  }

  static String? _languageName(String? code) => _names[normalizeLanguage(code)];

  static const _names = {
    'en': 'English', 'ro': 'Romanian', 'fr': 'French', 'de': 'German', 'es': 'Spanish',
    'it': 'Italian', 'pt': 'Portuguese', 'ja': 'Japanese', 'zh': 'Chinese', 'ko': 'Korean',
    'nl': 'Dutch', 'no': 'Norwegian', 'nb': 'Norwegian', 'da': 'Danish', 'fi': 'Finnish',
    'sv': 'Swedish', 'pl': 'Polish', 'ru': 'Russian', 'uk': 'Ukrainian', 'cs': 'Czech',
    'sk': 'Slovak', 'hu': 'Hungarian', 'el': 'Greek', 'tr': 'Turkish', 'ar': 'Arabic',
    'he': 'Hebrew', 'hi': 'Hindi', 'th': 'Thai', 'vi': 'Vietnamese', 'id': 'Indonesian',
    'bg': 'Bulgarian', 'hr': 'Croatian', 'sr': 'Serbian', 'sl': 'Slovenian',
  };
}
