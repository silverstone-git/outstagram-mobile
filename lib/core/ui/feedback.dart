import 'package:flutter/material.dart';

import '../../features/account/verify_gate.dart';
import '../../features/billing/paywall_sheet.dart';
import '../auth/google_auth.dart';
import '../net/api_error.dart';

/// Shows an error as a snackbar; opens the upgrade sheet for paywall errors (402/413/429 with
/// `detail.upgrade`), the confirm-email sheet for 403 email_unverified; silent for a cancelled sign-in.
void showError(BuildContext context, Object error) {
  if (error is SignInCancelled || !context.mounted) return;
  if (showPaywallFor(context, error)) return;
  if (showVerifyEmailFor(context, error)) return;
  final msg = error is ApiException ? error.message : 'Something went wrong. Please try again.';
  debugPrint('error: $error');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
