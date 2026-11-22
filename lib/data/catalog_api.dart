import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import '../services/janus/janus_service.dart';
import 'collection_index.dart';
import 'libraries.dart';
import 'metadata_localizer.dart';

enum CollectionsSource { both, tmdb, server }

final class LibraryView {
  const LibraryView({required this.id, required this.name, this.collectionType, this.imageTag});

  final String id;
  final String name;

  final String? collectionType;
  final String? imageTag;
}

typedef ServerLibrary = LibraryView;

final class ItemPage {
  const ItemPage(this.items, this.total, {this.scanned = -1});

  final List<EmbyItem> items;
  final int total;

  final int scanned;

  int get fetched => scanned < 0 ? items.length : scanned;
}

enum ImageKind { primary, backdrop, thumb, logo }

final class CatalogApi {
  CatalogApi({required this._janus});

  final JanusService _janus;

  MetadataLocalizer? localizer;

  CollectionIndex? collections;
  CollectionsSource collectionsSource = CollectionsSource.both;

  String get _userId => _janus.session.userId;

  Set<String> _hiddenLibraries = const {};
  Future<HiddenContent>? _hidden;

  Set<String> get hiddenLibraries => _hiddenLibraries;

  set hiddenLibraries(Set<String> ids) {
    if (ids.length == _hiddenLibraries.length && ids.containsAll(_hiddenLibraries)) return;
    _hiddenLibraries = {...ids};
    _hidden = null;
  }

  void forgetHiddenContent() => _hidden = null;

  Future<HiddenContent> hiddenContent() {
    if (_hiddenLibraries.isEmpty) return Future.value(HiddenContent.none);
    return _hidden ??= _loadHidden(_hiddenLibraries).catchError((Object e) {
      debugPrint('[libraries] hidden content: $e');
      _hidden = null;
      return HiddenContent.none;
    });
  }

  Future<HiddenContent> _loadHidden(Set<String> libraries) async {
    final pages = await Future.wait([
      for (final id in libraries)
        _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
          'ParentId': id,
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie,Series,Video,MusicVideo',
          'EnableImages': 'false',
          'EnableUserData': 'false',
          'EnableTotalRecordCount': 'false',
        }),
    ]);
    return HiddenContent({
      for (final json in pages)
        for (final raw in (json['Items'] as List? ?? const []))
          if (raw is Map && raw['Id'] is String) raw['Id'] as String,
    });
  }

  Future<int> hiddenTotal({List<String>? types, String? filters, List<String>? genres}) async {
    if (_hiddenLibraries.isEmpty) return 0;
    final counts = await Future.wait([
      for (final id in _hiddenLibraries)
        _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
          'ParentId': id,
          'Recursive': 'true',
          'IncludeItemTypes': types?.join(','),
          'Filters': filters,
          'Genres': genres?.join('|'),
          'Limit': '0',
          'EnableImages': 'false',
          'EnableUserData': 'false',
          'EnableTotalRecordCount': 'true',
        }).then((j) => (j['TotalRecordCount'] as num?)?.toInt() ?? 0, onError: (Object _) => 0),
    ]);
    return counts.fold<int>(0, (a, b) => a + b);
  }

  Future<List<EmbyItem>> _visible(List<EmbyItem> items) async {
    if (_hiddenLibraries.isEmpty) return items;
    return (await hiddenContent()).filter(items);
  }

  static const cardFields = 'PrimaryImageAspectRatio,ProductionYear,CommunityRating,OfficialRating,'
      'RunTimeTicks,Overview,Genres,ParentId,SeriesId,SeasonId,ProviderIds,ChildCount,'
      'RecursiveItemCount,Status,EndDate,PremiereDate';

  static const detailFields = '$cardFields,Taglines,Studios,People,MediaSources,MediaStreams,Chapters,'
      'OriginalTitle,PartCount,LocationType';

  static const _imageArgs = {
    'EnableImageTypes': 'Primary,Backdrop,Thumb,Logo',
    'ImageTypeLimit': '1',
    'EnableUserData': 'true',
  };

  Future<List<LibraryView>> views() async {
    final json = await _janus.client.getJson('/Users/$_userId/Views');
    return [
      for (final raw in (json['Items'] as List? ?? const []))
        if (raw is Map)
          LibraryView(
            id: raw['Id'] as String,
            name: (raw['Name'] as String?) ?? '',
            collectionType: raw['CollectionType'] as String?,
            imageTag: (raw['ImageTags'] as Map?)?['Primary'] as String?,
          ),
    ];
  }

  Future<List<EmbyItem>> resume({int limit = 24}) => _list('/Users/$_userId/Items/Resume', {
        'Limit': '$limit',
        'MediaTypes': 'Video',
        'Fields': '$cardFields,Chapters',
      });

  Future<List<EmbyItem>> nextUp({int limit = 24, String? seriesId}) => _list('/Shows/NextUp', {
        'UserId': _userId,
        'Limit': '$limit',
        'SeriesId': seriesId,
        'Fields': '$cardFields,Chapters',
        'LegacyNextUp': 'true',
      });

  Future<EmbyItem?> seriesNext(String seriesId) async {
    final (next, recent) = await (
      nextUp(seriesId: seriesId, limit: 1),
      _list('/Users/$_userId/Items', {
        'ParentId': seriesId,
        'Recursive': 'true',
        'IncludeItemTypes': 'Episode',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Limit': '1',
        'Fields': '$cardFields,Chapters',
      }),
    ).wait;
    return pickNextEpisode(next.firstOrNull, recent);
  }

  static EmbyItem? pickNextEpisode(EmbyItem? nextUp, Iterable<EmbyItem> recent) {
    EmbyItem? latest;
    for (final e in recent) {
      final played = e.lastPlayedDate;
      if (played == null) continue;
      if (latest == null || played.isAfter(latest.lastPlayedDate!)) latest = e;
    }
    if (latest != null && latest.resumePosition != null) return latest;
    return nextUp;
  }

  Future<List<EmbyItem>> continueWatching({int limit = 24}) async {
    final (inProgress, next) = await (resume(limit: limit), nextUp(limit: limit)).wait;
    return mergeContinueWatching(inProgress, next);
  }

  static List<EmbyItem> mergeContinueWatching(List<EmbyItem> resume, List<EmbyItem> nextUp) {
    final ids = {for (final i in resume) i.id};
    final shows = {for (final i in resume) ?i.seriesId};
    return [
      ...resume,
      for (final i in nextUp)
        if (!ids.contains(i.id) && !shows.contains(i.seriesId)) i,
    ];
  }

  Future<List<EmbyItem>> watchingSeries({Duration within = const Duration(days: 120)}) async {
    Future<Map<String, dynamic>> episodes(String path, Map<String, String> args) =>
        _janus.client.getJson(path, queryParameters: {
          ...args,
          'Fields': 'SeriesId',
          'EnableImages': 'false',
          'EnableTotalRecordCount': 'false',
        });
    final since = DateTime.now().subtract(within);
    final (played, resume, next) = await (
      episodes('/Users/$_userId/Items', {
        'IncludeItemTypes': 'Episode',
        'Recursive': 'true',
        'Filters': 'IsPlayed',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Limit': '300',
      }),
      episodes('/Users/$_userId/Items/Resume', {'IncludeItemTypes': 'Episode', 'Limit': '50'}),
      episodes('/Shows/NextUp', {'UserId': _userId, 'Limit': '50'}),
    ).wait;
    final ids = <String>{
      for (final e in _parse(played))
        if (e.seriesId != null && (e.lastPlayedDate?.isAfter(since) ?? false)) e.seriesId!,
      for (final e in [..._parse(resume), ..._parse(next)]) ?e.seriesId,
    };
    if (ids.isEmpty) return const [];
    final page = await query(ids: ids.toList(), types: ['Series'], limit: ids.length, localize: false);
    final ended = DateTime.now().subtract(const Duration(days: 45));
    return [
      for (final s in page.items)
        if (s.status != 'Ended' || (s.endDate?.isAfter(ended) ?? false)) s,
    ];
  }

  Future<List<EmbyItem>> latest({String? parentId, List<String>? types, int limit = 24}) async {
    final json = await _janus.client.getJsonList('/Users/$_userId/Items/Latest', queryParameters: {
      'Limit': '$limit',
      'ParentId': parentId,
      'IncludeItemTypes': types?.join(','),
      'GroupItems': 'true',
      'Fields': cardFields,
      ..._imageArgs,
    });
    return _localize(
        await _visible([for (final raw in json) if (raw is Map) EmbyItem.fromJson(raw.cast<String, dynamic>())]));
  }

  Future<ItemPage> query({
    String? parentId,
    List<String>? types,
    String sortBy = 'SortName',
    bool descending = false,
    int start = 0,
    int limit = 60,
    bool recursive = true,
    List<String>? genres,
    List<String>? tags,
    List<int>? years,
    String? filters,
    double? minCommunityRating,
    String? searchTerm,
    String? anyProviderIdEquals,
    String? personIds,
    List<String>? ids,
    String? listItemIds,
    String fields = cardFields,
    bool localize = true,
    bool collapseBoxSets = false,
  }) async {
    if (anyProviderIdEquals != null && _janus.client.isJellyfin) {
      final index = await _providerIndex();
      final matched = {
        for (final key in anyProviderIdEquals.toLowerCase().split(',')) ...?index[key.trim()],
      };
      if (ids != null) matched.retainAll(ids);
      if (matched.isEmpty) return const ItemPage([], 0);
      ids = matched.toList();
      anyProviderIdEquals = null;
    }
    final json = await _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
      'ParentId': parentId,
      'IncludeItemTypes': types?.join(','),
      'Recursive': '$recursive',
      'SortBy': sortBy,
      'SortOrder': descending ? 'Descending' : 'Ascending',
      'StartIndex': '$start',
      'Limit': '$limit',
      'Genres': genres?.join('|'),
      'Tags': tags?.join('|'),
      'Years': years?.join(','),
      'Filters': filters,
      'MinCommunityRating': minCommunityRating?.toString(),
      'SearchTerm': searchTerm,
      'AnyProviderIdEquals': anyProviderIdEquals,
      'PersonIds': personIds,
      'Ids': ids?.join(','),
      'ListItemIds': listItemIds,
      'GroupItemsIntoCollections': collapseBoxSets ? 'true' : null,
      'CollapseBoxSetItems': collapseBoxSets ? 'true' : null,
      'Fields': fields,
      'EnableTotalRecordCount': 'true',
      ..._imageArgs,
    });
    final parsed = _parse(json);
    final items = await _visible(parsed);
    return ItemPage(localize ? await _localize(items) : items, (json['TotalRecordCount'] as num?)?.toInt() ?? 0,
        scanned: parsed.length);
  }

  Future<Map<String, List<String>>> _providerIndex() {
    final key = '${_janus.session.serverUrl}|$_userId';
    final cached = _providerIds;
    if (cached != null && cached.key == key && DateTime.now().difference(cached.at) < const Duration(minutes: 10)) {
      return cached.index;
    }
    final index = _loadProviderIndex();
    _providerIds = (key: key, at: DateTime.now(), index: index);
    index.catchError((Object _) {
      _providerIds = null;
      return const <String, List<String>>{};
    });
    return index;
  }

  ({String key, DateTime at, Future<Map<String, List<String>>> index})? _providerIds;

  Future<Map<String, List<String>>> _loadProviderIndex() async {
    final json = await _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
      'IncludeItemTypes': 'Movie,Series,BoxSet',
      'Recursive': 'true',
      'Fields': 'ProviderIds',
      'EnableImages': 'false',
      'EnableUserData': 'false',
      'EnableTotalRecordCount': 'false',
    });
    final out = <String, List<String>>{};
    for (final raw in (json['Items'] as List? ?? const [])) {
      if (raw is! Map || raw['Id'] is! String || raw['ProviderIds'] is! Map) continue;
      for (final e in (raw['ProviderIds'] as Map).entries) {
        final value = '${e.value ?? ''}'.trim().toLowerCase();
        if (value.isEmpty) continue;
        (out['${'${e.key}'.toLowerCase()}.$value'] ??= []).add(raw['Id'] as String);
      }
    }
    return out;
  }

  Future<EmbyItem> item(String id) async {
    final json = await _janus.client.getJson('/Users/$_userId/Items/$id', queryParameters: {
      'Fields': detailFields,
    });
    return localize(EmbyItem.fromJson(json));
  }

  Future<Map<String, int>> seriesTmdbIds(Set<String> seriesIds) async {
    final json = await _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
      'Ids': seriesIds.join(','),
      'Fields': 'ProviderIds',
      'EnableImages': 'false',
      'EnableUserData': 'false',
    });
    return {
      for (final i in _parse(json))
        if (i.tmdbId != null) i.id: i.tmdbId!,
    };
  }

  Future<List<EmbyItem>> seasons(String seriesId) => _list('/Shows/$seriesId/Seasons', {
        'UserId': _userId,
        'Fields': '$cardFields,LocationType',
        'IsMissing': null,
      });

  Future<EmbyItem?> episodeToPlay(EmbyItem show) async {
    final seriesId = show.isSeries ? show.id : show.seriesId;
    if (seriesId == null) return null;
    final next = await seriesNext(seriesId);
    if (next != null && (!show.isSeason || next.seasonId == show.id)) return next;
    final all = (await episodes(seriesId, seasonId: show.isSeason ? show.id : null)).where((e) => e.isPlayable);
    return all.where((e) => (e.parentIndexNumber ?? 1) > 0).firstOrNull ?? all.firstOrNull;
  }

  Future<List<EmbyItem>> episodes(String seriesId, {String? seasonId}) =>
      _list('/Shows/$seriesId/Episodes', {
        'UserId': _userId,
        'SeasonId': seasonId,
        'Fields': '$cardFields,Chapters,LocationType,MediaSources',
      });

  Future<List<EmbyItem>> similar(String id, {int limit = 16}) => _list('/Items/$id/Similar', {
        'UserId': _userId,
        'Limit': '$limit',
        'Fields': cardFields,
      });

  Future<List<EmbyItem>> boxSets() async =>
      (await query(types: ['BoxSet'], sortBy: 'SortName', limit: 500, localize: false)).items;

  Future<List<EmbyItem>> collectionItems(EmbyItem collection) async {
    if (collection.id.isNotEmpty) {
      final page = await query(
        parentId: collection.id,
        recursive: false,
        sortBy: 'PremiereDate,ProductionYear,SortName',
        limit: 300,
        fields: '$cardFields,Taglines',
      );
      return page.items;
    }
    final tmdbId = collection.tmdbId;
    final info = tmdbId == null
        ? null
        : await (collections?.collection(tmdbId) ?? localizer?.collection(tmdbId) ?? Future.value());
    final parts = info?.parts;
    if (parts == null || parts.isEmpty) return const [];
    final page = await query(
      types: ['Movie'],
      anyProviderIdEquals: parts.map((id) => 'tmdb.$id').join(','),
      sortBy: 'PremiereDate,ProductionYear,SortName',
      limit: 300,
      fields: '$cardFields,Taglines',
    );
    return [for (final i in page.items) if (parts.contains(i.tmdbId)) i];
  }

  Future<List<EmbyItem>> allCollections({bool recent = false, int limit = 500}) async {
    final index = collections;
    const none = <EmbyItem>[];
    final (tmdb, server) = await (
      index != null && collectionsSource != CollectionsSource.server
          ? (recent ? index.recent(limit: limit) : index.all()).then((list) => [for (final c in list.take(limit)) c.item])
          : Future.value(none),
      index == null || collectionsSource != CollectionsSource.tmdb
          ? query(
              types: ['BoxSet'],
              sortBy: recent ? 'DateLastContentAdded,SortName' : 'SortName',
              descending: recent,
              limit: limit,
            ).then((page) => page.items)
          : Future.value(none),
    ).wait;
    if (tmdb.isEmpty || server.isEmpty) return [...tmdb, ...server];
    final onServer = {for (final b in server) ?b.tmdbId};
    final merged = [...server, ...tmdb.where((c) => !onServer.contains(c.tmdbId))];
    if (!recent) merged.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return merged.take(limit).toList();
  }

  Future<({EmbyItem collection, List<EmbyItem> films, int? total})?> collectionOf(EmbyItem movie) async {
    if (!movie.isMovie) return null;
    final index = collections;
    if (index == null) return _boxSetOf(movie);
    final tmdbId = movie.tmdbId;
    final cid = movie.localizedCollectionId ??
        (tmdbId != null ? await index.collectionOfMovie(tmdbId) : movie.tmdbCollectionId);
    if (cid == null) return null;
    final info = await index.collection(cid);
    if (info == null || info.parts.length < 2) return null;
    final films = await collectionItems(CollectionIndex.itemFor(info, owned: 0));
    if (films.isEmpty) return null;
    return (collection: CollectionIndex.itemFor(info, owned: films.length), films: films, total: info.parts.length);
  }

  Future<({EmbyItem collection, List<EmbyItem> films, int? total})?> _boxSetOf(EmbyItem movie) async {
    final cid = movie.tmdbCollectionId;
    if (cid != null) {
      final boxSets = await query(types: ['BoxSet'], anyProviderIdEquals: 'tmdb.$cid', limit: 1);
      final collection = boxSets.items.where((b) => b.tmdbId == cid).firstOrNull;
      if (collection != null) {
        final films = await collectionItems(collection);
        if (films.isNotEmpty) return (collection: collection, films: films, total: null);
      }
    }
    final listing = await query(types: ['BoxSet'], listItemIds: movie.id, limit: 6);
    if (listing.total > 5) {
      debugPrint('[collections] the server ignored ListItemIds (${listing.total} box sets)');
      return null;
    }
    for (final collection in listing.items) {
      final films = await collectionItems(collection);
      if (films.any((f) => f.id == movie.id)) return (collection: collection, films: films, total: null);
    }
    debugPrint('[collections] ${movie.name}: in no box set (tmdb collection ${cid ?? '-'})');
    return null;
  }

  Future<List<MovieRef>> movieRefs() async {
    final out = <MovieRef>[];
    const pageSize = 2000;
    for (var start = 0;; start += pageSize) {
      final json = await _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
        'IncludeItemTypes': 'Movie',
        'Recursive': 'true',
        'Fields': 'ProviderIds,DateCreated',
        'StartIndex': '$start',
        'Limit': '$pageSize',
        'EnableImages': 'false',
        'EnableUserData': 'false',
        'EnableTotalRecordCount': 'true',
      });
      final items = json['Items'] as List? ?? const [];
      for (final raw in items) {
        if (raw is! Map || raw['Id'] is! String) continue;
        final ids = {
          for (final e in ((raw['ProviderIds'] as Map?) ?? const {}).entries) '${e.key}'.toLowerCase(): '${e.value}',
        };
        out.add((
          id: raw['Id'] as String,
          tmdbId: int.tryParse(ids['tmdb'] ?? ''),
          collectionHint: int.tryParse(ids['tmdbcollection'] ?? ''),
          added: DateTime.tryParse(raw['DateCreated'] as String? ?? ''),
        ));
      }
      final total = (json['TotalRecordCount'] as num?)?.toInt() ?? 0;
      if (items.length < pageSize || start + pageSize >= total) break;
    }
    return out;
  }

  Future<EmbyItem?> byTmdbId(int tmdbId, {required bool series}) async {
    final page = await query(
      types: [series ? 'Series' : 'Movie'],
      anyProviderIdEquals: 'tmdb.$tmdbId',
      limit: 1,
    );
    return page.items.firstOrNull;
  }

  Future<List<String>> genres({String? parentId, List<String>? types}) async {
    final json = await _janus.client.getJson('/Genres', queryParameters: {
      'UserId': _userId,
      'ParentId': parentId,
      'IncludeItemTypes': types?.join(','),
      'SortBy': 'SortName',
    });
    return [
      for (final raw in (json['Items'] as List? ?? const []))
        if (raw is Map && raw['Name'] is String) raw['Name'] as String,
    ];
  }

  Future<void> setPlayed(String id, bool played) => played
      ? _janus.client.postNoContent('/Users/$_userId/PlayedItems/$id')
      : _janus.client.deleteNoContent('/Users/$_userId/PlayedItems/$id');

  Future<void> setFavorite(String id, bool favorite) => favorite
      ? _janus.client.postNoContent('/Users/$_userId/FavoriteItems/$id')
      : _janus.client.deleteNoContent('/Users/$_userId/FavoriteItems/$id');

  Uri image(String itemId, ImageKind kind, {String? tag, int width = 480, int index = 0}) {
    final type = switch (kind) {
      ImageKind.primary => 'Primary',
      ImageKind.backdrop => 'Backdrop',
      ImageKind.thumb => 'Thumb',
      ImageKind.logo => 'Logo',
    };
    final path = kind == ImageKind.backdrop ? '/Items/$itemId/Images/$type/$index' : '/Items/$itemId/Images/$type';
    return _janus.client.buildUri(path, queryParameters: {
      'maxWidth': '$width',
      'quality': kind == ImageKind.logo ? null : '88',
      'tag': tag,
    });
  }

  Uri personImage(Person p, {int width = 240}) =>
      image(p.id, ImageKind.primary, tag: p.imageTag, width: width);

  Future<List<EmbyItem>> _list(String path, Map<String, String?> params) async {
    final json = await _janus.client.getJson(path, queryParameters: {...params, ..._imageArgs});
    return _localize(await _visible(_parse(json)));
  }

  Future<EmbyItem> localize(EmbyItem item) async => await localizer?.localize(item) ?? item;

  Future<List<EmbyItem>> _localize(List<EmbyItem> items) async => await localizer?.localizeAll(items) ?? items;

  static List<EmbyItem> _parse(Map<String, dynamic> json) => [
        for (final raw in (json['Items'] as List? ?? const []))
          if (raw is Map) EmbyItem.fromJson(raw.cast<String, dynamic>()),
      ];
}
