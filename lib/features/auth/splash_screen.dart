import 'package:flutter/material.dart';

import 'brand_mark.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  // Same mark and size as the Android 12+ system splash, so the hand-off doesn't jump.
  Widget build(BuildContext context) => const Scaffold(body: Center(child: BrandSymbol(size: 130)));
}
