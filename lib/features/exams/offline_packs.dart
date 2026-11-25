import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/net/api_error.dart';
import '../streak/streak_api.dart';
import 'engine/engine.dart';
import 'exam_api.dart';

/// Offline exam packs: a subject's question-bank topics saved on the phone, so quick practice, pop
/// quizzes and mocks (when all their subjects are saved) work without a connection. Attempts made
/// offline wait in [PendingAttempts] and upload later with their real finish time.
///
/// Files: `<app documents>/exam_packs/<slug>.json` = {subject, saved_at, topics: {slug: [question]}}.
const packQuestionsPerTopic = 40;

class PackInfo {
  const PackInfo({required this.subject, required this.savedAt, required this.questions, required this.bytes});

  final String subject;
  final DateTime savedAt;
  final int questions;
  final int bytes;
}

class OfflinePacks {
  OfflinePacks._();
  static final instance = OfflinePacks._();

  final _cache = <String, Map<String, List<Question>>>{}; // subject -> topic slug -> questions

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/exam_packs');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<File> _file(String subject) async => File('${(await _dir()).path}/${topicSlug(subject)}.json');

  Future<List<PackInfo>> list() async {
    final out = <PackInfo>[];
    for (final f in (await _dir()).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final topics = Map<String, dynamic>.from(j['topics'] as Map);
        out.add(PackInfo(
          subject: '${j['subject']}',
          savedAt: DateTime.tryParse('${j['saved_at']}')?.toLocal() ?? DateTime.now(),
          questions: topics.values.fold(0, (n, l) => n + (l as List).length),
          bytes: await f.length(),
        ));
      } catch (e) {
        debugPrint('dropping unreadable pack ${f.path}: $e');
        f.deleteSync();
      }
    }
    out.sort((a, b) => a.subject.compareTo(b.subject));
    return out;
  }

  /// Downloads every topic of [subject] ([packQuestionsPerTopic] each). [onProgress] gets 0..1.
  Future<PackInfo> download(ExamApi api, String subject, {void Function(double)? onProgress}) async {
    final topics = subjectGroups[subject] ?? const [];
    if (topics.isEmpty) throw ApiException('Unknown subject $subject');
    final out = <String, List<Map<String, dynamic>>>{};
    var done = 0;
    for (final t in topics) {
      final slug = topicSlug(t);
      final qs = await api.sample(slug, packQuestionsPerTopic); // network errors propagate: nothing saved
      out[slug] = [for (final q in qs) q.toJson()];
      onProgress?.call(++done / topics.length);
    }
    if (out.values.every((l) => l.isEmpty)) throw ApiException('No questions found for $subject');
    final f = await _file(subject);
    await f.writeAsString(jsonEncode({'subject': subject, 'saved_at': DateTime.now().toUtc().toIso8601String(), 'topics': out}));
    _cache.remove(subject);
    return (await list()).firstWhere((p) => p.subject == subject);
  }

  Future<void> remove(String subject) async {
    final f = await _file(subject);
    if (f.existsSync()) f.deleteSync();
    _cache.remove(subject);
  }

  Future<Map<String, List<Question>>?> _load(String subject) async {
    if (_cache.containsKey(subject)) return _cache[subject];
    final f = await _file(subject);
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final topics = {
        for (final e in Map<String, dynamic>.from(j['topics'] as Map).entries)
          e.key: [for (final q in e.value as List) Question.fromJson(Map<String, dynamic>.from(q as Map))],
      };
      return _cache[subject] = topics;
    } catch (e) {
      debugPrint('unreadable pack $subject: $e');
      return null;
    }
  }

  /// [count] random questions of a topic from any saved pack, or null if no pack has the topic.
  Future<List<Question>?> sampleOffline(String slug, int count, [Random? rng]) async {
    for (final subject in subjectGroups.keys) {
      if (!(subjectGroups[subject]!.map(topicSlug).contains(slug))) continue;
      final pack = await _load(subject);
      final qs = pack?[slug];
      if (qs == null) continue;
      return (List<Question>.of(qs)..shuffle(rng ?? Random())).take(count).toList();
    }
    return null;
  }

  Future<bool> has(String subject) async => (await _file(subject)).existsSync();
}

/// The question sampler exams use: the server, falling back to a saved pack when the phone is offline
/// (or the server is unreachable). Other errors still surface.
TopicSampler offlineAwareSampler(ExamApi api) => (slug, count) async {
      try {
        return await api.sample(slug, count);
      } catch (e) {
        if (!ApiException.from(e).isNetwork) rethrow;
        final local = await OfflinePacks.instance.sampleOffline(slug, count);
        if (local == null) rethrow;
        return local;
      }
    };

final offlinePacksProvider = FutureProvider.autoDispose<List<PackInfo>>((ref) => OfflinePacks.instance.list());

// --- attempts finished offline -------------------------------------------------------------------------

class _Pending {
  const _Pending(this.examId, this.result, this.maxScore, this.takenAt);

  factory _Pending.fromJson(Map<String, dynamic> j) => _Pending(
        j['exam_id'] as String?,
        ExamResult.fromJson(Map<String, dynamic>.from(j['result'] as Map)),
        (j['max_score'] as num).toDouble(),
        DateTime.parse('${j['taken_at']}'),
      );

  final String? examId;
  final ExamResult result;
  final double maxScore;
  final DateTime takenAt;

  Map<String, dynamic> toJson() => {
        'exam_id': examId,
        'result': result.toJson(),
        'max_score': maxScore,
        'taken_at': takenAt.toUtc().toIso8601String(),
      };
}

/// Attempts that couldn't be saved (no connection). Uploaded on launch/resume and after the next
/// successful save; the server counts each one on the day it was taken (`taken_at`, up to 7 days).
class PendingAttempts {
  PendingAttempts._();
  static final instance = PendingAttempts._();
  static const _key = 'pending_attempts_v1';

  Future<List<_Pending>> _read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    try {
      return [for (final j in jsonDecode(raw) as List) _Pending.fromJson(Map<String, dynamic>.from(j as Map))];
    } catch (e) {
      debugPrint('dropping unreadable pending attempts: $e');
      return [];
    }
  }

  Future<void> _write(List<_Pending> l) async {
    final p = await SharedPreferences.getInstance();
    l.isEmpty ? await p.remove(_key) : await p.setString(_key, jsonEncode([for (final x in l) x.toJson()]));
  }

  Future<int> get count async => (await _read()).length;

  Future<void> add(String? examId, ExamResult result, double maxScore, DateTime takenAt) async =>
      _write([...await _read(), _Pending(examId, result, maxScore, takenAt)]);

  Future<void>? _flushing;

  /// Uploads what's waiting, oldest first; stops at the first network error. Returns how many went up.
  Future<int> flush(ExamApi api, {StreakController? streak}) async {
    if (_flushing != null) {
      await _flushing;
      return 0;
    }
    var sent = 0;
    final run = () async {
      final list = await _read();
      while (list.isNotEmpty) {
        final p = list.first;
        try {
          final saved = await api.saveAttempt(p.examId, p.result, p.maxScore, takenAt: p.takenAt);
          if (saved.streak != null) streak?.apply(saved.streak!);
        } catch (e) {
          if (ApiException.from(e).isNetwork) break; // still offline: try later
          debugPrint('dropping a pending attempt the server refused: $e');
        }
        list.removeAt(0);
        sent++;
        await _write(list);
      }
    }();
    _flushing = run;
    try {
      await run;
    } finally {
      _flushing = null;
    }
    return sent;
  }
}
