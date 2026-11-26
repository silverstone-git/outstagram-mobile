import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_client.dart';
import '../../core/ui/feedback.dart';

/// "Your data" on `/account`: download everything as JSON (`GET /me/export`, shared as a file) or delete
/// the account and everything in it (`POST /me/delete`, then sign out). Google Play requires the latter.
class YourDataCard extends ConsumerStatefulWidget {
  const YourDataCard({super.key, required this.username});

  final String username;

  @override
  ConsumerState<YourDataCard> createState() => _YourDataCardState();
}

class _YourDataCardState extends ConsumerState<YourDataCard> {
  var _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final data = await ref.read(apiProvider).get<dynamic>('/me/export');
      final dir = await getTemporaryDirectory();
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/outstagram-${widget.username}-$day.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'My Outstagram data',
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _DeleteDialog(username: widget.username));
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiProvider).post<dynamic>('/me/delete', data: {'confirm_username': widget.username});
      HapticFeedback.heavyImpact();
      messenger.showSnackBar(const SnackBar(content: Text('Your account and all its data were deleted')));
      await ref.read(authControllerProvider.notifier).signOut(); // the router goes to sign-in
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          leading: _exporting
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_rounded),
          title: const Text('Download my data'),
          subtitle: const Text('Everything Outstagram stores about you, as a JSON file'),
          onTap: _exporting ? null : _export,
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.delete_forever_rounded, color: cs.error),
          title: Text('Delete my account', style: TextStyle(color: cs.error)),
          subtitle: const Text('Permanently, with all your posts, chats and exam history'),
          onTap: _delete,
        ),
      ]),
    );
  }
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.username});

  final String username;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = _c.text.trim().replaceFirst('@', '') == widget.username;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'This permanently deletes your profile and everything you made: posts with their photos and videos, '
            'comments, likes, follows, exam history, tutor chats, saved equations, plan and streak. '
            "It can't be undone. Download your data first if you want a copy.",
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Type ${widget.username} to confirm'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          style: TextButton.styleFrom(foregroundColor: cs.error),
          child: const Text('Delete forever'),
        ),
      ],
    );
  }
}
