import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/session.dart';
import '../features/activity/activity_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/compose/compose_screen.dart';
import '../features/feed/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/social/search_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/coming_soon.dart';

const _authRoutes = {'/sign-in', '/register'};

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AsyncValue<Session?>>(const AsyncLoading());
  ref.listen(authControllerProvider, (_, next) => auth.value = next, fireImmediately: true);
  ref.onDispose(auth.dispose);

  return GoRouter(
    initialLocation: '/feed',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (auth.value.isLoading && !auth.value.hasValue) return loc == '/splash' ? null : '/splash';
      final signedIn = auth.value.value != null;
      if (!signedIn) return _authRoutes.contains(loc) ? null : '/sign-in';
      if (_authRoutes.contains(loc) || loc == '/splash') return '/feed';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(path: '/u/:username', builder: (_, s) => UserProfileScreen(username: s.pathParameters['username']!)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/feed', builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/exams',
              builder: (_, _) => const ComingSoon(title: 'Exams', icon: Icons.school_rounded, phase: 'P3'),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/create', builder: (_, _) => const ComposeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});
