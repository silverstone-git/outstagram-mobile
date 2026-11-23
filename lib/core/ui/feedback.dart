import 'package:flutter/material.dart';

import '../auth/google_auth.dart';
import '../net/api_error.dart';

/// Shows an error as a snackbar; silent for a cancelled sign-in.
void showError(BuildContext context, Object error) {
  if (error is SignInCancelled || !context.mounted) return;
  final msg = error is ApiException ? error.message : 'Something went wrong. Please try again.';
  debugPrint('error: $error');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
