import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/session.dart';
import '../features/account/account_screen.dart';
import '../features/account/verify_email_screen.dart';
import '../features/activity/activity_screen.dart';
import '../features/auth/email_code_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/compose/compose_screen.dart';
import '../features/exams/exam_result_screen.dart';
import '../features/exams/exam_runner_screen.dart';
import '../features/exams/exam_session.dart';
import '../features/exams/exams_home_screen.dart';
import '../features/feed/home_screen.dart';
import '../features/feed/post_detail_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/follow_list_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/social/search_screen.dart';
import '../features/streak/streak_screen.dart';
import '../features/tutor/tutor_chat_screen.dart';
import '../features/tutor/tutor_library_screen.dart';
import '../features/shell/app_shell.dart';

const _authRoutes = {'/sign-in', '/register', '/sign-in/email', '/forgot-password'};

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AsyncValue<Session?>>(const AsyncLoading());
  ref.listen(authControllerProvider, (_, next) => auth.value = next, fireImmediately: true);
  ref.onDispose(auth.dispose);

  // Where a launch was heading (a launcher shortcut / deep link such as /tutor) while the session was
  // still loading or nobody was signed in; we go there once signed in instead of the feed.
  String? pending;
  void remember(GoRouterState s) {
    final loc = s.matchedLocation;
    if (loc != '/splash' && loc != '/feed' && !_authRoutes.contains(loc)) pending = s.uri.toString();
  }

  return GoRouter(
    initialLocation: '/feed',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (auth.value.isLoading && !auth.value.hasValue) {
        if (loc == '/splash') return null;
        remember(state);
        return '/splash';
      }
      final signedIn = auth.value.value != null;
      if (!signedIn) {
        if (_authRoutes.contains(loc)) return null;
        remember(state);
        return '/sign-in';
      }
      if (_authRoutes.contains(loc) || loc == '/splash') {
        final to = ref.read(authControllerProvider.notifier).takeLanding() ?? pending ?? '/feed';
        pending = null;
        return to;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/sign-in/email', builder: (_, _) => const EmailCodeScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, s) => ForgotPasswordScreen(email: s.uri.queryParameters['email']),
      ),
      // Signed in: confirm / change email, change password (the reset flow, prefilled)
      GoRoute(
        path: '/verify-email',
        builder: (_, s) => VerifyEmailScreen(onboarding: s.uri.queryParameters['onboarding'] == '1'),
      ),
      GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
      GoRoute(path: '/account/email', builder: (_, _) => const ChangeEmailScreen()),
      GoRoute(
        path: '/account/password',
        builder: (_, s) => ForgotPasswordScreen(email: s.uri.queryParameters['email'], signedIn: true),
      ),
      GoRoute(
        path: '/streak',
        builder: (_, s) => StreakScreen(startQuiz: s.uri.queryParameters['quiz'] == '1'),
      ),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(
        path: '/u/:username',
        builder: (_, s) => UserProfileScreen(username: s.pathParameters['username']!),
        routes: [
          GoRoute(
            path: 'followers',
            builder: (_, s) => FollowListScreen(username: s.pathParameters['username']!, initial: 'followers'),
          ),
          GoRoute(
            path: 'following',
            builder: (_, s) => FollowListScreen(username: s.pathParameters['username']!, initial: 'following'),
          ),
        ],
      ),
      GoRoute(path: '/p/:id', builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id']!)),
      GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
      // Exams run full-screen, outside the tab shell.
      GoRoute(path: '/exam/run', builder: (_, _) => const ExamRunnerScreen()),
      GoRoute(
        path: '/exam/result',
        builder: (_, s) => s.extra is FinishedExam
            ? FreshResultScreen(finished: s.extra! as FinishedExam)
            : const ExamsHomeScreen(), // extra is lost if the route is restored from scratch
      ),
      GoRoute(
        path: '/exam/attempt/:id',
        builder: (_, s) => AttemptScreen(attemptId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/tutor', builder: (_, _) => const TutorLibraryScreen()),
      GoRoute(
        path: '/tutor/:attemptId/:questionId',
        builder: (_, s) => TutorChatScreen(
          attemptId: s.pathParameters['attemptId']!,
          questionId: s.pathParameters['questionId']!,
          question: s.extra is TutorQuestion ? s.extra! as TutorQuestion : null,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/feed', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/exams', builder: (_, _) => const ExamsHomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/create', builder: (_, _) => const ComposeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
    ],
  );
});
