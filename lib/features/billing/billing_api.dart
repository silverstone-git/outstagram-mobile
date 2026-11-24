import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_client.dart';

/// Free/Pro limits (`lib/plans.py` on the server).
class Limits {
  const Limits({required this.aiPromptsPerHour, required this.tutorThreads, required this.tutorBytes, required this.mediaBytes});

  factory Limits.fromJson(Map<String, dynamic> j) => Limits(
    aiPromptsPerHour: (j['ai_prompts_per_hour'] as num).toInt(),
    tutorThreads: (j['tutor_threads'] as num).toInt(),
    tutorBytes: (j['tutor_bytes'] as num).toInt(),
    mediaBytes: (j['media_bytes'] as num).toInt(),
  );

  static const free = Limits(aiPromptsPerHour: 10, tutorThreads: 10, tutorBytes: 100000, mediaBytes: 200000);

  final int aiPromptsPerHour;
  final int tutorThreads;
  final int tutorBytes;
  final int mediaBytes;
}

/// Price of the Pro pass; [amount] is in the currency's minor unit (paise).
class Price {
  const Price({required this.amount, required this.currency, required this.days});

  factory Price.fromJson(Map<String, dynamic> j) => Price(
    amount: (j['amount'] as num).toInt(),
    currency: j['currency'] as String? ?? 'INR',
    days: (j['days'] as num?)?.toInt() ?? 30,
  );

  final int amount;
  final String currency;
  final int days;

  /// "₹99" (no decimals unless the price has paise).
  String get label {
    final major = amount / 100;
    return NumberFormat.simpleCurrency(
      locale: 'en_IN',
      name: currency,
      decimalDigits: amount % 100 == 0 ? 0 : 2,
    ).format(major);
  }
}

/// `GET /billing/status`.
class BillingStatus {
  const BillingStatus({
    required this.plan,
    required this.validUntil,
    required this.limits,
    required this.freeLimits,
    required this.proLimits,
    required this.paymentsEnabled,
    required this.testMode,
    required this.price,
  });

  factory BillingStatus.fromJson(Map<String, dynamic> j) {
    Limits l(String k) => Limits.fromJson(Map<String, dynamic>.from(j[k] as Map));
    final until = j['valid_until'] as String?;
    return BillingStatus(
      plan: j['plan'] as String? ?? 'free',
      validUntil: until == null ? null : DateTime.tryParse(until)?.toLocal(),
      limits: l('limits'),
      freeLimits: l('free_limits'),
      proLimits: l('pro_limits'),
      paymentsEnabled: j['payments_enabled'] == true,
      testMode: j['test_mode'] == true,
      price: Price.fromJson(Map<String, dynamic>.from(j['price'] as Map)),
    );
  }

  final String plan;
  final DateTime? validUntil;
  final Limits limits;
  final Limits freeLimits;
  final Limits proLimits;
  final bool paymentsEnabled;
  final bool testMode;
  final Price price;

  bool get isPro => plan == 'pro';
}

/// `POST /billing/razorpay/order`: everything Razorpay Checkout needs. The amount is fixed server-side.
class RazorpayOrder {
  const RazorpayOrder({
    required this.keyId,
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.name,
    required this.description,
    required this.prefill,
  });

  factory RazorpayOrder.fromJson(Map<String, dynamic> j) => RazorpayOrder(
    keyId: j['key_id'] as String,
    orderId: j['order_id'] as String,
    amount: (j['amount'] as num).toInt(),
    currency: j['currency'] as String,
    name: j['name'] as String? ?? 'Outstagram Pro',
    description: j['description'] as String? ?? '',
    prefill: {
      for (final e in Map<String, dynamic>.from(j['prefill'] as Map? ?? const {}).entries)
        if (e.value is String && (e.value as String).isNotEmpty) e.key: e.value as String,
    },
  );

  final String keyId;
  final String orderId;
  final int amount;
  final String currency;
  final String name;
  final String description;
  final Map<String, String> prefill;
}

/// What Checkout hands back on success; the server checks the signature before granting Pro.
class RazorpayResult {
  const RazorpayResult({required this.orderId, required this.paymentId, required this.signature});

  final String orderId;
  final String paymentId;
  final String signature;

  Map<String, String> toJson() => {
    'razorpay_order_id': orderId,
    'razorpay_payment_id': paymentId,
    'razorpay_signature': signature,
  };
}

class BillingApi {
  BillingApi(this._api);

  final Api _api;

  Future<BillingStatus> status() async =>
      BillingStatus.fromJson(Map<String, dynamic>.from(await _api.get<Map<dynamic, dynamic>>('/billing/status')));

  Future<RazorpayOrder> order(String reason) async => RazorpayOrder.fromJson(
    Map<String, dynamic>.from(await _api.post<Map<dynamic, dynamic>>('/billing/razorpay/order', data: {'reason': reason})),
  );

  /// Returns the plan after verification ("pro" on success).
  Future<String> verify(RazorpayResult r) async {
    final res = await _api.post<Map<dynamic, dynamic>>('/billing/razorpay/verify', data: r.toJson());
    return res['plan'] as String? ?? 'free';
  }
}

final billingApiProvider = Provider<BillingApi>((ref) => BillingApi(ref.watch(apiProvider)));

/// The signed-in user's plan, limits and the Pro price. Invalidate after a purchase.
final billingStatusProvider = FutureProvider<BillingStatus>((ref) {
  ref.watch(authControllerProvider.select((s) => s.value?.user.userId)); // refetch for another account
  return ref.watch(billingApiProvider).status();
});

/// "200 kB", "15 MB".
String fmtBytes(int b) => b >= 1000000 ? '${(b / 1000000).round()} MB' : '${(b / 1000).round()} kB';
