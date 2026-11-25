import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/auth/auth_controller.dart';
import 'package:outstagram/core/net/api_client.dart';
import 'package:outstagram/core/net/api_error.dart';
import 'package:outstagram/core/ui/code_field.dart';
import 'package:outstagram/features/account/account_api.dart';
import 'package:outstagram/features/account/verify_gate.dart';
import 'package:outstagram/features/exams/exam_api.dart';
import 'package:outstagram/features/streak/streak_api.dart';
import 'package:outstagram/features/streak/streak_reminders.dart';
import 'package:outstagram/features/streak/streak_visuals.dart';

import 'auth_test.dart' show authBody, setUpApp, session;

Map<String, dynamic> streakJson({
  int current = 3,
  bool todayDone = false,
  bool atRisk = true,
  int? next = 7,
  List<String> days = const ['2026-11-22', '2026-11-23', '2026-11-24'],
  Map<String, dynamic> extra = const {},
}) => {
  'current': current,
  'longest': 9,
  'today_done': todayDone,
  'at_risk': atRisk,
  'broken': false,
  'lost': 0,
  'last_day': '2026-11-24',
  'today': '2026-11-25',
  'day_ends_at': '2026-11-25T18:30:00Z',
  'tz': 'Asia/Kolkata',
  'subject': 'Quantum Mechanics',
  'days': days,
  'milestones': [3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 365],
  'next_milestone': next,
  'prev_milestone': 3,
  'reward': {
    'goal': 250,
    'unlocked': false,
    'unlocked_at': null,
    'days_left': 250 - current,
    'ai_prompts_per_hour': 60,
    'tutor_threads': 1000,
  },
  ...extra,
};

void main() {
  group('email codes', () {
    test('email code sign-in stores the session; reset password too', () async {
      final seen = <String, Object?>{};
      final (c, server, store) = await setUpApp(null, (o) {
        seen[o.path] = o.data;
        return switch (o.path) {
          '/auth/email/start' || '/auth/password/forgot' => (204, null),
          '/auth/email/verify' => (200, {...authBody('a1', 'r1'), 'created': true}),
          '/auth/password/reset' => (200, authBody('a2', 'r2')),
          _ => (404, {'detail': 'nope'}),
        };
      });
      final auth = c.read(authControllerProvider.notifier);
      await auth.sendEmailCode('  Asha@Example.com ');
      expect(seen['/auth/email/start'], {'email': 'asha@example.com'});
      await auth.signInWithEmailCode('asha@example.com', '123456');
      expect(store.saved?.accessToken, 'a1');
      expect(seen['/auth/email/verify'], {'email': 'asha@example.com', 'code': '123456'});

      await auth.sendPasswordResetCode('asha@example.com');
      await auth.resetPassword('asha@example.com', '654321', 'new-password');
      expect(store.saved?.refreshToken, 'r2');
      expect(seen['/auth/password/reset'], {
        'email': 'asha@example.com',
        'code': '654321',
        'new_password': 'new-password',
      });
      expect(server.calls.where((x) => x.contains('/auth/')).length, 4);
    });

    test('a wrong code surfaces the server message', () async {
      final (c, _, store) = await setUpApp(null, (o) => (401, {'detail': 'That code is wrong or has expired'}));
      expect(
        () => c.read(authControllerProvider.notifier).signInWithEmailCode('a@b.co', '000000'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'That code is wrong or has expired')),
      );
      expect(store.saved, isNull);
    });

    test('register lands on the confirm-email step once', () async {
      final (c, _, _) = await setUpApp(
        null,
        (o) => switch (o.path) {
          '/register' => (201, {'user_id': 1}),
          '/login' => (200, authBody('a', 'r')),
          _ => (404, null),
        },
      );
      final auth = c.read(authControllerProvider.notifier);
      await auth.register(
        fullname: 'Asha',
        username: 'asha',
        email: 'asha@example.com',
        password: 'password1',
        dateOfBirth: DateTime(2000),
      );
      expect(auth.takeLanding(), '/verify-email?onboarding=1');
      expect(auth.takeLanding(), isNull);
    });

    test('GET /me and the verified-email error', () async {
      final (c, _, _) = await setUpApp(
        session('a'),
        (o) => switch (o.path) {
          '/me' => (200, {'user_id': 1, 'username': 'asha', 'email': 'asha@example.com', 'email_verified': false}),
          '/posts' => (
            403,
            {
              'detail': {'code': 'email_unverified', 'verify': true, 'message': 'Confirm your email address first.'},
            },
          ),
          _ => (404, null),
        },
      );
      final me = await c.read(meProvider.future);
      expect(me!.needsVerification, isTrue);
      try {
        await c.read(dioProvider).post('/posts');
        fail('should throw');
      } on DioException catch (e) {
        final err = ApiException.from(e);
        expect(isEmailUnverified(err), isTrue);
        expect(err.message, 'Confirm your email address first.');
      }
    });

    testWidgets('CodeField completes at the last digit', (tester) async {
      String? got;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CodeField(onCompleted: (v) => got = v)),
        ),
      );
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      expect(got, isNull);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(got, '123456');
      expect(find.text('6'), findsOneWidget);
    });
  });

  group('streaks', () {
    test('parses /me/streak and an attempt with a streak', () {
      final s = StreakStatus.fromJson(streakJson());
      expect(s.current, 3);
      expect(s.atRisk, isTrue);
      expect(s.done(DateTime(2026, 11, 24)), isTrue);
      expect(s.done(DateTime(2026, 11, 25)), isFalse);
      expect(s.reward.daysLeft, 247);
      expect(s.dayEndsAt!.isUtc, isFalse);

      final a = AttemptSummary.fromJson({
        'attempt_id': 'x',
        'exam_title': 'Pop quiz',
        'datetime_taken': '2026-11-25T10:00:00',
        'streak': streakJson(current: 4, todayDone: true, atRisk: false, extra: {'extended': true, 'milestone': null}),
      });
      expect(a.streak!.extended, isTrue);
      expect(a.streak!.current, 4);
      expect(AttemptSummary.fromJson({'attempt_id': 'y', 'datetime_taken': '2026-11-25T10:00:00'}).streak, isNull);
    });

    test('reminder copy fits the situation', () {
      final s = StreakStatus.fromJson(streakJson(current: 6, next: 7));
      expect(StreakCopy.nudge(6, s).title, contains('7 days')); // one away from a milestone
      final fresh = StreakStatus.fromJson(streakJson(current: 0, atRisk: false, days: []));
      expect(StreakCopy.nudge(0, fresh).title, contains('Start'));
      expect(StreakCopy.lastCall(12).title, contains('12-day'));
      expect(StreakCopy.comeBack(12, 20, 1).body, contains('20'));
      for (var n = 1; n < 30; n++) {
        final t = StreakCopy.nudge(n, StreakStatus.fromJson(streakJson(current: n, next: 300)));
        expect(t.title, isNotEmpty);
        expect(t.body, isNotEmpty);
      }
    });

    testWidgets('streak visuals render (chip, week, calendar, reward, milestones)', (tester) async {
      final s = StreakStatus.fromJson(streakJson());
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    StreakChip(status: s),
                    WeekStrip(status: s),
                    StreakCalendar(status: s),
                    RewardCard(status: s),
                    MilestoneRow(status: s),
                    const SizedBox(height: 200, child: ConfettiBurst(count: 20)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('3'), findsWidgets);
      expect(find.textContaining('247 to go'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink()); // stop the repeating animations
    });
  });
}
