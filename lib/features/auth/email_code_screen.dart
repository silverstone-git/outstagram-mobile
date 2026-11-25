import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/code_field.dart';
import '../../core/ui/feedback.dart';

final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// "Continue with email": address → 6-digit code → signed in. A new address gets an account
/// (confirmed already, since the code proves the email). The router leaves this screen on sign-in.
class EmailCodeScreen extends ConsumerStatefulWidget {
  const EmailCodeScreen({super.key});

  @override
  ConsumerState<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends ConsumerState<EmailCodeScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  var _sent = false;
  var _busy = false;
  var _wrong = false;
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
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!emailRegex.hasMatch(email)) {
      showError(context, ApiException('Enter a valid email address'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _auth.sendEmailCode(email);
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    try {
      await _auth.signInWithEmailCode(_email.text, code);
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _wrong = true);
      HapticFeedback.heavyImpact();
      showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Continue with email')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Icon(_sent ? Icons.mark_email_unread_rounded : Icons.alternate_email_rounded, size: 56, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              _sent ? 'Check your inbox' : 'No password needed',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _sent
                  ? 'We sent a $_length-digit code to ${_email.text.trim()}. It expires in a few minutes.'
                  : "We'll email you a $_length-digit code. New here? The code creates your account.",
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            if (!_sent) ...[
              TextField(
                controller: _email,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
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
              CodeField(length: _length, controller: _code, enabled: !_busy, error: _wrong, onCompleted: _verify),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _sent = false),
                    child: const Text('Wrong email?'),
                  ),
                  ResendButton(
                    onResend: () async {
                      try {
                        await _auth.sendEmailCode(_email.text);
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                        rethrow;
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Can't find it? Check spam or promotions.",
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
