import 'package:flutter/material.dart';

import 'brand_mark.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: BrandMark(size: 64)));
}
