import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/ui/feedback.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _fullname = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _bio = TextEditingController();
  DateTime? _dob;
  var _busy = false;

  @override
  void dispose() {
    for (final c in [_fullname, _username, _email, _password, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 18),
      firstDate: DateTime(1920),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return; // includes the date-of-birth field
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            fullname: _fullname.text,
            username: _username.text,
            email: _email.text,
            password: _password.text,
            dateOfBirth: _dob!,
            bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
          );
      HapticFeedback.mediumImpact(); // the router moves to the feed
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
            TextFormField(
              controller: _fullname,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
            ),
            gap,
            TextFormField(
              controller: _username,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newUsername],
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]'))],
              decoration: const InputDecoration(labelText: 'Username', prefixText: '@'),
              validator: (v) => (v == null || v.trim().length < 3) ? 'At least 3 characters' : null,
            ),
            gap,
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v == null || !RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim())) ? 'Enter a valid email' : null,
            ),
            gap,
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
            ),
            gap,
            FormField<DateTime>(
              validator: (_) => _dob == null ? 'Pick your date of birth' : null,
              builder: (field) => InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _busy
                    ? null
                    : () async {
                        await _pickDob();
                        field.didChange(_dob);
                      },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date of birth',
                    errorText: field.errorText,
                    suffixIcon: const Icon(Icons.cake_outlined),
                  ),
                  child: Text(_dob == null ? '' : DateFormat.yMMMd().format(_dob!)),
                ),
              ),
            ),
            gap,
            TextFormField(
              controller: _bio,
              enabled: !_busy,
              maxLines: 3,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Bio (optional)', alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.onPrimary))
                  : const Text('Create account'),
            ),
          ]),
        ),
      ),
    );
  }
}
