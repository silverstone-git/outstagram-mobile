// README screenshots: the real app on fake data (fixtures.dart), rendered at phone size.
//
//   flutter test test/screenshots --update-goldens --dart-define=SCREENSHOTS=true
//   python tool/screenshots/compose.py     # framed PNGs + the banner in docs/screenshots/
//
// Skipped in normal `flutter test` runs (fonts differ per machine, so they aren't goldens to compare against).
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:outstagram/app/app.dart';
import 'package:outstagram/app/router.dart';
import 'package:outstagram/app/theme.dart';
import 'package:outstagram/core/auth/auth_controller.dart';
import 'package:outstagram/core/auth/session.dart';
import 'package:outstagram/core/auth/session_store.dart';
import 'package:outstagram/core/net/api_client.dart';
import 'package:outstagram/features/tutor/tutor_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';
import 'fixtures.dart';

const enabled = bool.fromEnvironment('SCREENSHOTS');

class _Store extends SessionStore {
  @override
  Future<Session?> read() async => Session(
        accessToken: 'demo',
        refreshToken: 'demo',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        user: AppUser.fromJson(Map<String, dynamic>.from(me)),
      );

  @override
  Future<void> write(Session s) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  setUpAll(() async {
    if (!enabled) return;
    await loadFonts();
    debugFontFamily = 'Roboto';
    debugFontFamilyFallback = const ['SegoeEmoji', 'SegoeSymbol'];
    CachedNetworkImageProvider.defaultCacheManager = FakeImageCache();
  });

  /// Opens [location] in the app, lets [act] drive it, then saves `out/<name>.png`.
  Future<void> shoot(WidgetTester tester, String name, String location,
      {Future<void> Function(WidgetTester t, GoRouter r)? act}) async {
    SharedPreferences.setMockInitialValues({});
    // plugins that have no test implementation: answer "nothing" instead of throwing
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in ['receive_sharing_intent/messages', 'home_widget', 'home_widget/background']) {
      m.setMockMethodCallHandler(MethodChannel(c), (call) async => call.method == 'getInitialMedia' ? '[]' : null);
    }
    for (final c in ['receive_sharing_intent/events-media', 'home_widget/updates']) {
      m.setMockStreamHandler(EventChannel(c), MockStreamHandler.inline(onListen: (_, _) {}));
    }
    // pigeon (wakelock while an exam runs): reply "ok"
    for (final api in ['toggle', 'isEnabled']) {
      m.setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.$api',
          (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]));
    }
    tester.view.physicalSize = const Size(1080, 2340); // Galaxy S22
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final api = FakeApi(routes);
    final container = ProviderContainer(overrides: [
      sessionStoreProvider.overrideWithValue(_Store()),
      dioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = api),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const OutstagramApp()));
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    final router = container.read(routerProvider);
    router.go(location);
    await settle();
    if (act != null) {
      await act(tester, router);
      await settle();
    }
    if (api.unknown.isNotEmpty) debugPrint('[$name] unmocked: ${api.unknown.join(', ')}');
    await expectLater(find.byType(OutstagramApp), matchesGoldenFile('out/$name.png'));
  }

  testWidgets('feed', (t) => shoot(t, 'feed', '/feed'), skip: !enabled);
  testWidgets('exams', (t) => shoot(t, 'exams', '/exams'), skip: !enabled);
  testWidgets('streak', (t) => shoot(t, 'streak', '/streak'), skip: !enabled);
  testWidgets('profile', (t) => shoot(t, 'profile', '/profile'), skip: !enabled);
  testWidgets('exam', (t) => shoot(t, 'exam', '/exams', act: (t, r) async {
        await t.tap(find.text('Quantum Mechanics').first);
        await t.pump(const Duration(milliseconds: 300));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.tap(find.text('A').last); // pick an answer
        await t.pump(const Duration(milliseconds: 300));
      }), skip: !enabled);
  testWidgets('tutor', (t) => shoot(t, 'tutor', '/feed', act: (t, r) async {
        r.push(tutorPath('a1', 'q1'),
            extra: TutorQuestion(text: questions[0]['question']! as String, topic: 'Quantum Mechanics',
                examTitle: 'Quantum Mechanics · quick practice'));
      }), skip: !enabled);
}
