import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/auth/auth_controller.dart';
import 'package:outstagram/core/auth/session.dart';
import 'package:outstagram/core/auth/session_store.dart';
import 'package:outstagram/core/net/api_client.dart';
import 'package:outstagram/core/net/api_error.dart';

class MemoryStore extends SessionStore {
  Session? saved;
  @override
  Future<Session?> read() async => saved;
  @override
  Future<void> write(Session s) async => saved = s;
  @override
  Future<void> clear() async => saved = null;
}

typedef Handler = FutureOr<(int, Object?)> Function(RequestOptions o);

/// Fake outsie: routes every request through [handler] and records it.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.handler);
  final Handler handler;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls.add('${o.method} ${o.path} ${o.headers['Authorization'] ?? '-'}');
    final (status, data) = await handler(o);
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const user = {'user_id': 1, 'username': 'asha', 'fullname': 'Asha', 'bio': null};

Session session(String access, {String refresh = 'r0', Duration ttl = const Duration(minutes: 30)}) =>
    Session(accessToken: access, refreshToken: refresh, expiresAt: DateTime.now().add(ttl), user: AppUser.fromJson(user));

Map<String, dynamic> authBody(String access, String refresh) =>
    {'access_token': access, 'token_type': 'bearer', 'expires_in': 1800, 'refresh_token': refresh, 'user': user};

Future<(ProviderContainer, FakeServer, MemoryStore)> setUpApp(Session? initial, Handler handler) async {
  final store = MemoryStore()..saved = initial;
  final server = FakeServer(handler);
  final container = ProviderContainer(overrides: [
    sessionStoreProvider.overrideWithValue(store),
    bareDioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server),
  ]);
  container.read(dioProvider).httpClientAdapter = server;
  await container.read(authControllerProvider.future);
  return (container, server, store);
}

void main() {
  group('AuthInterceptor', () {
    test('401 -> one refresh -> retry with the new token; concurrent requests share the refresh', () async {
      var refreshes = 0;
      final (c, server, store) = await setUpApp(session('old'), (o) async {
        if (o.path == '/auth/refresh') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return (200, authBody('new', 'r1'));
        }
        return o.headers['Authorization'] == 'Bearer new' ? (200, {'ok': true}) : (401, {'detail': 'expired'});
      });

      final api = c.read(apiProvider);
      final results = await Future.wait([api.get<Map>('/me/stats'), api.get<Map>('/feed')]);

      expect(results, everyElement(equals({'ok': true})));
      expect(refreshes, 1);
      expect(store.saved!.accessToken, 'new');
      expect(store.saved!.refreshToken, 'r1');
      expect(server.calls.where((x) => x.contains('/auth/refresh')).single, contains('-')); // no bearer on refresh
    });

    test('a stale token is refreshed before the request leaves', () async {
      final (c, server, _) = await setUpApp(session('stale', ttl: const Duration(seconds: 10)), (o) {
        if (o.path == '/auth/refresh') return (200, authBody('fresh', 'r1'));
        return (200, {'auth': o.headers['Authorization']});
      });

      final r = await c.read(apiProvider).get<Map>('/me/stats');

      expect(r['auth'], 'Bearer fresh');
      expect(server.calls.first, startsWith('POST /auth/refresh'));
    });

    test('refresh refused -> signed out, original error surfaces', () async {
      final (c, _, store) = await setUpApp(session('old'), (o) {
        if (o.path == '/auth/refresh') return (401, {'detail': 'Session expired, please sign in again'});
        return (401, {'detail': 'Could not validate credentials'});
      });

      await expectLater(
        c.read(apiProvider).get<Map>('/me/stats'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(c.read(authControllerProvider).value, isNull);
      expect(store.saved, isNull);
    });

    test('offline refresh keeps the session', () async {
      final (c, _, store) = await setUpApp(session('stale', ttl: Duration.zero), (o) {
        if (o.path == '/auth/refresh') throw DioException.connectionError(requestOptions: o, reason: 'offline');
        return (200, {'ok': true});
      });

      await c.read(apiProvider).get<Map>('/me/stats');
      expect(store.saved, isNotNull);
      expect(c.read(authControllerProvider).value, isNotNull);
    });
  });

  group('sign-in', () {
    test('password sign-in stores the session', () async {
      final (c, server, store) = await setUpApp(null, (o) {
        expect(o.contentType, Headers.formUrlEncodedContentType);
        return (200, authBody('a', 'r'));
      });
      await c.read(authControllerProvider.notifier).signInWithPassword(' asha ', 'pw');
      expect(store.saved!.user.username, 'asha');
      expect(server.calls.single, startsWith('POST /login'));
    });

    test('sign-out revokes the refresh token on the server', () async {
      final (c, server, store) = await setUpApp(session('a', refresh: 'rX'), (o) => (204, null));
      await c.read(authControllerProvider.notifier).signOut();
      expect(store.saved, isNull);
      expect(server.calls.single, startsWith('POST /auth/logout'));
    });
  });

  group('ApiException', () {
    RequestOptions ro() => RequestOptions(path: '/x');
    ApiException fromResponse(int status, Object data) => ApiException.from(DioException(
          requestOptions: ro(),
          response: Response(requestOptions: ro(), statusCode: status, data: data),
        ));

    test('paywall detail', () {
      final e = fromResponse(429, {
        'detail': {'code': 'ai_quota', 'message': 'Hourly limit reached', 'upgrade': true}
      });
      expect(e.isPaywall, isTrue);
      expect(e.code, 'ai_quota');
      expect(e.message, 'Hourly limit reached');
    });

    test('422 validation list', () {
      final e = fromResponse(422, {
        'detail': [
          {'loc': ['body', 'email'], 'msg': 'value is not a valid email address'}
        ]
      });
      expect(e.message, 'email: value is not a valid email address');
      expect(e.isPaywall, isFalse);
    });

    test('no response = network', () {
      final e = ApiException.from(DioException.connectionError(requestOptions: ro(), reason: 'x'));
      expect(e.isNetwork, isTrue);
    });
  });
}
