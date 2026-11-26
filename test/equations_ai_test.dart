import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/ui/equation_menu.dart';
import 'package:outstagram/features/tutor/ai_options.dart';
import 'package:outstagram/features/tutor/models.dart';
import 'package:outstagram/features/tutor/tutor_library_screen.dart';

AIOptions _opts({bool allowed = true}) => AIOptions.fromJson({
      'plan': allowed ? 'pro' : 'free',
      'allowed': allowed,
      'efforts': ['auto', 'low', 'medium', 'high'],
      'models': [
        {'id': 'gemini-flash', 'label': 'Gemini Flash · smarter', 'plan': 'pro', 'available': allowed},
        {'id': 'heavy', 'label': 'Heavy', 'plan': 'contributor', 'available': false},
      ],
      'byok': {
        'per_hour': 300,
        'providers': [
          {'id': 'openai', 'api_type': 'openai', 'label': 'OpenAI', 'base_url': 'https://api.openai.com/v1'},
        ],
      },
      'context': {'passages': 12, 'history_turns': 20},
    });

void main() {
  group('tutor choices', () {
    test('defaults send nothing', () => expect(const TutorPrefs().choice(_opts()), isNull));
    test('free users send nothing', () {
      expect(const TutorPrefs(model: 'gemini-flash', effort: 'high').choice(_opts(allowed: false)), isNull);
    });
    test('model + thinking', () {
      const p = TutorPrefs(model: 'gemini-flash', effort: 'high');
      expect(p.choice(_opts()), {'model': 'gemini-flash', 'effort': 'high'});
      expect(p.label(_opts()), 'Gemini Flash · high thinking');
    });
    test('an unavailable model is dropped', () {
      expect(const TutorPrefs(model: 'heavy').choice(_opts()), isNull);
    });
    test('byok carries the key and the provider base url', () {
      const p = TutorPrefs(useByok: true, apiKey: 'sk-test-123456', byokModel: 'gpt-x');
      final c = p.choice(_opts())!;
      expect(c['byok'], containsPair('api_key', 'sk-test-123456'));
      expect(c['byok'], containsPair('base_url', 'https://api.openai.com/v1'));
      expect(c.containsKey('model'), isFalse);
    });
    test('byok without a model falls back to the gateway', () {
      expect(const TutorPrefs(useByok: true, apiKey: 'sk-test-123456').choice(_opts()), isNull);
    });
  });

  group('saved equation locations', () {
    FavoriteEquation fav(Map<String, dynamic> j) =>
        FavoriteEquation.fromJson({'id': 1, 'latex': r'E = mc^2', 'display': false, ...j});
    test('tutor reply', () {
      final loc = equationLocation(fav({'attempt_id': 'a1', 'question_id': 'q1', 'message_id': 7, 'source': 'tutor'}))!;
      expect(loc, startsWith('/tutor/a1/q1?eq='));
      expect(loc, endsWith('&mid=7'));
      expect(Uri.parse(loc).queryParameters['eq'], r'E = mc^2');
    });
    test('exam review', () {
      final loc = equationLocation(fav({'attempt_id': 'a1', 'question_id': 'q1', 'source': 'explanation'}))!;
      expect(Uri.parse(loc).path, '/exam/attempt/a1');
      expect(Uri.parse(loc).queryParameters['q'], 'q1');
    });
    test('post', () => expect(equationLocation(fav({'post_id': 'p9', 'source': 'post'})), startsWith('/p/p9?eq=')));
    test('unknown origin', () => expect(equationLocation(fav({})), isNull));
    test('old favourites with an attempt count as tutor ones', () {
      expect(fav({'attempt_id': 'a', 'question_id': 'q'}).from, 'AI tutor');
    });
  });

  test('equation keys ignore spacing', () => expect(eqKey(r'E = m c^2'), eqKey(r'E=mc^2')));

  test('done event carries the model and message id', () {
    final ev = tutorEventFrom('done', {
      'message': {'id': 5, 'role': 'assistant', 'content': 'x', 'datetime_sent': '2026-11-26T10:00:00'},
      'quota': {'limit': 300, 'used': 1, 'remaining': 299, 'byok': true},
      'model': 'Mine · gpt-x',
    });
    expect(ev, isA<TutorDone>());
    final d = ev! as TutorDone;
    expect(d.message.id, 5);
    expect(d.model, 'Mine · gpt-x');
    expect(d.quota!.byok, isTrue);
  });
}
