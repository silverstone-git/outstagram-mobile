import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/engine.dart';

/// A running exam. Saved to disk after every change so an attempt survives the app being killed or
/// the phone rebooting. The exam clock is wall-clock time since [startedAtMs], like a real exam hall:
/// time away from the app still counts.
@immutable
class ExamSession {
  const ExamSession({
    required this.config,
    required this.examId,
    required this.questions,
    required this.answers,
    required this.timers,
    required this.index,
    required this.startedAtMs,
    required this.leftApp,
  });

  factory ExamSession.fromJson(Map<String, dynamic> j) => ExamSession(
    config: ExamConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map)),
    examId: j['examId'] as String?,
    questions: [for (final q in j['questions'] as List) Question.fromJson(Map<String, dynamic>.from(q as Map))],
    answers: {
      for (final e in (j['answers'] as Map).entries)
        '${e.key}': DraftAnswer.fromJson(Map<String, dynamic>.from(e.value as Map)),
    },
    timers: {for (final e in (j['timers'] as Map).entries) '${e.key}': (e.value as num).toDouble()},
    index: (j['index'] as num).toInt(),
    startedAtMs: (j['startedAtMs'] as num).toInt(),
    leftApp: (j['leftApp'] as num?)?.toInt() ?? 0,
  );

  final ExamConfig config; // normalized
  final String? examId; // community exam id, null for presets/practice
  final List<Question> questions;
  final Map<String, DraftAnswer> answers;
  final Map<String, double> timers; // seconds per question id
  final int index;
  final int startedAtMs;
  final int leftApp; // times the app went to the background mid-exam

  int get totalSeconds => examMinutes(config) * 60;
  double remainingSeconds([int? nowMs]) =>
      (totalSeconds - ((nowMs ?? DateTime.now().millisecondsSinceEpoch) - startedAtMs) / 1000)
          .clamp(0, totalSeconds)
          .toDouble();
  int get answeredCount => questions.where((q) => answers[q.id]?.isAttempted ?? false).length;
  Question get current => questions[index];
  DraftAnswer answerFor(String id) => answers[id] ?? const DraftAnswer();

  ExamSession copyWith({Map<String, DraftAnswer>? answers, Map<String, double>? timers, int? index, int? leftApp}) =>
      ExamSession(
        config: config,
        examId: examId,
        questions: questions,
        answers: answers ?? this.answers,
        timers: timers ?? this.timers,
        index: index ?? this.index,
        startedAtMs: startedAtMs,
        leftApp: leftApp ?? this.leftApp,
      );

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'examId': examId,
    'questions': [for (final q in questions) q.toJson()],
    'answers': {for (final e in answers.entries) e.key: e.value.toJson()},
    'timers': timers,
    'index': index,
    'startedAtMs': startedAtMs,
    'leftApp': leftApp,
  };
}

/// What the results screen needs after submitting.
class FinishedExam {
  const FinishedExam({
    required this.result,
    required this.maxScore,
    required this.config,
    required this.examId,
    this.leftApp = 0,
  });
  final ExamResult result;
  final int leftApp;
  final double maxScore;
  final ExamConfig config; // for "Retake"
  final String? examId;
}

const _key = 'exam_session_v1';

/// The saved session on disk (for the "Resume" card), read once per Exams-tab visit.
final savedSessionProvider = FutureProvider.autoDispose<ExamSession?>((ref) async {
  final raw = (await SharedPreferences.getInstance()).getString(_key);
  if (raw == null) return null;
  try {
    return ExamSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (e) {
    debugPrint('dropping unreadable exam session: $e');
    await (await SharedPreferences.getInstance()).remove(_key);
    return null;
  }
});

final examSessionProvider = NotifierProvider<ExamSessionController, ExamSession?>(ExamSessionController.new);

class ExamSessionController extends Notifier<ExamSession?> {
  int _questionStartMs = DateTime.now().millisecondsSinceEpoch;
  Future<void> _saving = Future.value();

  @override
  ExamSession? build() => null;

  void start(ExamConfig raw, {String? examId}) {
    final config = normalizeExamConfig(raw);
    _questionStartMs = DateTime.now().millisecondsSinceEpoch;
    _set(
      ExamSession(
        config: config,
        examId: examId,
        questions: prepareQuestions(config),
        answers: const {},
        timers: const {},
        index: 0,
        startedAtMs: _questionStartMs,
        leftApp: 0,
      ),
    );
  }

  void resume(ExamSession s) {
    _questionStartMs = DateTime.now().millisecondsSinceEpoch;
    state = s;
  }

  /// Adds the time spent on the current question since it was shown.
  Map<String, double> _committedTimers(ExamSession s) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = s.current.id;
    final t = {...s.timers, id: (s.timers[id] ?? 0) + (now - _questionStartMs) / 1000};
    _questionStartMs = now;
    return t;
  }

  void goTo(int i) {
    final s = state;
    if (s == null || i < 0 || i >= s.questions.length || i == s.index) return;
    _set(s.copyWith(timers: _committedTimers(s), index: i));
  }

  void update(DraftAnswer Function(DraftAnswer a) f) {
    final s = state;
    if (s == null) return;
    final id = s.current.id;
    _set(s.copyWith(answers: {...s.answers, id: f(s.answerFor(id))}));
  }

  /// MCQ: select (tap again to unselect). MSQ: toggle.
  void pick(int label) => update((a) {
    if (state!.current.type == QuestionType.msq) {
      final cur = a.labels ?? const <int>[];
      return a.copyWith(labels: cur.contains(label) ? (cur.where((l) => l != label).toList()) : [...cur, label]);
    }
    return a.copyWith(label: () => a.label == label ? null : label);
  });

  void enterText(String text) => update((a) => a.copyWith(text: text));
  void toggleFlag() => update((a) => a.copyWith(isFlagged: !a.isFlagged));
  void clear() => update((a) => a.cleared());

  /// App went to the background: bank the time and count it (shown on the results screen).
  void paused() {
    final s = state;
    if (s == null) return;
    _set(s.copyWith(timers: _committedTimers(s), leftApp: s.leftApp + 1));
  }

  void resumed() => _questionStartMs = DateTime.now().millisecondsSinceEpoch;

  FinishedExam? submit() {
    final s = state;
    if (s == null) return null;
    final timers = _committedTimers(s);
    final result = scoreExam(s.config, s.questions, s.answers, timers, s.startedAtMs);
    final done = FinishedExam(
      result: result,
      maxScore: maxScore(s.config, s.questions),
      config: s.config,
      examId: s.examId,
      leftApp: s.leftApp,
    );
    discard();
    return done;
  }

  void discard() {
    state = null;
    _saving = _saving.then((_) async => (await SharedPreferences.getInstance()).remove(_key));
  }

  void _set(ExamSession s) {
    state = s;
    final json = jsonEncode(s.toJson());
    // Serialized so an older write can never land after a newer one.
    _saving = _saving
        .then((_) async {
          if (state == null) return; // submitted/discarded meanwhile
          await (await SharedPreferences.getInstance()).setString(_key, json);
        })
        .catchError((Object e) {
          debugPrint('exam autosave failed: $e');
        });
  }
}
