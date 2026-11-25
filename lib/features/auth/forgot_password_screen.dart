import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/code_field.dart';
import '../../core/ui/feedback.dart';
import 'email_code_screen.dart';

/// Forgot password (signed out, `/forgot-password`) and change password (signed in,
/// `/account/password`): email → code + new password. Either way this device ends up signed in
/// with the new password and every other device is signed out.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.email, this.signedIn = false});

  final String? email;
  final bool signedIn;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  var _sent = false;
  var _busy = false;
  var _show = false;
  int _length = 6;

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    ref.read(authRepositoryProvider).emailCodeLength().then((n) {
      if (mounted) setState(() => _length = n);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!emailRegex.hasMatch(_email.text.trim())) {
      showError(context, ApiException('Enter the email address of your account'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _auth.sendPasswordResetCode(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_code.text.length != _length) {
      showError(context, ApiException('Enter the $_length-digit code from the email'));
      return;
    }
    if (_password.text.length < 8) {
      showError(context, ApiException('Use at least 8 characters for the new password'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _auth.resetPassword(_email.text, _code.text, _password.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password changed. Other devices were signed out.')));
      if (widget.signedIn && context.canPop()) context.pop(); // signed out: the router moves on by itself
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.signedIn ? 'Change password' : 'Reset password')),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Icon(Icons.lock_reset_rounded, size: 56, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                _sent ? 'Enter the code and a new password' : 'We\'ll email you a code',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _sent
                    ? 'If ${_email.text.trim()} belongs to an account, a $_length-digit code is on its way.'
                    : 'Use the email address of your Outstagram account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              if (!_sent) ...[
                TextField(
                  controller: _email,
                  enabled: !_busy && !widget.signedIn,
                  autofocus: widget.email == null,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: _busy
                      ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                      : const Text('Send code'),
                ),
              ] else ...[
                CodeField(length: _length, controller: _code, enabled: !_busy, onCompleted: (_) => setState(() {})),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: !_show,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _reset(),
                  decoration: InputDecoration(
                    hintText: 'New password (8+ characters)',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _reset,
                  child: _busy
                      ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                      : const Text('Set new password'),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (!widget.signedIn)
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _sent = false),
                        child: const Text('Wrong email?'),
                      )
                    else
                      const SizedBox.shrink(),
                    ResendButton(
                      onResend: () async {
                        try {
                          await _auth.sendPasswordResetCode(_email.text);
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                          rethrow;
                        }
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
