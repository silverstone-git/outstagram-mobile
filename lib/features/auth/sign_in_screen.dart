import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/google_auth.dart';
import '../../core/config/env.dart';
import '../../core/ui/feedback.dart';
import 'brand_mark.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _Busy { none, google, password }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  var _busy = _Busy.none;
  var _showPassword = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(_Busy kind, Future<void> Function() action) async {
    if (_busy != _Busy.none) return;
    setState(() => _busy = kind);
    try {
      await action();
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  void _google() => _run(_Busy.google, () => ref.read(authControllerProvider.notifier).signInWithGoogle());

  void _googleBrowser() =>
      _run(_Busy.google, () => ref.read(authControllerProvider.notifier).signInWithGoogleInBrowser());

  void _passwordSignIn() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _run(_Busy.password,
        () => ref.read(authControllerProvider.notifier).signInWithPassword(_username.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final busy = _busy != _Busy.none;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: BrandMark(size: 44)),
                  const SizedBox(height: 10),
                  Text(
                    'Study together. Grow together.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                  ),
                  if (Env.isStaging) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Chip(
                        label: const Text('staging'),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: cs.tertiary),
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                  if (GoogleAuth.configured) ...[
                    FilledButton.icon(
                      onPressed: busy ? null : _google,
                      onLongPress: busy ? null : _googleBrowser, // escape hatch if the sheet misbehaves
                      icon: _busy == _Busy.google
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : const _GoogleG(),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 24),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or with your username', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 24),
                  ],
                  TextFormField(
                    controller: _username,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Username', prefixIcon: Icon(Icons.alternate_email)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    enabled: !busy,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _passwordSignIn(),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'Hide password' : 'Show password',
                        icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: busy ? null : _passwordSignIn,
                    child: _busy == _Busy.password
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 28),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('New here?', style: TextStyle(color: cs.onSurfaceVariant)),
                    TextButton(onPressed: busy ? null : () => context.push('/register'), child: const Text('Create an account')),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: const Text('G', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 14)),
      );
}
