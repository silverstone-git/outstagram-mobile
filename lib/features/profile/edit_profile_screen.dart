import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/feedback.dart';
import '../account/account_api.dart';
import '../feed/models.dart';
import '../feed/social_api.dart';
import 'profile_view.dart' show profileProvider;

/// Same limits as the server (`social.FULLNAME_MAX`, `social.BIO_MAX`).
const fullnameMax = 60;
const bioMax = 160;

/// `/profile/edit`: your name and bio (`PUT /me`). The photo is changed by tapping it on the profile.
class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(authControllerProvider).value?.user.username;
    if (username == null) return const SizedBox.shrink();
    final profile = ref.watch(profileProvider(username));
    return profile.when(
      loading: () => Scaffold(appBar: AppBar(title: const Text('Edit profile')), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: Center(child: Text(ApiException.from(e).message)),
      ),
      data: (p) => EditProfileForm(profile: p),
    );
  }
}

class EditProfileForm extends ConsumerStatefulWidget {
  const EditProfileForm({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<EditProfileForm> {
  late final _name = TextEditingController(text: widget.profile.fullname);
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  final _form = GlobalKey<FormState>();
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _changed =>
      _name.text.trim() != widget.profile.fullname || _bio.text.trim() != (widget.profile.bio ?? '').trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_changed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(socialApiProvider).updateProfile(fullname: _name.text.trim(), bio: _bio.text.trim());
      HapticFeedback.mediumImpact();
      ref.invalidate(profileProvider(widget.profile.username));
      ref.invalidate(meProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              maxLength: fullnameMax,
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').trim().isEmpty ? "Your name can't be empty" : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bio,
              decoration: const InputDecoration(labelText: 'Bio', hintText: 'What are you studying?', alignLabelWithHint: true),
              textCapitalization: TextCapitalization.sentences,
              minLines: 3,
              maxLines: 5,
              maxLength: bioMax,
            ),
            const SizedBox(height: 8),
            Text(
              'Your username (@${widget.profile.username}) stays the same. Tap your photo on the profile to change it.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
