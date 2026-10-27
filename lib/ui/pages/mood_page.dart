import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/moods.dart';
import '../../data/recommendations.dart';
import '../../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/mixed_cards.dart';
import '../widgets/mood_shelf.dart';
import 'details_parts.dart';
import 'mixed_rows_view.dart';

class MoodPage extends StatefulWidget {
  const MoodPage({super.key, required this.mood});

  final Mood mood;

  @override
  State<MoodPage> createState() => _MoodPageState();
}

class _MoodPageState extends State<MoodPage> {
  late final List<MixedRowSpec> _rows = () {
    final s = AppServicesScope.read(context);
    final r = s.recommender;
    final m = widget.mood;
    Future<MixedItems> visible(Future<MixedItems> items) async =>
        s.seerr != null ? await items : (await items).whereType<EmbyItem>().toList();
    final movies = visible(m.items(r, pages: 3));
    final shows = visible(m.items(r, tv: true, pages: 3));
    final owned = Future.wait([movies, shows]).then((lists) => <Object>[
          for (final l in lists) ...l.whereType<EmbyItem>(),
        ]);
    return [
      MixedRowSpec((l) => l.inYourLibrary, owned, style: CardStyle.landscape),
      if (m.movie != null) MixedRowSpec((l) => l.movies, movies),
      if (m.tv != null) MixedRowSpec((l) => l.shows, shows, style: m.movie == null ? CardStyle.poster : CardStyle.landscape),
      if (m.movie != null) MixedRowSpec((l) => l.topRatedMovies, visible(m.items(r, topRated: true))),
      if (m.tv != null) MixedRowSpec((l) => l.topRatedShows, visible(m.items(r, tv: true, topRated: true))),
    ];
  }();

  @override
  Widget build(BuildContext context) {
    final t = moodText(context.l10n, widget.mood);
    return MixedRowsView(
      rows: _rows,
      left: pageLeft,
      header: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: Color(widget.mood.color), shape: BoxShape.circle),
          child: Icon(t.icon, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 18),
        Text(t.title, style: Zt.headline),
      ]),
    );
  }
}
