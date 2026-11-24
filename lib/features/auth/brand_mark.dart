import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Outstagram logo: the gradient mark (`assets/brand/mark.svg`) plus the "Outsta" + "gram" wordmark.
/// The wordmark is real text (not the SVG's text), so it has no gap and follows the theme:
/// "Outsta" in the text colour, "gram" in the brand colour.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.showMark = true});

  /// Font size of the wordmark; the mark is scaled to match.
  final double size;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -size * 0.045, height: 1);
    return Semantics(
      label: 'Outstagram',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMark) ...[
            BrandSymbol(size: size * 1.15),
            SizedBox(width: size * 0.28),
          ],
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Outsta', style: style.copyWith(color: cs.onSurface)),
              TextSpan(text: 'gram', style: style.copyWith(color: cs.primary)),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Just the gradient mark.
class BrandSymbol extends StatelessWidget {
  const BrandSymbol({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset('assets/brand/mark.svg', width: size, height: size);
}
