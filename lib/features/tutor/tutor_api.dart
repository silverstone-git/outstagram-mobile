import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/net/api_error.dart';
import '../streak/local_alerts.dart';
import 'models.dart';
import 'sse.dart';

final tutorApiProvider = Provider<TutorApi>((ref) => TutorApi(ref.watch(apiProvider)));

/// The tutor's knowledge-bank skills; the same for every question, so fetched once per app run.
final tutorSkillsProvider = FutureProvider<SkillList>((ref) async {
  try {
    return await ref.watch(tutorApiProvider).skills();
  } catch (_) {
    return const SkillList([], 'physics');
  }
});

/// The hourly AI prompt quota. Chat screens refresh it on open and set it from each answer.
final tutorQuotaProvider = NotifierProvider<QuotaNotifier, Quota?>(QuotaNotifier.new);

class QuotaNotifier extends Notifier<Quota?> {
  @override
  Quota? build() => null;

  Future<void> refresh() async {
    try {
      set(await ref.read(tutorApiProvider).quota());
    } catch (_) {
      // the pill just stays hidden
    }
  }

  void set(Quota? q) {
    if (q == null) return;
    state = q;
    TutorAlerts.sync(q); // "your tutor is back" when the hour resets after running out
  }
}

final tutorThreadsProvider = FutureProvider.autoDispose<ThreadList>((ref) => ref.watch(tutorApiProvider).threads());
final favoriteEquationsProvider =
    FutureProvider.autoDispose<List<FavoriteEquation>>((ref) => ref.watch(tutorApiProvider).favorites());

class TutorApi {
  TutorApi(this._api);

  final Api _api;

  Future<List<ChatMessage>> chat(String attemptId, String questionId) async => [
    for (final m in await _api.get<List<dynamic>>('/exam-attempts/$attemptId/chat', query: {'question_id': questionId}))
      ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)),
  ];

  /// Streams the answer. Limit errors (402/429) and 404s arrive as [ApiException] before the first
  /// event; a failure mid-stream throws [TutorStreamError]. Cancel with [cancel].
  Stream<TutorEvent> ask(
    String attemptId,
    String questionId,
    String message, {
    List<String>? skills,
    CancelToken? cancel,
  }) async* {
    final Response<ResponseBody> res;
    try {
      res = await _api.dio.post<ResponseBody>(
        '/exam-attempts/$attemptId/chat/stream',
        data: {'question_id': questionId, 'message': message, if (skills != null && skills.isNotEmpty) 'skills': skills},
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
    } on DioException catch (e) {
      throw await streamError(e);
    }
    var done = false;
    try {
      await for (final sse in decodeSse(res.data!.stream)) {
        final ev = tutorEventFrom(sse.event, sse.data);
        if (ev == null) continue;
        if (ev is TutorDone) done = true;
        yield ev;
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
    if (!done) throw const TutorStreamError('The answer was cut off. Please try again.');
  }

  Future<SkillList> skills() async {
    final d = await _api.get<Map<String, dynamic>>('/ai/skills');
    return SkillList(
      [for (final s in (d['skills'] as List? ?? const [])) Skill.fromJson(Map<String, dynamic>.from(s as Map))],
      '${d['default'] ?? 'physics'}',
    );
  }

  Future<Quota> quota() async => Quota.fromJson(await _api.get<Map<String, dynamic>>('/ai/quota'));

  Future<ThreadList> threads() async {
    final d = await _api.get<Map<String, dynamic>>('/ai/chats');
    return ThreadList(
      [for (final t in (d['threads'] as List? ?? const [])) ChatThread.fromJson(Map<String, dynamic>.from(t as Map))],
      ThreadUsage.fromJson(Map<String, dynamic>.from((d['usage'] as Map?) ?? const {})),
    );
  }

  Future<void> deleteThread(String attemptId, String questionId) =>
      _api.delete<dynamic>('/ai/chats', query: {'attempt_id': attemptId, 'question_id': questionId});

  Future<List<FavoriteEquation>> favorites() async => [
    for (final f in await _api.get<List<dynamic>>('/favorites/equations'))
      FavoriteEquation.fromJson(Map<String, dynamic>.from(f as Map)),
  ];

  Future<FavoriteEquation> addFavorite({
    required String latex,
    required bool display,
    String? skill,
    String? context,
    String? attemptId,
    String? questionId,
  }) async => FavoriteEquation.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/favorites/equations',
      data: {
        'latex': latex,
        'display': display,
        'skill': skill,
        'context': context,
        'attempt_id': attemptId,
        'question_id': questionId,
      },
    ),
  );

  Future<void> deleteFavorite(int id) => _api.delete<dynamic>('/favorites/equations/$id');
}

/// With `ResponseType.stream` an error response's body is still a byte stream; read and decode it so
/// [ApiException] sees FastAPI's `detail` (paywall code, quota, message).
Future<ApiException> streamError(DioException e) async {
  final res = e.response;
  final body = res?.data;
  if (res != null && body is ResponseBody) {
    try {
      final text = await utf8.decoder.bind(body.stream).join();
      Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
      return ApiException.from(
        DioException(
          requestOptions: e.requestOptions,
          type: e.type,
          response: Response<dynamic>(
            requestOptions: e.requestOptions,
            statusCode: res.statusCode,
            data: json,
            headers: res.headers,
          ),
        ),
      );
    } catch (_) {
      // fall through
    }
  }
  if (res?.statusCode == 502) {
    return ApiException('The AI tutor is unavailable right now. Your prompt was not counted.', status: 502);
  }
  return ApiException.from(e);
}
