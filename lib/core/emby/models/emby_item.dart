import 'media_source.dart';

int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
double? _double(Object? v) => v is num ? v.toDouble() : null;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
List<String> _strings(Object? v) =>
    v is List ? [for (final e in v) ?_str(e is Map ? e['Name'] : e)] : const [];

final class Person {
  const Person({required this.id, required this.name, this.role, this.type, this.imageTag, this.localizedImagePath});

  final String id;
  final String name;
  final String? role;

  final String? type;
  final String? imageTag;

  final String? localizedImagePath;

  Person withLocalizedImage(String? path) => path == null
      ? this
      : Person(id: id, name: name, role: role, type: type, imageTag: imageTag, localizedImagePath: path);

  static Person? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _str(raw['Id']);
    final name = _str(raw['Name']);
    if (id == null || name == null) return null;
    return Person(
      id: id,
      name: name,
      role: _str(raw['Role']),
      type: _str(raw['Type']),
      imageTag: _str(raw['PrimaryImageTag']),
    );
  }
}

final class EmbyItem {
  EmbyItem({
    required this.id,
    required this.name,
    required this.type,
    this.originalTitle,
    this.overview,
    this.tagline,
    this.productionYear,
    this.premiereDate,
    this.endDate,
    this.status,
    this.officialRating,
    this.communityRating,
    this.criticRating,
    this.genres = const [],
    this.studios = const [],
    this.runTimeTicks,
    this.primaryImageTag,
    this.primaryImageAspectRatio,
    this.thumbImageTag,
    this.logoImageTag,
    this.backdropImageTags = const [],
    this.parentBackdropItemId,
    this.parentBackdropImageTags = const [],
    this.parentLogoItemId,
    this.parentLogoImageTag,
    this.parentThumbItemId,
    this.parentThumbImageTag,
    this.seriesPrimaryImageTag,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.seasonName,
    this.parentId,
    this.indexNumber,
    this.indexNumberEnd,
    this.parentIndexNumber,
    this.locationType,
    this.isFolder = false,
    this.childCount,
    this.recursiveItemCount,
    this.isPlayed = false,
    this.playbackPositionTicks,
    this.playedPercentage,
    this.unplayedItemCount,
    this.isFavorite = false,
    this.lastPlayedDate,
    this.providerIds = const {},
    this.people = const [],
    this.mediaSources = const [],
    this.partCount,
    this.introStartTicks,
    this.introEndTicks,
    this.creditsStartTicks,
    this.localizedPosterPath,
    this.localizedLogoPath,
    this.localizedBackdropPath,
    this.localizedStillPath,
    this.localizedCollectionId,
    this.localizedCollectionName,
  });

  final String id;
  final String name;

  final String type;
  final String? originalTitle;
  final String? overview;
  final String? tagline;
  final int? productionYear;
  final DateTime? premiereDate;
  final DateTime? endDate;

  final String? status;
  final String? officialRating;
  final double? communityRating;
  final double? criticRating;
  final List<String> genres;
  final List<String> studios;
  final int? runTimeTicks;

  final String? primaryImageTag;
  final double? primaryImageAspectRatio;
  final String? thumbImageTag;
  final String? logoImageTag;
  final List<String> backdropImageTags;

  final String? parentBackdropItemId;
  final List<String> parentBackdropImageTags;
  final String? parentLogoItemId;
  final String? parentLogoImageTag;
  final String? parentThumbItemId;
  final String? parentThumbImageTag;
  final String? seriesPrimaryImageTag;

  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final String? seasonName;
  final String? parentId;

  final int? indexNumber;

  final int? indexNumberEnd;

  final int? parentIndexNumber;

  final String? locationType;
  final bool isFolder;
  final int? childCount;
  final int? recursiveItemCount;

  final bool isPlayed;
  final int? playbackPositionTicks;
  final double? playedPercentage;
  final int? unplayedItemCount;
  final bool isFavorite;
  final DateTime? lastPlayedDate;

  final Map<String, String> providerIds;
  final List<Person> people;

  final List<MediaSourceInfo> mediaSources;
  final int? partCount;

  final int? introStartTicks;
  final int? introEndTicks;
  final int? creditsStartTicks;

  final String? localizedPosterPath;
  final String? localizedLogoPath;
  final String? localizedBackdropPath;

  final String? localizedStillPath;

  final int? localizedCollectionId;
  final String? localizedCollectionName;

  int? get tmdbCollectionId =>
      localizedCollectionId ?? int.tryParse(providerIds['TmdbCollection'] ?? providerIds['tmdbcollection'] ?? '');

  bool get isEpisode => type == 'Episode';
  bool get isMovie => type == 'Movie';
  bool get isSeries => type == 'Series';
  bool get isSeason => type == 'Season';
  bool get isCollection => type == 'BoxSet';

  bool get isChannel => type == 'TvChannel';

  bool get isVirtual => locationType == 'Virtual';
  bool get isPlayable => !isFolder && !isVirtual && !isSeries && !isSeason && !isCollection;

  bool get hasVersions => mediaSources.length > 1;

  int? get tmdbId => int.tryParse(providerIds['Tmdb'] ?? providerIds['tmdb'] ?? '');

  Duration? get runtime => runTimeTicks == null ? null : Duration(microseconds: runTimeTicks! ~/ 10);

  Duration? get resumePosition {
    final t = playbackPositionTicks;
    if (t == null || t <= 0 || isPlayed) return null;
    return Duration(microseconds: t ~/ 10);
  }

  double? get progress {
    final pos = resumePosition;
    final rt = runtime;
    if (pos == null || rt == null || rt.inSeconds <= 0) return null;
    return (pos.inMilliseconds / rt.inMilliseconds).clamp(0.0, 1.0);
  }

  String? get episodeCode {
    if (!isEpisode) return null;
    final s = parentIndexNumber, e = indexNumber;
    if (s == null && e == null) return null;
    final ep = e == null ? null : (indexNumberEnd != null && indexNumberEnd != e ? 'E$e-E$indexNumberEnd' : 'E$e');
    return [if (s != null) 'S$s', ?ep].join(' · ');
  }

  EmbyItem copyWithUserData({bool? isPlayed, int? playbackPositionTicks, bool? isFavorite}) =>
      copyWith(isPlayed: isPlayed, playbackPositionTicks: playbackPositionTicks, isFavorite: isFavorite);

  static const _keep = Object();

  EmbyItem copyWith({
    String? name,
    String? overview,
    Object? tagline = _keep,
    List<String>? genres,
    String? seriesName,
    String? seasonName,
    String? localizedPosterPath,
    String? localizedLogoPath,
    String? localizedBackdropPath,
    String? localizedStillPath,
    int? localizedCollectionId,
    String? localizedCollectionName,
    List<Person>? people,
    bool? isPlayed,
    int? playbackPositionTicks,
    bool? isFavorite,
  }) {
    return EmbyItem(
      id: id, name: name ?? this.name, type: type, originalTitle: originalTitle,
      overview: overview ?? this.overview,
      tagline: identical(tagline, _keep) ? this.tagline : tagline as String?,
      productionYear: productionYear, premiereDate: premiereDate,
      endDate: endDate, status: status, officialRating: officialRating,
      communityRating: communityRating, criticRating: criticRating, genres: genres ?? this.genres,
      studios: studios, runTimeTicks: runTimeTicks, primaryImageTag: primaryImageTag,
      primaryImageAspectRatio: primaryImageAspectRatio, thumbImageTag: thumbImageTag,
      logoImageTag: logoImageTag, backdropImageTags: backdropImageTags,
      parentBackdropItemId: parentBackdropItemId, parentBackdropImageTags: parentBackdropImageTags,
      parentLogoItemId: parentLogoItemId, parentLogoImageTag: parentLogoImageTag,
      parentThumbItemId: parentThumbItemId, parentThumbImageTag: parentThumbImageTag,
      seriesPrimaryImageTag: seriesPrimaryImageTag, seriesId: seriesId,
      seriesName: seriesName ?? this.seriesName, seasonId: seasonId,
      seasonName: seasonName ?? this.seasonName, parentId: parentId, indexNumber: indexNumber,
      indexNumberEnd: indexNumberEnd, parentIndexNumber: parentIndexNumber,
      locationType: locationType, isFolder: isFolder, childCount: childCount,
      recursiveItemCount: recursiveItemCount,
      isPlayed: isPlayed ?? this.isPlayed,
      playbackPositionTicks: playbackPositionTicks ?? this.playbackPositionTicks,
      playedPercentage: playedPercentage, unplayedItemCount: unplayedItemCount,
      isFavorite: isFavorite ?? this.isFavorite, lastPlayedDate: lastPlayedDate,
      providerIds: providerIds, people: people ?? this.people, mediaSources: mediaSources, partCount: partCount,
      introStartTicks: introStartTicks, introEndTicks: introEndTicks,
      creditsStartTicks: creditsStartTicks,
      localizedPosterPath: localizedPosterPath ?? this.localizedPosterPath,
      localizedLogoPath: localizedLogoPath ?? this.localizedLogoPath,
      localizedBackdropPath: localizedBackdropPath ?? this.localizedBackdropPath,
      localizedStillPath: localizedStillPath ?? this.localizedStillPath,
      localizedCollectionId: localizedCollectionId ?? this.localizedCollectionId,
      localizedCollectionName: localizedCollectionName ?? this.localizedCollectionName,
    );
  }

  factory EmbyItem.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] is Map ? json['ImageTags'] as Map : const {};
    final userData = json['UserData'] is Map ? json['UserData'] as Map : const {};

    final providerIds = <String, String>{};
    final rawIds = json['ProviderIds'];
    if (rawIds is Map) {
      rawIds.forEach((k, v) {
        if (k is String && v != null && '$v'.isNotEmpty) providerIds[k] = '$v';
      });
    }

    final sources = <MediaSourceInfo>[];
    final rawSources = json['MediaSources'];
    if (rawSources is List) {
      for (final s in rawSources) {
        if (s is Map) sources.add(MediaSourceInfo.fromJson(s.cast<String, dynamic>()));
      }
    }

    final (introStart, introEnd, creditsStart) = _markers(json['Chapters']);
    final taglines = json['Taglines'];

    return EmbyItem(
      id: _str(json['Id']) ?? '',
      name: _str(json['Name']) ?? '',
      type: _str(json['Type']) ?? '',
      originalTitle: _str(json['OriginalTitle']),
      overview: _str(json['Overview']),
      tagline: taglines is List && taglines.isNotEmpty ? _str(taglines.first) : null,
      productionYear: _int(json['ProductionYear']),
      premiereDate: _date(json['PremiereDate']),
      endDate: _date(json['EndDate']),
      status: _str(json['Status']),
      officialRating: _str(json['OfficialRating']),
      communityRating: _double(json['CommunityRating']),
      criticRating: _double(json['CriticRating']),
      genres: _strings(json['Genres']),
      studios: _strings(json['Studios']),
      runTimeTicks: _int(json['RunTimeTicks']),
      primaryImageTag: _str(imageTags['Primary']),
      primaryImageAspectRatio: _double(json['PrimaryImageAspectRatio']),
      thumbImageTag: _str(imageTags['Thumb']),
      logoImageTag: _str(imageTags['Logo']),
      backdropImageTags: _strings(json['BackdropImageTags']),
      parentBackdropItemId: _str(json['ParentBackdropItemId']),
      parentBackdropImageTags: _strings(json['ParentBackdropImageTags']),
      parentLogoItemId: _str(json['ParentLogoItemId']),
      parentLogoImageTag: _str(json['ParentLogoImageTag']),
      parentThumbItemId: _str(json['ParentThumbItemId']),
      parentThumbImageTag: _str(json['ParentThumbImageTag']),
      seriesPrimaryImageTag: _str(json['SeriesPrimaryImageTag']),
      seriesId: _str(json['SeriesId']),
      seriesName: _str(json['SeriesName']),
      seasonId: _str(json['SeasonId']),
      seasonName: _str(json['SeasonName']),
      parentId: _str(json['ParentId']),
      indexNumber: _int(json['IndexNumber']),
      indexNumberEnd: _int(json['IndexNumberEnd']),
      parentIndexNumber: _int(json['ParentIndexNumber']),
      locationType: _str(json['LocationType']),
      isFolder: json['IsFolder'] == true,
      childCount: _int(json['ChildCount']),
      recursiveItemCount: _int(json['RecursiveItemCount']),
      isPlayed: userData['Played'] == true,
      playbackPositionTicks: _int(userData['PlaybackPositionTicks']),
      playedPercentage: _double(userData['PlayedPercentage']),
      unplayedItemCount: _int(userData['UnplayedItemCount']),
      isFavorite: userData['IsFavorite'] == true,
      lastPlayedDate: _date(userData['LastPlayedDate']),
      providerIds: providerIds,
      people: [for (final p in (json['People'] as List? ?? const [])) ?Person.fromJson(p)],
      mediaSources: sources,
      partCount: _int(json['PartCount']),
      introStartTicks: introStart,
      introEndTicks: introEnd,
      creditsStartTicks: creditsStart,
    );
  }

  static (int?, int?, int?) _markers(Object? chapters) {
    int? introStart, introEnd, creditsStart;
    if (chapters is! List) return (null, null, null);
    for (final c in chapters) {
      if (c is! Map) continue;
      final start = _int(c['StartPositionTicks']) ?? 0;
      switch (c['MarkerType']) {
        case 'IntroStart':
          introStart ??= start;
        case 'IntroEnd':
          introEnd ??= start;
        case 'CreditsStart':
          creditsStart ??= start;
        case 'Chapter':
          final name = (_str(c['Name']) ?? '').toLowerCase();
          if (name.contains('credits')) creditsStart ??= start;
      }
    }
    return (introStart, introEnd, creditsStart);
  }
}
