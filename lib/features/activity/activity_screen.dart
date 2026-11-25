import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/api_error.dart';
import '../../core/ui/avatar.dart';
import '../../core/ui/feedback.dart';
import '../feed/models.dart';
import '../feed/social_api.dart';

final followRequestsProvider = FutureProvider.autoDispose<List<FollowRequest>>(
  (ref) => ref.watch(socialApiProvider).followRequests(),
);

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final requests = ref.watch(followRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(followRequestsProvider.future),
        child: requests.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(ApiException.from(e).message))),
          ]),
          data: (list) => list.isEmpty
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
                    child: Column(children: [
                      Icon(Icons.notifications_none_rounded, size: 56, color: cs.primary),
                      const SizedBox(height: 12),
                      const Text('No follow requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('When someone wants to follow you, it shows up here.',
                          textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ])
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('Follow requests', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
                  ),
                  for (final r in list) _RequestTile(request: r),
                ]),
        ),
      ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({required this.request});

  final FollowRequest request;

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  var _busy = false;

  /// null = still pending, else "Approved" / "Declined".
  String? _outcome;

  Future<void> _answer(bool approve) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(socialApiProvider);
      await (approve ? api.approve(widget.request.id) : api.reject(widget.request.id));
      approve ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
      setState(() => _outcome = approve ? 'Approved' : 'Declined');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return ListTile(
      leading: Avatar(name: r.username, url: r.avatar, radius: 22),
      title: Text(r.username, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(r.at == null ? 'wants to follow you' : 'wants to follow you · ${timeAgo(r.at!)}'),
      onTap: () => context.push('/u/${r.username}'),
      trailing: _outcome != null
          ? Chip(label: Text(_outcome!))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Decline',
                onPressed: _busy ? null : () => _answer(false),
                icon: const Icon(Icons.close_rounded),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
                onPressed: _busy ? null : () => _answer(true),
                child: const Text('Approve'),
              ),
            ]),
    );
  }
}
