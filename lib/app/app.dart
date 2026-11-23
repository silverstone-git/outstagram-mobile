import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
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
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => Env.isStaging
          ? Banner(
              message: 'STAGING',
              location: BannerLocation.topEnd,
              color: Theme.of(context).colorScheme.tertiary,
              textStyle: TextStyle(
                color: Theme.of(context).colorScheme.onTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
              child: child!,
            )
          : child!,
    );
  }
}
