import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/app/router.dart' show appLinkTarget;
import 'package:outstagram/core/net/api_client.dart';
import 'package:outstagram/core/net/api_error.dart';
import 'package:outstagram/features/compose/share_intent.dart';
import 'package:outstagram/features/exams/engine/engine.dart';
import 'package:outstagram/features/exams/exam_api.dart';
import 'package:outstagram/features/exams/offline_packs.dart';
import 'package:outstagram/features/feed/models.dart';
import 'package:outstagram/features/streak/streak_api.dart';
import 'package:outstagram/features/streak/streak_visuals.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:dio/dio.dart';

class _OfflineApi extends ExamApi {
  _OfflineApi(this.error) : super(Api(Dio()));
  final ApiException error;
  var calls = 0;

  @override
  Future<List<Question>> sample(String slug, int count) async {
    calls++;
    throw error;
  }
}

void main() {
  group('App Links', () {
    test('share links map onto app routes', () {
      expect(appLinkTarget(Uri.parse('https://aryan.cfd/outstagram/p/?id=abc-123')), '/p/abc-123');
      expect(appLinkTarget(Uri.parse('/outstagram/p?id=x')), '/p/x');
      expect(appLinkTarget(Uri.parse('https://aryan.cfd/outstagram/u/?name=asha_v')), '/u/asha_v');
      expect(appLinkTarget(Uri.parse('https://aryan.cfd/outstagram/p/')), '/feed', reason: 'no id');
      expect(appLinkTarget(Uri.parse('https://aryan.cfd/outstagram/u/?name=')), '/feed');
    });

    test('the app\'s own links are navigation, not shared content', () {
      expect(isOwnDeepLink('outstagram://app/tutor'), isTrue);
      expect(isOwnDeepLink('https://aryan.cfd/outstagram/p/?id=abc'), isTrue);
      expect(isOwnDeepLink(' https://aryan.cfd/outstagram/u/?name=asha '), isTrue);
      expect(isOwnDeepLink('Look at this https://aryan.cfd/outstagram/p/?id=abc'), isFalse, reason: 'text around it');
      expect(isOwnDeepLink('https://example.com/p/?id=abc'), isFalse);
    });
  });

  test('shared videos become draft videos; missing files are skipped', () async {
    final dir = Directory.systemTemp.createTempSync('share');
    final v = File('${dir.path}/clip.mp4')..writeAsBytesSync(List.filled(10, 1));
    final d = await draftFromShared([
      SharedMediaFile(path: v.path, type: SharedMediaType.video),
      SharedMediaFile(path: '${dir.path}/gone.mp4', type: SharedMediaType.video),
      SharedMediaFile(path: 'https://aryan.cfd/outstagram/p/?id=1', type: SharedMediaType.url),
    ]);
    expect(d.videos, [v.path]);
    expect(d.caption, isNull, reason: 'own App Link dropped');
    expect(d.isEmpty, isFalse);
    dir.deleteSync(recursive: true);
  });

  group('streak extras', () {
    test('freeze fields parse, with defaults for older servers', () {
      final s = StreakStatus.fromJson({
        'current': 9,
        'freezes': 1,
        'freezes_max': 2,
        'freeze_every': 7,
        'freezes_used': 1,
        'frozen_days': ['2026-06-08'],
        'last_day': '2026-06-09',
        'tz': 'Asia/Kolkata',
      });
      expect((s.freezes, s.freezesUsed, s.lastDay, s.tz), (1, 1, '2026-06-09', 'Asia/Kolkata'));
      expect(s.frozen(DateTime(2026, 6, 8)), isTrue);
      expect(s.done(DateTime(2026, 6, 8)), isFalse);
      expect(s.daysToFreeze, 5); // 9 -> 14
      final full = StreakStatus.fromJson({'current': 3, 'freezes': 2});
      expect(full.daysToFreeze, isNull);
      final old = StreakStatus.fromJson({'current': 3});
      expect((old.freezes, old.freezesMax, old.freezeEvery), (0, 2, 7));
    });

    test('friends and profiles carry streaks', () {
      final f = FriendStreak.fromJson({'username': 'b', 'fullname': 'B', 'streak': 4, 'today_done': true, 'is_you': false});
      expect((f.streak, f.todayDone, f.isYou), (4, true, false));
      final p = Profile.fromJson({
        'username': 'a', 'fullname': 'A', 'posts_count': 0, 'followers_count': 0, 'following_count': 0,
        'you_follow_them': 0, 'they_follow_you': 0, 'streak': 12,
      });
      expect(p.streak, 12);
    });

    testWidgets('freeze card explains how freezes work', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FreezeCard(status: StreakStatus.fromJson({'current': 3, 'freezes': 1}))),
      ));
      expect(find.text('1 streak freeze'), findsOneWidget);
      expect(find.textContaining('Next one in 4 days'), findsOneWidget);
      expect(find.byIcon(Icons.ac_unit_rounded), findsNWidgets(2));
    });

    testWidgets('streak badge', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StreakBadge(days: 14))));
      expect(find.text('14'), findsOneWidget);
    });
  });

  group('offline sampler', () {
    test('server errors that are not about the connection still surface', () async {
      final api = _OfflineApi(ApiException('boom', status: 500));
      await expectLater(offlineAwareSampler(api)('hydrogen_atom', 5), throwsA(isA<ApiException>()));
    });
  });
}
