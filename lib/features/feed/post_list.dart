import 'package:flutter/material.dart';

import '../../core/net/api_error.dart';
import 'models.dart';
import 'post_card.dart';

typedef PageLoader = Future<List<Post>> Function(int page);

/// Infinite, pull-to-refresh list of posts. Change [loaderKey] to reload from page 1.
class PostList extends StatefulWidget {
  const PostList({
    super.key,
    required this.loader,
    required this.pageSize,
    this.empty,
    this.header,
  });

  final PageLoader loader;
  final int pageSize;
  final Widget? empty;
  final Widget? header;

  @override
  State<PostList> createState() => PostListState();
}

class PostListState extends State<PostList> with AutomaticKeepAliveClientMixin {
  final _posts = <Post>[];
  var _page = 1;
  var _loading = false;
  var _done = false;
  ApiException? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> refresh() async {
    _page = 1;
    _done = false;
    _error = null;
    final first = await _fetch();
    if (!mounted || first == null) return;
    setState(() {
      _posts
        ..clear()
        ..addAll(first);
    });
  }

  Future<List<Post>?> _fetch() async {
    try {
      final next = await widget.loader(_page);
      _page++;
      _done = next.length < widget.pageSize;
      return next;
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e));
      return null;
    }
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final next = await _fetch();
    if (!mounted) return;
    setState(() {
      if (next != null) _posts.addAll(next);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final header = widget.header;
    final extra = header == null ? 0 : 1;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: extra + (_posts.isEmpty ? 1 : _posts.length + 1),
        itemBuilder: (context, i) {
          if (header != null && i == 0) return header;
          final idx = i - extra;
          if (_posts.isEmpty) {
            if (_error != null) return _ErrorBox(error: _error!, onRetry: _more);
            if (_loading || !_done) {
              return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
            }
            return widget.empty ?? const SizedBox.shrink();
          }
          if (idx == _posts.length) {
            if (_error != null) return _ErrorBox(error: _error!, onRetry: _more);
            if (_done) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
                child: Center(child: Text("You're all caught up", style: TextStyle(color: cs.onSurfaceVariant))),
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) => _more());
            return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          }
          final p = _posts[idx];
          return PostCard(
            key: ValueKey(p.id),
            post: p,
            onDeleted: () => setState(() => _posts.remove(p)),
          );
        },
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error, required this.onRetry});

  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Text(error.message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}
