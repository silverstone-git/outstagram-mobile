import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../streak/streak_api.dart';
import 'engine/engine.dart';

final examApiProvider = Provider<ExamApi>((ref) => ExamApi(ref.watch(apiProvider)));

/// A saved attempt (result screen, tutor question header).
final attemptProvider = FutureProvider.autoDispose.family<Attempt, String>(
  (ref, id) => ref.watch(examApiProvider).attempt(id),
);

DateTime _utc(String s) => DateTime.parse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z').toLocal();

class CommunityExam {
  const CommunityExam({required this.id, required this.title, required this.uploadedAt});

  factory CommunityExam.fromJson(Map<String, dynamic> j) => CommunityExam(
    id: '${j['exam_id']}',
    title: '${j['exam_title'] ?? 'Untitled exam'}',
    uploadedAt: j['datetime_uploaded'] is String ? _utc(j['datetime_uploaded'] as String) : null,
  );

  final String id;
  final String title;
  final DateTime? uploadedAt;
}

class AttemptSummary {
  const AttemptSummary({
    required this.id,
    required this.examId,
    required this.title,
    required this.score,
    required this.maxScore,
    required this.accuracy,
    required this.totalQuestions,
    required this.totalTimeSeconds,
    required this.takenAt,
    this.streak,
  });

  factory AttemptSummary.fromJson(Map<String, dynamic> j) => AttemptSummary(
    id: '${j['attempt_id']}',
    examId: j['exam_id'] as String?,
    title: '${j['exam_title'] ?? 'Exam'}',
    score: (j['score'] as num?)?.toDouble() ?? 0,
    maxScore: (j['max_score'] as num?)?.toDouble() ?? 0,
    accuracy: (j['accuracy'] as num?)?.toDouble() ?? 0,
    totalQuestions: (j['total_questions'] as num?)?.toInt() ?? 0,
    totalTimeSeconds: (j['total_time_seconds'] as num?)?.toInt() ?? 0,
    takenAt: _utc('${j['datetime_taken']}'),
    streak: j['streak'] is Map ? StreakStatus.fromJson(Map<String, dynamic>.from(j['streak'] as Map)) : null,
  );

  final String id;
  final String? examId;
  final String title;
  final double score;
  final double maxScore;
  final double accuracy;
  final int totalQuestions;
  final int totalTimeSeconds;
  final DateTime takenAt;

  /// Only on a fresh save: the daily streak after this attempt (null if it didn't count).
  final StreakStatus? streak;
}

class Attempt {
  const Attempt(this.summary, this.result);
  final AttemptSummary summary;
  final ExamResult result;
}

class ExamApi {
  ExamApi(this._api);

  final Api _api;

  /// One topic from the question bank (`slug` like `hydrogen_atom`).
  Future<List<Question>> sample(String slug, int count) async => [
    for (final q in await _api.get<List<dynamic>>('/api/question_bank/sample', query: {'topic': slug, 'count': count}))
      Question.fromJson(Map<String, dynamic>.from(q as Map)),
  ];

  Future<ExamConfig> preset(ExamPreset p) => generatePresetExam(p, sample);

  Future<ExamConfig> practice(String subject) => generatePracticeExam(subject, sample);

  /// The daily streak quiz: 5 questions from the user's subject, 5 minutes, no negative marking.
  Future<ExamConfig> popQuiz(String subject) async {
    final p = await generatePracticeExam(subject, sample, count: 5);
    return ExamConfig(
      name: 'Pop quiz · $subject',
      sections: p.sections,
      settings: const ExamSettings(timerMinutes: 5, shuffleQuestions: true, shuffleOptions: true),
    );
  }

  Future<List<CommunityExam>> communityExams({int page = 1}) async => [
    for (final e in await _api.get<List<dynamic>>('/pariksha', query: {'page': page}))
      CommunityExam.fromJson(Map<String, dynamic>.from(e as Map)),
  ];

  /// A community exam. Newer ones carry `sections`; older ones only `exam_json_str` (a question list
  /// or a full config).
  Future<ExamConfig> communityExam(String id) async {
    final d = await _api.get<Map<String, dynamic>>('/pariksha/$id');
    final title = '${d['exam_title'] ?? 'Exam'}';
    final sections = d['sections'];
    if (sections is List && sections.isNotEmpty) {
      return normalizeExamConfig(ExamConfig.fromJson({'name': title, 'sections': sections}));
    }
    final parsed = jsonDecode('${d['exam_json_str'] ?? '[]'}');
    final json = parsed is List
        ? {'name': title, 'questions': parsed}
        : {'name': title, ...(parsed as Map<String, dynamic>)};
    return normalizeExamConfig(ExamConfig.fromJson(json));
  }

  Future<AttemptSummary> saveAttempt(String? examId, ExamResult result, double maxScore) async =>
      AttemptSummary.fromJson(
        await _api.post<Map<String, dynamic>>(
          '/exam-attempts',
          data: {
            'exam_id': examId,
            'exam_title': result.examName,
            'score': result.score,
            'max_score': maxScore,
            'accuracy': result.accuracy,
            'total_questions': result.totalQuestions,
            'total_time_seconds': result.totalTimeTaken.round(),
            'result': result.toJson(),
          },
        ),
      );

  Future<List<AttemptSummary>> attempts({int page = 1}) async => [
    for (final a in await _api.get<List<dynamic>>('/exam-attempts', query: {'page': page}))
      AttemptSummary.fromJson(Map<String, dynamic>.from(a as Map)),
  ];

  Future<Attempt> attempt(String id) async {
    final d = await _api.get<Map<String, dynamic>>('/exam-attempts/$id');
    return Attempt(AttemptSummary.fromJson(d), ExamResult.fromJson(Map<String, dynamic>.from(d['result'] as Map)));
  }
}
