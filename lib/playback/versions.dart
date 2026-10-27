import '../core/emby/models/media_source.dart';

final class VersionInfo {
  VersionInfo(this.source);

  final MediaSourceInfo source;

  MediaStream? get _video => source.video;

  String get resolution {
    final h = _video?.height ?? 0;
    final w = _video?.width ?? 0;
    if (w >= 3200 || h >= 1800) return '2160p';
    if (w >= 1800 || h >= 1000) return '1080p';
    if (w >= 1200 || h >= 700) return '720p';
    if (h > 0) return '${h}p';
    return 'SD';
  }

  bool get is4k => resolution == '2160p';

  String? get hdr {
    final v = _video;
    if (v == null) return null;
    final ext = (v.extendedVideoType ?? '').toLowerCase();
    final range = (v.videoRange ?? '').toLowerCase();
    if (ext.contains('dolbyvision') || range.contains('dolby') || range.contains('dovi')) return 'Dolby Vision';
    if (ext.contains('hdr10plus') || range.contains('hdr10+')) return 'HDR10+';
    if (ext.contains('hyperloggamma') || range.contains('hlg')) return 'HLG';
    if (ext.contains('hdr10') || range.contains('hdr')) return 'HDR10';
    return null;
  }

  String? get bestAudio {
    MediaStream? best;
    var bestScore = -1;
    for (final a in source.audioStreams) {
      final s = _audioScore(a);
      if (s > bestScore) {
        best = a;
        bestScore = s;
      }
    }
    if (best == null) return null;
    final hint = '${best.profile ?? ''} ${best.displayTitle ?? ''} ${best.title ?? ''}'.toLowerCase();
    if (hint.contains('atmos')) return 'Atmos';
    if (hint.contains('dts:x') || hint.contains('dts-x')) return 'DTS:X';
    final ch = switch (best.channels) { 8 => ' 7.1', 6 => ' 5.1', 2 => ' 2.0', _ => '' };
    return switch (best.codecLower) {
      'truehd' => 'TrueHD$ch',
      'dts' || 'dca' => hint.contains('ma') ? 'DTS-HD MA$ch' : 'DTS$ch',
      'eac3' => 'DD+$ch',
      'ac3' => 'DD$ch',
      'flac' => 'FLAC$ch',
      _ => ch.isEmpty ? best.codecLower.toUpperCase() : best.codecLower.toUpperCase() + ch,
    };
  }

  static int _audioScore(MediaStream a) {
    final hint = '${a.profile ?? ''} ${a.displayTitle ?? ''}'.toLowerCase();
    var s = (a.channels ?? 2) * 10;
    if (hint.contains('atmos') || hint.contains('dts:x')) s += 100;
    s += switch (a.codecLower) { 'truehd' => 8, 'dts' => 6, 'flac' => 5, 'eac3' => 4, 'ac3' => 3, _ => 0 };
    return s;
  }

  String get codec => switch ((_video?.codec ?? '').toLowerCase()) {
        'hevc' || 'h265' => 'HEVC',
        'h264' || 'avc' => 'H.264',
        'av1' => 'AV1',
        'vp9' => 'VP9',
        'mpeg2video' => 'MPEG-2',
        'vc1' => 'VC-1',
        final c => c.toUpperCase(),
      };

  String? get size {
    final b = source.size;
    if (b == null || b <= 0) return null;
    final gb = b / (1024 * 1024 * 1024);
    return gb >= 1 ? '${gb.toStringAsFixed(1)} GB' : '${(b / (1024 * 1024)).round()} MB';
  }

  String? get bitrate {
    final b = source.bitrate;
    if (b == null || b <= 0) return null;
    return '${(b / 1e6).toStringAsFixed(b > 20e6 ? 0 : 1)} Mbps';
  }

  String get label {
    final name = source.name?.trim();
    final derived = [resolution, ?hdr].join(' ');
    if (name == null || name.isEmpty) return derived;
    return name;
  }

  String get summary => [resolution, ?hdr, codec, ?bestAudio, ?size].join('  ·  ');

  String get preferenceKey => '$resolution|${hdr ?? 'SDR'}';
}

MediaSourceInfo pickVersion(List<MediaSourceInfo> sources, {String? preferenceKey}) {
  if (sources.length <= 1) return sources.first;
  final infos = sources.map(VersionInfo.new).toList();
  if (preferenceKey != null) {
    for (final v in infos) {
      if (v.preferenceKey == preferenceKey) return v.source;
    }
  }
  infos.sort((a, b) {
    int res(VersionInfo v) => switch (v.resolution) { '2160p' => 4, '1080p' => 3, '720p' => 2, _ => 1 };
    final r = res(b).compareTo(res(a));
    if (r != 0) return r;
    final h = (b.hdr != null ? 1 : 0).compareTo(a.hdr != null ? 1 : 0);
    if (h != 0) return h;
    return (b.source.bitrate ?? 0).compareTo(a.source.bitrate ?? 0);
  });
  return infos.first.source;
}
