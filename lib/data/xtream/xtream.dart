import 'dart:convert';

import 'package:http/http.dart' as http;

final class XtreamAccount {
  const XtreamAccount(this.username, this.password);

  final String username;
  final String password;

  @override
  bool operator ==(Object other) =>
      other is XtreamAccount && other.username == username && other.password == password;

  @override
  int get hashCode => Object.hash(username, password);
}

final class AccountStatus {
  const AccountStatus(this.account, this.number, {this.active = 0, this.max = 1, this.problem});

  final XtreamAccount account;

  final int number;

  final int active;
  final int max;

  final String? problem;

  bool get usable => problem == null;
  bool get free => usable && (max <= 0 || active < max);
}

final class AccountsBusy implements Exception {
  const AccountsBusy(this.statuses);

  final List<AccountStatus> statuses;
}

final class XtreamServer {
  XtreamServer(String server, this.accounts) : base = _base(server);

  final String base;
  final List<XtreamAccount> accounts;

  bool get configured => base.isNotEmpty && accounts.isNotEmpty;

  String get key => '$base|${accounts.map((a) => a.username).join(',')}';

  Uri api(XtreamAccount a, [String? action]) => Uri.parse('$base/player_api.php').replace(
        queryParameters: {'username': a.username, 'password': a.password, 'action': ?action},
      );

  Uri guide(XtreamAccount a) =>
      Uri.parse('$base/xmltv.php').replace(queryParameters: {'username': a.username, 'password': a.password});

  Uri stream(XtreamAccount a, int streamId) =>
      Uri.parse('$base/live/${Uri.encodeComponent(a.username)}/${Uri.encodeComponent(a.password)}/$streamId.ts');

  Future<AccountStatus> status(XtreamAccount a) async {
    final number = accounts.indexOf(a) + 1;
    try {
      final res = await http.get(api(a)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return AccountStatus(a, number, problem: 'HTTP ${res.statusCode}');
      final info = (jsonDecode(res.body) as Map)['user_info'] as Map?;
      if (info == null || '${info['auth']}' == '0') return AccountStatus(a, number, problem: 'wrong username or password');
      final state = info['status']?.toString();
      final expires = int.tryParse('${info['exp_date']}');
      final expired = expires != null && DateTime.fromMillisecondsSinceEpoch(expires * 1000).isBefore(DateTime.now());
      return AccountStatus(
        a,
        number,
        active: int.tryParse('${info['active_cons']}') ?? 0,
        max: int.tryParse('${info['max_connections']}') ?? 1,
        problem: expired ? 'Expired' : (state == null || state == 'Active' ? null : state),
      );
    } catch (e) {
      return AccountStatus(a, number, problem: e.toString());
    }
  }

  Future<List<AccountStatus>> statuses() => Future.wait(accounts.map(status));

  static String _base(String server) {
    var s = server.trim();
    if (s.isEmpty) return '';
    if (!s.contains('://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

abstract final class AccountPool {
  static Future<AccountStatus> pick(XtreamServer server, {Set<XtreamAccount> avoid = const {}}) async {
    final all = await server.statuses();
    final candidates = all.where((s) => !avoid.contains(s.account));
    final free = candidates.where((s) => s.free).firstOrNull;
    if (free != null) return free;
    final until = _releasedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final mine = candidates.where((s) => s.usable && s.account == _released).firstOrNull;
      if (mine != null) return mine;
    }
    throw AccountsBusy(all);
  }

  static XtreamAccount? _released;
  static DateTime? _releasedUntil;

  static void release(XtreamAccount account) {
    _released = account;
    _releasedUntil = DateTime.now().add(const Duration(minutes: 2));
  }
}
