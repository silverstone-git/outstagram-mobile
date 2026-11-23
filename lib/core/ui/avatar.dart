import 'package:flutter/material.dart';

/// Letter avatar with a colour derived from the username (no profile photos on the API yet).
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.radius = 18});

  final String name;
  final double radius;

  static const _hues = [152.0, 200.0, 265.0, 320.0, 30.0, 50.0, 175.0, 230.0];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hue = _hues[name.codeUnits.fold<int>(0, (a, b) => a + b) % _hues.length];
    final bg = HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.28 : 0.86).toColor();
    final fg = HSLColor.fromAHSL(1, hue, 0.8, dark ? 0.78 : 0.3).toColor();
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: radius * 0.9),
      ),
    );
  }
}
