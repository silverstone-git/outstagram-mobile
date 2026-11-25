import 'package:dio/dio.dart';

/// Demo content for the README screenshots. Made-up people and posts; images from test/screenshots/media.
final _now = DateTime.now().toUtc();
String ago(Duration d) => _now.subtract(d).toIso8601String().replaceAll('Z', ''); // the API's naive UTC

const me = {
  'user_id': 1,
  'username': 'aarav',
  'fullname': 'Aarav Mehta',
  'bio': 'PG physics aspirant · GATE 2027 · coffee + Griffiths',
  'email': 'demo@example.com',
  'email_verified': true,
  'verification_required': true,
  'avatar_url': null,
};

Map<String, Object?> post(String id, String author, int authorId, String category, String caption, Duration age,
        {List<String> images = const [], int likes = 0, int comments = 0, bool liked = false}) =>
    {
      'post_id': id,
      'author': author,
      'author_user_id': authorId,
      'post_category': category,
      'caption': caption,
      'datetime_posted': ago(age),
      'highlighted_by_author': false,
      'is_liked': liked,
      'like_count': likes,
      'comment_count': comments,
      'author_avatar_url': null,
      'media_urls': [for (final i in images) {'url': 'https://img.test/$i', 'media_type': 'image'}],
    };

final feed = [
  post('p1', 'meera.iyer', 2, 'Academic',
      'Hydrogen atom in one page 📝 Energy levels, Bohr radius and the ground state. Save it for revision! #QuantumMechanics #GATE',
      const Duration(hours: 2), images: ['notes.jpg'], likes: 48, comments: 9, liked: true),
  post('p2', 'kabir_s', 3, 'Exam Result',
      '📊 GATE Physics Mock #8: 72/100 (61/65 attempted, 84% accuracy). Eight mocks in, finally above 70! #ExamPrep',
      const Duration(hours: 5), images: ['chart.jpg'], likes: 112, comments: 23),
  post('p3', 'riya.physics', 4, 'Achievement', 'Cleared CSIR NET Physical Sciences 🎉 Thank you all for the study sessions!',
      const Duration(days: 1), images: ['badge.jpg'], likes: 256, comments: 41, liked: true),
];

final myPosts = [
  post('m1', 'aarav', 1, 'Exam Result', '📊 Quantum Mechanics · quick practice: 8/10 (80% accuracy) #ExamPrep',
      const Duration(hours: 20), images: ['chart.jpg'], likes: 17, comments: 3),
  post('m2', 'aarav', 1, 'Academic', 'My hydrogen atom notes', const Duration(days: 3), images: ['notes.jpg'], likes: 31),
  post('m3', 'aarav', 1, 'Achievement', 'Streak day 30 🔥', const Duration(days: 6), images: ['badge.jpg'], likes: 54),
];

List<String> _streakDays(int n) {
  final today = DateTime.now();
  return [for (var i = 0; i < n; i++) today.subtract(Duration(days: i)).toIso8601String().substring(0, 10)];
}

Map<String, Object?> streak() {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return {
    'current': 34,
    'longest': 41,
    'today_done': true,
    'at_risk': false,
    'broken': false,
    'lost': 0,
    'last_day': today,
    'today': today,
    'day_ends_at': null,
    'tz': 'Asia/Kolkata',
    'subject': 'quantum',
    'days': _streakDays(34),
    'frozen_days': [],
    'milestones': [3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 365],
    'next_milestone': 50,
    'prev_milestone': 30,
    'freezes': 2,
    'freezes_max': 2,
    'freeze_every': 7,
    'reward': {'goal': 250, 'unlocked': false, 'days_left': 216, 'ai_prompts_per_hour': 60, 'tutor_threads': 1000},
  };
}

const limitsFree = {
  'ai_prompts_per_hour': 10, 'tutor_threads': 10, 'tutor_bytes': 100000, 'media_bytes': 200000,
  'video_bytes': 0, 'media_per_post': 4, 'posts': 50,
};
const limitsPro = {
  'ai_prompts_per_hour': 60, 'tutor_threads': 1000, 'tutor_bytes': 25000000, 'media_bytes': 4000000,
  'video_bytes': 4000000, 'media_per_post': 4, 'posts': 400,
};

final billing = {
  'plan': 'pro',
  'valid_until': _now.add(const Duration(days: 21)).toIso8601String(),
  'limits': limitsPro,
  'free_limits': limitsFree,
  'pro_limits': limitsPro,
  'usage': {},
  'payments_enabled': true,
  'test_mode': false,
  'price': {'amount': 9900, 'currency': 'INR', 'days': 30},
  'posts': 3,
};

Map<String, Object?> q(String id, String text, List<String> opts, int answer, String topic) => {
      'id': id,
      'type': 'MCQ',
      'question': text,
      'options': [for (var i = 0; i < opts.length; i++) {'label': i + 1, 'value': opts[i]}],
      'answer_label': answer,
      'topic': topic,
      'explanation': '',
    };

final questions = [
  q('q1', r'A particle in the ground state of the potential $V(x) = \\tfrac{1}{2} m \\omega^2 x^2$. What is $\\langle x^2 \\rangle$?',
      [r'$\\dfrac{\\hbar}{2 m \\omega}$', r'$\\dfrac{\\hbar}{m \\omega}$', r'$\\dfrac{2\\hbar}{m \\omega}$', r'$0$'], 1,
      'Quantum Mechanics'),
  q('q2', r'The commutator $[\\hat{x}, \\hat{p}^2]$ equals', [r'$2i\\hbar\\,\\hat{p}$', r'$i\\hbar$', r'$0$', r'$-2i\\hbar\\,\\hat{x}$'], 1,
      'Quantum Mechanics'),
  q('q3', r'For hydrogen, the degeneracy of level $n$ (ignoring spin) is', [r'$n$', r'$n^2$', r'$2n^2$', r'$2n+1$'], 2,
      'Quantum Mechanics'),
];

final friends = [
  {'username': 'aarav', 'fullname': 'Aarav Mehta', 'avatar_url': null, 'streak': 34, 'today_done': true, 'is_you': true},
  {'username': 'meera.iyer', 'fullname': 'Meera Iyer', 'avatar_url': null, 'streak': 58, 'today_done': true, 'is_you': false},
  {'username': 'kabir_s', 'fullname': 'Kabir Singh', 'avatar_url': null, 'streak': 12, 'today_done': false, 'is_you': false},
];

const _answer = r'''
Good question. Your answer $\dfrac{\hbar}{m\omega}$ is **twice** the right value.

### Why
In the ground state the energy splits evenly between kinetic and potential (virial theorem):

$$\langle V \rangle = \tfrac{1}{2} m \omega^2 \langle x^2 \rangle = \tfrac{1}{2} E_0 = \tfrac{1}{4}\hbar\omega$$

so

$$\langle x^2 \rangle = \frac{\hbar}{2 m \omega}$$

### Quick check
- Units: $\hbar / (m\omega)$ is a length squared ✓
- Larger mass or stiffer spring → narrower wavefunction ✓

**Tip:** for any eigenstate, $\langle x^2 \rangle = \frac{\hbar}{m\omega}\left(n + \tfrac{1}{2}\right)$. [1]
''';

final chat = [
  {'role': 'user', 'content': 'Why is my answer wrong?', 'datetime_sent': ago(const Duration(minutes: 6))},
  {'role': 'assistant', 'content': _answer, 'datetime_sent': ago(const Duration(minutes: 6)),
   'citations': [{'n': 1, 'doc': 'Griffiths, Introduction to Quantum Mechanics', 'section': 'The harmonic oscillator'}]},
];

final attempt = {
  'attempt_id': 'a1', 'exam_id': null, 'exam_title': 'Quantum Mechanics · quick practice', 'score': 8, 'max_score': 10,
  'accuracy': 80, 'total_questions': 10, 'total_time_seconds': 1260, 'datetime_taken': ago(const Duration(hours: 1)),
};

var _sampled = 0;

/// (method, path regex, response) rows for [FakeApi].
final routes = <(String, RegExp, Object? Function(RequestOptions))>[
  ('GET', RegExp(r'^/exam-attempts/a1/chat'), (_) => chat),
  ('GET', RegExp(r'^/ai/skills'), (_) => {
        'skills': [{'skill': 'physics', 'title': 'Physics'}, {'skill': 'maths', 'title': 'Maths'}], 'default': 'physics'}),
  ('GET', RegExp(r'^/ai/chats'), (_) => {'threads': [], 'usage': {'threads': 3, 'bytes': 9000, 'max_threads': 1000,
        'max_bytes': 25000000, 'plan': 'pro'}}),
  ('GET', RegExp(r'^/me$'), (_) => me),
  ('GET', RegExp(r'^/me/streak/friends'), (_) => friends),
  ('GET', RegExp(r'^/me/streak'), (_) => streak()),
  ('GET', RegExp(r'^/billing/status'), (_) => billing),
  ('GET', RegExp(r'^/feed'), (_) => feed),
  ('GET', RegExp(r'^/explore'), (_) => feed.reversed.toList()),
  ('GET', RegExp(r'^/trending'), (_) => [
        {'tag': 'GATE', 'posts': 41}, {'tag': 'QuantumMechanics', 'posts': 23}, {'tag': 'ExamPrep', 'posts': 19},
      ]),
  ('GET', RegExp(r'^/users/aarav/posts/1'), (_) => myPosts),
  ('GET', RegExp(r'^/users/[^/]+/posts/'), (_) => []),
  ('GET', RegExp(r'^/users/aarav$'), (_) => {
        ...me, 'posts_count': 3, 'followers_count': 128, 'following_count': 86, 'you_follow_them': 0,
        'they_follow_you': 0, 'streak': 34,
      }),
  ('GET', RegExp(r'^/me/stats'), (_) => {
        'posts': 3, 'posts_this_week': 1, 'achievements': 1, 'achievements_this_month': 1, 'followers': 128,
        'following': 86, 'exams_taken': 46, 'exams_this_week': 7, 'avg_accuracy': 71.4, 'best_score_pct': 90,
      }),
  ('GET', RegExp(r'^/follow-requests'), (_) => []),
  ('GET', RegExp(r'^/exam-attempts'), (_) => [
        {'attempt_id': 'a1', 'exam_id': null, 'exam_title': 'Quantum Mechanics · quick practice', 'score': 8,
         'max_score': 10, 'accuracy': 80, 'total_questions': 10, 'total_time_seconds': 1260,
         'datetime_taken': ago(const Duration(hours: 20))},
        {'attempt_id': 'a2', 'exam_id': null, 'exam_title': 'GATE Physics Mock', 'score': 72, 'max_score': 100,
         'accuracy': 84, 'total_questions': 65, 'total_time_seconds': 10400,
         'datetime_taken': ago(const Duration(days: 2))},
      ]),
  ('GET', RegExp(r'^/pariksha'), (_) => [
        {'exam_id': 'c1', 'exam_title': 'Mathematical Methods: Complex Analysis Drill', 'datetime_uploaded': ago(const Duration(days: 4))},
        {'exam_id': 'c2', 'exam_title': 'Statistical Mechanics: Ensembles', 'datetime_uploaded': ago(const Duration(days: 9))},
      ]),
  ('GET', RegExp(r'^/api/question_bank/sample'), (_) => [{...questions.first, 'id': 'q${_sampled++}'}]), // oscillator
  ('GET', RegExp(r'^/ai/quota'), (_) => {'limit': 60, 'used': 4, 'remaining': 56, 'window_seconds': 3600, 'resets_at': null}),
];
