// Exam data model: a Dart mirror of outstagram-web/src/features/exams/types.ts.
// Pure Dart (no Flutter). Questions keep their raw JSON so unknown fields survive a round trip
// through POST /exam-attempts, and the web can open attempts made on the phone (and vice versa).

enum QuestionType {
  mcq('MCQ'),
  msq('MSQ'),
  nat('NAT');

  const QuestionType(this.wire);
  final String wire;

  static QuestionType parse(Object? v) =>
      QuestionType.values.firstWhere((t) => t.wire == v, orElse: () => QuestionType.mcq);
}

class Option {
  const Option({required this.label, required this.value});

  factory Option.fromJson(Map<String, dynamic> j) =>
      Option(label: (j['label'] as num).toInt(), value: '${j['value'] ?? ''}');

  final int label;
  final String value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

class NumRange {
  const NumRange(this.min, this.max);
  final double min;
  final double max;
}

/// One question. [raw] holds the original JSON; getters read from it.
class Question {
  Question(Map<String, dynamic> json, {String? id, List<Option>? shuffledOptions})
    : raw = Map<String, dynamic>.of(json),
      shuffledOptions = shuffledOptions ?? _options(json['shuffledOptions']) {
    if (id != null) raw['id'] = id;
    raw['type'] ??= 'MCQ';
  }

  factory Question.fromJson(Map<String, dynamic> j) => Question(j);

  final Map<String, dynamic> raw;

  /// The options in the order the runner shows them (empty until [prepareQuestions]).
  final List<Option> shuffledOptions;

  String get id => '${raw['id'] ?? ''}';
  QuestionType get type => QuestionType.parse(raw['type']);
  String get question => '${raw['question'] ?? ''}';
  List<Option> get options => _options(raw['options']);
  int? get answerLabel => (raw['answer_label'] as num?)?.toInt();
  List<int>? get answerLabels => (raw['answer_labels'] as List?)?.map((e) => (e as num).toInt()).toList();
  NumRange? get answerRange {
    final r = raw['answer_range'];
    if (r is! Map || r['min'] == null || r['max'] == null) return null;
    return NumRange((r['min'] as num).toDouble(), (r['max'] as num).toDouble());
  }

  String? get answerValue => raw['answer_value']?.toString();
  String get topic => '${raw['topic'] ?? 'General'}';
  String get explanation => '${raw['explanation'] ?? ''}';
  String? get imagePath => (raw['image_path'] as String?)?.isEmpty ?? true ? null : raw['image_path'] as String;

  /// Options to show in review: the shuffled order if there is one.
  List<Option> get displayOptions => shuffledOptions.isNotEmpty ? shuffledOptions : options;

  Question copyWith({String? id, List<Option>? shuffledOptions}) =>
      Question(raw, id: id ?? this.id, shuffledOptions: shuffledOptions ?? this.shuffledOptions);

  Map<String, dynamic> toJson() => {
    ...raw,
    if (shuffledOptions.isNotEmpty) 'shuffledOptions': [for (final o in shuffledOptions) o.toJson()],
  };

  static List<Option> _options(Object? v) =>
      v is List ? [for (final o in v) Option.fromJson(Map<String, dynamic>.from(o as Map))] : const [];
}

class Marking {
  const Marking({required this.positive, required this.negative});

  factory Marking.fromJson(Map<String, dynamic>? j) =>
      Marking(positive: (j?['positive'] as num?)?.toDouble() ?? 1, negative: (j?['negative'] as num?)?.toDouble() ?? 0);

  final double positive;
  final double negative;

  Map<String, dynamic> toJson() => {'positive': positive, 'negative': negative};
}

class ExamSection {
  ExamSection({
    required this.id,
    required this.name,
    required this.questions,
    required this.marking,
    this.maxAttempts,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? const {};

  factory ExamSection.fromJson(Map<String, dynamic> j) => ExamSection(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? 'Section'}',
    questions: [
      for (final q in (j['questions'] as List? ?? const [])) Question.fromJson(Map<String, dynamic>.from(q as Map)),
    ],
    marking: Marking.fromJson((j['marking'] as Map?)?.cast<String, dynamic>()),
    maxAttempts: (j['maxAttempts'] as num?)?.toInt(),
    extra: {
      for (final e in j.entries)
        if (!const {'id', 'name', 'questions', 'marking', 'maxAttempts'}.contains(e.key)) e.key: e.value,
    },
  );

  final String id;
  final String name;
  final List<Question> questions;
  final Marking marking;
  final int? maxAttempts;
  final Map<String, dynamic> extra;

  ExamSection copyWith({String? id, List<Question>? questions}) => ExamSection(
    id: id ?? this.id,
    name: name,
    questions: questions ?? this.questions,
    marking: marking,
    maxAttempts: maxAttempts,
    extra: extra,
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'questions': [for (final q in questions) q.toJson()],
    'marking': marking.toJson(),
    'maxAttempts': ?maxAttempts,
  };
}

class ExamSettings {
  const ExamSettings({
    this.timerMinutes = 0,
    this.timerHours = 0,
    this.shuffleQuestions = false,
    this.shuffleOptions = false,
    this.questionCount,
    this.negativeMarking,
    this.positiveMarking,
  });

  factory ExamSettings.fromJson(Map<String, dynamic> j) => ExamSettings(
    timerMinutes: (j['timerMinutes'] as num?)?.toInt() ?? 0,
    timerHours: (j['timerHours'] as num?)?.toInt() ?? 0,
    shuffleQuestions: j['shuffleQuestions'] == true,
    shuffleOptions: j['shuffleOptions'] == true,
    questionCount: (j['questionCount'] as num?)?.toInt(),
    negativeMarking: (j['negativeMarking'] as num?)?.toDouble(),
    positiveMarking: (j['positiveMarking'] as num?)?.toDouble(),
  );

  final int timerMinutes;
  final int timerHours;
  final bool shuffleQuestions;
  final bool shuffleOptions;
  final int? questionCount;
  final double? negativeMarking;
  final double? positiveMarking;

  Map<String, dynamic> toJson() => {
    'timerMinutes': timerMinutes,
    'timerHours': timerHours,
    'shuffleQuestions': shuffleQuestions,
    'shuffleOptions': shuffleOptions,
    'questionCount': ?questionCount,
    'negativeMarking': ?negativeMarking,
    'positiveMarking': ?positiveMarking,
  };
}

class ExamConfig {
  const ExamConfig({required this.name, this.sections, this.questions, this.settings});

  factory ExamConfig.fromJson(Map<String, dynamic> j) => ExamConfig(
    name: '${j['name'] ?? 'Exam'}',
    sections: (j['sections'] as List?)?.map((s) => ExamSection.fromJson(Map<String, dynamic>.from(s as Map))).toList(),
    questions: (j['questions'] as List?)?.map((q) => Question.fromJson(Map<String, dynamic>.from(q as Map))).toList(),
    settings: j['settings'] is Map ? ExamSettings.fromJson(Map<String, dynamic>.from(j['settings'] as Map)) : null,
  );

  final String name;
  final List<ExamSection>? sections;
  final List<Question>? questions; // legacy flat list
  final ExamSettings? settings;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (sections != null) 'sections': [for (final s in sections!) s.toJson()],
    if (questions != null) 'questions': [for (final q in questions!) q.toJson()],
    if (settings != null) 'settings': settings!.toJson(),
  };
}

/// What the user has entered for one question while the exam runs.
class DraftAnswer {
  const DraftAnswer({this.label, this.labels, this.text, this.isFlagged = false});

  factory DraftAnswer.fromJson(Map<String, dynamic> j) => DraftAnswer(
    label: (j['label'] as num?)?.toInt(),
    labels: (j['labels'] as List?)?.map((e) => (e as num).toInt()).toList(),
    text: j['text'] as String?,
    isFlagged: j['isFlagged'] == true,
  );

  final int? label; // MCQ
  final List<int>? labels; // MSQ
  final String? text; // NAT
  final bool isFlagged;

  bool get isAttempted => label != null || (labels?.isNotEmpty ?? false) || (text != null && text!.isNotEmpty);

  DraftAnswer copyWith({int? Function()? label, List<int>? labels, String? text, bool? isFlagged}) => DraftAnswer(
    label: label != null ? label() : this.label,
    labels: labels ?? this.labels,
    text: text ?? this.text,
    isFlagged: isFlagged ?? this.isFlagged,
  );

  DraftAnswer cleared() => DraftAnswer(isFlagged: isFlagged, labels: const [], text: '');

  Map<String, dynamic> toJson() => {
    'label': ?label,
    'labels': ?labels,
    'text': ?text,
    if (isFlagged) 'isFlagged': true,
  };
}

class UserAnswer {
  const UserAnswer({
    required this.questionId,
    required this.type,
    this.selectedOptionLabel,
    this.selectedOptionLabels,
    this.enteredAnswer,
    required this.isCorrect,
    required this.timeSpent,
    this.isFlagged,
  });

  factory UserAnswer.fromJson(Map<String, dynamic> j) => UserAnswer(
    questionId: '${j['questionId']}',
    type: QuestionType.parse(j['type']),
    selectedOptionLabel: (j['selectedOptionLabel'] as num?)?.toInt(),
    selectedOptionLabels: (j['selectedOptionLabels'] as List?)?.map((e) => (e as num).toInt()).toList(),
    enteredAnswer: j['enteredAnswer'] as String?,
    isCorrect: j['isCorrect'] == true,
    timeSpent: (j['timeSpent'] as num?)?.toDouble() ?? 0,
    isFlagged: j['isFlagged'] as bool?,
  );

  final String questionId;
  final QuestionType type;
  final int? selectedOptionLabel;
  final List<int>? selectedOptionLabels;
  final String? enteredAnswer;
  final bool isCorrect;
  final double timeSpent;
  final bool? isFlagged;

  bool get isAttempted =>
      selectedOptionLabel != null || (selectedOptionLabels?.isNotEmpty ?? false) || (enteredAnswer ?? '').isNotEmpty;

  Map<String, dynamic> toJson() => {
    'questionId': questionId,
    'type': type.wire,
    'selectedOptionLabel': selectedOptionLabel,
    'selectedOptionLabels': ?selectedOptionLabels,
    'enteredAnswer': ?enteredAnswer,
    'isCorrect': isCorrect,
    'timeSpent': timeSpent,
    'isFlagged': ?isFlagged,
  };
}

class Swot {
  const Swot({
    this.strengths = const [],
    this.weaknesses = const [],
    this.opportunities = const [],
    this.threats = const [],
  });

  factory Swot.fromJson(Map<String, dynamic>? j) {
    List<String> l(String k) => [for (final s in (j?[k] as List? ?? const [])) '$s'];
    return Swot(
      strengths: l('strengths'),
      weaknesses: l('weaknesses'),
      opportunities: l('opportunities'),
      threats: l('threats'),
    );
  }

  final List<String> strengths;
  final List<String> weaknesses;
  final List<String> opportunities;
  final List<String> threats;

  Map<String, dynamic> toJson() => {
    'strengths': strengths,
    'weaknesses': weaknesses,
    'opportunities': opportunities,
    'threats': threats,
  };
}

class ExamResult {
  const ExamResult({
    required this.id,
    required this.examName,
    required this.date,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.incorrectAnswers,
    required this.accuracy,
    required this.totalTimeTaken,
    required this.timePerTopic,
    required this.accuracyPerTopic,
    required this.swot,
    required this.answers,
    required this.originalQuestions,
    this.sectionScores,
  });

  factory ExamResult.fromJson(Map<String, dynamic> j) {
    Map<String, double> nums(Object? m) => {
      for (final e in (m as Map? ?? const {}).entries) '${e.key}': (e.value as num).toDouble(),
    };
    return ExamResult(
      id: '${j['id'] ?? ''}',
      examName: '${j['examName'] ?? 'Exam'}',
      date: (j['date'] as num?)?.toInt() ?? 0,
      score: (j['score'] as num?)?.toDouble() ?? 0,
      totalQuestions: (j['totalQuestions'] as num?)?.toInt() ?? 0,
      correctAnswers: (j['correctAnswers'] as num?)?.toInt() ?? 0,
      incorrectAnswers: (j['incorrectAnswers'] as num?)?.toInt() ?? 0,
      accuracy: (j['accuracy'] as num?)?.toDouble() ?? 0,
      totalTimeTaken: (j['totalTimeTaken'] as num?)?.toDouble() ?? 0,
      timePerTopic: nums(j['timePerTopic']),
      accuracyPerTopic: nums(j['accuracyPerTopic']),
      swot: Swot.fromJson((j['swot'] as Map?)?.cast<String, dynamic>()),
      answers: [
        for (final a in (j['answers'] as List? ?? const [])) UserAnswer.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      originalQuestions: [
        for (final q in (j['originalQuestions'] as List? ?? const []))
          Question.fromJson(Map<String, dynamic>.from(q as Map)),
      ],
      sectionScores: j['sectionScores'] == null ? null : nums(j['sectionScores']),
    );
  }

  final String id;
  final String examName;
  final int date; // epoch ms
  final double score;
  final int totalQuestions;
  final int correctAnswers;
  final int incorrectAnswers;
  final double accuracy; // percent
  final double totalTimeTaken; // seconds
  final Map<String, double> timePerTopic;
  final Map<String, double> accuracyPerTopic; // 0..1
  final Swot swot;
  final List<UserAnswer> answers;
  final List<Question> originalQuestions;
  final Map<String, double>? sectionScores;

  Map<String, dynamic> toJson() => {
    'id': id,
    'examName': examName,
    'date': date,
    'score': score,
    'totalQuestions': totalQuestions,
    'correctAnswers': correctAnswers,
    'incorrectAnswers': incorrectAnswers,
    'accuracy': accuracy,
    'totalTimeTaken': totalTimeTaken,
    'timePerTopic': timePerTopic,
    'accuracyPerTopic': accuracyPerTopic,
    'swot': swot.toJson(),
    'answers': [for (final a in answers) a.toJson()],
    'originalQuestions': [for (final q in originalQuestions) q.toJson()],
    'sectionScores': ?sectionScores,
  };
}
