import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/net/api_client.dart';
import 'package:outstagram/core/net/api_error.dart';
import 'package:outstagram/core/ui/feedback.dart';
import 'package:outstagram/features/billing/billing_api.dart';
import 'package:outstagram/features/billing/paywall_sheet.dart';

/// Shape of outsie's `GET /billing/status` (src/repository/billing.py `status`).
Map<String, dynamic> statusJson({String plan = 'free', bool payments = true, bool test = true}) => {
  'plan': plan,
  'valid_until': plan == 'pro' ? '2026-12-24T10:00:00Z' : null,
  'limits': {'ai_prompts_per_hour': 10, 'tutor_threads': 10, 'tutor_bytes': 100000, 'media_bytes': 200000},
  'usage': {
    'ai': {'limit': 10, 'used': 10, 'remaining': 0, 'resets_at': null},
    'tutor_threads': 3,
    'tutor_bytes': 1200,
  },
  'payments_enabled': payments,
  'test_mode': test,
  'price': {'amount': 9900, 'currency': 'INR', 'days': 30},
  'pro_limits': {'ai_prompts_per_hour': 60, 'tutor_threads': 1000, 'tutor_bytes': 25000000, 'media_bytes': 15000000},
  'free_limits': {'ai_prompts_per_hour': 10, 'tutor_threads': 10, 'tutor_bytes': 100000, 'media_bytes': 200000},
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
    expect(find.text('Pay ₹99 with Razorpay'), findsOneWidget);
    expect(find.text('60'), findsOneWidget); // Pro prompts/hour
    expect(find.textContaining('success@razorpay'), findsOneWidget);
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
    expect(find.text('Outstagram Pro'), findsOneWidget);
    expect(find.textContaining('Pay '), findsNothing);
    expect(find.text("Payments aren't set up on this server yet."), findsOneWidget);
    await t.ensureVisible(find.text('Maybe later'));
    await t.pumpAndSettle();
    await t.tap(find.text('Maybe later'));
    await t.pumpAndSettle(); // releases the one-sheet-at-a-time guard for the next test
  });

  testWidgets('Pro users see their pass instead of the offer', (t) async {
    await t.pumpWidget(host(statusJson(plan: 'pro'), (c) => showPaywall(c)));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.textContaining("You're on Pro until"), findsOneWidget);
    expect(find.textContaining('Pay '), findsNothing);
  });
}
