import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/net/api_client.dart';
import '../../core/net/api_error.dart';

/// `GET /me/stats` (all counted server-side).
final myStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(apiProvider).get<Map<String, dynamic>>('/me/stats'),
);

/// P1 profile: proves the authenticated client (token refresh included) against real data.
/// The full profile (posts grid, follow state, edit) arrives in P2.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;
    final stats = ref.watch(myStatsProvider);
    final cs = Theme.of(context).colorScheme;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: Text('@${user.username}'),
        actions: [
          IconButton(
            tooltip: 'Theme',
            icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).set(
                  Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
                ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'signout') await ref.read(authControllerProvider.notifier).signOut();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'signout', child: Text('Sign out'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myStatsProvider.future),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: cs.primary.withValues(alpha: 0.15),
              child: Text(
                user.fullname.isEmpty ? '?' : user.fullname.characters.first.toUpperCase(),
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: cs.primary),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.fullname, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if ((user.bio ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(user.bio!, style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          stats.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _ErrorCard(error: ApiException.from(e), onRetry: () => ref.invalidate(myStatsProvider)),
            data: (s) => GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                _Stat('Posts', '${s['posts'] ?? 0}'),
                _Stat('Followers', '${s['followers'] ?? 0}'),
                _Stat('Following', '${s['following'] ?? 0}'),
                _Stat('Exams', '${s['exams_taken'] ?? 0}'),
                _Stat('Avg accuracy', s['avg_accuracy'] == null ? '—' : '${s['avg_accuracy']}%'),
                _Stat('Best score', s['best_score_pct'] == null ? '—' : '${s['best_score_pct']}%'),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FittedBox(
            child: Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: cs.primary)),
          ),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(error.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}
