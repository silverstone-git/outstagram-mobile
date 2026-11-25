import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/feedback.dart';
import '../billing/billing_api.dart' show fmtBytes;
import 'engine/engine.dart';
import 'exam_api.dart';
import 'offline_packs.dart';

/// `/exams/offline`: save subjects for offline practice. Quick practice, pop quizzes and mocks fall back
/// to saved packs when there's no connection; attempts upload later.
class OfflinePacksScreen extends ConsumerStatefulWidget {
  const OfflinePacksScreen({super.key});

  @override
  ConsumerState<OfflinePacksScreen> createState() => _OfflinePacksScreenState();
}

class _OfflinePacksScreenState extends ConsumerState<OfflinePacksScreen> {
  final _progress = <String, double>{}; // subject -> 0..1 while downloading

  Future<void> _download(String subject) async {
    setState(() => _progress[subject] = 0);
    try {
      await OfflinePacks.instance.download(
        ref.read(examApiProvider),
        subject,
        onProgress: (p) => mounted ? setState(() => _progress[subject] = p) : null,
      );
      HapticFeedback.mediumImpact();
      ref.invalidate(offlinePacksProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _progress.remove(subject));
    }
  }

  Future<void> _remove(String subject) async {
    await OfflinePacks.instance.remove(subject);
    ref.invalidate(offlinePacksProvider);
  }

  Future<void> _downloadAll(Set<String> have) async {
    for (final s in subjectGroups.keys.where((s) => !have.contains(s))) {
      if (!mounted) return;
      await _download(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final packs = ref.watch(offlinePacksProvider);
    final saved = {for (final p in packs.value ?? const <PackInfo>[]) p.subject: p};
    final pending = ref.watch(_pendingCountProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline packs'),
        actions: [
          if (saved.length < subjectGroups.length)
            TextButton(
              onPressed: _progress.isNotEmpty ? null : () => _downloadAll(saved.keys.toSet()),
              child: const Text('Save all'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Save a subject to practise without a connection: quick practice, pop quizzes and mocks use saved '
            'questions when you\'re offline ($packQuestionsPerTopic per topic). Attempts made offline upload '
            'when you\'re back and still count for that day\'s streak. Question images need a connection.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          if (pending > 0) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_queue_rounded),
                title: Text(pending == 1 ? '1 attempt waiting to upload' : '$pending attempts waiting to upload'),
                trailing: TextButton(
                  onPressed: () async {
                    final n = await PendingAttempts.instance.flush(ref.read(examApiProvider));
                    ref.invalidate(_pendingCountProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(n > 0 ? 'Uploaded $n' : 'Still offline. They\'ll go up later.')),
                      );
                    }
                  },
                  child: const Text('Upload'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final subject in subjectGroups.keys) ...[
                  if (subject != subjectGroups.keys.first) const Divider(height: 1),
                  _PackTile(
                    subject: subject,
                    topics: subjectGroups[subject]!.length,
                    pack: saved[subject],
                    progress: _progress[subject],
                    onDownload: () => _download(subject),
                    onRemove: () => _remove(subject),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _pendingCountProvider = FutureProvider.autoDispose<int>((ref) => PendingAttempts.instance.count);

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.subject,
    required this.topics,
    required this.pack,
    required this.progress,
    required this.onDownload,
    required this.onRemove,
  });

  final String subject;
  final int topics;
  final PackInfo? pack;
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = pack;
    return ListTile(
      leading: Icon(p == null ? Icons.cloud_download_outlined : Icons.offline_pin_rounded,
          color: p == null ? cs.onSurfaceVariant : cs.primary),
      title: Text(subject, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: progress != null
          ? Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: progress))
          : Text(p == null
              ? '$topics topics'
              : '${p.questions} questions · ${fmtBytes(p.bytes)} · saved ${_ago(p.savedAt)}'),
      trailing: progress != null
          ? null
          : p == null
          ? IconButton(tooltip: 'Save for offline', icon: const Icon(Icons.download_rounded), onPressed: onDownload)
          : PopupMenuButton<String>(
              onSelected: (v) => v == 'update' ? onDownload() : onRemove(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'update', child: Text('Refresh questions')),
                PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays >= 1) return '${d.inDays}d ago';
    if (d.inHours >= 1) return '${d.inHours}h ago';
    return 'just now';
  }
}
