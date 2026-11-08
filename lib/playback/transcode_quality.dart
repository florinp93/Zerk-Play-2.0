const kTranscodeMbps = [2, 3, 4, 6, 8, 10, 15, 20, 30, 40, 60, 80, 100, 120, 150, 200];

const _bitsPerMbps = 1000000;

Iterable<int> get transcodeBitrates => kTranscodeMbps.reversed.map((mbps) => mbps * _bitsPerMbps);

int normalizeTranscodeBitrate(int bitsPerSecond) {
  if (bitsPerSecond <= 0) return 0;
  final mbps = (bitsPerSecond / _bitsPerMbps).clamp(kTranscodeMbps.first, kTranscodeMbps.last);
  final nearest = kTranscodeMbps.reduce((a, b) => (a - mbps).abs() <= (b - mbps).abs() ? a : b);
  return nearest * _bitsPerMbps;
}

String mbpsLabel(int bitsPerSecond) => '${bitsPerSecond ~/ _bitsPerMbps} Mbps';
