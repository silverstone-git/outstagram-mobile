// Exam engine: a Dart port of outstagram-web/src/features/exams/engine.ts (itself ported from pariksha).
// Pure Dart. Scores must match the web exactly; test/exam_engine_test.dart checks this against golden
// output produced by the TypeScript engine (tool/exam_golden.ts).
import 'dart:math';

import 'models.dart';

export 'models.dart';

/// Fisher-Yates shuffle (returns a new list).
List<T> shuffled<T>(List<T> list, [Random? rng]) {
  final r = rng ?? Random();
  final a = [...list];
  for (var i = a.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

String formatTime(num seconds) {
  if (seconds.isNaN || seconds < 0) return '00:00:00';
  final s = seconds.floor();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(s ~/ 3600)}:${p((s % 3600) ~/ 60)}:${p(s % 60)}';
}

const r2PublicEndpoint = 'https://pub-682f1a94c94443278f61ec7ca3dadaec.r2.dev';

/// Question images: absolute URLs as-is, relative paths on the public R2 bucket.
String resolveImagePath(String? path) {
  if (path == null || path.isEmpty) return '';
  if (RegExp(r'^(https?:|data:)').hasMatch(path)) return path;
  return '$r2PublicEndpoint/${path.replaceFirst(RegExp(r'^/'), '')}';
}

/// Legacy flat-question exams become a single section; ids and types are filled in.
ExamConfig normalizeExamConfig(ExamConfig config) {
  final sections = config.sections;
  if (sections != null && sections.isNotEmpty) {
    return ExamConfig(
      name: config.name,
      settings: config.settings,
      sections: [
        for (var s = 0; s < sections.length; s++)
          () {
            final sid = sections[s].id.isNotEmpty ? sections[s].id : 'section-$s';
            final qs = sections[s].questions;
            return sections[s].copyWith(
              id: sid,
              questions: [
                for (var i = 0; i < qs.length; i++) qs[i].copyWith(id: qs[i].id.isNotEmpty ? qs[i].id : '$sid-q-$i'),
              ],
            );
          }(),
      ],
    );
  }
  final qs = config.questions ?? const <Question>[];
  return ExamConfig(
    name: config.name,
    settings: config.settings,
    sections: [
      ExamSection(
        id: 'default-section',
        name: 'General',
        questions: [for (var i = 0; i < qs.length; i++) qs[i].copyWith(id: qs[i].id.isNotEmpty ? qs[i].id : 'q-$i')],
        marking: Marking(
          positive: config.settings?.positiveMarking ?? 1,
          negative: config.settings?.negativeMarking ?? 0,
        ),
      ),
    ],
  );
}

/// JavaScript's parseFloat: the longest numeric prefix, or NaN.
double jsParseFloat(String s) {
  final m = RegExp(r'^\s*([+-]?(?:Infinity|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?))').firstMatch(s);
  if (m == null) return double.nan;
  final t = m.group(1)!;
  if (t.endsWith('Infinity')) return t.startsWith('-') ? double.negativeInfinity : double.infinity;
  return double.parse(t);
}

bool isQuestionCorrect(Question q, {int? label, List<int>? labels, String? text}) {
  switch (q.type) {
    case QuestionType.mcq:
      return label != null && label == q.answerLabel;
    case QuestionType.msq:
      final want = q.answerLabels;
      if (labels == null || want == null) return false;
      final u = [...labels]..sort();
      final c = [...want]..sort();
      if (u.length != c.length) return false;
      for (var i = 0; i < u.length; i++) {
        if (u[i] != c[i]) return false;
      }
      return true;
    case QuestionType.nat:
      if (text == null || text.isEmpty) return false;
      final n = jsParseFloat(text);
      if (n.isNaN) return false;
      final range = q.answerRange;
      if (range != null) return n >= range.min && n <= range.max;
      final v = q.answerValue;
      if (v != null && v.isNotEmpty) return jsParseFloat(v) == n;
      return false;
  }
}

/// The question list the runner shows: per-section order (shuffled if set), options shuffled if set,
/// then capped at settings.questionCount.
List<Question> prepareQuestions(ExamConfig config, [Random? rng]) {
  var all = <Question>[];
  for (final section in config.sections ?? const <ExamSection>[]) {
    final qs = config.settings?.shuffleQuestions == true ? shuffled(section.questions, rng) : section.questions;
    for (var i = 0; i < qs.length; i++) {
      final q = qs[i];
      all.add(
        q.copyWith(
          id: q.id.isNotEmpty ? q.id : '${section.id}-q-$i',
          shuffledOptions: config.settings?.shuffleOptions == true ? shuffled(q.options, rng) : q.options,
        ),
      );
    }
  }
  final n = config.settings?.questionCount;
  if (n != null && n > 0 && n < all.length) all = all.sublist(0, n);
  return all;
}

ExamSection? sectionOf(ExamConfig config, String questionId) {
  for (final s in config.sections ?? const <ExamSection>[]) {
    if (s.questions.any((q) => q.id == questionId)) return s;
  }
  return null;
}

double maxScore(ExamConfig config, List<Question> questions) =>
    questions.fold(0.0, (sum, q) => sum + (sectionOf(config, q.id)?.marking.positive ?? 1));

int examMinutes(ExamConfig c) {
  final m = (c.settings?.timerHours ?? 0) * 60 + (c.settings?.timerMinutes ?? 0);
  return m == 0 ? 60 : m;
}

Swot _swot(ExamResult r) {
  final s = <String>[], w = <String>[], o = <String>[], t = <String>[];
  final topics = r.timePerTopic.keys.toList();
  if (topics.isEmpty) return const Swot();
  final avg = r.totalQuestions > 0 ? r.totalTimeTaken / r.totalQuestions : 0.0;
  for (final topic in topics) {
    final acc = (r.accuracyPerTopic[topic] ?? 0) * 100;
    final n = r.originalQuestions.where((q) => q.topic == topic).length;
    final perQ = n > 0 ? (r.timePerTopic[topic] ?? 0) / n : 0.0;
    final high = acc >= 80, low = acc <= 50, fast = perQ < avg, slow = perQ > avg * 1.5;
    if (high && fast) {
      s.add('$topic: Mastered. High accuracy with excellent pace.');
    } else if (low && slow) {
      w.add('$topic: Conceptual gaps. Low accuracy and slow speed need fundamental review.');
    } else if (high && slow) {
      o.add('$topic: Speed practice. Good accuracy, but reduce time per question.');
    } else if (low && fast) {
      t.add('$topic: Accuracy risk. Low accuracy at speed suggests guessing.');
    }
  }
  if (s.isEmpty) s.add('No standout strengths identified yet. Keep practicing!');
  if (w.isEmpty) w.add('No major conceptual weaknesses identified. Maintain consistency.');
  if (o.isEmpty) o.add('Focus on increasing speed in topics where you have good accuracy.');
  if (t.isEmpty) t.add("Avoid guessing when you're moving quickly through questions.");
  return Swot(strengths: s, weaknesses: w, opportunities: o, threats: t);
}

/// Pariksha's scoring: per-section marking, negative marks and maxAttempts caps (the first N attempted
/// questions of a section, in the order shown, count).
ExamResult scoreExam(
  ExamConfig config,
  List<Question> questions,
  Map<String, DraftAnswer> answers,
  Map<String, double> questionTimers,
  int startedAtMs, {
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final processed = [
    for (final q in questions)
      () {
        final a = answers[q.id] ?? const DraftAnswer();
        return UserAnswer(
          questionId: q.id,
          type: q.type,
          selectedOptionLabel: a.label,
          selectedOptionLabels: a.labels,
          enteredAnswer: a.text,
          isCorrect: isQuestionCorrect(q, label: a.label, labels: a.labels, text: a.text),
          timeSpent: (questionTimers[q.id] ?? 0).roundToDouble(),
          isFlagged: a.isFlagged ? true : null,
        );
      }(),
  ];

  var totalScore = 0.0;
  var totalCorrect = 0;
  final sectionScores = <String, double>{};
  for (final section in config.sections ?? const <ExamSection>[]) {
    var score = 0.0, correct = 0, attempted = 0;
    final ids = {for (final q in section.questions) q.id};
    for (final p in processed.where((p) => ids.contains(p.questionId))) {
      if (!p.isAttempted) continue;
      final cap = section.maxAttempts;
      if (cap != null && cap > 0 && attempted >= cap) continue;
      attempted++;
      if (p.isCorrect) {
        correct++;
        score += section.marking.positive;
      } else {
        score -= section.marking.negative;
      }
    }
    sectionScores[section.id] = score;
    totalScore += score;
    totalCorrect += correct;
  }

  final perTopic = <String, int>{};
  final accuracyPerTopic = <String, double>{};
  final timePerTopic = <String, double>{};
  final byId = {for (final p in processed) p.questionId: p};
  for (final q in questions) {
    perTopic[q.topic] = (perTopic[q.topic] ?? 0) + 1;
    accuracyPerTopic[q.topic] = (accuracyPerTopic[q.topic] ?? 0) + ((byId[q.id]?.isCorrect ?? false) ? 1 : 0);
    timePerTopic[q.topic] = (timePerTopic[q.topic] ?? 0) + (questionTimers[q.id] ?? 0);
  }
  for (final t in accuracyPerTopic.keys.toList()) {
    final n = perTopic[t] ?? 0;
    accuracyPerTopic[t] = n > 0 ? accuracyPerTopic[t]! / n : 0;
  }

  final base = ExamResult(
    id: 'res-$now',
    examName: config.name,
    date: now,
    score: totalScore,
    totalQuestions: questions.length,
    correctAnswers: totalCorrect,
    incorrectAnswers: questions.length - totalCorrect,
    accuracy: questions.isEmpty ? 0 : (totalCorrect / questions.length) * 100,
    totalTimeTaken: (now - startedAtMs) / 1000,
    timePerTopic: timePerTopic,
    accuracyPerTopic: accuracyPerTopic,
    swot: const Swot(),
    answers: processed,
    originalQuestions: questions,
    sectionScores: sectionScores,
  );
  return ExamResult(
    id: base.id,
    examName: base.examName,
    date: base.date,
    score: base.score,
    totalQuestions: base.totalQuestions,
    correctAnswers: base.correctAnswers,
    incorrectAnswers: base.incorrectAnswers,
    accuracy: base.accuracy,
    totalTimeTaken: base.totalTimeTaken,
    timePerTopic: base.timePerTopic,
    accuracyPerTopic: base.accuracyPerTopic,
    swot: _swot(base),
    answers: base.answers,
    originalQuestions: base.originalQuestions,
    sectionScores: base.sectionScores,
  );
}

// --- presets (question bank sampling), from pariksha -------------------------------------------

const subjectGroups = <String, List<String>>{
  'Quantum Mechanics': [
    'Foundations of Quantum Mechanics',
    'Schrödinger Equation',
    'Angular Momentum',
    'Hydrogen Atom',
    'Approximation Methods',
    'Scattering Theory',
  ],
  'Electromagnetic Theory': [
    'Magnetostatics',
    'Electrodynamics',
    'Electromagnetic Waves',
    'Waveguides and Cavities',
    'Radiation',
  ],
  'Thermodynamics & Statistical': [
    'Laws of Thermodynamics',
    'Statistical Ensembles',
    'Quantum Statistics',
    'Random Walks & Ising Model',
  ],
  'Mathematical Physics': [
    'Complex Analysis',
    'Linear Algebra',
    'Differential Equations',
    'Fourier & Laplace Transforms',
    'Numerical Methods',
  ],
  'Classical Mechanics': [
    'Constraints',
    'Lagrangian Dynamics',
    'Hamiltonian Dynamics',
    'Symmetry and Conservation Laws',
    'Central Force Motion',
    'Scattering',
    'Small Oscillations',
    'Rigid Body Dynamics',
    'Canonical Transformations',
    'Poisson Brackets',
    'Kepler Problems',
    'Special Theory of Relativity',
    'Phase Space Dynamics',
    'Action-Angle Variables',
    'Non-Inertial Frames',
    'Hamilton-Jacobi Theory',
  ],
  'Solid State Physics': ['Condensed Matter'],
  'Atomic & Molecular': ['Atomic Physics', 'Molecular Physics'],
  'Nuclear & Particle': ['Nuclear Physics', 'Particle Physics'],
  'Electronics': ['Analog Electronics', 'Digital Electronics'],
};

final subjects = subjectGroups.keys.toList();

enum ExamPreset {
  gate('GATE', 'GATE Physics', '61 Qs · 1 & 2 mark · −⅓ negative', 180),
  csirNet('CSIR_NET', 'CSIR NET', 'Part B + C · Part C best 20', 180),
  tifrGs('TIFR_GS', 'TIFR GS', '40 Qs · +3 / −1', 180),
  barcOces('BARC_OCES', 'BARC OCES', '100 Qs · +3 / −1', 120);

  const ExamPreset(this.id, this.title, this.blurb, this.minutes);
  final String id;
  final String title;
  final String blurb;
  final int minutes;
}

const presetPatterns = <ExamPreset, Map<String, int>>{
  ExamPreset.gate: {
    'Quantum Mechanics': 10,
    'Electromagnetic Theory': 9,
    'Thermodynamics & Statistical': 9,
    'Mathematical Physics': 6,
    'Classical Mechanics': 6,
    'Solid State Physics': 6,
    'Atomic & Molecular': 5,
    'Nuclear & Particle': 5,
    'Electronics': 5,
  },
  ExamPreset.csirNet: {
    'Mathematical Physics': 10,
    'Quantum Mechanics': 10,
    'Electromagnetic Theory': 9,
    'Classical Mechanics': 8,
    'Thermodynamics & Statistical': 7,
    'Solid State Physics': 5,
    'Electronics': 5,
    'Nuclear & Particle': 5,
    'Atomic & Molecular': 4,
  },
  ExamPreset.tifrGs: {
    'Quantum Mechanics': 9,
    'Classical Mechanics': 7,
    'Electromagnetic Theory': 7,
    'Thermodynamics & Statistical': 7,
    'Mathematical Physics': 6,
    'Electronics': 4,
  },
  ExamPreset.barcOces: {
    'Quantum Mechanics': 18,
    'Electromagnetic Theory': 18,
    'Thermodynamics & Statistical': 18,
    'Classical Mechanics': 11,
    'Nuclear & Particle': 11,
    'Solid State Physics': 11,
    'Mathematical Physics': 6,
    'Electronics': 4,
    'Atomic & Molecular': 3,
  },
};

/// Fetches `count` questions for a topic (slug). Supplied by the API layer so the engine stays pure.
typedef TopicSampler = Future<List<Question>> Function(String topicSlug, int count);

String topicSlug(String topic) => topic.replaceAll(' ', '_').toLowerCase();

Future<List<Question>> _sampleGroups(Map<String, int> pattern, TopicSampler sample) async {
  final jobs = <Future<List<Question>>>[];
  pattern.forEach((group, count) {
    final topics = subjectGroups[group] ?? const [];
    if (topics.isEmpty) return;
    final per = (count / topics.length).ceil();
    for (final t in topics) {
      jobs.add(sample(topicSlug(t), per).catchError((_) => <Question>[]));
    }
  });
  return (await Future.wait(jobs)).expand((l) => l).toList();
}

Future<ExamConfig> generatePresetExam(ExamPreset preset, TopicSampler sample, [Random? rng]) async {
  final pattern = presetPatterns[preset]!;
  final total = pattern.values.fold(0, (a, b) => a + b);
  final pool = shuffled(await _sampleGroups(pattern, sample), rng).take(total).toList();
  List<Question> slice(int a, int b) => pool.sublist(min(a, pool.length), min(b, pool.length));
  const three = ExamSettings(timerHours: 3, shuffleQuestions: true, shuffleOptions: true);
  switch (preset) {
    case ExamPreset.gate:
      return ExamConfig(
        name: 'GATE Physics Mock',
        settings: three,
        sections: [
          ExamSection(
            id: 'gate-physics-1m',
            name: '1 Mark',
            questions: slice(0, 25),
            marking: const Marking(positive: 1, negative: 0.33),
          ),
          ExamSection(
            id: 'gate-physics-2m',
            name: '2 Mark',
            questions: slice(25, 65),
            marking: const Marking(positive: 2, negative: 0.66),
          ),
        ],
      );
    case ExamPreset.csirNet:
      return ExamConfig(
        name: 'CSIR NET Physical Sciences Mock',
        settings: three,
        sections: [
          ExamSection(
            id: 'net-part-b',
            name: 'Part B',
            questions: slice(0, 20),
            marking: const Marking(positive: 3.5, negative: 0.875),
          ),
          ExamSection(
            id: 'net-part-c',
            name: 'Part C',
            questions: slice(20, 50),
            marking: const Marking(positive: 5, negative: 1.25),
            maxAttempts: 20,
          ),
        ],
      );
    case ExamPreset.tifrGs:
      return ExamConfig(
        name: 'TIFR GS Mock',
        questions: pool,
        settings: const ExamSettings(
          timerHours: 3,
          shuffleQuestions: true,
          shuffleOptions: true,
          positiveMarking: 3,
          negativeMarking: 1,
          questionCount: 40,
        ),
      );
    case ExamPreset.barcOces:
      return ExamConfig(
        name: 'BARC OCES Mock',
        questions: pool,
        settings: const ExamSettings(
          timerHours: 2,
          shuffleQuestions: true,
          shuffleOptions: true,
          positiveMarking: 3,
          negativeMarking: 1,
          questionCount: 100,
        ),
      );
  }
}

Future<ExamConfig> generatePracticeExam(String subject, TopicSampler sample, {int count = 10, Random? rng}) async {
  final pool = shuffled(await _sampleGroups({subject: count}, sample), rng).take(count).toList();
  return ExamConfig(
    name: '$subject · quick practice',
    sections: [
      ExamSection(id: 'practice', name: subject, questions: pool, marking: const Marking(positive: 1, negative: 0)),
    ],
    settings: ExamSettings(timerMinutes: max(10, count * 3), shuffleQuestions: true, shuffleOptions: true),
  );
}
