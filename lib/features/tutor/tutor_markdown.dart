import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/ui/equation_menu.dart';

/// An equation the student long-pressed.
class PickedEquation {
  const PickedEquation(this.latex, {required this.display});
  final String latex;
  final bool display;
}

/// Port of outstagram-web `TutorMarkdown.normalizeMath`: models emit `\( \)` / `\[ \]` and sometimes
/// bare `\begin{..}`; display math is put on its own `$$` fenced lines. A dangling `$$` (mid-stream)
/// is dropped so half an equation doesn't swallow the rest of the answer.
String normalizeMath(String src) {
  var t = src
      .replaceAllMapped(RegExp(r'\\\[([\s\S]+?)\\\]'), (m) => '\$\$${m[1]}\$\$')
      .replaceAllMapped(RegExp(r'\\\(([\s\S]+?)\\\)'), (m) => '\$${m[1]}\$');
  final marks = RegExp(r'\$\$').allMatches(t).length;
  if (marks.isOdd) {
    final i = t.lastIndexOf(r'$$');
    t = t.substring(0, i) + t.substring(i + 2);
  }
  final out = StringBuffer();
  var last = 0;
  for (final m in RegExp(r'\$\$([\s\S]*?)\$\$').allMatches(t)) {
    out.write(_bareEnvs(t.substring(last, m.start)));
    out.write('\n\n\$\$\n${m[1]!.trim()}\n\$\$\n\n');
    last = m.end;
  }
  out.write(_bareEnvs(t.substring(last)));
  return out.toString();
}

final _env = RegExp(r'\\begin\{([a-zA-Z*]+)\}[\s\S]*?\\end\{\1\}');

String _bareEnvs(String s) => s.replaceAllMapped(_env, (m) => '\n\n\$\$\n${m[0]}\n\$\$\n\n');

/// `$$` on its own line … `$$` → `<mathblock tex="…">`.
class _MathBlockSyntax extends md.BlockSyntax {
  static final _fence = RegExp(r'^\s*\$\$\s*$');

  @override
  RegExp get pattern => _fence;

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final lines = <String>[];
    while (!parser.isDone) {
      final line = parser.current.content;
      parser.advance();
      if (_fence.hasMatch(line)) break;
      lines.add(line);
    }
    return md.Element.empty('mathblock')..attributes['tex'] = lines.join('\n').trim();
  }
}

/// `$…$` on one line → `<math tex="…">`. Runs before the default syntaxes, so `_` and `\` inside
/// the formula aren't treated as emphasis or escapes.
class _MathInlineSyntax extends md.InlineSyntax {
  _MathInlineSyntax() : super(r'\$([^$\n]+?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('math')..attributes['tex'] = match[1]!.trim());
    return true;
  }
}

class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder({required this.display, required this.onPick, this.highlight});

  final bool display;
  final ValueChanged<PickedEquation>? onPick;
  final String? highlight;

  @override
  bool isBlockElement() => display;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.attributes['tex'] ?? '';
    final style = DefaultTextStyle.of(context).style.merge(parentStyle).merge(preferredStyle);
    final lit = highlight != null && eqKey(highlight!) == eqKey(tex);
    Widget pressable(Widget child) {
      final c = lit ? EquationPulse(child: child) : child;
      if (onPick == null) return c;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onPick!(PickedEquation(tex, display: display));
        },
        child: c,
      );
    }

    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: style,
      onErrorFallback: (_) => Text(display ? '\$\$$tex\$\$' : '\$$tex\$', style: style),
    );
    if (display) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: pressable(SingleChildScrollView(scrollDirection: Axis.horizontal, child: math)),
      );
    }
    // A Text.rich is merged into the paragraph by flutter_markdown, so inline math flows with the text.
    // texBreak splits long formulas at operators so they wrap (and puts back the space it drops).
    List<Widget> parts;
    try {
      parts = lit ? [math] : math.texBreak().parts;
    } catch (_) {
      parts = [math];
    }
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const TextSpan(text: ' '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: pressable(parts[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tutor answer: GitHub-flavoured Markdown + LaTeX. Long-press an equation to call [onPickEquation].
class TutorMarkdown extends StatelessWidget {
  const TutorMarkdown(this.text, {super.key, this.onPickEquation, this.onTapLink, this.highlight});

  final String text;
  final ValueChanged<PickedEquation>? onPickEquation;

  /// LaTeX of an equation to scroll to and pulse (opened from "Saved equations").
  final String? highlight;
  final void Function(String href)? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodyMedium!.copyWith(fontSize: 15, height: 1.45, color: cs.onSurface);
    return MarkdownBody(
      data: normalizeMath(text),
      fitContent: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: [_MathBlockSyntax()],
      inlineSyntaxes: [_MathInlineSyntax()],
      builders: {
        'math': _MathBuilder(display: false, onPick: onPickEquation, highlight: highlight),
        'mathblock': _MathBuilder(display: true, onPick: onPickEquation, highlight: highlight),
      },
      onTapLink: (_, href, _) {
        if (href != null) onTapLink?.call(href);
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        listBullet: base,
        h1: base.copyWith(fontSize: 19, fontWeight: FontWeight.w800),
        h2: base.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
        h3: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        code: base.copyWith(fontFamily: 'monospace', fontSize: 13.5, backgroundColor: cs.surfaceContainerHighest),
        codeblockDecoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.primary.withValues(alpha: 0.6), width: 3)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 10),
        a: base.copyWith(color: cs.primary, decoration: TextDecoration.underline),
        tableBorder: TableBorder.all(color: cs.outlineVariant),
        tableBody: base.copyWith(fontSize: 13.5),
        tableHead: base.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
