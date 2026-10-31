import 'dart:async';

import 'package:flutter/foundation.dart';

import '../player_backend.dart';

final class OsdChoice {
  const OsdChoice({required this.id, required this.label, this.detail, this.selected = false});

  final String id;
  final String label;
  final String? detail;
  final bool selected;

  static List<OsdChoice> list(Object? raw) => [
        for (final e in (raw as List? ?? const []).cast<Map<Object?, Object?>>())
          OsdChoice(
            id: '${e['id']}',
            label: e['label'] as String? ?? '',
            detail: e['detail'] as String?,
            selected: e['selected'] == true,
          ),
      ];
}

final class OsdChapter {
  const OsdChapter({required this.start, this.title, this.image});

  final Duration start;
  final String? title;
  final Uri? image;

  static List<OsdChapter> list(Object? raw) => [
        for (final e in (raw is List ? raw : const []).whereType<Map<Object?, Object?>>())
          if (e['time'] case final num time)
            OsdChapter(
              start: Duration(milliseconds: (time * 1000).round()),
              title: e['title'] as String?,
              image: switch (Uri.tryParse(e['image'] as String? ?? '')) { final u? when u.hasScheme => u, _ => null },
            ),
      ];
}

final class NextUp {
  const NextUp({required this.title, this.subtitle, this.image, this.autoplay = false, this.countdown = 10});

  final String title;
  final String? subtitle;

  final Uri? image;
  final bool autoplay;
  final int countdown;
}

final class OsdModel extends ChangeNotifier {
  OsdModel({
    required this.state,
    required this.send,
    required this.togglePause,
    required this.seekTo,
    this.setVolume,
    this.toggleMute,
    this.setSpeed,
    this.setAspect,
    this.stats,
  });

  final ValueListenable<PlayerState> state;

  final void Function(String name, [String? arg]) send;
  final VoidCallback togglePause;
  final void Function(Duration position) seekTo;

  final void Function(double volume)? setVolume;
  final VoidCallback? toggleMute;

  final void Function(double speed)? setSpeed;
  final void Function(String mode)? setAspect;
  final Future<Map<String, Object?>> Function()? stats;

  double speed = 1;
  String aspect = 'fit';

  String phase = 'loading';
  String title = '';
  String subtitle = '';
  String? message;

  Uri? backdrop;
  Uri? logo;
  List<OsdChoice> audio = const [];
  List<OsdChoice> subs = const [];
  List<OsdChoice> versions = const [];
  Duration? introStart;
  Duration? introEnd;
  Duration? creditsStart;
  List<OsdChapter> chapters = const [];
  NextUp? next;
  double scope = 0;

  int seekForward = 10;
  int seekBack = 10;

  String? versionsTitle;

  bool zap = false;
  bool autoSkipIntro = false;

  double subtitleScale = 1;

  bool subtitleSearch = false;
  List<OsdChoice> subtitleLanguages = const [];
  Completer<({List<OsdChoice> results, String? error})>? _search;

  Future<({List<OsdChoice> results, String? error})> searchSubtitles(String language) {
    _search = Completer();
    send('subsearch', language);
    return _search!.future;
  }

  String? videoFormat;
  String? videoOutput;

  void Function(String text)? onToast;

  final subtitleLift = ValueNotifier<double>(0);

  @override
  void dispose() {
    subtitleLift.dispose();
    super.dispose();
  }

  void handle(String command, Object? data) {
    final m = data is Map ? data : const {};
    Duration? secs(Object? v) => v is num ? Duration(milliseconds: (v * 1000).round()) : null;
    switch (command) {
      case 'state':
        phase = m['phase'] as String? ?? phase;
        title = m['title'] as String? ?? '';
        subtitle = m['subtitle'] as String? ?? '';
        message = m['message'] as String?;
        backdrop = Uri.tryParse(m['backdrop'] as String? ?? '');
        logo = Uri.tryParse(m['logo'] as String? ?? '');
        if (backdrop?.hasScheme != true) backdrop = null;
        if (logo?.hasScheme != true) logo = null;
      case 'tracks':
        audio = OsdChoice.list(m['audio']);
        subs = OsdChoice.list(m['subs']);
      case 'versions':
        versions = OsdChoice.list(data);
      case 'segments':
        introStart = secs(m['introStart']);
        introEnd = secs(m['introEnd']);
        creditsStart = secs(m['creditsStart']);
      case 'chapters':
        chapters = OsdChapter.list(data);
      case 'next':
        next = data is Map
            ? NextUp(
                title: data['title'] as String? ?? '',
                subtitle: data['subtitle'] as String?,
                image: switch (Uri.tryParse(data['image'] as String? ?? '')) { final u? when u.hasScheme => u, _ => null },
                autoplay: data['autoplay'] == true,
                countdown: (data['countdown'] as num?)?.toInt() ?? 10,
              )
            : null;
      case 'config':
        seekForward = (m['seekForward'] as num?)?.toInt() ?? seekForward;
        seekBack = (m['seekBack'] as num?)?.toInt() ?? seekBack;
        scope = (m['scope'] as num?)?.toDouble() ?? 0;
        final aspectMode = switch (m['defaultAspect']) { 'zoom' => 'zoom', 'stretch' => 'fill', _ => 'fit' };
        if (aspectMode != aspect) {
          aspect = aspectMode;
          setAspect?.call(aspectMode);
        }
        versionsTitle = m['versionsTitle'] as String?;
        autoSkipIntro = m['autoSkipIntro'] == true;
        zap = m['zap'] == true;
        subtitleSearch = m['subtitleSearch'] == true;
        subtitleLanguages = OsdChoice.list(m['subLanguages']);
      case 'video':
        videoFormat = m['format'] as String?;
        videoOutput = m['output'] as String?;
      case 'subsearch':
        final search = _search;
        _search = null;
        if (search != null && !search.isCompleted) search.complete((results: OsdChoice.list(m['results']), error: m['error'] as String?));
        return;
      case 'toast':
        if (data is String) onToast?.call(data);
        return;
      default:
        return;
    }
    notifyListeners();
  }
}
