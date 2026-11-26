import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/net/api_client.dart';
import '../account/account_api.dart';
import 'follow_list_screen.dart' show confirmUnfollow;
import 'profile_photo.dart';
import '../streak/streak_visuals.dart' show StreakBadge;
import '../streak/streak_api.dart' show streakProvider;
import '../account/account_screen.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/avatar.dart';
import '../../core/ui/feedback.dart';
import '../compose/compose_screen.dart';
import '../feed/models.dart';
import '../feed/post_list.dart';
import '../feed/social_api.dart';

final profileProvider = FutureProvider.autoDispose.family<Profile, String>((ref, username) {
  ref.watch(postsVersionProvider); // a new or deleted post changes the counts
  return ref.watch(socialApiProvider).profile(username);
});

/// `GET /me/stats` (counted server-side).
final myStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  // recount after a post is added/deleted and after exam attempts land (they update the streak, also
  // when attempts made offline upload later)
  ref.watch(postsVersionProvider);
  ref.watch(streakProvider);
  return ref.watch(apiProvider).get<Map<String, dynamic>>('/me/stats');
});

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
      cached: () => api.cachedUserPosts(username),
      header: _Header(username: username, isMe: isMe),
      // follower/following counts change without a new post: reload the header too
      onRefresh: () async {
        ref.invalidate(profileProvider(username));
        if (isMe) ref.invalidate(myStatsProvider);
        await ref.read(profileProvider(username).future);
      },
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
        error: (e, _) => SizedBox(height: 160, child: Center(child: Text(ApiException.from(e).message))),
        data: (p) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                isMe
                    ? ProfilePhotoButton(name: p.username, url: p.avatar)
                    : Avatar(name: p.username, url: p.avatar, radius: 38),
                const SizedBox(width: 18),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Count('${p.posts}', 'posts'),
                      _Count('${p.followers}', 'followers',
                          onTap: () => context.push('/u/${p.username}/followers')),
                      _Count('${p.following}', 'following',
                          onTap: () => context.push('/u/${p.username}/following')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Flexible(
                  child: Text(p.fullname, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                if (p.streak > 0) ...[
                  const SizedBox(width: 8),
                  Tooltip(message: '${p.streak}-day exam streak', child: StreakBadge(days: p.streak)),
                ],
                if (isMe && (ref.watch(meProvider).value?.needsVerification ?? false)) ...[
                  const SizedBox(width: 8),
                  const _UnverifiedBadge(),
                ],
              ],
            ),
            if ((p.bio ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(p.bio!)),
            if (!isMe) ...[
              const SizedBox(height: 14),
              _FollowButton(profile: p),
              if (p.theyFollow == 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Follows you', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ),
            ],
            if (isMe) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                onPressed: () => context.push('/profile/edit'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit profile'),
              ),
            ],
            if (isMe && (ref.watch(meProvider).value?.needsVerification ?? false)) ...[
              const SizedBox(height: 14),
              const VerifyEmailBanner(),
            ],
            if (isMe) ...[const SizedBox(height: 16), const _MyStats()],
            const SizedBox(height: 12),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

/// Warning chip next to your name while the email isn't confirmed.
class _UnverifiedBadge extends StatelessWidget {
  const _UnverifiedBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Email not confirmed',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/verify-email'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.error.withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: cs.onErrorContainer),
              const SizedBox(width: 4),
              Text(
                'Unverified',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onErrorContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.label, {this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    ),
  );
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

  /// Unfollow, or cancel a pending request (after a confirm).
  Future<void> _undo() async {
    final p = widget.profile;
    if (!await confirmUnfollow(context, p.username, pending: p.youFollow != 1)) return;
    setState(() => _busy = true);
    try {
      await ref.read(socialApiProvider).unfollow(p.username);
      HapticFeedback.lightImpact();
      ref.read(postsVersionProvider.notifier).bump(); // the feed loses their posts; the profile reloads
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.profile.youFollow;
    if (f == 1 || f == 0.5) {
      return OutlinedButton.icon(
        onPressed: _busy ? null : _undo,
        icon: Icon(f == 1 ? Icons.check_rounded : Icons.schedule_rounded),
        label: Text(f == 1 ? 'Following' : 'Requested'),
      );
    }
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
        return Row(
          children: [
            for (final (label, value, icon) in items)
              Expanded(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Column(
                      children: [
                        Icon(icon, size: 18, color: cs.primary),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: cs.primary),
                        ),
                        Text(label, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
