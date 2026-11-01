import '../../core/host.dart';
import '../player_settings.dart';
import '../subtitle_style.dart';

Map<String, String> buildMpvOptions({
  int? wid,
  required PlayerSettings settings,
  bool acceptInvalidCertificates = false,
  String? logFile,
  String? osdFontsDir,
}) {
  final spdif = settings.mpvSpdif;
  final bitstream = spdif.isNotEmpty;
  final own = !settings.mpvConfOnly;
  final linux = Host.isLinux;
  return {
    if (wid != null) 'wid': '$wid',
    'log-file': ?logFile,
    'osd-fonts-dir': ?osdFontsDir,
    'config': 'no',
    'load-scripts': 'no',
    'osc': 'no',
    'ytdl': 'no',
    'load-console': 'no',
    'load-select': 'no',
    'load-positioning': 'no',
    'load-commands': 'no',
    'load-auto-profiles': 'no',
    'load-stats-overlay': 'yes',
    'input-default-bindings': 'no',
    'input-builtin-bindings': 'no',
    'input-vo-keyboard': 'yes',
    'input-gamepad': 'no',
    'input-cursor': 'yes',
    'cursor-autohide': '1500',
    'osd-bar': 'no',
    'osd-on-seek': 'no',
    'osd-level': '1',
    if (!linux) 'force-window': 'yes',
    'msg-level': 'ffmpeg=error',
    'keep-open': 'yes',
    'idle': 'yes',

    'vo': linux ? 'libmpv' : (own ? settings.videoOutput : 'gpu-next'),
    if (!linux) 'gpu-api': 'd3d11',
    if (own) ...{
      'hwdec': linux && settings.hwdec.startsWith('d3d11') ? 'auto-safe' : settings.hwdec,
      if (!linux) 'target-colorspace-hint': settings.hdrPassthrough ? 'yes' : 'no',
      'video-sync': !settings.smoothMotion ? 'audio' : (bitstream ? 'display-vdrop' : 'display-resample'),
      'interpolation': settings.smoothMotion ? 'yes' : 'no',
      'tscale': 'oversample',
      ...switch (settings.videoQuality) {
        VideoQuality.fast => {'scale': 'bilinear', 'dscale': 'bilinear', 'cscale': 'bilinear', 'dither-depth': 'no'},
        VideoQuality.balanced => {'scale': 'spline36', 'dscale': 'mitchell'},
        VideoQuality.high => {'profile': 'high-quality'},
      },
      'deband': settings.deband ? 'yes' : 'no',
      'tone-mapping': settings.toneMapping,
      if (settings.targetPrim != 'auto') 'target-prim': settings.targetPrim,
      if (settings.targetTrc != 'auto') 'target-trc': settings.targetTrc,
      if (settings.targetPeak > 0) 'target-peak': '${settings.targetPeak}',
    },

    'cache': 'yes',
    'demuxer-max-bytes': '512MiB',
    'demuxer-max-back-bytes': '128MiB',
    'demuxer-readahead-secs': '60',
    'stream-buffer-size': '4MiB',
    'network-timeout': '30',
    'user-agent': 'ZerkPlay/2.0 (${linux ? 'Linux' : 'Windows'}; libmpv)',
    'tls-verify': acceptInvalidCertificates ? 'no' : 'yes',

    'audio-spdif': spdif,
    if (bitstream) ...{'audio-stream-silence': 'yes', 'audio-buffer': '0.5'},
    if (!linux) 'audio-exclusive': settings.audioExclusive ? 'yes' : 'no',
    'audio-channels': 'auto',
    'audio-pitch-correction': 'yes',
    'volume': settings.volume.round().toString(),
    'volume-max': '150',

    'sub-auto': 'no',
    'audio-file-auto': 'no',
    ...SubtitleStyle.mpvOptions(settings),
    'sub-fix-timing': 'yes',
    'blend-subtitles': 'no',
  };
}
