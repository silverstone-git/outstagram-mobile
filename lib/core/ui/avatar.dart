import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Profile photo, or a letter avatar coloured by the username while there's none (or it's loading).
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.radius = 18});

  final String name;
  final String? url;
  final double radius;

  static const _hues = [152.0, 200.0, 265.0, 320.0, 30.0, 50.0, 175.0, 230.0];

  /// Presigned links change when the server re-signs them; cache by the object path instead.
  static String cacheKey(String url) => url.split('?').first;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hue = _hues[name.codeUnits.fold<int>(0, (a, b) => a + b) % _hues.length];
    final bg = HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.28 : 0.86).toColor();
    final fg = HSLColor.fromAHSL(1, hue, 0.8, dark ? 0.78 : 0.3).toColor();
    final u = url;
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      foregroundImage: u == null || u.isEmpty
          ? null
          : CachedNetworkImageProvider(u, cacheKey: cacheKey(u), maxWidth: (radius * 6).round()),
      onForegroundImageError: u == null || u.isEmpty ? null : (_, _) {},
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: radius * 0.9),
      ),
    );
  }
}
