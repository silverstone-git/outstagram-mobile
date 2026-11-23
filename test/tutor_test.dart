import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/net/api_client.dart';
import 'package:outstagram/core/net/api_error.dart';
import 'package:outstagram/features/tutor/models.dart';
import 'package:outstagram/features/tutor/sse.dart';
import 'package:outstagram/features/tutor/tutor_api.dart';
import 'package:outstagram/features/tutor/tutor_markdown.dart';

Stream<List<int>> chunks(List<String> parts) => Stream.fromIterable([for (final p in parts) utf8.encode(p)]);

String sse(String event, Object data) => 'event: $event\ndata: ${jsonEncode(data)}\n\n';

/// Serves one canned response (raw body + status) for every request.
class CannedServer implements HttpClientAdapter {
  CannedServer(this.status, this.body, {this.contentType = 'text/event-stream'});
  final int status;
  final List<String> body;
  final String contentType;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    last = o;
    return ResponseBody(
      Stream.fromIterable([for (final p in this.body) Uint8List.fromList(utf8.encode(p))]),
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

TutorApi apiWith(CannedServer s) => TutorApi(Api(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = s));

void main() {
  group('decodeSse', () {
    test('splits events across arbitrary chunk boundaries, handles CRLF and multi-byte text', () async {
      final raw = '${sse('status', {'text': 'Checking…'})}${sse('delta', {'text': 'θ = π'})}'.replaceAll('\n', '\r\n');
      // split inside the multi-byte θ and inside the separator
      final bytes = utf8.encode(raw);
      final cut1 = 20, cut2 = raw.indexOf('θ') + 3;
      final events = await decodeSse(
        Stream.fromIterable([bytes.sublist(0, cut1), bytes.sublist(cut1, cut2), bytes.sublist(cut2)]),
      ).toList();
      expect(events.map((e) => e.event), ['status', 'delta']);
      expect(events[1].data['text'], 'θ = π');
    });

    test('skips comments and malformed blocks; keeps an unterminated final block', () async {
      final events = await decodeSse(chunks([': ping\n\n', 'event: x\ndata: {nope\n\n', 'event: done\ndata: {"a":1}'])).toList();
      expect(events.single.event, 'done');
      expect(events.single.data['a'], 1);
    });
  });

  group('tutorEventFrom', () {
    test('maps every event', () {
      expect(tutorEventFrom('status', {'text': 'hi'}), isA<TutorStatus>());
      final meta = tutorEventFrom('meta', {
        'citations': [
          {'n': 1, 'doc': 'Griffiths', 'section': '4.2'},
        ],
        'skills': ['physics'],
      });
      expect((meta! as TutorMeta).citations.single.doc, 'Griffiths');
      final done = tutorEventFrom('done', {
        'message': {'role': 'assistant', 'content': 'ok', 'citations': null, 'datetime_sent': '2026-11-24T10:00:00'},
        'quota': {'limit': 10, 'used': 3, 'remaining': 7, 'window_seconds': 3600, 'resets_at': null, 'plan': 'free'},
      })! as TutorDone;
      expect(done.message.content, 'ok');
      expect(done.message.sentAt.toUtc().hour, 10); // naive timestamps are UTC
      expect(done.quota!.remaining, 7);
      expect(tutorEventFrom('unknown', {}), isNull);
    });

    test('error events throw a readable message', () {
      expect(
        () => tutorEventFrom('error', {'status': 502, 'detail': 'x'}),
        throwsA(isA<TutorStreamError>().having((e) => e.message, 'message', contains('not counted'))),
      );
      expect(
        () => tutorEventFrom('error', {'status': 500, 'detail': 'KeyError'}),
        throwsA(isA<TutorStreamError>().having((e) => e.message, 'message', 'KeyError')),
      );
    });
  });

  group('TutorApi.ask', () {
    test('streams status, meta, deltas, done and sends skills', () async {
      final server = CannedServer(200, [
        sse('status', {'text': 'Checking the textbooks…'}),
        sse('meta', {'citations': [], 'skills': ['physics']}),
        'event: delta\ndata: {"text": "Hel',
        'lo"}\n\n',
        sse('delta', {'text': ' there'}),
        sse('done', {
          'message': {'role': 'assistant', 'content': 'Hello there', 'datetime_sent': '2026-11-24T10:00:00'},
          'quota': {'limit': 10, 'used': 1, 'remaining': 9},
        }),
      ]);
      final events = await apiWith(server).ask('a1', 'q 1', 'why?', skills: ['physics']).toList();
      expect(events.whereType<TutorDelta>().map((d) => d.text).join(), 'Hello there');
      expect(events.last, isA<TutorDone>());
      expect(server.last!.path, '/exam-attempts/a1/chat/stream');
      expect(server.last!.data, {'question_id': 'q 1', 'message': 'why?', 'skills': ['physics']});
    });

    test('a stream without done is reported as cut off', () async {
      final server = CannedServer(200, [sse('delta', {'text': 'Hel'})]);
      expect(
        apiWith(server).ask('a1', 'q1', 'why?').toList(),
        throwsA(isA<TutorStreamError>().having((e) => e.message, 'message', contains('cut off'))),
      );
    });

    test('429 paywall body is decoded from the stream response', () async {
      final body = {
        'detail': {
          'code': 'ai_quota',
          'message': "You've used all your AI prompts for this hour.",
          'upgrade': true,
          'quota': {'limit': 10, 'used': 10, 'remaining': 0, 'resets_at': '2026-11-24T11:00:00Z'},
        },
      };
      final server = CannedServer(429, [jsonEncode(body)], contentType: 'application/json');
      await expectLater(
        apiWith(server).ask('a1', 'q1', 'why?').toList(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 429)
              .having((e) => e.code, 'code', 'ai_quota')
              .having((e) => e.isPaywall, 'isPaywall', true)
              .having((e) => e.message, 'message', contains('AI prompts')),
        ),
      );
    });

    test('402 free-plan limit and 404 come through with their messages', () async {
      final s402 = CannedServer(402, [
        jsonEncode({
          'detail': {'code': 'tutor_threads', 'message': 'Free plan keeps 10 chats', 'upgrade': true},
        }),
      ], contentType: 'application/json');
      await expectLater(
        apiWith(s402).ask('a1', 'q1', 'x').toList(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'tutor_threads')),
      );
      final s404 = CannedServer(404, [jsonEncode({'detail': 'Attempt not found'})], contentType: 'application/json');
      await expectLater(
        apiWith(s404).ask('a1', 'q1', 'x').toList(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Attempt not found')),
      );
    });
  });

  group('models', () {
    test('skill guess follows the topic, else the default', () {
      const list = SkillList([Skill(skill: 'physics', title: 'Physics'), Skill(skill: 'organic-chemistry', title: 'Organic')], 'physics');
      expect(list.guess('Organic Chemistry: SN2'), 'organic-chemistry');
      expect(list.guess('Quantum Mechanics'), 'physics');
      expect(list.guess(null), 'physics');
    });

    test('usage fill is the larger of the two limits', () {
      const u = ThreadUsage(threads: 2, bytes: 80000, maxThreads: 10, maxBytes: 100000, plan: 'free');
      expect(u.fill, closeTo(0.8, 1e-9));
    });
  });

  group('normalizeMath', () {
    test('converts \\( \\) and \\[ \\] and fences display math', () {
      final out = normalizeMath(r'Energy \(E=mc^2\) and \[F = ma\] done');
      expect(out, contains(r'$E=mc^2$'));
      expect(out, contains('\n\n\$\$\nF = ma\n\$\$\n\n'));
    });

    test('drops a dangling \$\$ mid-stream', () {
      expect(normalizeMath(r'so $$x = '), r'so x = ');
    });

    test('wraps bare environments', () {
      expect(normalizeMath(r'A \begin{pmatrix}1\\2\end{pmatrix}'), contains('\$\$\n\\begin{pmatrix}'));
    });
  });

  group('TutorMarkdown', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('renders markdown with inline and display math', (t) async {
      await t.pumpWidget(host(const TutorMarkdown('**Bold** and \$x_1^2\$ inline.\n\n\$\$\n\\frac{a}{b}\n\$\$\n\n- item')));
      expect(find.byType(Math), findsNWidgets(2));
      expect(find.textContaining('Bold', findRichText: true), findsOneWidget);
      expect(find.textContaining('item', findRichText: true), findsOneWidget);
    });

    testWidgets('long-pressing an equation picks its LaTeX', (t) async {
      final picked = <PickedEquation>[];
      await t.pumpWidget(host(TutorMarkdown('Look:\n\n\$\$E = h\\nu\$\$', onPickEquation: picked.add)));
      await t.longPress(find.ancestor(of: find.byType(Math), matching: find.byType(GestureDetector)).first);
      expect(picked.single.latex, r'E = h\nu');
      expect(picked.single.display, isTrue);
    });

    testWidgets('a half-streamed answer still renders', (t) async {
      await t.pumpWidget(host(const TutorMarkdown(r'The energy is $$E = \frac{')));
      expect(t.takeException(), isNull);
    });
  });

  test('stream error helper falls back for non-JSON bodies', () async {
    final opts = RequestOptions(path: '/x');
    final e = DioException(
      requestOptions: opts,
      response: Response<ResponseBody>(
        requestOptions: opts,
        statusCode: 502,
        data: ResponseBody.fromString('<html>bad gateway</html>', 502),
      ),
    );
    final err = await streamError(e);
    expect(err.status, 502);
    expect(err.message, isNotEmpty);
  });
}
