import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../data/seerr_api.dart';
import '../widgets/mixed_cards.dart';
import 'mixed_rows_view.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  late final List<MixedRowSpec> _rows = () {
    final s = AppServicesScope.read(context);
    final seerr = s.seerr!;
    final r = s.recommender;
    return [
      MixedRowSpec((l) => l.trendingThisWeek,
          r.mixed((p) => seerr.trending(page: p, timeWindow: 'week'), limit: 10), style: CardStyle.ranked),
      MixedRowSpec((l) => l.trending, r.mixed((p) => seerr.trending(page: p + 1), pages: 4)),
      MixedRowSpec((l) => l.popularMovies,
          r.mixed((p) => r.discover(SeerrMediaType.movie, page: p, voteCountGte: 200), pages: 4)),
      MixedRowSpec((l) => l.popularShows,
          r.mixed((p) => r.discover(SeerrMediaType.tv, page: p, voteCountGte: 100), pages: 4),
          style: CardStyle.landscape),
      MixedRowSpec((l) => l.comingSoon, r.mixed((p) => seerr.upcomingMovies(page: p))),
      MixedRowSpec(
          (l) => l.topRatedMovies,
          r.mixed((p) => r.discover(SeerrMediaType.movie,
              page: p, sortBy: 'vote_average.desc', voteCountGte: 3000))),
      MixedRowSpec(
          (l) => l.topRatedShows,
          r.mixed((p) => r.discover(SeerrMediaType.tv, page: p, sortBy: 'vote_average.desc', voteCountGte: 1500)),
          style: CardStyle.landscape),
    ];
  }();

  @override
  Widget build(BuildContext context) => MixedRowsView(rows: _rows);
}
