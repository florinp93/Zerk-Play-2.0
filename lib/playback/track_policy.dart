import '../core/emby/models/media_source.dart';
import 'language.dart';
import 'player_settings.dart';

final class TrackChoice {
  const TrackChoice({this.audioIndex, this.subtitleIndex});

  final int? audioIndex;

  final int? subtitleIndex;
}

final class StickyLanguages {
  StickyLanguages({this.audio, this.subtitle, this.subtitleForced = false, this.subtitlesOff = false});

  String? audio;
  String? subtitle;
  bool subtitleForced;
  bool subtitlesOff;
}

abstract final class TrackPolicy {
  static TrackChoice choose(
    MediaSourceInfo source,
    PlayerSettings settings, {
    StickyLanguages? sticky,
  }) {
    final audio = _chooseAudio(source, sticky?.audio ?? settings.preferredAudioLanguage);
    final audioLang = normalizeLanguage(audio?.language);

    if (sticky != null && (sticky.subtitle != null || sticky.subtitlesOff)) {
      final sub = sticky.subtitlesOff
          ? _forcedFor(source, audioLang)
          : sticky.subtitleForced
              ? _forcedIn(source, sticky.subtitle!) ?? _forcedFor(source, audioLang)
              : _firstInLanguage(source, sticky.subtitle!, preferForced: false) ?? _forcedFor(source, audioLang);
      return TrackChoice(audioIndex: audio?.index, subtitleIndex: sub?.index);
    }

    final sub = switch (settings.subtitleMode) {
      SubtitleMode.off => null,
      SubtitleMode.forced => _forcedFor(source, audioLang),
      SubtitleMode.always => _preferredSubtitle(source, settings.preferredSubtitleLanguage) ??
          _byIndex(source, source.defaultSubtitleStreamIndex),
      SubtitleMode.smart => _preferredSubtitle(source, settings.preferredSubtitleLanguage) ??
          _smartSubtitle(source, settings, audioLang),
    };
    return TrackChoice(audioIndex: audio?.index, subtitleIndex: sub?.index);
  }

  static MediaStream? _chooseAudio(MediaSourceInfo source, String preferred) {
    final streams = source.audioStreams;
    if (streams.isEmpty) return null;
    final want = normalizeLanguage(preferred);
    if (want.isNotEmpty) {
      final matches = streams.where((s) => normalizeLanguage(s.language) == want).toList();
      if (matches.isNotEmpty) {
        matches.sort((a, b) {
          if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
          return (b.channels ?? 0).compareTo(a.channels ?? 0);
        });
        return matches.first;
      }
    }
    return _byIndex(source, source.defaultAudioStreamIndex) ??
        streams.firstWhere((s) => s.isDefault, orElse: () => streams.first);
  }

  static MediaStream? _preferredSubtitle(MediaSourceInfo source, String preferred) {
    if (normalizeLanguage(preferred).isEmpty) return null;
    return _firstInLanguage(source, preferred, preferForced: false) ??
        _firstInLanguage(source, 'en', preferForced: false);
  }

  static MediaStream? _smartSubtitle(MediaSourceInfo source, PlayerSettings s, String audioLang) {
    final forced = _forcedFor(source, audioLang);
    if (forced != null) return forced;
    if (normalizeLanguage(s.preferredSubtitleLanguage).isEmpty) {
      return _byIndex(source, source.defaultSubtitleStreamIndex);
    }
    return null;
  }

  static MediaStream? _forcedFor(MediaSourceInfo source, String audioLang) {
    for (final s in source.subtitleStreams) {
      if (!s.isForced) continue;
      final lang = normalizeLanguage(s.language);
      if (lang.isEmpty || lang == audioLang) return s;
    }
    return null;
  }

  static MediaStream? _forcedIn(MediaSourceInfo source, String language) {
    final want = normalizeLanguage(language);
    for (final s in source.subtitleStreams) {
      if (s.isForced && normalizeLanguage(s.language) == want) return s;
    }
    return null;
  }

  static MediaStream? _firstInLanguage(MediaSourceInfo source, String language,
      {required bool preferForced}) {
    final want = normalizeLanguage(language);
    if (want.isEmpty) return null;
    final matches =
        source.subtitleStreams.where((s) => normalizeLanguage(s.language) == want).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      if (a.isForced != b.isForced) return (a.isForced == preferForced) ? -1 : 1;
      if (a.isTextSubtitleStream != b.isTextSubtitleStream) return a.isTextSubtitleStream ? -1 : 1;
      return a.index.compareTo(b.index);
    });
    return matches.first;
  }

  static MediaStream? _byIndex(MediaSourceInfo source, int? index) =>
      index == null || index < 0 ? null : source.streamByIndex(index);
}

abstract final class TrackMatcher {
  static MediaStream? match(MediaStream? previous, List<MediaStream> candidates) {
    if (previous == null || candidates.isEmpty) return null;
    final lang = normalizeLanguage(previous.language);
    MediaStream? best;
    var bestScore = -1 << 30;
    for (final c in candidates) {
      var score = 0;
      final cl = normalizeLanguage(c.language);
      if (lang.isNotEmpty) score += cl == lang ? 1000 : -1000;
      if (c.isForced == previous.isForced) score += 200;
      if (_isSdh(c) == _isSdh(previous)) score += 60;
      if (_isCommentary(c) == _isCommentary(previous)) {
        score += 300;
      } else {
        score -= 300;
      }
      if (c.codecLower == previous.codecLower) score += 20;
      if (c.type == MediaStreamType.subtitle && c.isTextSubtitleStream == previous.isTextSubtitleStream) score += 15;
      if (c.type == MediaStreamType.audio) score -= ((c.channels ?? 2) - (previous.channels ?? 2)).abs() * 5;
      if (c.isDefault) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (lang.isNotEmpty && normalizeLanguage(best?.language) != lang) return null;
    return best;
  }

  static bool _isSdh(MediaStream s) {
    final t = '${s.title ?? ''} ${s.displayTitle ?? ''}'.toLowerCase();
    return t.contains('sdh') || t.contains('hearing') || RegExp(r'\b(cc|hi)\b').hasMatch(t);
  }

  static bool _isCommentary(MediaStream s) {
    final t = '${s.title ?? ''} ${s.displayTitle ?? ''}'.toLowerCase();
    return t.contains('commentary') || t.contains('comentariu');
  }
}
