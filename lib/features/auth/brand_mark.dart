import 'package:flutter/material.dart';

/// Wordmark: "out" in the brand colour, "stagram" in the text colour.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -size * 0.04, height: 1);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'out', style: style.copyWith(color: cs.primary)),
        TextSpan(text: 'stagram', style: style.copyWith(color: cs.onSurface)),
      ]),
    );
  }
}
