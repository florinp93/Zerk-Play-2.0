import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../app/hub_link.dart';

final class RoomMember {
  const RoomMember(
      {required this.id, required this.name, required this.device, this.userId, this.watching, this.ready = false});

  final String id;

  final String? userId;
  final String name;
  final String device;

  final String? watching;

  final bool ready;
}

final class RoomState {
  const RoomState({
    required this.code,
    required this.members,
    this.itemId,
    this.itemTitle,
    this.live,
    this.playing = false,
    this.running = false,
    this.position = 0,
    this.at = 0,
    this.rev = 0,
    this.by,
    this.action,
  });

  final String code;
  final List<RoomMember> members;
  final String? itemId;
  final String? itemTitle;

  final Map<String, Object?>? live;

  final bool playing;

  final bool running;

  final double position;
  final int at;
  final int rev;

  final String? by;
  final String? action;

  Duration positionAt(int serverNow) {
    final secs = running ? position + (serverNow - at) / 1000 : position;
    return Duration(milliseconds: (secs * 1000).round());
  }

  RoomMember? member(String? id) => members.where((m) => m.id == id).firstOrNull;

  List<RoomMember> get waitingFor =>
      [for (final m in members) if (itemId != null && m.watching == itemId && !m.ready) m];

  static RoomState fromJson(Map json) => RoomState(
        code: json['code'] as String,
        members: [
          for (final m in json['members'] as List? ?? const [])
            if (m is Map)
              RoomMember(
                id: m['id'] as String,
                userId: m['user'] as String?,
                name: m['name'] as String? ?? '',
                device: m['device'] as String? ?? '',
                watching: m['watching'] as String?,
                ready: m['ready'] == true,
              ),
        ],
        itemId: (json['item'] as Map?)?['id'] as String?,
        itemTitle: (json['item'] as Map?)?['title'] as String?,
        live: ((json['item'] as Map?)?['live'] as Map?)?.cast<String, Object?>(),
        playing: json['playing'] == true,
        running: json['running'] == true,
        position: (json['position'] as num?)?.toDouble() ?? 0,
        at: (json['at'] as num?)?.toInt() ?? 0,
        rev: (json['rev'] as num?)?.toInt() ?? 0,
        by: json['by'] as String?,
        action: json['action'] as String?,
      );
}

enum TogetherProblem { unreachable, signedOut, noRoom, roomFull }

final class WatchTogether extends ChangeNotifier {
  WatchTogether({required this.credentials, required this.device});

  final ({String token, String userId})? Function() credentials;

  final String device;

  Uri? _endpoint;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  var _retries = 0;

  String? _wanted;

  Map<String, Object?>? _watch;
  bool? _ready;

  final _updates = StreamController<RoomState>.broadcast();

  bool get available => _endpoint != null;

  String? get me => _me;
  String? _me;

  RoomState? get room => _room;
  RoomState? _room;

  bool get busy => _wanted != null && _room == null;

  TogetherProblem? get problem => _problem;
  TogetherProblem? _problem;

  Stream<RoomState> get updates => _updates.stream;

  int get serverNow => DateTime.now().millisecondsSinceEpoch + _offset;
  int _offset = 0;
  final _samples = <({int rtt, int offset})>[];

  Future<void> detect({Uri? server}) async {
    final base = server ?? (HubLink.features.together ? HubLink.base : null);
    final who = credentials();
    if (base == null || who == null) return _unavailable();
    try {
      final res = await http
          .get(base.resolve('sync/health'), headers: {'X-Emby-Token': who.token, 'X-Emby-User-Id': who.userId})
          .timeout(const Duration(seconds: 4));
      final json = res.statusCode == 200 ? jsonDecode(res.body) : null;
      if (json is Map && json['service'] == 'zerk-sync' && json['enabled'] == true) {
        final ws = base.resolve('sync');
        final endpoint = ws.replace(scheme: ws.scheme == 'https' ? 'wss' : 'ws');
        if (endpoint == _endpoint) return;
        if (_endpoint != null) leave();
        _endpoint = endpoint;
        debugPrint('[together] available at $_endpoint');
        notifyListeners();
      } else if (res.statusCode == 200) {
        _unavailable();
      }
    } catch (_) {
    }
  }

  void _unavailable() {
    if (_endpoint == null) return;
    leave();
    _endpoint = null;
    notifyListeners();
  }

  Future<void> create() => _enter('');

  Future<void> join(String code) => _enter(code.trim().toUpperCase());

  Future<void> _enter(String code) async {
    _problem = null;
    _wanted = code;
    _watch = null;
    _ready = null;
    notifyListeners();
    if (_me != null) {
      _send(code.isEmpty ? {'type': 'create'} : {'type': 'join', 'code': code});
    } else {
      await _connect();
    }
  }

  void leave() {
    _wanted = null;
    _watch = null;
    _ready = null;
    _room = null;
    _problem = null;
    _retries = 0;
    _disconnect();
    notifyListeners();
  }

  void watch(String itemId,
      {required String title, required Duration position, bool playing = true, Map<String, Object?>? live}) {
    _watch = {
      'type': 'watch',
      'itemId': itemId,
      'title': title,
      'position': _secs(position),
      'playing': playing,
      'live': ?live,
    };
    _ready = false;
    _send(_watch!);
  }

  void unwatch() {
    if (_watch == null) return;
    _watch = null;
    _ready = null;
    _send({'type': 'unwatch'});
  }

  void liveSource(int index) {
    final live = _watch?['live'];
    if (live is! Map) return;
    _watch = {..._watch!, 'live': {...live, 'first': index}};
    _send({'type': 'source', 'index': index});
  }

  void stop() {
    if (_watch == null) return;
    _watch = null;
    _ready = null;
    _send({'type': 'stop'});
  }

  void ready(bool ready) {
    if (_ready == ready || _watch == null) return;
    _ready = ready;
    _send({'type': 'ready', 'ready': ready});
  }

  void action(String type, Duration position) => _send({'type': type, 'position': _secs(position)});

  static double _secs(Duration d) => d.inMilliseconds / 1000;

  Future<void> _connect() async {
    final endpoint = _endpoint;
    if (endpoint == null || _channel != null) return;
    final who = credentials();
    if (who == null) return _fail(TogetherProblem.signedOut);
    final channel = _channel = WebSocketChannel.connect(endpoint);
    try {
      await channel.ready.timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[together] connect failed: $e');
      if (_channel == channel) _channel = null;
      return _connectionLost();
    }
    if (_channel != channel) return;
    _sub = channel.stream.listen(_onMessage, onDone: _connectionLost, onError: (_) => _connectionLost());
    _send({'type': 'hello', 'token': who.token, 'userId': who.userId, 'device': device}, force: true);
  }

  void _disconnect() {
    _retry?.cancel();
    _ping?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    unawaited(_channel?.sink.close());
    _channel = null;
    _me = null;
  }

  void _connectionLost() {
    final hadRoom = _room != null;
    _disconnect();
    if (_wanted == null) return;
    if (!hadRoom && _retries == 0) {
      _wanted = null;
      return _fail(TogetherProblem.unreachable);
    }
    final delay = Duration(seconds: [1, 2, 5, 10, 20][_retries.clamp(0, 4)]);
    _retries++;
    _retry = Timer(delay, () => unawaited(_connect()));
  }

  void _fail(TogetherProblem problem) {
    _problem = problem;
    notifyListeners();
  }

  void _send(Map<String, Object?> message, {bool force = false}) {
    if (_channel == null || (_me == null && !force)) return;
    _channel!.sink.add(jsonEncode(message));
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final json = jsonDecode(data);
    if (json is! Map) return;
    switch (json['type']) {
      case 'welcome':
        _me = json['you'] as String?;
        _retries = 0;
        _samples.clear();
        _startPing();
        final code = _wanted;
        if (code == null) return;
        _send(code.isEmpty ? {'type': 'create'} : {'type': 'join', 'code': code});
        if (_watch != null) _send(_watch!);
        if (_ready != null && _watch != null) _send({'type': 'ready', 'ready': _ready});
      case 'room':
        final room = RoomState.fromJson(json);
        _room = room;
        _wanted = room.code;
        _problem = null;
        _updates.add(room);
        notifyListeners();
      case 'closed':
        _room = null;
        notifyListeners();
      case 'pong':
        _onPong(json);
      case 'error':
        final problem = switch (json['code']) {
          'no-room' => TogetherProblem.noRoom,
          'room-full' => TogetherProblem.roomFull,
          'bad-hello' => TogetherProblem.signedOut,
          _ => null,
        };
        if (problem == null) return;
        _wanted = null;
        _room = null;
        _watch = null;
        _disconnect();
        _fail(problem);
    }
  }

  void _startPing() {
    _ping?.cancel();
    var sent = 0;
    void ping() {
      sent++;
      _send({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch});
    }

    ping();
    _ping = Timer.periodic(const Duration(milliseconds: 700), (t) {
      ping();
      if (sent >= 5) {
        t.cancel();
        _ping = Timer.periodic(const Duration(seconds: 15), (_) => ping());
      }
    });
  }

  void _onPong(Map json) {
    final sent = (json['t'] as num?)?.toInt();
    final server = (json['now'] as num?)?.toInt();
    if (sent == null || server == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rtt = now - sent;
    _samples.add((rtt: rtt, offset: server - (sent + rtt ~/ 2)));
    if (_samples.length > 8) _samples.removeAt(0);
    _offset = _samples.reduce((a, b) => a.rtt <= b.rtt ? a : b).offset;
  }

  @override
  void dispose() {
    _disconnect();
    unawaited(_updates.close());
    super.dispose();
  }
}
