import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/code_field.dart';
import '../../core/ui/feedback.dart';
import '../auth/email_code_screen.dart';
import 'account_api.dart';
import 'your_data.dart';

/// `/account`: email (confirmed or not), change email, change password, download / delete my data.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(ApiException.from(e).message)),
        data: (m) => m == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: () => ref.refresh(meProvider.future),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (m.needsVerification) ...[const VerifyEmailBanner(), const SizedBox(height: 16)],
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.mail_outline_rounded),
                            title: Text(m.email),
                            subtitle: Text(
                              m.emailVerified ? 'Confirmed' : 'Not confirmed yet',
                              style: TextStyle(color: m.emailVerified ? cs.primary : cs.error),
                            ),
                            trailing: Icon(
                              m.emailVerified ? Icons.verified_rounded : Icons.error_outline_rounded,
                              color: m.emailVerified ? cs.primary : cs.error,
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.edit_outlined),
                            title: const Text('Change email'),
                            subtitle: const Text('We confirm the new address with a code'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => context.push('/account/email'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.password_rounded),
                            title: const Text('Change password'),
                            subtitle: const Text('With a code sent to your email'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => context.push('/account/password?email=${Uri.encodeQueryComponent(m.email)}'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Signed in as @${m.username}. You can sign in with your username or email and password, '
                        'Google (same email), or a code sent to your email.',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 20),
                    YourDataCard(username: m.username),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Amber card: "Confirm your email to post…". Used on the profile, account screen and composer.
class VerifyEmailBanner extends ConsumerWidget {
  const VerifyEmailBanner({super.key, this.reason = 'post, change your profile photo and use the AI tutor'});

  final String reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/verify-email'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.mark_email_unread_outlined, color: cs.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Confirm your email', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('You need it to $reason.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                onPressed: () => context.push('/verify-email'),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `/account/email`: new address → code → it replaces the old one (and counts as confirmed).
class ChangeEmailScreen extends ConsumerStatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  ConsumerState<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends ConsumerState<ChangeEmailScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  var _sent = false;
  var _busy = false;
  var _wrong = false;
  int _length = 6;

  AccountApi get _api => ref.read(accountApiProvider);

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
    if (!emailRegex.hasMatch(_email.text.trim())) {
      showError(context, ApiException('Enter a valid email address'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _api.sendChangeCode(_email.text);
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
      final me = await _api.changeEmail(_email.text, code);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Your email is now ${me.email}')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _wrong = true);
      showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = ref.watch(meProvider).value?.email;
    return Scaffold(
      appBar: AppBar(title: const Text('Change email')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            if (current != null)
              Text(
                'Current: $current',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            const SizedBox(height: 20),
            if (!_sent) ...[
              TextField(
                controller: _email,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'New email address',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : const Text('Send code to the new address'),
              ),
            ] else ...[
              Text('Enter the $_length-digit code we sent to ${_email.text.trim()}.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              CodeField(length: _length, controller: _code, enabled: !_busy, error: _wrong, onCompleted: _verify),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _sent = false),
                    child: const Text('Use another email'),
                  ),
                  ResendButton(
                    onResend: () async {
                      try {
                        await _api.sendChangeCode(_email.text);
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
    );
  }
}
