import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_client.dart';

/// Plan limits (`lib/plans.py` on the server). null = unlimited; [videoBytes] 0 = no videos.
class Limits {
  const Limits({
    required this.aiPromptsPerHour,
    required this.tutorThreads,
    required this.tutorBytes,
    required this.mediaBytes,
    this.videoBytes = 0,
    this.mediaPerPost = 4,
    this.posts,
  });

  factory Limits.fromJson(Map<String, dynamic> j) {
    int? n(String k, int? fallback) => j.containsKey(k) ? (j[k] as num?)?.toInt() : fallback;
    return Limits(
      aiPromptsPerHour: n('ai_prompts_per_hour', 10),
      tutorThreads: n('tutor_threads', 10),
      tutorBytes: n('tutor_bytes', 100000),
      mediaBytes: n('media_bytes', 200000) ?? 200000,
      videoBytes: n('video_bytes', 0),
      mediaPerPost: n('media_per_post', 4),
      posts: n('posts', null),
    );
  }

  static const free = Limits(aiPromptsPerHour: 10, tutorThreads: 10, tutorBytes: 100000, mediaBytes: 200000, posts: 50);

  final int? aiPromptsPerHour;
  final int? tutorThreads;
  final int? tutorBytes;
  final int mediaBytes;
  final int? videoBytes;
  final int? mediaPerPost;
  final int? posts;

  bool get videosAllowed => videoBytes != 0;
}

/// A pass price; [amount] is in the currency's minor unit (paise).
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

/// One plan of `GET /billing/status` → `plans` (free, pro, contributor).
class PlanInfo {
  const PlanInfo({required this.id, required this.name, required this.price, required this.limits});

  factory PlanInfo.fromJson(Map<String, dynamic> j) => PlanInfo(
    id: '${j['id']}',
    name: '${j['name'] ?? j['id']}',
    price: Price(
      amount: (j['price'] as num?)?.toInt() ?? 0,
      currency: j['currency'] as String? ?? 'INR',
      days: (j['days'] as num?)?.toInt() ?? 30,
    ),
    limits: Limits.fromJson(Map<String, dynamic>.from(j['limits'] as Map)),
  );

  final String id;
  final String name;
  final Price price;
  final Limits limits;

  /// "Pro", "Contributor".
  String get short => id == 'free' ? 'Free' : name.split(' ').last;
}

const planRank = {'free': 0, 'pro': 1, 'contributor': 2};

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
    this.plans = const [],
    this.posts,
  });

  factory BillingStatus.fromJson(Map<String, dynamic> j) {
    Limits l(String k) => Limits.fromJson(Map<String, dynamic>.from(j[k] as Map));
    final until = j['valid_until'] as String?;
    final price = Price.fromJson(Map<String, dynamic>.from(j['price'] as Map));
    final free = l('free_limits'), pro = l('pro_limits');
    return BillingStatus(
      plan: j['plan'] as String? ?? 'free',
      validUntil: until == null ? null : DateTime.tryParse(until)?.toLocal(),
      limits: l('limits'),
      freeLimits: free,
      proLimits: pro,
      paymentsEnabled: j['payments_enabled'] == true,
      testMode: j['test_mode'] == true,
      price: price,
      plans: j['plans'] is List
          ? [for (final p in j['plans'] as List) PlanInfo.fromJson(Map<String, dynamic>.from(p as Map))]
          : [ // older server: free + pro only
              PlanInfo(id: 'free', name: 'Free', price: Price(amount: 0, currency: price.currency, days: 0), limits: free),
              PlanInfo(id: 'pro', name: 'Outstagram Pro', price: price, limits: pro),
            ],
      posts: (j['posts'] as num?)?.toInt(),
    );
  }

  final String plan;
  final DateTime? validUntil;
  final Limits limits;
  final Limits freeLimits;
  final Limits proLimits;
  final bool paymentsEnabled;
  final bool testMode;
  final Price price; // Pro's (older field)
  final List<PlanInfo> plans;
  final int? posts; // how many posts the user has

  /// Any paid pass (Pro or Contributor).
  bool get isPro => plan != 'free';
  bool get isContributor => plan == 'contributor';
  PlanInfo? get current => plans.where((p) => p.id == plan).firstOrNull;

  /// Plans above the current one, cheapest first.
  List<PlanInfo> get upgrades =>
      plans.where((p) => (planRank[p.id] ?? 0) > (planRank[plan] ?? 0)).toList();
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

  /// [plan]: `pro` or `contributor`.
  Future<RazorpayOrder> order(String reason, {String plan = 'pro'}) async => RazorpayOrder.fromJson(
    Map<String, dynamic>.from(
      await _api.post<Map<dynamic, dynamic>>('/billing/razorpay/order', data: {'reason': reason, 'plan': plan}),
    ),
  );

  /// Returns the plan after verification ("pro" / "contributor" on success).
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

/// "200 kB", "4 MB".
String fmtBytes(int b) => b >= 1000000 ? '${(b / 1000000).round()} MB' : '${(b / 1000).round()} kB';

/// A limit for display: "Unlimited" for null, else [fmt] of it.
String fmtLimit(int? v, [String Function(int)? fmt]) => v == null ? 'Unlimited' : (fmt ?? (n) => '$n')(v);
