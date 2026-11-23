import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/avatar.dart';
import '../../core/ui/feedback.dart';
import '../compose/compose_screen.dart';
import '../feed/models.dart';
import '../feed/post_list.dart';
import '../feed/social_api.dart';

final profileProvider = FutureProvider.autoDispose.family<Profile, String>(
  (ref, username) => ref.watch(socialApiProvider).profile(username),
);

/// `GET /me/stats` (counted server-side).
final myStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(apiProvider).get<Map<String, dynamic>>('/me/stats'),
);

/// Profile header + that user's posts. Used for your own tab and for anyone else.
class ProfileView extends ConsumerWidget {
  const ProfileView({super.key, required this.username, required this.isMe});

  final String username;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(socialApiProvider);
    final v = ref.watch(postsVersionProvider);
    return PostList(
      key: ValueKey('posts-$username-$v'),
      pageSize: 10,
      loader: (page) => api.userPosts(username, page),
      header: _Header(username: username, isMe: isMe),
      empty: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(child: Text(isMe ? 'Share your first post from the + tab' : 'No posts yet')),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.username, required this.isMe});

  final String username;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final profile = ref.watch(profileProvider(username));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: profile.when(
        loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => SizedBox(
          height: 160,
          child: Center(child: Text(ApiException.from(e).message)),
        ),
        data: (p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(name: p.username, radius: 38),
            const SizedBox(width: 18),
            Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Count('${p.posts}', 'posts'),
                _Count('${p.followers}', 'followers'),
                _Count('${p.following}', 'following'),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(p.fullname, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if ((p.bio ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(p.bio!)),
          if (!isMe) ...[
            const SizedBox(height: 14),
            _FollowButton(profile: p),
            if (p.theyFollow == 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Follows you', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
          ],
          if (isMe) ...[const SizedBox(height: 16), const _MyStats()],
          const SizedBox(height: 12),
          const Divider(height: 1),
        ]),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        Text(label, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
}

class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  var _busy = false;

  Future<void> _follow() async {
    setState(() => _busy = true);
    try {
      await ref.read(socialApiProvider).follow(widget.profile.username);
      HapticFeedback.mediumImpact();
      ref.invalidate(profileProvider(widget.profile.username));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.profile.youFollow;
    if (f == 1) return OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.check_rounded), label: const Text('Following'));
    if (f == 0.5) return OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.schedule_rounded), label: const Text('Requested'));
    return FilledButton(
      onPressed: _busy ? null : _follow,
      child: Text(widget.profile.theyFollow == 1 ? 'Follow back' : 'Follow'),
    );
  }
}

class _MyStats extends ConsumerWidget {
  const _MyStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final stats = ref.watch(myStatsProvider);
    return stats.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (s) {
        final items = [
          ('Exams', '${s['exams_taken'] ?? 0}', Icons.school_rounded),
          ('Avg accuracy', s['avg_accuracy'] == null ? '—' : '${s['avg_accuracy']}%', Icons.track_changes_rounded),
          ('Best score', s['best_score_pct'] == null ? '—' : '${s['best_score_pct']}%', Icons.emoji_events_rounded),
        ];
        return Row(children: [
          for (final (label, value, icon) in items)
            Expanded(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Column(children: [
                    Icon(icon, size: 18, color: cs.primary),
                    const SizedBox(height: 4),
                    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: cs.primary)),
                    Text(label, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }
}
