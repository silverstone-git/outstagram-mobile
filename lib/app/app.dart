import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class OutstagramApp extends ConsumerWidget {
  const OutstagramApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Outstagram',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      // Staging is marked by the app name ("Outstagram β") and the chip on the sign-in screen;
      // a corner banner would cover the status bar on edge-to-edge screens.
      routerConfig: ref.watch(routerProvider),
    );
  }
}
