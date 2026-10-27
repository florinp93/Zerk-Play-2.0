import 'dart:async';

import 'package:flutter/foundation.dart';

import 'seerr_api.dart';

enum ReleaseStage {
  upcoming,

  inCinemas,

  out,
}

@immutable
final class ReleaseInfo {
  const ReleaseInfo(this.stage, {this.cinema, this.digital});

  final ReleaseStage stage;

  final DateTime? cinema;

  final DateTime? digital;

  bool get notOut => stage != ReleaseStage.out;

  static const _out = ReleaseInfo(ReleaseStage.out);

  static const _cinemaWindow = Duration(days: 120);

  static ReleaseInfo? fromDetails(Map<String, dynamic> j, {DateTime? now}) {
    now ??= DateTime.now();
    DateTime? premiere, cinema, home;
    DateTime? earliest(DateTime? a, DateTime b) => a == null || b.isBefore(a) ? b : a;
    final releases = j['releases'];
    final countries = releases is Map ? releases['results'] as List? ?? const [] : const [];
    for (final c in countries) {
      if (c is! Map) continue;
      for (final d in (c['release_dates'] as List? ?? const [])) {
        if (d is! Map) continue;
        final date = DateTime.tryParse('${d['release_date']}');
        if (date == null) continue;
        switch ((d['type'] as num?)?.toInt()) {
          case 1:
            premiere = earliest(premiere, date);
          case 2 || 3:
            cinema = earliest(cinema, date);
          case 4 || 5 || 6:
            home = earliest(home, date);
        }
      }
    }
    cinema ??= premiere;
    if (cinema == null && home == null) return guess(DateTime.tryParse('${j['releaseDate']}'), now: now) ?? _out;
    if (home != null && !home.isAfter(now)) return _out;
    if (cinema != null && !cinema.isAfter(now)) {
      if (home == null && now.difference(cinema) > _cinemaWindow) return _out;
      return ReleaseInfo(ReleaseStage.inCinemas, cinema: cinema, digital: home);
    }
    return ReleaseInfo(ReleaseStage.upcoming, cinema: cinema, digital: home);
  }

  static ReleaseInfo? guess(DateTime? releaseDate, {DateTime? now}) {
    now ??= DateTime.now();
    if (releaseDate == null) return null;
    if (releaseDate.isAfter(now)) return ReleaseInfo(ReleaseStage.upcoming, cinema: releaseDate);
    if (now.difference(releaseDate) > _cinemaWindow) return _out;
    return null;
  }
}

abstract final class ReleaseInfos {
  static final _known = <int, ReleaseInfo>{};
  static final _queued = <int>{};
  static final _queue = <(SeerrApi, int)>[];
  static var _running = 0;

  static final changed = ValueNotifier<int>(0);

  static ReleaseInfo? of(SeerrMedia m) =>
      m.isTv ? null : _known[m.tmdbId] ?? m.release ?? ReleaseInfo.guess(m.releaseDate);

  static void record(SeerrMedia m) {
    final r = m.release;
    if (m.isTv || r == null || _known[m.tmdbId] == r) return;
    _known[m.tmdbId] = r;
    changed.value++;
  }

  static Future<ReleaseInfo?> load(SeerrApi seerr, SeerrMedia m) async {
    if (m.isTv || of(m) != null) return of(m);
    try {
      final d = await seerr.details(m.tmdbId, SeerrMediaType.movie);
      _known[m.tmdbId] = d.release ?? const ReleaseInfo(ReleaseStage.out);
      changed.value++;
    } catch (_) {}
    return of(m);
  }

  static void ensure(SeerrApi? seerr, SeerrMedia m) {
    if (seerr == null || of(m) != null || !_queued.add(m.tmdbId)) return;
    _queue.add((seerr, m.tmdbId));
    _pump();
  }

  static void _pump() {
    while (_running < 3 && _queue.isNotEmpty) {
      final (seerr, id) = _queue.removeAt(0);
      _running++;
      unawaited(seerr.details(id, SeerrMediaType.movie).then((d) {
        _known[id] = d.release ?? const ReleaseInfo(ReleaseStage.out);
        changed.value++;
      }, onError: (_) {
        _queued.remove(id);
      }).whenComplete(() {
        _running--;
        _pump();
      }));
    }
  }
}
