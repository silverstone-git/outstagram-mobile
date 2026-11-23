// The Dart exam engine must score exactly like the web's TypeScript engine.
// Fixtures come from tool/exam_golden.ts (bun), which runs outstagram-web's engine.ts.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/features/exams/engine/engine.dart';

void main() {
  final cases = (jsonDecode(File('test/fixtures/exam_golden.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  for (final c in cases) {
    test('golden: ${c['name']}', () {
      final config = normalizeExamConfig(ExamConfig.fromJson(c['config'] as Map<String, dynamic>));
      final questions = prepareQuestions(config);
      final answers = {
        for (final e in (c['answers'] as Map<String, dynamic>).entries)
          e.key: DraftAnswer.fromJson(e.value as Map<String, dynamic>),
      };
      final timers = {for (final e in (c['timers'] as Map<String, dynamic>).entries) e.key: (e.value as num).toDouble()};
      final r = scoreExam(config, questions, answers, timers, c['startedAt'] as int, nowMs: c['now'] as int);
      final want = c['expected'] as Map<String, dynamic>;

      expect(questions.map((q) => q.id).toList(), want['questionIds']);
      expect(maxScore(config, questions), (want['maxScore'] as num).toDouble());
      expect(r.score, (want['score'] as num).toDouble());
      expect(r.totalQuestions, want['totalQuestions']);
      expect(r.correctAnswers, want['correctAnswers']);
      expect(r.incorrectAnswers, want['incorrectAnswers']);
      expect(r.accuracy, (want['accuracy'] as num).toDouble());
      expect(r.totalTimeTaken, (want['totalTimeTaken'] as num).toDouble());
      expect(r.date, want['date']);
      expect(r.id, want['id']);
      expect(jsonDecode(jsonEncode(r.sectionScores)), _nums(want['sectionScores']));
      expect(jsonDecode(jsonEncode(r.accuracyPerTopic)), _nums(want['accuracyPerTopic']));
      expect(jsonDecode(jsonEncode(r.timePerTopic)), _nums(want['timePerTopic']));
      expect(r.swot.toJson(), want['swot']);
      expect(r.timePerTopic.keys.toList(), (want['timePerTopic'] as Map).keys.toList(), reason: 'topic order drives SWOT order');

      final wantAnswers = (want['answers'] as List).cast<Map<String, dynamic>>();
      expect(r.answers.length, wantAnswers.length);
      for (var i = 0; i < wantAnswers.length; i++) {
        final a = r.answers[i], w = wantAnswers[i];
        expect(a.questionId, w['questionId']);
        expect(a.isCorrect, w['isCorrect'], reason: 'isCorrect for ${a.questionId}');
        expect(a.timeSpent, (w['timeSpent'] as num).toDouble());
        expect(a.type.wire, w['type']);
      }
    });
  }

  test('result JSON round-trips (what POST /exam-attempts stores and the web reads back)', () {
    final c = cases.first;
    final config = normalizeExamConfig(ExamConfig.fromJson(c['config'] as Map<String, dynamic>));
    final qs = prepareQuestions(config, Random(1));
    final r = scoreExam(config, qs, {qs.first.id: const DraftAnswer(label: 2)}, {}, 0, nowMs: 1000);
    final back = ExamResult.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
    expect(back.toJson(), r.toJson());
    expect(back.originalQuestions.first.question, qs.first.question);
    expect(back.originalQuestions.first.raw['explanation'], 'because', reason: 'unknown/extra fields survive');
  });

  test('shuffling keeps every question and option', () {
    final config = normalizeExamConfig(ExamConfig.fromJson({
      ...(cases.first['config'] as Map<String, dynamic>),
      'settings': {'shuffleQuestions': true, 'shuffleOptions': true},
    }));
    final qs = prepareQuestions(config, Random(7));
    expect(qs.map((q) => q.id).toSet(), {for (final s in config.sections!) ...s.questions.map((q) => q.id)});
    for (final q in qs) {
      expect(q.shuffledOptions.map((o) => o.label).toSet(), q.options.map((o) => o.label).toSet());
    }
  });

  test('jsParseFloat follows JavaScript', () {
    expect(jsParseFloat('1e'), 1);
    expect(jsParseFloat(' 2.5.1'), 2.5);
    expect(jsParseFloat('.5'), 0.5);
    expect(jsParseFloat('-0'), 0);
    expect(jsParseFloat('abc').isNaN, isTrue);
    expect(jsParseFloat('1e3x'), 1000);
  });

  test('presets sample the right number of questions', () async {
    var calls = 0;
    Future<List<Question>> sampler(String slug, int n) async {
      calls++;
      return [
        for (var i = 0; i < n; i++)
          Question.fromJson({'id': '$slug-$i', 'question': 'q', 'options': [], 'answer_label': 1, 'topic': slug}),
      ];
    }

    final gate = await generatePresetExam(ExamPreset.gate, sampler, Random(3));
    expect(gate.sections!.map((s) => s.questions.length), [25, 36], reason: "the GATE pattern sums to 61, same as the web");
    expect(calls, greaterThan(0));
    final net = await generatePresetExam(ExamPreset.csirNet, sampler, Random(3));
    expect(net.sections![1].maxAttempts, 20);
    final practice = await generatePracticeExam('Electronics', sampler, rng: Random(3));
    expect(practice.sections!.single.questions.length, 10);
    expect(examMinutes(practice), 30);
    expect(examMinutes(normalizeExamConfig(gate)), 180);
  });

  test('formatTime', () {
    expect(formatTime(0), '00:00:00');
    expect(formatTime(3725.9), '01:02:05');
    expect(formatTime(-1), '00:00:00');
  });
}

Map<String, dynamic> _nums(Object? m) => {for (final e in (m as Map).entries) '${e.key}': (e.value as num).toDouble()};
