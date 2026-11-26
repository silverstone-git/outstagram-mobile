import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/feedback.dart';

/// The magic link in the code email (`https://outstagram.aryan.cfd/signin/?h=…`, staging:
/// `https://aryan.cfd/outstagram/signin/?h=…`), opened here through App Links. Uses the link right away:
/// unlike the web page, nothing but the person opens a link in the app.
///   sign-in / confirm email -> signed in, on to the feed
///   forgot password         -> signed in, then "set a new password"
///   change email            -> "your email is now …"
class EmailLinkScreen extends ConsumerStatefulWidget {
  const EmailLinkScreen({super.key, required this.tokenHash});

  final String tokenHash;

  @override
  ConsumerState<EmailLinkScreen> createState() => _EmailLinkScreenState();
}

enum _Step { working, password, changed, failed }

class _EmailLinkScreenState extends ConsumerState<EmailLinkScreen> {
  var _step = _Step.working;
  String? _resetToken;
  String? _changedEmail;
  String _error = '';
  final _password = TextEditingController();
  var _show = false;
  var _busy = false;

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _use();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _use() async {
    if (widget.tokenHash.isEmpty) {
      setState(() {
        _step = _Step.failed;
        _error = 'This sign-in link is incomplete.';
      });
      return;
    }
    try {
      await ref.read(authControllerProvider.future); // the stored session must finish loading first
      final r = await _auth.signInWithEmailLink(widget.tokenHash);
      if (!mounted) return;
      if (r.changedEmail != null) {
        setState(() {
          _step = _Step.changed;
          _changedEmail = r.changedEmail;
        });
      } else if (r.resetToken != null) {
        setState(() {
          _step = _Step.password;
          _resetToken = r.resetToken;
        });
      } else {
        HapticFeedback.mediumImpact();
        context.go('/feed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.failed;
        _error = e is ApiException ? e.message : 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _setPassword() async {
    if (_password.text.length < 8) {
      showError(context, ApiException('Use at least 8 characters for the new password'));
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.resetPasswordWithLink(_resetToken!, _password.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed. Other devices were signed out.')),
      );
      context.go('/feed');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() {
    final signedIn = ref.read(authControllerProvider).value != null;
    context.go(signedIn ? '/feed' : '/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget title(String t) => Text(
      t,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
    );
    Widget body(String t) => Text(t, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant));

    final children = switch (_step) {
      _Step.working => [
        const SizedBox(height: 80),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 20),
        body('Signing you in…'),
      ],
      _Step.password => [
        Icon(Icons.lock_reset_rounded, size: 56, color: cs.primary),
        const SizedBox(height: 16),
        title('Set a new password'),
        const SizedBox(height: 8),
        body("You're signed in. Choose a new password to finish."),
        const SizedBox(height: 28),
        AutofillGroup(
          child: TextField(
            controller: _password,
            enabled: !_busy,
            autofocus: true,
            obscureText: !_show,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _setPassword(),
            decoration: InputDecoration(
              hintText: 'New password (8+ characters)',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _setPassword,
          child: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              : const Text('Set new password'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : () => context.go('/feed'), child: const Text('Not now')),
      ],
      _Step.changed => [
        Icon(Icons.mark_email_read_rounded, size: 56, color: cs.primary),
        const SizedBox(height: 16),
        title('Email changed'),
        const SizedBox(height: 8),
        body("Your account's email is now $_changedEmail."),
        const SizedBox(height: 28),
        FilledButton(onPressed: _leave, child: const Text('Continue')),
      ],
      _Step.failed => [
        Icon(Icons.link_off_rounded, size: 56, color: cs.error),
        const SizedBox(height: 16),
        title("This link didn't work"),
        const SizedBox(height: 8),
        body(_error),
        const SizedBox(height: 8),
        body("If the email also has a code you haven't used, you can type it in. Otherwise ask for a new email."),
        const SizedBox(height: 28),
        FilledButton(onPressed: _leave, child: const Text('OK')),
      ],
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Email sign-in')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: children),
      ),
    );
  }
}
