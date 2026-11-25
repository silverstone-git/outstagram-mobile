import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/theme.dart';
import 'streak_api.dart';

/// Local streak reminders (no push server: everything is planned on the phone).
///
/// Each time the app learns the streak (launch, resume, finished exam) it cancels the old plan and
/// schedules a new one: on the next day the streak is at risk, a nudge at the chosen time, then
/// "ends at midnight" at 21:30 and a last call at 23:00. The days after that get come-back messages
/// in case the app isn't opened (by then the streak would have ended).
class StreakReminders {
  StreakReminders._();
  static final instance = StreakReminders._();

  static const route = '/streak?quiz=1';
  static const _channel = AndroidNotificationChannel(
    'streak',
    'Streak reminders',
    description: 'A nudge before your daily streak ends',
    importance: Importance.high,
  );
  static const _firstId = 7100;
  static const _maxIds = 16;
  static const _prefOn = 'streak_reminders_on';
  static const _prefAsked = 'streak_reminders_asked';
  static const _prefHour = 'streak_reminder_minutes'; // minutes after midnight

  final _plugin = FlutterLocalNotificationsPlugin();
  var _ready = false;
  void Function(String route)? _onTap;
  String? launchRoute; // set when a reminder opened the app from scratch

  Future<void> init({required void Function(String route) onTap}) async {
    _onTap = onTap;
    if (_ready || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_streak')),
        onDidReceiveNotificationResponse: (r) => _onTap?.call(r.payload ?? route),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        launchRoute = launch!.notificationResponse?.payload ?? route;
      }
      _ready = true;
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  // --- settings -------------------------------------------------------------------------------

  Future<bool> get enabled async => (await SharedPreferences.getInstance()).getBool(_prefOn) ?? false;
  Future<bool> get asked async => (await SharedPreferences.getInstance()).getBool(_prefAsked) ?? false;

  Future<TimeOfDay> get time async {
    final m = (await SharedPreferences.getInstance()).getInt(_prefHour) ?? 19 * 60;
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  Future<void> setTime(TimeOfDay t, StreakStatus? s) async {
    await (await SharedPreferences.getInstance()).setInt(_prefHour, t.hour * 60 + t.minute);
    if (s != null) await plan(s);
  }

  /// Asks Android for the notification permission (13+). Returns whether reminders are on.
  Future<bool> enable(StreakStatus? s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAsked, true);
    var granted = true;
    try {
      granted =
          await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          true;
    } catch (_) {}
    await prefs.setBool(_prefOn, granted);
    if (granted && s != null) await plan(s);
    return granted;
  }

  Future<void> disable() async {
    await (await SharedPreferences.getInstance()).setBool(_prefOn, false);
    await cancelAll();
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    for (var i = 0; i < _maxIds; i++) {
      await _plugin.cancel(id: _firstId + i);
    }
  }

  // --- planning -----------------------------------------------------------------------------------

  Future<void>? _planning;

  /// Re-plans every reminder from [s]. Calls overlap safely (the last one wins).
  Future<void> plan(StreakStatus s) =>
      _planning = (_planning ?? Future.value()).then((_) => _plan(s)).catchError((Object e) {
        debugPrint('planning reminders failed: $e');
      });

  Future<void> _plan(StreakStatus s) async {
    if (!_ready) return;
    await cancelAll();
    if (!await enabled) return;
    final t = await time;
    final now = tz.TZDateTime.now(tz.local);
    final today = tz.TZDateTime(tz.local, now.year, now.month, now.day);
    var id = _firstId;

    Future<void> at(tz.TZDateTime when, StreakNudge n) async {
      if (!when.isAfter(now.add(const Duration(minutes: 1))) || id >= _firstId + _maxIds) return;
      await _plugin.zonedSchedule(
        id: id++,
        scheduledDate: when,
        title: n.title,
        body: n.body,
        payload: route,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            color: Brand.flameOrange,
            styleInformation: BigTextStyleInformation(n.body),
            category: AndroidNotificationCategory.reminder,
            actions: const [AndroidNotificationAction('quiz', 'Start 5-question quiz', showsUserInterface: true)],
          ),
        ),
      );
    }

    tz.TZDateTime on(tz.TZDateTime day, int h, int m) => tz.TZDateTime(tz.local, day.year, day.month, day.day, h, m);

    // The day the streak is at risk: today if not done yet, else tomorrow.
    final riskDay = s.todayDone ? today.add(const Duration(days: 1)) : today;
    final n = s.current; // still alive on riskDay (it was done today or yesterday), or 0
    final main = on(riskDay, t.hour, t.minute);
    await at(main, StreakCopy.nudge(n, s));
    final evening = on(riskDay, 21, 30);
    if (evening.isAfter(main.add(const Duration(minutes: 30)))) await at(evening, StreakCopy.evening(n, s));
    final last = on(riskDay, 23, 0);
    if (n > 0 && last.isAfter(main.add(const Duration(minutes: 30)))) await at(last, StreakCopy.lastCall(n));

    // If the app isn't opened, the streak ends at riskDay's midnight: come-back messages after that.
    for (var d = 1; d <= 3; d++) {
      await at(on(riskDay.add(Duration(days: d)), t.hour, t.minute), StreakCopy.comeBack(n, s.longest, d));
    }
  }
}

class StreakNudge {
  const StreakNudge(this.title, this.body);
  final String title;
  final String body;
}

/// Reminder texts. Loss aversion ("don't lose N days"), tiny effort ("5 questions"), progress to the
/// 250-day reward, and identity ("you show up every day"). Rotated by the streak length so they
/// don't feel canned.
abstract final class StreakCopy {
  static StreakNudge nudge(int n, StreakStatus s) {
    if (n == 0) {
      return s.lost > 1
          ? StreakNudge(
              'Your ${s.lost}-day streak can be beaten 💪',
              'Day 1 starts with one 5-question pop quiz. Your best is ${s.longest} days. Go get it.',
            )
          : const StreakNudge(
              'Start your streak today 🔥',
              'One 5-question pop quiz is all it takes. 250 days in a row unlocks 60 AI messages an hour, for good.',
            );
    }
    final left = s.reward.unlocked ? 0 : (s.reward.goal - n).clamp(0, s.reward.goal);
    final options = <StreakNudge>[
      StreakNudge('🔥 Your $n-day streak is waiting', 'One 5-question pop quiz keeps it alive. About 3 minutes.'),
      StreakNudge(
        "Don't let $n days go to waste",
        "You've shown up $n days in a row. Today counts too: 5 quick questions.",
      ),
      StreakNudge(
        '$n days strong. Make it ${n + 1} 🔥',
        'Your future self is grateful. Five questions, three minutes.',
      ),
      if (left > 0)
        StreakNudge('🔥 $n → ${n + 1}?', 'Only $left days to unlock 60 AI messages an hour and 1000 saved chats.')
      else
        StreakNudge('Legend status: $n days 👑', "Keep the flame you've built. One quick quiz today."),
    ];
    final next = s.nextMilestone;
    if (next != null && next - n == 1) {
      return StreakNudge(
        '🏆 One quiz away from $next days',
        'Finish today\'s pop quiz to hit your $next-day milestone.',
      );
    }
    return options[n % options.length];
  }

  static StreakNudge evening(int n, StreakStatus s) => n == 0
      ? const StreakNudge('Still time for day 1 ⏳', 'A 5-question pop quiz before midnight starts your streak.')
      : StreakNudge('⏳ Your $n-day streak ends at midnight', '2½ hours left. One quick quiz saves it.');

  static StreakNudge lastCall(int n) => StreakNudge(
    '🚨 Last call: $n-day streak ends in 60 minutes',
    'Tap now, answer 5 questions, keep your flame burning.',
  );

  static StreakNudge comeBack(int n, int longest, int daysLater) {
    if (n > 1 && daysLater == 1) {
      return StreakNudge(
        'Your $n-day flame went out 😢',
        'Streaks restart with one quiz. Beat your best of $longest days.',
      );
    }
    return const StreakNudge(
      'Your study streak misses you 🔥',
      'Five questions today and the flame is back. You\'ve got this.',
    );
  }
}
