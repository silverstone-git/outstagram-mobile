import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_client.dart';
import 'streak_reminders.dart';

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

  bool done(DateTime day) => days.contains(dayKey(day));

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

/// The signed-in user's streak; null while signed out. Every new value re-plans the reminders.
final streakProvider = AsyncNotifierProvider<StreakController, StreakStatus?>(StreakController.new);

class StreakController extends AsyncNotifier<StreakStatus?> {
  Api get _api => ref.read(apiProvider);

  @override
  Future<StreakStatus?> build() async {
    final uid = ref.watch(authControllerProvider.select((s) => s.value?.user.userId));
    if (uid == null) {
      await StreakReminders.instance.cancelAll();
      return null;
    }
    final s = StreakStatus.fromJson(await _api.get<Map<String, dynamic>>('/me/streak'));
    StreakReminders.instance.plan(s);
    return s;
  }

  Future<void> reload() async {
    try {
      final s = StreakStatus.fromJson(await _api.get<Map<String, dynamic>>('/me/streak'));
      state = AsyncData(s);
      StreakReminders.instance.plan(s);
    } catch (_) {
      // keep what we had (offline)
    }
  }

  /// From `POST /exam-attempts`.
  void apply(StreakStatus s) {
    state = AsyncData(s);
    StreakReminders.instance.plan(s);
  }

  Future<void> setSubject(String subject) async {
    final s = StreakStatus.fromJson(await _api.put<Map<String, dynamic>>('/me/streak', data: {'subject': subject}));
    state = AsyncData(s);
  }
}
