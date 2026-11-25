import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/api_error.dart';

/// The server refused because the email isn't confirmed (403, detail.code == "email_unverified").
bool isEmailUnverified(Object error) => error is ApiException && error.code == 'email_unverified';

var _open = false;

/// Opens the "confirm your email" sheet for that error. Returns whether it handled [error].
bool showVerifyEmailFor(BuildContext context, Object error) {
  if (!isEmailUnverified(error)) return false;
  showVerifyEmailSheet(context);
  return true;
}

Future<void> showVerifyEmailSheet(BuildContext context) async {
  if (_open || !context.mounted) return;
  _open = true;
  try {
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final cs = Theme.of(c).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.mark_email_unread_rounded, size: 52, color: cs.primary),
                const SizedBox(height: 12),
                const Text(
                  'Confirm your email first',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Posting, profile photos and the AI tutor unlock once you confirm your email. '
                  "It's one 6-digit code and takes under a minute.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm now')),
                const SizedBox(height: 6),
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
              ],
            ),
          ),
        );
      },
    );
    if (go == true && context.mounted) await context.push('/verify-email');
  } finally {
    _open = false;
  }
}
