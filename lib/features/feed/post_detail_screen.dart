import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_error.dart';
import 'models.dart';
import 'post_card.dart';
import 'social_api.dart';

final postProvider = FutureProvider.autoDispose.family<Post, String>((ref, id) => ref.watch(socialApiProvider).post(id));

/// `/p/:id`: one post, e.g. from a shared link or a launcher deep link (`outstagram://app/p/<id>`).
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.postId, this.focusLatex});

  final String postId;

  /// Opened from "Saved equations": pulse this caption equation.
  final String? focusLatex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(postId));
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(postProvider(postId).future),
        child: post.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) {
            final err = ApiException.from(e);
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
                child: Column(children: [
                  Icon(Icons.image_not_supported_outlined, size: 56, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    err.status == 404 ? 'This post was deleted' : err.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ]);
          },
          data: (p) => ListView(children: [
            PostCard(post: p, detail: true, highlightLatex: focusLatex, onDeleted: () => Navigator.of(context).maybePop()),
          ]),
        ),
      ),
    );
  }
}
