import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_client.dart';
import '../../core/net/json_cache.dart';
import 'streak_reminders.dart';
import 'streak_widget.dart';
import '../exams/exam_api.dart';
import '../exams/offline_packs.dart';

/// `GET /me/streak` (and the `streak` field of `POST /exam-attempts`). Days are `YYYY-MM-DD` in the
/// user's time zone, which the app sends as `X-Timezone`.
class StreakStatus {
  const StreakStatus({
    required this.current,
    required this.longest,
    required this.todayDone,
    required this.atRisk,
    required this.broken,
    required this.lost,
    required this.today,
    required this.dayEndsAt,
    required this.subject,
    required this.days,
    required this.milestones,
    required this.nextMilestone,
    required this.prevMilestone,
    required this.reward,
    this.extended = false,
    this.milestone,
    this.rewardUnlocked = false,
    this.frozenDays = const {},
    this.freezes = 0,
    this.freezesMax = 2,
    this.freezeEvery = 7,
    this.freezesUsed = 0,
    this.freezeEarned = false,
    this.lastDay,
    this.tz,
  });

  factory StreakStatus.fromJson(Map<String, dynamic> j) {
    int i(Object? v) => (v as num?)?.toInt() ?? 0;
    final r = Map<String, dynamic>.from((j['reward'] as Map?) ?? const {});
    return StreakStatus(
      current: i(j['current']),
      longest: i(j['longest']),
      todayDone: j['today_done'] == true,
      atRisk: j['at_risk'] == true,
      broken: j['broken'] == true,
      lost: i(j['lost']),
      today: DateTime.tryParse('${j['today']}') ?? DateTime.now(),
      dayEndsAt: DateTime.tryParse('${j['day_ends_at']}')?.toLocal(),
      subject: j['subject'] as String?,
      days: {for (final d in (j['days'] as List?) ?? const []) '$d'},
      milestones: [
        for (final m in (j['milestones'] as List?) ?? const [3, 7, 14, 30, 50, 100, 250]) i(m),
      ],
      nextMilestone: (j['next_milestone'] as num?)?.toInt(),
      prevMilestone: i(j['prev_milestone']),
      reward: StreakReward(
        goal: r['goal'] == null ? 250 : i(r['goal']),
        unlocked: r['unlocked'] == true,
        daysLeft: i(r['days_left']),
        aiPromptsPerHour: r['ai_prompts_per_hour'] == null ? 60 : i(r['ai_prompts_per_hour']),
        tutorThreads: r['tutor_threads'] == null ? 1000 : i(r['tutor_threads']),
      ),
      extended: j['extended'] == true,
      milestone: (j['milestone'] as num?)?.toInt(),
      rewardUnlocked: j['reward_unlocked'] == true,
      frozenDays: {for (final d in (j['frozen_days'] as List?) ?? const []) '$d'},
      freezes: i(j['freezes']),
      freezesMax: j['freezes_max'] == null ? 2 : i(j['freezes_max']),
      freezeEvery: j['freeze_every'] == null ? 7 : i(j['freeze_every']),
      freezesUsed: i(j['freezes_used']),
      freezeEarned: j['freeze_earned'] == true,
      lastDay: j['last_day'] as String?,
      tz: j['tz'] as String?,
    );
  }

  final int current;
  final int longest;
  final bool todayDone;
  final bool atRisk; // a streak that ends tonight unless the user finishes an exam
  final bool broken; // had a streak, missed a day
  final int lost; // length of the streak that ended
  final DateTime today; // date only, in the user's zone
  final DateTime? dayEndsAt; // local midnight, when an at-risk streak ends
  final String? subject; // pop-quiz subject
  final Set<String> days; // done days, last six weeks
  final List<int> milestones;
  final int? nextMilestone;
  final int prevMilestone;
  final StreakReward reward;

  // only right after an attempt
  final bool extended;
  final int? milestone;
  final bool rewardUnlocked;

  /// Streak freezes: missed days a freeze covered, how many are held / can be held, earned every N days.
  final Set<String> frozenDays;
  final int freezes;
  final int freezesMax;
  final int freezeEvery;
  final int freezesUsed; // spent on this read to save the streak (say so once)
  final bool freezeEarned; // right after an attempt
  final String? lastDay; // last counted day, YYYY-MM-DD in [tz]
  final String? tz;

  bool done(DateTime day) => days.contains(dayKey(day));
  bool frozen(DateTime day) => frozenDays.contains(dayKey(day));

  /// Days until the next freeze is earned, or null when the max is held.
  int? get daysToFreeze => freezes >= freezesMax || freezeEvery < 1 ? null : freezeEvery - current % freezeEvery;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class StreakReward {
  const StreakReward({
    required this.goal,
    required this.unlocked,
    required this.daysLeft,
    required this.aiPromptsPerHour,
    required this.tutorThreads,
  });

  final int goal;
  final bool unlocked;
  final int daysLeft;
  final int aiPromptsPerHour;
  final int tutorThreads;
}

/// One row of `GET /me/streak/friends`: you and the people you follow who have a streak.
class FriendStreak {
  const FriendStreak({required this.username, required this.fullname, required this.streak,
      required this.todayDone, required this.isYou, this.avatar});

  factory FriendStreak.fromJson(Map<String, dynamic> j) => FriendStreak(
        username: '${j['username']}',
        fullname: '${j['fullname'] ?? ''}',
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        todayDone: j['today_done'] == true,
        isYou: j['is_you'] == true,
        avatar: j['avatar_url'] as String?,
      );

  final String username;
  final String fullname;
  final int streak;
  final bool todayDone;
  final bool isYou;
  final String? avatar;
}

final friendStreaksProvider = FutureProvider.autoDispose<List<FriendStreak>>((ref) async {
  ref.watch(streakProvider); // refresh after your own streak changes
  final l = await ref.watch(apiProvider).get<List<dynamic>>('/me/streak/friends');
  return [for (final f in l) FriendStreak.fromJson(Map<String, dynamic>.from(f as Map))];
});

/// The signed-in user's streak; null while signed out. Every new value re-plans the reminders.
final streakProvider = AsyncNotifierProvider<StreakController, StreakStatus?>(StreakController.new);

class StreakController extends AsyncNotifier<StreakStatus?> {
  Api get _api => ref.read(apiProvider);

  @override
  Future<StreakStatus?> build() async {
    final uid = ref.watch(authControllerProvider.select((s) => s.value?.user.userId));
    if (uid == null) {
      await StreakReminders.instance.cancelAll();
      StreakWidget.update(null);
      return null;
    }
    await _flushPending();
    // Offline, the last known streak (the chip read "0" offline: QA 2026-11-27).
    final raw = await JsonCache.fetchOrCached('/me/streak', () => _api.get<Map<String, dynamic>>('/me/streak'),
        onLate: ref.invalidateSelf);
    final s = StreakStatus.fromJson(Map<String, dynamic>.from(raw as Map));
    StreakReminders.instance.plan(s);
    StreakWidget.update(s);
    return s;
  }

  /// Exams finished offline go up first, so the streak below already counts them.
  Future<void> _flushPending() async {
    try {
      await PendingAttempts.instance.flush(ref.read(examApiProvider));
    } catch (_) {}
  }

  Future<void> reload() async {
    await _flushPending();
    try {
      final s = StreakStatus.fromJson(await _api.get<Map<String, dynamic>>('/me/streak'));
      state = AsyncData(s);
      StreakReminders.instance.plan(s);
      StreakWidget.update(s);
    } catch (_) {
      // keep what we had (offline)
    }
  }

  /// From `POST /exam-attempts`.
  void apply(StreakStatus s) {
    state = AsyncData(s);
    StreakReminders.instance.plan(s);
    StreakWidget.update(s);
  }

  Future<void> setSubject(String subject) async {
    final s = StreakStatus.fromJson(await _api.put<Map<String, dynamic>>('/me/streak', data: {'subject': subject}));
    state = AsyncData(s);
  }
}
