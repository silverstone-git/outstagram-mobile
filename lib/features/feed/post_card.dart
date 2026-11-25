import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../profile/profile_view.dart' show profileProvider;
import '../../core/auth/auth_controller.dart';
import '../../core/ui/avatar.dart';
import '../../core/ui/feedback.dart';
import '../../core/config/env.dart';
import 'comments_sheet.dart';
import 'media_viewer.dart';
import 'models.dart';
import 'social_api.dart';

class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post, this.onDeleted, this.detail = false});

  final Post post;
  final VoidCallback? onDeleted;

  /// Shown on its own page (`/p/:id`): no "Open post" item.
  final bool detail;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> with SingleTickerProviderStateMixin {
  late final _heart = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  var _page = 0;
  var _liking = false;

  Post get p => widget.post;

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  Future<void> _toggleLike({bool onlyLike = false}) async {
    if (_liking || (onlyLike && p.isLiked)) return;
    HapticFeedback.lightImpact();
    final was = p.isLiked;
    setState(() {
      p.isLiked = !was;
      p.likeCount += was ? -1 : 1;
      _liking = true;
    });
    try {
      final api = ref.read(socialApiProvider);
      await (was ? api.unlike(p.id) : api.like(p.id));
    } catch (e) {
      if (mounted) {
        setState(() {
          p.isLiked = was;
          p.likeCount += was ? 1 : -1;
        });
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  void _doubleTapLike() {
    _heart.forward(from: 0);
    _toggleLike(onlyLike: true);
  }

  Future<void> _openComments() async {
    final added = await showCommentsSheet(context, p);
    if (added != 0 && mounted) setState(() => p.commentCount = (p.commentCount + added).clamp(0, 1 << 30));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This removes it for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(socialApiProvider).deletePost(p.id);
      widget.onDeleted?.call();
      ref.invalidate(profileProvider(p.author)); // the post count
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = ref.watch(authControllerProvider).value?.user.username;
    final mine = me == p.author;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // header
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 8),
        child: Row(children: [
          GestureDetector(onTap: () => context.push('/u/${p.author}'), child: Avatar(name: p.author, url: p.authorAvatar)),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/u/${p.author}'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.author, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [if (p.category != null) '${p.category!.emoji} ${p.category!.label}', timeAgo(p.postedAt)].join(' · '),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ]),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'delete') _delete();
              if (v == 'share') sharePost(p);
              if (v == 'open') context.push('/p/${p.id}');
            },
            itemBuilder: (_) => [
              if (!widget.detail) const PopupMenuItem(value: 'open', child: Text('Open post')),
              const PopupMenuItem(value: 'share', child: Text('Share link')),
              if (mine) const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ),
      // media
      if (p.media.isNotEmpty)
        GestureDetector(
          onTap: p.media[_page].isVideo ? null : () => openMediaViewer(context, p.media, _page),
          onDoubleTap: _doubleTapLike,
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(alignment: Alignment.center, children: [
              PageView.builder(
                itemCount: p.media.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _MediaView(media: p.media[i]),
              ),
              _HeartBurst(controller: _heart),
              if (p.media.length > 1)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Text('${_page + 1}/${p.media.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
            ]),
          ),
        )
      else if (p.caption.isNotEmpty)
        GestureDetector(
          onDoubleTap: _doubleTapLike,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary.withValues(alpha: 0.16), cs.tertiary.withValues(alpha: 0.10)],
                ),
              ),
              child: _Caption(text: p.caption, big: true),
            ),
            _HeartBurst(controller: _heart),
          ]),
        ),
      // dots
      if (p.media.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < p.media.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: i == _page ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? cs.primary : cs.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ]),
        ),
      // actions
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
        child: Row(children: [
          IconButton(
            onPressed: _toggleLike,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                p.isLiked ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                key: ValueKey(p.isLiked),
                color: p.isLiked ? const Color(0xFFFF3B6B) : null,
              ),
            ),
          ),
          Text('${p.likeCount}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          IconButton(onPressed: _openComments, icon: const Icon(Icons.mode_comment_outlined)),
          Text('${p.commentCount}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
      if (p.media.isNotEmpty && p.caption.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: _Caption(text: p.caption, author: p.author),
        ),
      if (p.commentCount > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
          child: GestureDetector(
            onTap: _openComments,
            child: Text(
              p.commentCount == 1 ? 'View 1 comment' : 'View all ${p.commentCount} comments',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      const SizedBox(height: 16),
    ]);
  }
}

class _MediaView extends StatelessWidget {
  const _MediaView({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (media.isVideo) return PostVideo(url: media.url);
    return CachedNetworkImage(
      imageUrl: media.url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, _) => Container(color: cs.surfaceContainerHigh),
      errorWidget: (_, _, _) => Container(
        color: cs.surfaceContainerHigh,
        child: Center(child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant, size: 40)),
      ),
    );
  }
}

class _HeartBurst extends StatelessWidget {
  const _HeartBurst({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, _) {
            final t = controller.value;
            if (t == 0 || t == 1) return const SizedBox.shrink();
            final scale = Curves.elasticOut.transform((t * 2).clamp(0, 1)) * 1.1;
            final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 110,
                    shadows: [Shadow(blurRadius: 24, color: Colors.black38)]),
              ),
            );
          },
        ),
      );
}

/// Caption with hashtags in the brand colour.
class _Caption extends StatelessWidget {
  const _Caption({required this.text, this.author, this.big = false});

  final String text;
  final String? author;
  final bool big;

  static final _tag = RegExp(r'#\w+');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = TextStyle(fontSize: big ? 17 : 14.5, height: 1.35, color: cs.onSurface, fontWeight: big ? FontWeight.w500 : null);
    final spans = <TextSpan>[
      if (author != null) TextSpan(text: '$author  ', style: const TextStyle(fontWeight: FontWeight.w700)),
    ];
    var i = 0;
    for (final m in _tag.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(0), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)));
      i = m.end;
    }
    spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

/// The post's web link (`<WEB_BASE>/p/<id>`); the app opens it at `/p/:id`.
String postLink(Post p) => '${Env.webBase}/p/${p.id}';

Future<void> sharePost(Post p) => SharePlus.instance.share(ShareParams(
      text: [if (p.caption.isNotEmpty) p.caption.split('\n').first, postLink(p)].join('\n'),
      subject: 'Post by @${p.author} on Outstagram',
    ));
