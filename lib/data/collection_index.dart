import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import 'metadata_localizer.dart';

typedef MovieRef = ({String id, int? tmdbId, int? collectionHint, DateTime? added});

final class LibraryCollection {
  const LibraryCollection({required this.info, required this.ownedIds, this.lastAdded});

  final TmdbCollectionInfo info;

  final List<String> ownedIds;

  final DateTime? lastAdded;

  int get owned => ownedIds.length;
  int get total => info.parts.length;

  EmbyItem get item => CollectionIndex.itemFor(info, owned: owned);
}

final class CollectionIndex {
  CollectionIndex({required this._movies, required this._tmdb});

  final Future<List<MovieRef>> Function() _movies;
  final MetadataLocalizer _tmdb;

  final progress = ValueNotifier<double?>(null);

  static const _maxAge = Duration(minutes: 20);
  Future<List<LibraryCollection>>? _built;
  DateTime? _builtAt;

  Future<List<LibraryCollection>> all() {
    final stale = _builtAt != null && DateTime.now().difference(_builtAt!) > _maxAge;
    if (_built == null || stale) {
      _builtAt = DateTime.now();
      _built = _build()
        ..catchError((Object e) {
          _built = null;
          return const <LibraryCollection>[];
        });
    }
    return _built!;
  }

  Future<List<LibraryCollection>> recent({int limit = 20}) async {
    final list = [...await all()]..sort((a, b) {
        final byOwned = (b.owned > 1 ? 1 : 0).compareTo(a.owned > 1 ? 1 : 0);
        if (byOwned != 0) return byOwned;
        return (b.lastAdded ?? DateTime(0)).compareTo(a.lastAdded ?? DateTime(0));
      });
    return list.take(limit).toList();
  }

  void invalidate() => _built = null;

  Future<TmdbCollectionInfo?> collection(int id) => _tmdb.collection(id);

  Future<int?> collectionOfMovie(int tmdbMovieId) => _tmdb.movieCollectionId(tmdbMovieId);

  static EmbyItem itemFor(TmdbCollectionInfo info, {required int owned}) => EmbyItem(
        id: '',
        name: info.name,
        type: 'BoxSet',
        overview: info.overview,
        providerIds: {'Tmdb': '${info.id}'},
        childCount: owned,
        recursiveItemCount: info.parts.length,
        localizedPosterPath: info.posterPath,
        localizedBackdropPath: info.backdropPath,
        localizedLogoPath: info.logoPath,
      );

  Future<List<LibraryCollection>> _build() async {
    final movies = await _movies();
    final byCollection = <int, List<MovieRef>>{};
    var done = 0;
    final watch = Stopwatch()..start();
    await Future.wait(movies.map((m) async {
      int? cid;
      try {
        cid = m.tmdbId != null ? await _tmdb.movieCollectionId(m.tmdbId!) : m.collectionHint;
      } catch (_) {}
      if (cid != null) (byCollection[cid] ??= []).add(m);
      done++;
      if (watch.elapsedMilliseconds > 600 && done % 10 == 0) progress.value = done / movies.length;
    }));
    final collections = await Future.wait(byCollection.entries.map((e) async {
      final info = await _tmdb.collection(e.key);
      if (info == null || info.parts.length < 2) return null;
      final added = [for (final m in e.value) ?m.added]..sort();
      return LibraryCollection(info: info, ownedIds: [for (final m in e.value) m.id], lastAdded: added.lastOrNull);
    }));
    progress.value = null;
    debugPrint('[collections] ${movies.length} movies -> ${byCollection.length} collections '
        'in ${watch.elapsedMilliseconds} ms');
    return collections.nonNulls.toList()..sort((a, b) => _sortKey(a.info.name).compareTo(_sortKey(b.info.name)));
  }

  static String _sortKey(String name) {
    final n = name.toLowerCase();
    for (final article in const ['the ', 'a ', 'an ']) {
      if (n.startsWith(article)) return n.substring(article.length);
    }
    return n;
  }
}
