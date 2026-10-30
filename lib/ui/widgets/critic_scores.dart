import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/title_ratings.dart';
import '../theme/tokens.dart';

class CriticScores extends StatefulWidget {
  const CriticScores({super.key, required this.tmdbId, required this.tv}) : item = null;

  const CriticScores.forItem(EmbyItem this.item, {super.key})
      : tmdbId = null,
        tv = false;

  final int? tmdbId;
  final bool tv;
  final EmbyItem? item;

  @override
  State<CriticScores> createState() => _CriticScoresState();
}

class _CriticScoresState extends State<CriticScores> {
  Future<TitleRatings?>? _ratings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ratings ??= _load(AppServicesScope.read(context));
  }

  Future<TitleRatings?> _load(AppServices services) async {
    final item = widget.item;
    if (item == null) {
      final id = widget.tmdbId;
      return id == null ? null : services.titleRatings(id, tv: widget.tv);
    }
    final seriesId = item.seriesId;
    if (!item.isEpisode && !item.isSeason || seriesId == null) {
      final id = item.tmdbId;
      return id == null ? null : services.titleRatings(id, tv: item.isSeries);
    }
    final id = (await services.catalog.seriesTmdbIds({seriesId}))[seriesId];
    return id == null ? null : services.titleRatings(id, tv: true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _ratings,
      builder: (context, snapshot) {
        final r = snapshot.data;
        if (r == null) return const SizedBox.shrink();
        return Row(mainAxisSize: MainAxisSize.min, children: [
          if (r.critics != null) ...[
            const SizedBox(width: 22),
            CustomPaint(size: const Size.square(22), painter: _Tomato(fresh: r.fresh, certified: r.certified)),
            const SizedBox(width: 6),
            Text('${r.critics}%', style: Zt.meta.copyWith(color: Zc.text)),
          ],
          if (r.audience != null) ...[
            const SizedBox(width: 18),
            const Icon(Icons.people_alt_rounded, size: 22, color: Zc.rating),
            const SizedBox(width: 6),
            Text('${r.audience}%', style: Zt.meta.copyWith(color: Zc.text)),
          ],
        ]);
      },
    );
  }
}

class _Tomato extends CustomPainter {
  const _Tomato({required this.fresh, required this.certified});

  final bool fresh;
  final bool certified;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r * 1.08);
    canvas.drawCircle(center, r * 0.86, Paint()..color = fresh ? const Color(0xFFFA320A) : const Color(0xFF0AC855));
    if (!fresh) return;
    final leaf = Paint()..color = const Color(0xFF00912D);
    canvas.drawOval(Rect.fromCenter(center: Offset(r * 0.72, r * 0.3), width: r * 0.8, height: r * 0.36), leaf);
    canvas.drawOval(Rect.fromCenter(center: Offset(r * 1.28, r * 0.3), width: r * 0.8, height: r * 0.36), leaf);
    if (certified) {
      canvas.drawCircle(center, r * 0.86, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..color = Zc.rating);
    }
  }

  @override
  bool shouldRepaint(_Tomato old) => old.fresh != fresh || old.certified != certified;
}
