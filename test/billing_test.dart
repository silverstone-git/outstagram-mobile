import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/net/api_client.dart';
import 'package:outstagram/core/net/api_error.dart';
import 'package:outstagram/core/ui/feedback.dart';
import 'package:outstagram/features/billing/billing_api.dart';
import 'package:outstagram/features/billing/paywall_sheet.dart';
import 'package:outstagram/features/tutor/models.dart';

/// Shape of outsie's `GET /billing/status` (src/repository/billing.py `status`).
const _free = {'ai_prompts_per_hour': 10, 'tutor_threads': 10, 'tutor_bytes': 100000, 'media_bytes': 200000,
    'video_bytes': 0, 'media_per_post': 4, 'posts': 50};
const _pro = {'ai_prompts_per_hour': 60, 'tutor_threads': 1000, 'tutor_bytes': 25000000, 'media_bytes': 4000000,
    'video_bytes': 4000000, 'media_per_post': 4, 'posts': 400};
const _contributor = {'ai_prompts_per_hour': null, 'tutor_threads': 1000, 'tutor_bytes': 25000000,
    'media_bytes': 4000000, 'video_bytes': 500000000, 'media_per_post': 4, 'posts': null};

Map<String, dynamic> statusJson({String plan = 'free', bool payments = true, bool test = true}) => {
  'plan': plan,
  'valid_until': plan != 'free' ? '2026-12-24T10:00:00Z' : null,
  'plans': [
    {'id': 'free', 'name': 'Free', 'price': 0, 'currency': 'INR', 'days': null, 'limits': _free},
    {'id': 'pro', 'name': 'Outstagram Pro', 'price': 9900, 'currency': 'INR', 'days': 30, 'limits': _pro},
    {'id': 'contributor', 'name': 'Outstagram Contributor', 'price': 49900, 'currency': 'INR', 'days': 30,
      'limits': _contributor},
  ],
  'posts': 12,
  'limits': {'ai_prompts_per_hour': 10, 'tutor_threads': 10, 'tutor_bytes': 100000, 'media_bytes': 200000},
  'usage': {
    'ai': {'limit': 10, 'used': 10, 'remaining': 0, 'resets_at': null},
    'tutor_threads': 3,
    'tutor_bytes': 1200,
  },
  'payments_enabled': payments,
  'test_mode': test,
  'price': {'amount': 9900, 'currency': 'INR', 'days': 30},
  'pro_limits': _pro,
  'free_limits': _free,
};

class FakeBilling extends BillingApi {
  FakeBilling(this.json) : super(Api(Dio()));

  final Map<String, dynamic> json;

  @override
  Future<BillingStatus> status() async => BillingStatus.fromJson(json);
}

ApiException paywallError() => ApiException.from(
  DioException(
    requestOptions: RequestOptions(path: '/exam-attempts/1/chat'),
    response: Response(
      requestOptions: RequestOptions(path: '/exam-attempts/1/chat'),
      statusCode: 429,
      data: {
        'detail': {'code': 'ai_quota', 'message': "You've used all your AI prompts for this hour.", 'upgrade': true},
      },
    ),
  ),
);

Widget host(Map<String, dynamic> json, void Function(BuildContext) onTap) => ProviderScope(
  overrides: [billingApiProvider.overrideWithValue(FakeBilling(json))],
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (c) => TextButton(onPressed: () => onTap(c), child: const Text('go')),
      ),
    ),
  ),
);

void main() {
  test('BillingStatus parses the server payload', () {
    final s = BillingStatus.fromJson(statusJson(plan: 'pro'));
    expect(s.isPro, isTrue);
    expect(s.validUntil, DateTime.utc(2026, 12, 24, 10).toLocal());
    expect(s.proLimits.aiPromptsPerHour, 60);
    expect(s.freeLimits.mediaBytes, 200000);
    expect(s.paymentsEnabled && s.testMode, isTrue);
    expect(s.price.days, 30);
    expect([for (final p in s.plans) p.short], ['Free', 'Pro', 'Contributor']);
    expect(s.upgrades.map((p) => p.id), ['contributor']);
    final c = s.plans.last.limits;
    expect((c.posts, c.aiPromptsPerHour, c.videoBytes, c.videosAllowed), (null, null, 500000000, true));
    expect(s.freeLimits.videosAllowed, isFalse);
    expect(BillingStatus.fromJson(statusJson(plan: 'contributor')).upgrades, isEmpty);
  });

  test('unlimited AI quota (Contributor) is never out', () {
    final q = Quota.fromJson({'limit': null, 'used': 140, 'remaining': null, 'unlimited': true, 'plan': 'contributor'});
    expect((q.isOut, q.isPro, q.upgradeTo), (false, true, null));
    expect(q.pill, 'Unlimited AI prompts · Contributor');
    final pro = Quota.fromJson({'limit': 60, 'used': 60, 'remaining': 0, 'plan': 'pro'});
    expect((pro.isOut, pro.upgradeTo), (true, 'contributor'));
  });

  test('older servers (free + pro only) still parse', () {
    final j = statusJson()..remove('plans');
    final s = BillingStatus.fromJson(j);
    expect(s.plans.map((p) => p.id), ['free', 'pro']);
    expect(fmtLimit(null), 'Unlimited');
    expect(fmtLimit(4000000, fmtBytes), '4 MB');
  });

  test('price label and byte formatting', () {
    expect(const Price(amount: 9900, currency: 'INR', days: 30).label, '₹99');
    expect(const Price(amount: 9950, currency: 'INR', days: 30).label, '₹99.50');
    expect(fmtBytes(200000), '200 kB');
    expect(fmtBytes(15000000), '15 MB');
  });

  test('order prefill drops empty values', () {
    final o = RazorpayOrder.fromJson({
      'key_id': 'rzp_test_x',
      'order_id': 'order_1',
      'amount': 9900,
      'currency': 'INR',
      'prefill': {'name': 'A', 'email': ''},
    });
    expect(o.prefill, {'name': 'A'});
  });

  testWidgets('a paywall error opens the upgrade sheet instead of a snackbar', (t) async {
    await t.pumpWidget(host(statusJson(), (c) => showError(c, paywallError())));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text("You've used this hour's AI prompts"), findsOneWidget);
    expect(find.text('Get Pro · ₹99'), findsOneWidget);
    expect(find.text('Get Contributor · ₹499'), findsOneWidget);
    expect(find.text('60'), findsOneWidget); // Pro prompts/hour
    expect(find.text('Unlimited'), findsWidgets); // Contributor
    expect(find.textContaining('demo bank page'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await t.ensureVisible(find.text('Maybe later'));
    await t.pumpAndSettle();
    await t.tap(find.text('Maybe later'));
    await t.pumpAndSettle();
    expect(find.byType(PaywallSheet), findsNothing);
  });

  testWidgets('a normal error is still a snackbar', (t) async {
    await t.pumpWidget(host(statusJson(), (c) => showError(c, ApiException('Nope', status: 400))));
    await t.tap(find.text('go'));
    await t.pump();
    expect(find.text('Nope'), findsOneWidget);
    expect(find.byType(PaywallSheet), findsNothing);
  });

  testWidgets('no pay button when the server has no payment keys', (t) async {
    await t.pumpWidget(host(statusJson(payments: false), (c) => showPaywall(c)));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Outstagram plans'), findsOneWidget);
    expect(find.textContaining('Get '), findsNothing);
    expect(find.text("Payments aren't set up on this server yet."), findsOneWidget);
    await t.ensureVisible(find.text('Maybe later'));
    await t.pumpAndSettle();
    await t.tap(find.text('Maybe later'));
    await t.pumpAndSettle(); // releases the one-sheet-at-a-time guard for the next test
  });

  testWidgets('Pro users see their pass and the Contributor upgrade', (t) async {
    await t.pumpWidget(host(statusJson(plan: 'pro'), (c) => showPaywall(c)));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.textContaining("You're on Pro until"), findsOneWidget);
    expect(find.text('Get Contributor · ₹499'), findsOneWidget);
    expect(find.textContaining('Get Pro'), findsNothing);
    await t.ensureVisible(find.text('Maybe later'));
    await t.pumpAndSettle();
    await t.tap(find.text('Maybe later'));
    await t.pumpAndSettle();
  });

  testWidgets('Contributors see the top plan, no offer', (t) async {
    await t.pumpWidget(host(statusJson(plan: 'contributor'), (c) => showPaywall(c)));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.textContaining('the top plan'), findsOneWidget);
    expect(find.textContaining('Get '), findsNothing);
    await t.ensureVisible(find.text('Close'));
    await t.pumpAndSettle();
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
  });
}
