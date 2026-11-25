import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/ui/avatar.dart';
import '../../core/ui/feedback.dart';
import 'models.dart';
import 'social_api.dart';

/// Returns the change in the comment count (added minus deleted).
Future<int> showCommentsSheet(BuildContext context, Post post) async {
  final added = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CommentsSheet(post: post),
  );
  return added ?? 0;
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.post});

  final Post post;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _input = TextEditingController();
  final _comments = <Comment>[];
  var _page = 1;
  var _loading = true;
  var _done = false;
  var _sending = false;
  var _added = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final next = await ref.read(socialApiProvider).comments(widget.post.id, _page);
      setState(() {
        _comments.addAll(next);
        _done = next.length < 20;
        _page++;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final id = await ref.read(socialApiProvider).addComment(widget.post.id, text);
      HapticFeedback.lightImpact();
      final me = ref.read(authControllerProvider).value!.user.username;
      setState(() {
        _comments.add(Comment(id: id ?? -1, author: me, content: text, at: DateTime.now()));
        _added++;
        _input.clear();
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Long-press: your own comment, or any comment on your post.
  Future<void> _delete(Comment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete comment?'),
        content: Text(c.content, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(socialApiProvider).deleteComment(widget.post.id, c.id);
      HapticFeedback.mediumImpact();
      setState(() {
        _comments.remove(c);
        _added--;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = ref.watch(authControllerProvider).value?.user.username;
    final myPost = me == widget.post.author;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_added);
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(children: [
            const Text('Comments', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: _comments.isEmpty && !_loading
                  ? Center(
                      child: Text(_error != null ? '$_error' : 'No comments yet. Start the conversation.',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _comments.length + (_done ? 0 : 1),
                      itemBuilder: (_, i) {
                        if (i == _comments.length) {
                          if (!_loading) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final c = _comments[i];
                        final canDelete = c.id > 0 && (myPost || c.author == me);
                        return ListTile(
                          onLongPress: canDelete ? () => _delete(c) : null,
                          leading: GestureDetector(
                            onTap: () {
                              Navigator.of(context).pop(_added);
                              context.push('/u/${c.author}');
                            },
                            child: Avatar(name: c.author, url: c.authorAvatar, radius: 16),
                          ),
                          title: Text.rich(TextSpan(children: [
                            TextSpan(text: '${c.author}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: timeAgo(c.at), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          ])),
                          subtitle: Text(c.content, style: TextStyle(color: cs.onSurface, fontSize: 14.5)),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      autofocus: widget.post.commentCount == 0,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment…',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
