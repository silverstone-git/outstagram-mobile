import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/features/compose/compose_draft.dart';
import 'package:outstagram/features/compose/share_intent.dart';
import 'package:outstagram/features/exams/engine/engine.dart';
import 'package:outstagram/features/exams/result_card.dart';
import 'package:outstagram/features/feed/models.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// A scored result from the golden fixtures: first question answered, the rest skipped.
(ExamResult, double) sampleResult() {
  final c = (jsonDecode(File('test/fixtures/exam_golden.json').readAsStringSync()) as List).first as Map<String, dynamic>;
  final config = normalizeExamConfig(ExamConfig.fromJson(c['config'] as Map<String, dynamic>));
  final qs = prepareQuestions(config, Random(1));
  final r = scoreExam(config, qs, {qs.first.id: const DraftAnswer(label: 2)}, {}, 0, nowMs: 1000);
  return (r, maxScore(config, qs));
}

void main() {
  test('ResultSummary counts add up and the caption carries the score', () {
    final (r, max) = sampleResult();
    final s = ResultSummary(r, max);
    expect(r.correctAnswers + s.wrong + s.skipped, r.originalQuestions.length);
    expect(s.skipped, r.originalQuestions.length - 1);
    expect(s.percent, inInclusiveRange(0, 100));
    expect(s.caption, contains(r.examName));
    expect(s.caption, contains('#outstagram'));
  });

  testWidgets('the result card lays out at its fixed size without overflow', (t) async {
    final (r, max) = sampleResult();
    await t.pumpWidget(
      MaterialApp(
        home: Center(child: ResultCard(s: ResultSummary(r, max))),
      ),
    );
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(ResultCard)), ResultCard.size);
    expect(find.text('EXAM RESULT'), findsOneWidget);
    expect(find.text('STUDY SMARTER WITH AI'), findsOneWidget);
  });

  test('shared images and text become a composer draft', () async {
    final dir = await Directory.systemTemp.createTemp('share');
    final img = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
    final d = await draftFromShared([
      SharedMediaFile(path: img.path, type: SharedMediaType.image),
      SharedMediaFile(path: 'Look at this', type: SharedMediaType.text),
      SharedMediaFile(path: '${dir.path}/missing.jpg', type: SharedMediaType.image),
      SharedMediaFile(path: '${dir.path}/v.mp4', type: SharedMediaType.video),
    ]);
    expect(d.images.single, [1, 2, 3]);
    expect(d.caption, 'Look at this');
    expect(d.isEmpty, isFalse);
    await dir.delete(recursive: true);
  });

  test("a launcher shortcut's own link is not treated as shared content", () async {
    final d = await draftFromShared([SharedMediaFile(path: 'outstagram://app/exams', type: SharedMediaType.url)]);
    expect(d.isEmpty, isTrue);
  });

  test('a draft is taken once', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(composeDraftProvider.notifier).set(const ComposeDraft(caption: 'hi', category: PostCategory.examResult));
    expect(c.read(composeDraftProvider.notifier).take()?.category, PostCategory.examResult);
    expect(c.read(composeDraftProvider), isNull);
  });
}
