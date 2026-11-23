import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_controller.dart';
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
              if (v == 'signout') await ref.read(authControllerProvider.notifier).signOut();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'signout', child: Text('Sign out'))],
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
      appBar: AppBar(title: Text('@$username')),
      body: ProfileView(username: username, isMe: me == username),
    );
  }
}
