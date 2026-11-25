import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/avatar.dart';
import '../../core/ui/feedback.dart';
import '../feed/models.dart';
import '../feed/social_api.dart';
import 'profile_view.dart' show profileProvider;

const _pageSize = 30; // server: social.FOLLOW_PAGE_LENGTH

/// `/u/:username/followers` and `/u/:username/following`: two tabs, infinite lists.
class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({super.key, required this.username, required this.initial});

  final String username;

  /// `followers` or `following`.
  final String initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initial == 'following' ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text('@$username'),
          bottom: const TabBar(tabs: [Tab(text: 'Followers'), Tab(text: 'Following')]),
        ),
        body: TabBarView(children: [
          _FollowList(username: username, which: 'followers'),
          _FollowList(username: username, which: 'following'),
        ]),
      ),
    );
  }
}

class _FollowList extends ConsumerStatefulWidget {
  const _FollowList({required this.username, required this.which});

  final String username;
  final String which;

  @override
  ConsumerState<_FollowList> createState() => _FollowListState();
}

class _FollowListState extends ConsumerState<_FollowList> with AutomaticKeepAliveClientMixin {
  final _users = <UserSummary>[];
  var _page = 1;
  var _loading = false;
  var _done = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (reset) {
        _users.clear();
        _page = 1;
        _done = false;
      }
    });
    try {
      final next = await ref.read(socialApiProvider).followList(widget.username, widget.which, _page);
      if (!mounted) return;
      setState(() {
        _users.addAll(next);
        _done = next.length < _pageSize;
        _page++;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isMine => ref.read(authControllerProvider).value?.user.username == widget.username;

  Future<void> _remove(UserSummary u) async {
    final ok = await _confirm(
      context,
      title: 'Remove @${u.username}?',
      body: "They won't be told. They'll stop seeing your posts in their feed until they follow you again.",
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(socialApiProvider).removeFollower(u.username);
      HapticFeedback.mediumImpact();
      setState(() => _users.remove(u));
      ref.invalidate(profileProvider(widget.username));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    if (_users.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_users.isEmpty) {
      final msg = _error != null
          ? ApiException.from(_error!).message
          : widget.which == 'followers'
              ? 'No followers yet'
              : 'Not following anyone yet';
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.all(48),
            child: Center(child: Text(msg, style: TextStyle(color: cs.onSurfaceVariant))),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        itemCount: _users.length + (_done ? 0 : 1),
        itemBuilder: (_, i) {
          if (i == _users.length) {
            if (!_loading && _error == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          }
          final u = _users[i];
          return ListTile(
            leading: Avatar(name: u.username, url: u.avatar, radius: 22),
            title: Text(u.username, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(u.fullname, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => context.push('/u/${u.username}'),
            trailing: u.isYou
                ? null
                : _isMine && widget.which == 'followers'
                    ? OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(88, 36)),
                        onPressed: () => _remove(u),
                        child: const Text('Remove'),
                      )
                    : _RowFollowButton(user: u),
          );
        },
      ),
    );
  }
}

/// Follow / Requested / Following for a row; mirrors the server after each change.
class _RowFollowButton extends ConsumerStatefulWidget {
  const _RowFollowButton({required this.user});

  final UserSummary user;

  @override
  ConsumerState<_RowFollowButton> createState() => _RowFollowButtonState();
}

class _RowFollowButtonState extends ConsumerState<_RowFollowButton> {
  late double _state = widget.user.youFollow;
  var _busy = false;

  Future<void> _tap() async {
    final api = ref.read(socialApiProvider);
    final name = widget.user.username;
    if (_state != 0) {
      final ok = await _confirm(
        context,
        title: _state == 1 ? 'Unfollow @$name?' : 'Cancel your request?',
        action: _state == 1 ? 'Unfollow' : 'Cancel request',
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      if (_state == 0) {
        await api.follow(name);
        _state = 0.5;
      } else {
        await api.unfollow(name);
        _state = 0;
      }
      HapticFeedback.lightImpact();
      ref.invalidate(profileProvider(name));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = Size(104, 36);
    if (_state == 0) {
      return FilledButton(
        style: FilledButton.styleFrom(minimumSize: size),
        onPressed: _busy ? null : _tap,
        child: const Text('Follow'),
      );
    }
    return OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: size),
      onPressed: _busy ? null : _tap,
      child: Text(_state == 1 ? 'Following' : 'Requested'),
    );
  }
}

Future<bool> _confirm(BuildContext context, {required String title, String? body, required String action}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    ) ==
    true;

/// Shared by the profile's follow button.
Future<bool> confirmUnfollow(BuildContext context, String username, {required bool pending}) => _confirm(
      context,
      title: pending ? 'Cancel your request to @$username?' : 'Unfollow @$username?',
      action: pending ? 'Cancel request' : 'Unfollow',
    );
