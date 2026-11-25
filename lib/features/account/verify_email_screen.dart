import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/code_field.dart';
import '../../core/ui/feedback.dart';
import 'account_api.dart';

/// Confirm the account's email with a code. Right after registering (`onboarding`) it offers
/// "Do it later": the app still works, but posting, profile photos and the AI tutor stay locked and the
/// profile shows a warning until the email is confirmed.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.onboarding = false});

  final bool onboarding;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();
  var _sending = false;
  var _sent = false;
  var _busy = false;
  var _wrong = false;
  var _done = false;
  int _length = 6;

  AccountApi get _api => ref.read(accountApiProvider);

  @override
  void initState() {
    super.initState();
    ref.read(authRepositoryProvider).emailCodeLength().then((n) {
      if (mounted) setState(() => _length = n);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final me = await ref.read(meProvider.future).catchError((_) => null);
      if (me == null || me.emailVerified) return;
      try {
        await _send();
      } catch (_) {
        // shown already; "Resend" stays available
        if (mounted) setState(() => _sent = true);
      }
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await _api.sendVerifyCode();
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
      rethrow;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    try {
      await _api.verify(code);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() => _done = true);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) _leave();
    } catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _wrong = true);
      showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/feed');
    }
  }

  void _later() {
    _leave();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('You can confirm your email any time from your profile.')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = ref.watch(meProvider);
    final email = me.value?.email ?? '';
    final verified = _done || (me.value?.emailVerified ?? false);
    return PopScope(
      canPop: !widget.onboarding || verified,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _later();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.onboarding,
          title: Text(widget.onboarding ? 'One last step' : 'Confirm your email'),
          actions: [
            if (widget.onboarding && !verified) TextButton(onPressed: _later, child: const Text('Do it later')),
          ],
        ),
        body: SafeArea(
          child: me.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(ApiException.from(e).message)),
            data: (_) => verified ? _success(cs) : _form(cs, email),
          ),
        ),
      ),
    );
  }

  Widget _success(ColorScheme cs) => Center(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, t, child) => Transform.scale(scale: t, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 96, color: cs.primary),
          const SizedBox(height: 16),
          const Text('Email confirmed', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Posting and the AI tutor are unlocked.', style: TextStyle(color: cs.onSurfaceVariant)),
          if (!_done) ...[const SizedBox(height: 24), FilledButton(onPressed: _leave, child: const Text('Done'))],
        ],
      ),
    ),
  );

  Widget _form(ColorScheme cs, String email) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    children: [
      Icon(Icons.mark_email_unread_rounded, size: 56, color: cs.primary),
      const SizedBox(height: 16),
      const Text(
        'Confirm your email',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        _sending && !_sent ? 'Sending a code to $email…' : 'Enter the $_length-digit code we sent to $email.',
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 24),
      CodeField(length: _length, controller: _code, enabled: !_busy, error: _wrong, onCompleted: _verify),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _busy ? null : () => context.push('/account/email'),
            child: const Text('Wrong email? Change it'),
          ),
          if (_sent) ResendButton(onResend: _send) else const SizedBox.shrink(),
        ],
      ),
      const SizedBox(height: 20),
      _Unlocks(cs: cs),
    ],
  );
}

class _Unlocks extends StatelessWidget {
  const _Unlocks({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData i, String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(i, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(t)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Confirming unlocks', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            row(Icons.add_photo_alternate_outlined, 'Posting photos and updates'),
            row(Icons.face_retouching_natural_rounded, 'Changing your profile photo'),
            row(Icons.auto_awesome_rounded, 'The free AI tutor'),
            row(Icons.lock_reset_rounded, 'Resetting your password if you forget it'),
          ],
        ),
      ),
    );
  }
}
