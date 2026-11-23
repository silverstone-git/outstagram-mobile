import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/brand_mark.dart';
import '../compose/compose_screen.dart';
import 'models.dart';
import 'post_list.dart';
import 'social_api.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  PostCategory? _category;

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(socialApiProvider);
    final v = ref.watch(postsVersionProvider);
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const BrandMark(size: 26),
          actions: [
            IconButton(tooltip: 'Find people', icon: const Icon(Icons.search_rounded), onPressed: () => context.push('/search')),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(children: [
              TabBar(
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                tabs: const [Tab(text: 'Following'), Tab(text: 'Explore')],
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _chip('All', null),
                    for (final c in PostCategory.values) _chip('${c.emoji} ${c.label}', c),
                  ],
                ),
              ),
            ]),
          ),
        ),
        body: TabBarView(children: [
          PostList(
            key: ValueKey('feed-${_category?.name}-$v'),
            pageSize: 20,
            loader: (page) => api.feed(page, category: _category),
            empty: _EmptyFeed(
              onExplore: () => DefaultTabController.of(context).animateTo(1),
              color: cs.primary,
            ),
          ),
          PostList(
            key: ValueKey('explore-${_category?.name}-$v'),
            pageSize: 20,
            loader: (page) => api.explore(page, category: _category),
            empty: const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('Nothing here yet. Be the first to post!')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, PostCategory? c) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _category == c,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _category = c),
        ),
      );
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.onExplore, required this.color});

  final VoidCallback onExplore;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
        child: Column(children: [
          Icon(Icons.diversity_3_rounded, size: 64, color: color),
          const SizedBox(height: 16),
          const Text('Your feed is quiet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Follow classmates to see their posts here, or browse what everyone is sharing.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(onPressed: onExplore, child: const Text('Explore posts')),
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.push('/search'), child: const Text('Find people')),
        ]),
      );
}
