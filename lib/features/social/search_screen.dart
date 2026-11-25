import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/api_error.dart';
import '../../core/ui/avatar.dart';
import '../feed/models.dart';
import '../feed/social_api.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;
  var _q = '';
  List<UserSummary> _results = const [];
  var _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    _q = q;
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await ref.read(socialApiProvider).searchUsers(q);
      if (mounted && q == _q) {
        setState(() {
          _results = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            autofocus: true,
            maxLength: 50, // the server's limit for q
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search people',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _loading
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              counterText: '',
            ),
          ),
        ),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _q.isEmpty
              ? Center(child: Text('Find classmates by name or @username', style: TextStyle(color: cs.onSurfaceVariant)))
              : _results.isEmpty && !_loading
                  ? Center(child: Text('No one matches "$_q"', style: TextStyle(color: cs.onSurfaceVariant)))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final u = _results[i];
                        return ListTile(
                          leading: Avatar(name: u.username, url: u.avatar, radius: 22),
                          title: Text(u.fullname, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('@${u.username}${(u.bio ?? '').isEmpty ? '' : ' · ${u.bio}'}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => context.push('/u/${u.username}'),
                        );
                      },
                    ),
    );
  }
}
