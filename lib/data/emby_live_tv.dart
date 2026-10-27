import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import '../services/janus/janus_service.dart';

final class TvProgram {
  const TvProgram({
    required this.id,
    required this.channelId,
    required this.title,
    required this.start,
    required this.end,
    this.episodeTitle,
    this.overview,
  });

  final String id;
  final String channelId;
  final String title;
  final String? episodeTitle;
  final String? overview;
  final DateTime start;
  final DateTime end;

  bool isOn(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  double progress(DateTime now) =>
      (now.difference(start).inSeconds / end.difference(start).inSeconds.clamp(1, 1 << 30)).clamp(0.0, 1.0);

  static TvProgram? fromJson(Map<String, dynamic> j, {String? channelId}) {
    final start = DateTime.tryParse('${j['StartDate']}')?.toLocal();
    final end = DateTime.tryParse('${j['EndDate']}')?.toLocal();
    final id = j['Id'];
    if (start == null || end == null || id is! String) return null;
    final episode = j['EpisodeTitle'];
    final overview = j['Overview'];
    return TvProgram(
      id: id,
      channelId: (j['ChannelId'] as String?) ?? channelId ?? '',
      title: (j['Name'] as String?) ?? '',
      episodeTitle: episode is String && episode.isNotEmpty ? episode : null,
      overview: overview is String && overview.isNotEmpty ? overview : null,
      start: start,
      end: end,
    );
  }
}

final class TvChannel {
  const TvChannel({required this.id, required this.name, this.number, this.imageTag, this.current});

  final String id;
  final String name;
  final String? number;
  final String? imageTag;
  final TvProgram? current;

  EmbyItem asItem() => EmbyItem(
        id: id,
        name: name,
        type: 'TvChannel',
        overview: current?.title,
        primaryImageTag: imageTag,
      );

  static TvChannel? fromJson(Map<String, dynamic> j) {
    final id = j['Id'];
    if (id is! String) return null;
    final tags = j['ImageTags'];
    final number = j['ChannelNumber'] ?? j['Number'];
    final current = j['CurrentProgram'];
    return TvChannel(
      id: id,
      name: (j['Name'] as String?) ?? '',
      number: number == null || '$number'.isEmpty ? null : '$number',
      imageTag: tags is Map ? tags['Primary'] as String? : null,
      current: current is Map ? TvProgram.fromJson(current.cast<String, dynamic>(), channelId: id) : null,
    );
  }
}

final class EmbyLiveTv {
  EmbyLiveTv(this._janus);

  final JanusService _janus;

  String get _userId => _janus.session.userId;

  Future<bool> available() async {
    try {
      final json = await _janus.client.getJson('/LiveTv/Channels', queryParameters: {
        'UserId': _userId,
        'Limit': '1',
        'EnableImages': 'false',
        'EnableUserData': 'false',
        'EnableTotalRecordCount': 'true',
      });
      final total = (json['TotalRecordCount'] as num?)?.toInt() ?? (json['Items'] as List?)?.length ?? 0;
      debugPrint('[livetv] Emby Live TV: $total channel(s)');
      return total > 0;
    } catch (e) {
      debugPrint('[livetv] Emby Live TV not available: $e');
      return false;
    }
  }

  Future<({List<TvChannel> channels, int total})> channels({int start = 0, int limit = 300}) async {
    final json = await _janus.client.getJson('/LiveTv/Channels', queryParameters: {
      'UserId': _userId,
      'StartIndex': '$start',
      'Limit': '$limit',
      'AddCurrentProgram': 'true',
      'EnableImageTypes': 'Primary',
      'ImageTypeLimit': '1',
      'EnableUserData': 'false',
      'EnableTotalRecordCount': 'true',
    });
    final items = json['Items'] as List? ?? const [];
    final channels = [for (final raw in items) if (raw is Map) ?TvChannel.fromJson(raw.cast<String, dynamic>())];
    final total = (json['TotalRecordCount'] as num?)?.toInt() ?? start + channels.length;
    debugPrint('[livetv] channels $start-${start + channels.length} of $total, '
        '${channels.where((c) => c.current != null).length} with guide data');
    return (channels: channels, total: total);
  }

  Future<List<TvProgram>> guide(String channelId, {DateTime? from, Duration span = const Duration(hours: 24)}) async {
    final start = (from ?? DateTime.now()).toUtc();
    final json = await _janus.client.getJson('/LiveTv/Programs', queryParameters: {
      'UserId': _userId,
      'ChannelIds': channelId,
      'MinEndDate': start.toIso8601String(),
      'MaxStartDate': start.add(span).toIso8601String(),
      'SortBy': 'StartDate',
      'Fields': 'Overview',
      'EnableImages': 'false',
      'EnableUserData': 'false',
      'Limit': '60',
    });
    final items = json['Items'] as List? ?? const [];
    return [for (final raw in items) if (raw is Map) ?TvProgram.fromJson(raw.cast<String, dynamic>(), channelId: channelId)];
  }

  Uri? logo(TvChannel c, {int width = 240}) =>
      c.imageTag == null ? null : _janus.client.buildPrimaryImageUri(c.id, maxWidth: width, tag: c.imageTag);
}
