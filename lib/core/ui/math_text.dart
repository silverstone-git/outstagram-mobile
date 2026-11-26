import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'equation_menu.dart';

/// Text with LaTeX: `$…$` / `\(…\)` inline, `$$…$$` / `\[…\]` display. Mirrors outstagram-web's
/// `Latex.tsx` clean-up: question-bank text often has doubled backslashes (`\\theta`), and some
/// LLM-written items have bare `\begin{…}` or `\alpha` without delimiters.
///
/// With [onPickEquation], long-pressing an equation calls it (the equation menu: save, copy). An equation
/// equal to [highlight] scrolls into view and pulses (opened from "Saved equations").
class MathText extends StatelessWidget {
  const MathText(this.source, {super.key, this.style, this.maxLines, this.onPickEquation, this.highlight});

  final String source;
  final TextStyle? style;
  final int? maxLines;
  final EquationPick? onPickEquation;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final want = highlight == null ? null : eqKey(highlight!);
    Widget wrap(Widget w, MathSegment seg, {bool pulse = true}) {
      if (pulse && want != null && eqKey(seg.text) == want) w = EquationPulse(child: w);
      final pick = onPickEquation;
      if (pick == null) return w;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => pick(seg.text, seg.display),
        child: w,
      );
    }

    final blocks = <Widget>[];
    final spans = <InlineSpan>[];

    void flush() {
      if (spans.isEmpty) return;
      blocks.add(Text.rich(TextSpan(children: [...spans]), style: base, maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis));
      spans.clear();
    }

    for (final seg in parseMath(cleanLatex(source))) {
      if (!seg.isMath) {
        spans.add(TextSpan(text: seg.text));
      } else if (seg.display && maxLines == null) {
        flush();
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: wrap(
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(seg.text, mathStyle: MathStyle.display, textStyle: base,
                  onErrorFallback: (e) => Text(seg.text, style: base)),
            ),
            seg,
          ),
        ));
      } else {
        // texBreak splits at binary operators/relations so long inline formulas wrap like text.
        final math = Math.tex(seg.text, mathStyle: MathStyle.text, textStyle: base,
            onErrorFallback: (e) => Text(seg.text, style: base));
        // texBreak throws on some trees (e.g. `\,` spacing: UnsupportedError in TemporaryNode.rightType);
        // then the formula just doesn't wrap.
        List<Widget> parts;
        final highlighted = want != null && eqKey(seg.text) == want;
        try {
          parts = highlighted ? [math] : math.texBreak().parts; // one piece, so it pulses as one
        } catch (_) {
          parts = [math];
        }
        for (var i = 0; i < parts.length; i++) {
          // texBreak drops the space after the operator it breaks at; a normal space (~TeX's thick
          // space) puts it back and stays a line-break opportunity.
          if (i > 0) spans.add(const TextSpan(text: ' '));
          spans.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: wrap(parts[i], seg)));
        }
      }
    }
    flush();
    if (blocks.length == 1) return blocks.single;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: blocks);
  }
}

class MathSegment {
  const MathSegment(this.text, {this.isMath = false, this.display = false});
  final String text;
  final bool isMath;
  final bool display;

  @override
  String toString() => isMath ? (display ? '\$\$$text\$\$' : '\$$text\$') : text;
}

// letters (\\theta) and the spacing commands (\\, \\; \\: \\!), which would otherwise read as a row break + ","
final _cmd = RegExp(r'\\\\([a-zA-Z,;:!])');
final _bareCmd = RegExp(r'\\[a-zA-Z]+(?:\{[^{}]*\})*(?:[_^](?:\{[^{}]*\}|\w))*');

/// Repairs the text the way the web does before rendering.
String cleanLatex(String text) {
  var t = text.replaceAllMapped(_cmd, (m) => '\\${m[1]}'); // \\theta -> \theta (keeps standalone \\ row breaks)
  final hasDelims = t.contains(r'$') || t.contains(r'\(') || t.contains(r'\[');
  if (!hasDelims && (t.contains(r'\begin{') || t.contains(r'\pmatrix') || t.contains(r'\bmatrix'))) {
    return '\$\$ $t \$\$';
  }
  if (!hasDelims && t.contains('\\')) {
    t = t.replaceAllMapped(_bareCmd, (m) => '\$${m[0]}\$');
  }
  return t;
}

final _delims = RegExp(r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$([^$]+?)\$');

List<MathSegment> parseMath(String text) {
  final out = <MathSegment>[];
  var last = 0;
  for (final m in _delims.allMatches(text)) {
    if (m.start > last) out.add(MathSegment(text.substring(last, m.start)));
    final display = m[1] != null || m[2] != null;
    out.add(MathSegment((m[1] ?? m[2] ?? m[3] ?? m[4]!).trim(), isMath: true, display: display));
    last = m.end;
  }
  if (last < text.length) out.add(MathSegment(text.substring(last)));
  return out;
}
