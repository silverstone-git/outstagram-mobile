import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/net/api_error.dart';
import 'billing_api.dart';

/// Opens Razorpay's native Checkout for [order]. Resolves with the signed result, or null when the
/// user backs out. Throws [ApiException] when the payment fails.
///
/// Razorpay **test mode** only, in sideloaded builds: a Play build must use Google Play Billing
/// (see `docs/TODO.md` §8), which is why the paywall hides the button when [Env.razorpayAllowed] is false.
Future<RazorpayResult?> openRazorpay(RazorpayOrder order, {required String themeColor, String? reason}) {
  final rzp = Razorpay();
  final done = Completer<RazorpayResult?>();

  rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
    if (done.isCompleted) return;
    final (oid, pid, sig) = (r.orderId, r.paymentId, r.signature);
    if (pid == null || sig == null) {
      done.completeError(ApiException('Razorpay returned an incomplete payment. If you were charged, it will be refunded.'));
    } else {
      done.complete(RazorpayResult(orderId: oid ?? order.orderId, paymentId: pid, signature: sig));
    }
  });
  rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
    if (done.isCompleted) return;
    if (r.code == Razorpay.PAYMENT_CANCELLED) {
      done.complete(null);
    } else {
      done.completeError(ApiException(_failure(r)));
    }
  });
  rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
    if (done.isCompleted) return;
    done.completeError(ApiException("${r.walletName ?? 'That wallet'} isn't supported here. Pick UPI or a card."));
  });

  rzp.open({
    'key': order.keyId,
    'amount': order.amount,
    'currency': order.currency,
    'order_id': order.orderId,
    'name': order.name,
    'description': order.description,
    'prefill': order.prefill,
    'notes': {'reason': ?reason},
    'theme': {'color': themeColor},
    'retry': {'enabled': true, 'max_count': 2},
  });

  return done.future.whenComplete(rzp.clear);
}

String _failure(PaymentFailureResponse r) {
  final msg = r.message;
  if (r.code == Razorpay.NETWORK_ERROR) return 'No connection. Check your internet and try again.';
  if (msg == null || msg.isEmpty || msg.startsWith('{')) return 'The payment failed. You were not charged.';
  return msg;
}
