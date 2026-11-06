import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zerk_play/app/app_services.dart';
import 'package:zerk_play/app/hub_link.dart';
import 'package:zerk_play/core/emby/server_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('when the owner\'s plan ends, a code-linked app drops the hub settings and signs out', () async {
    var planActive = true;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((r) async {
      final path = r.uri.path;
      Object body = {};
      var status = 200;
      if (path == '/api/app/link') {
        if (planActive) {
          body = {
            'hub': '$base/s/abc/',
            'server': {'name': 'Test Fin', 'url': base, 'kind': 'jellyfin'},
            'tmdbApiKey': 'tmdb-from-hub',
            'seerr': {'enabled': true, 'url': '$base/s/abc/seerr-proxy'},
            'features': {'requests': true},
          };
        } else {
          status = 410;
          body = {'code': 'inactive', 'message': 'This sync code no longer works because the server owner\'s plan has ended.'};
        }
      } else if (path.endsWith('/Users/AuthenticateByName')) {
        body = {
          'AccessToken': 'tok',
          'ServerId': 'srv',
          'User': {'Id': 'aaaa1111bbbb2222cccc3333dddd4444', 'Name': 'Ana'},
        };
      } else if (path.endsWith('/System/Info/Public')) {
        body = {'Id': 'srv', 'ServerName': 'Test Fin', 'Version': '10.10.7', 'ProductName': 'Jellyfin Server'};
      } else if (path.contains('/Items') || path.contains('/Views')) {
        body = {'Items': [], 'TotalRecordCount': 0};
      }
      await utf8.decodeStream(r);
      r.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await r.response.close();
    });
    addTearDown(() => server.close(force: true));

    SharedPreferences.setMockInitialValues({});
    final services = await AppServices.create();
    await services.linkHub('K7QM-2XRP-9HDA', hub: base);
    expect(services.settings.tmdbApiKey, 'tmdb-from-hub');
    await services.signIn(server: base, kind: ServerKind.jellyfin, username: 'ana', password: 'pw');
    expect(services.isSignedIn, true);

    await services.refreshHub();
    expect(services.isSignedIn, true, reason: 'still active');

    planActive = false;
    await services.refreshHub();
    expect(HubLink.linked, false);
    expect(services.isSignedIn, false);
    expect(services.settings.tmdbApiKey, '');
    expect(services.settings.seerrUrl, '');
    expect(HubLink.droppedMessage, contains('plan has ended'));
  });
}
