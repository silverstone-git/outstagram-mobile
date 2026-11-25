import '../exams/exam_session.dart';
import '../tutor/models.dart';
import 'streak_reminders.dart';

/// "Your exam ends soon" / "Time's up" while you're away from a running exam (backgrounded, or
/// "Save and exit"). The exam clock keeps running, like a real exam hall.
abstract final class ExamAlerts {
  static const _soonId = 7200;
  static const _upId = 7201;
  static const route = '/exams'; // the Exams tab shows "Resume" (or auto-submits when time is up)

  static Future<void> scheduleFor(ExamSession s) async {
    final r = StreakReminders.instance;
    final end = DateTime.fromMillisecondsSinceEpoch(s.startedAtMs + s.totalSeconds * 1000);
    final name = s.config.name;
    final left = s.answeredCount;
    if (s.totalSeconds > 600) {
      await r.alertAt(
        _soonId,
        end.subtract(const Duration(minutes: 5)),
        title: '⏳ About 5 minutes left: $name',
        body: "The clock kept running while you were away. You've answered $left of ${s.questions.length}.",
        route: route,
      );
    }
    await r.alertAt(
      _upId,
      end,
      title: "⏰ Time's up: $name",
      body: 'Open the app to submit it and see your score.',
      route: route,
    );
  }

  static Future<void> cancel() async {
    await StreakReminders.instance.cancelAlert(_soonId);
    await StreakReminders.instance.cancelAlert(_upId);
  }
}

/// "Your AI tutor is back" when the hourly prompt quota resets after running out.
abstract final class TutorAlerts {
  static const _id = 7210;
  static const route = '/tutor';

  static Future<void> sync(Quota q) async {
    final at = q.resetsAt;
    if (!q.isOut || at == null) {
      await StreakReminders.instance.cancelAlert(_id);
      return;
    }
    await StreakReminders.instance.alertAt(
      _id,
      at,
      title: '✨ Your AI tutor is back',
      body: 'Your AI messages for this hour are ready again. Pick up where you left off.',
      route: route,
    );
  }
}
