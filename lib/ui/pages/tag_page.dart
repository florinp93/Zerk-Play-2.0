import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/seerr_api.dart';
import '../../data/title_tags.dart';
import '../../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/mixed_cards.dart';
import 'details_parts.dart';
import 'mixed_rows_view.dart';
import 'title_extras.dart';

class TagPage extends StatefulWidget {
  const TagPage({super.key, required this.tag});

  final TitleTag tag;

  @override
  State<TagPage> createState() => _TagPageState();
}

class _TagPageState extends State<TagPage> {
  late final List<MixedRowSpec> _rows = () {
    final r = AppServicesScope.read(context).recommender;
    final t = widget.tag;
    final movie = t.covers(SeerrMediaType.movie);
    final tv = t.covers(SeerrMediaType.tv);
    final movies = r.tagged(t, SeerrMediaType.movie, pages: 3);
    final shows = r.tagged(t, SeerrMediaType.tv, pages: 3);
    final owned = Future.wait([movies, shows]).then((lists) => <Object>[
          for (final l in lists) ...l.whereType<EmbyItem>(),
        ]);
    return [
      MixedRowSpec((l) => l.inYourLibrary, owned, style: CardStyle.landscape),
      if (movie) MixedRowSpec((l) => l.movies, movies),
      if (tv) MixedRowSpec((l) => l.shows, shows, style: movie ? CardStyle.landscape : CardStyle.poster),
      if (movie) MixedRowSpec((l) => l.topRatedMovies, r.tagged(t, SeerrMediaType.movie, topRated: true)),
      if (tv) MixedRowSpec((l) => l.topRatedShows, r.tagged(t, SeerrMediaType.tv, topRated: true)),
    ];
  }();

  @override
  Widget build(BuildContext context) => MixedRowsView(
        rows: _rows,
        left: pageLeft,
        header: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: Zc.accent, shape: BoxShape.circle),
            child: Icon(widget.tag.isKeyword ? Icons.sell_outlined : Icons.category_outlined, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 18),
          Text(tagLabel(context.l10n, widget.tag), style: Zt.headline),
        ]),
      );
}
