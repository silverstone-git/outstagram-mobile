import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_controller.dart';
import '../billing/paywall_sheet.dart';
import 'package:share_plus/share_plus.dart';

import '../feed/post_card.dart' show profileLink;
import 'profile_view.dart';

/// Your own profile (tab).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;
    if (user == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('@${user.username}'),
        actions: [
          IconButton(
            tooltip: 'Theme',
            icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).set(dark ? ThemeMode.light : ThemeMode.dark),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'pro') await showPaywall(context);
              if (v == 'account' && context.mounted) await context.push('/account');
              if (v == 'streak' && context.mounted) await context.push('/streak');
              if (v == 'signout') await ref.read(authControllerProvider.notifier).signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'account',
                child: ListTile(leading: Icon(Icons.manage_accounts_outlined), title: Text('Account & email')),
              ),
              PopupMenuItem(
                value: 'streak',
                child: ListTile(leading: Icon(Icons.local_fire_department_outlined), title: Text('Daily streak')),
              ),
              PopupMenuItem(
                value: 'pro',
                child: ListTile(leading: Icon(Icons.workspace_premium_outlined), title: Text('Outstagram Pro')),
              ),
              PopupMenuItem(
                value: 'signout',
                child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Sign out')),
              ),
            ],
          ),
        ],
      ),
      body: ProfileView(username: user.username, isMe: true),
    );
  }
}

/// Someone else's profile (pushed route).
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).value?.user.username;
    return Scaffold(
      appBar: AppBar(title: Text('@$username'), actions: [
        IconButton(
          tooltip: 'Share profile',
          icon: const Icon(Icons.share_outlined),
          onPressed: () => SharePlus.instance.share(ShareParams(text: '@$username on Outstagram\n${profileLink(username)}')),
        ),
      ]),
      body: ProfileView(username: username, isMe: me == username),
    );
  }
}
