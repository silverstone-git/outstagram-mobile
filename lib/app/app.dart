import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/account/account_api.dart';
import '../features/compose/share_intent.dart';
import '../features/streak/streak_api.dart';
import '../features/streak/streak_reminders.dart';
import 'router.dart';
import 'theme.dart';

class OutstagramApp extends ConsumerStatefulWidget {
  const OutstagramApp({super.key});

  @override
  ConsumerState<OutstagramApp> createState() => _OutstagramAppState();
}

class _OutstagramAppState extends ConsumerState<OutstagramApp> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // A streak reminder was tapped: open its route (the router waits for sign-in if needed).
    StreakReminders.instance.init(onTap: (route) => ref.read(routerProvider).push(route)).then((_) {
      final r = StreakReminders.instance.launchRoute;
      StreakReminders.instance.launchRoute = null;
      if (r != null) ref.read(routerProvider).push(r);
    });
    // Back in the app: the day may have changed, or the email was confirmed in another app.
    _life = AppLifecycleListener(
      onResume: () {
        if (ref.read(streakProvider).hasValue) ref.read(streakProvider.notifier).reload();
        ref.invalidate(meProvider);
      },
    );
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the streak loaded (and reminders planned) for as long as someone is signed in.
    ref.listen(streakProvider, (_, _) {});
    return MaterialApp.router(
      title: 'Outstagram',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      // Staging is marked by the app name ("Outstagram β") and the chip on the sign-in screen;
      // a corner banner would cover the status bar on edge-to-edge screens.
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => ShareIntentListener(child: child ?? const SizedBox.shrink()),
    );
  }
}
