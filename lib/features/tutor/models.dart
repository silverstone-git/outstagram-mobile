/// Shapes of the AI tutor endpoints (`docs/api.md`, outstagram-web `examApi.ts`).
library;

/// Server timestamps are naive UTC unless they carry `Z` / an offset.
DateTime? parseServerTime(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final hasZone = v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);
  return DateTime.tryParse(hasZone ? v : '${v}Z')?.toLocal();
}

Map<String, dynamic> _map(Object? o) => o is Map ? Map<String, dynamic>.from(o) : const {};

class Citation {
  const Citation({this.n, this.doc, this.section});

  factory Citation.fromJson(Map<String, dynamic> j) =>
      Citation(n: (j['n'] as num?)?.toInt(), doc: j['doc'] as String?, section: j['section'] as String?);

  final int? n;
  final String? doc;
  final String? section;

  /// "Book › Section". Headings come from the books' LaTeX sources, so trailing `\` row breaks are dropped
  /// (inline `$…$` is left for MathText).
  String get title {
    String tidy(String? s) => (s ?? '').replaceAll(RegExp(r'(\s*\\+)+\s*$'), '').trim();
    final d = tidy(doc), sec = tidy(section);
    return sec.isEmpty ? d : '$d › $sec';
  }
}

List<Citation> _citations(Object? v) =>
    v is List ? [for (final c in v) if (c is Map) Citation.fromJson(_map(c))] : const [];

class ChatMessage {
  ChatMessage({required this.role, required this.content, this.citations = const [], DateTime? sentAt})
    : sentAt = sentAt ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    role: '${j['role'] ?? 'assistant'}',
    content: '${j['content'] ?? ''}',
    citations: _citations(j['citations']),
    sentAt: parseServerTime(j['datetime_sent']),
  );

  final String role;
  String content;
  List<Citation> citations;
  final DateTime sentAt;

  bool get isUser => role == 'user';
}

class Quota {
  const Quota({required this.limit, required this.used, required this.remaining, this.resetsAt, this.plan});

  factory Quota.fromJson(Map<String, dynamic> j) => Quota(
    limit: (j['limit'] as num?)?.toInt() ?? 0,
    used: (j['used'] as num?)?.toInt() ?? 0,
    remaining: (j['remaining'] as num?)?.toInt() ?? 0,
    resetsAt: parseServerTime(j['resets_at']),
    plan: j['plan'] as String?,
  );

  final int limit;
  final int used;
  final int remaining;
  final DateTime? resetsAt;
  final String? plan;

  bool get isOut => remaining <= 0;
  bool get isPro => plan == 'pro';

  /// " Next prompt in ~12 min." or "" (mirrors the web).
  String get resetHint {
    final r = resetsAt;
    if (r == null) return '';
    final mins = (r.difference(DateTime.now()).inSeconds / 60).ceil().clamp(1, 1 << 20);
    return ' Next prompt in ~$mins min.';
  }
}

class Skill {
  const Skill({required this.skill, required this.title});

  factory Skill.fromJson(Map<String, dynamic> j) =>
      Skill(skill: '${j['skill']}', title: '${j['title'] ?? j['skill']}');

  final String skill;
  final String title;
}

class SkillList {
  const SkillList(this.skills, this.defaultSkill);
  final List<Skill> skills;
  final String defaultSkill;

  /// The skill whose name appears in the question's topic, else the default (same rule as the web).
  String guess(String? topic) {
    final t = (topic ?? '').toLowerCase();
    for (final s in skills) {
      if (t.contains(s.skill.replaceAll('-', ' '))) return s.skill;
    }
    return defaultSkill;
  }
}

class ChatThread {
  const ChatThread({
    required this.attemptId,
    required this.questionId,
    required this.examTitle,
    required this.question,
    this.topic,
    required this.messages,
    required this.bytes,
    this.lastAt,
    required this.lastPreview,
  });

  factory ChatThread.fromJson(Map<String, dynamic> j) => ChatThread(
    attemptId: '${j['attempt_id']}',
    questionId: '${j['question_id']}',
    examTitle: '${j['exam_title'] ?? ''}',
    question: '${j['question'] ?? ''}',
    topic: j['topic'] as String?,
    messages: (j['messages'] as num?)?.toInt() ?? 0,
    bytes: (j['bytes'] as num?)?.toInt() ?? 0,
    lastAt: parseServerTime(j['last_at']),
    lastPreview: '${j['last_preview'] ?? ''}',
  );

  final String attemptId;
  final String questionId;
  final String examTitle;
  final String question;
  final String? topic;
  final int messages;
  final int bytes;
  final DateTime? lastAt;
  final String lastPreview;
}

class ThreadUsage {
  const ThreadUsage({required this.threads, required this.bytes, required this.maxThreads, required this.maxBytes, required this.plan});

  factory ThreadUsage.fromJson(Map<String, dynamic> j) => ThreadUsage(
    threads: (j['threads'] as num?)?.toInt() ?? 0,
    bytes: (j['bytes'] as num?)?.toInt() ?? 0,
    maxThreads: (j['max_threads'] as num?)?.toInt() ?? 10,
    maxBytes: (j['max_bytes'] as num?)?.toInt() ?? 100000,
    plan: '${j['plan'] ?? 'free'}',
  );

  final int threads;
  final int bytes;
  final int maxThreads;
  final int maxBytes;
  final String plan;

  double get fill {
    final a = maxThreads > 0 ? threads / maxThreads : 0.0;
    final b = maxBytes > 0 ? bytes / maxBytes : 0.0;
    return (a > b ? a : b).clamp(0.0, 1.0);
  }
}

class ThreadList {
  const ThreadList(this.threads, this.usage);
  final List<ChatThread> threads;
  final ThreadUsage usage;
}

class FavoriteEquation {
  const FavoriteEquation({
    required this.id,
    required this.latex,
    required this.display,
    this.skill,
    this.context,
    this.attemptId,
    this.questionId,
  });

  factory FavoriteEquation.fromJson(Map<String, dynamic> j) => FavoriteEquation(
    id: (j['id'] as num).toInt(),
    latex: '${j['latex']}',
    display: j['display'] == true,
    skill: j['skill'] as String?,
    context: j['context'] as String?,
    attemptId: j['attempt_id'] as String?,
    questionId: j['question_id'] as String?,
  );

  final int id;
  final String latex;
  final bool display;
  final String? skill;
  final String? context;
  final String? attemptId;
  final String? questionId;
}

/// One event of `POST /exam-attempts/{id}/chat/stream`.
sealed class TutorEvent {
  const TutorEvent();
}

class TutorStatus extends TutorEvent {
  const TutorStatus(this.text);
  final String text;
}

class TutorMeta extends TutorEvent {
  const TutorMeta(this.citations);
  final List<Citation> citations;
}

class TutorDelta extends TutorEvent {
  const TutorDelta(this.text);
  final String text;
}

class TutorDone extends TutorEvent {
  const TutorDone(this.message, this.quota);
  final ChatMessage message;
  final Quota? quota;
}

/// Maps a decoded SSE event to a [TutorEvent]. `error` events throw [TutorStreamError].
TutorEvent? tutorEventFrom(String event, Map<String, dynamic> data) => switch (event) {
  'status' => TutorStatus('${data['text'] ?? ''}'),
  'meta' => TutorMeta(_citations(data['citations'])),
  'delta' => TutorDelta('${data['text'] ?? ''}'),
  'done' => TutorDone(
    ChatMessage.fromJson(_map(data['message'])),
    data['quota'] is Map ? Quota.fromJson(_map(data['quota'])) : null,
  ),
  'error' => throw TutorStreamError(
    data['status'] == 502
        ? 'The AI tutor is unavailable right now. Your prompt was not counted.'
        : '${data['detail'] ?? 'Something went wrong'}',
  ),
  _ => null,
};

class TutorStreamError implements Exception {
  const TutorStreamError(this.message);
  final String message;
  @override
  String toString() => message;
}
