import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/ui/equation_menu.dart' show eqKey, stripCitations;
import 'package:outstagram/core/ui/math_text.dart';

void main() {
  test('doubled backslashes from the question bank collapse', () {
    expect(cleanLatex(r'free particle $(r, \\theta, \\phi)$'), r'free particle $(r, \theta, \phi)$');
  });

  test('inline and display math split from text', () {
    final segs = parseMath(r'Energy $E = mc^2$ and $$\int_0^1 x\,dx$$ done');
    expect(segs.map((s) => s.toString()).toList(), ['Energy ', r'$E = mc^2$', ' and ', r'$$\int_0^1 x\,dx$$', ' done']);
    expect(segs[3].display, isTrue);
    expect(segs[1].display, isFalse);
  });

  test(r'\( \) and \[ \] delimiters', () {
    final segs = parseMath(r'a \(x\) b \[y\]');
    expect(segs.where((s) => s.isMath).map((s) => (s.text, s.display)).toList(), [('x', false), ('y', true)]);
  });

  test('bare environments are wrapped as display math', () {
    expect(cleanLatex(r'\begin{pmatrix}1&0\\0&1\end{pmatrix}'), startsWith(r'$$'));
  });

  test('bare commands without delimiters get wrapped', () {
    final segs = parseMath(cleanLatex(r'the value of \alpha_1 is \frac{1}{2}'));
    expect(segs.where((s) => s.isMath).map((s) => s.text).toList(), [r'\alpha_1', r'\frac{1}{2}']);
  });

  test('plain text is untouched', () {
    expect(parseMath('no math here').single.isMath, isFalse);
  });

  test('doubled spacing commands collapse too (\\\\, is not a row break)', () {
    expect(cleanLatex(r'$2i\\hbar\\,\\hat{p}$'), r'$2i\hbar\,\hat{p}$');
    expect(cleanLatex(r'$a \\; b \\! c$'), r'$a \; b \! c$');
  });

  testWidgets('inline math that texBreak cannot split (doubled thin space) still renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MathText(r'Answer: $2i\\hbar\\,\\hat{p}$'))));
    expect(tester.takeException(), isNull);
    expect(find.byType(MathText), findsOneWidget);
  });

  // QA 2026-11-27
  test('saved equations drop the trailing citation marker', () {
    expect(stripCitations(r'J_x = \frac{\hbar k|A|^2}{m} \quad [2]'), r'J_x = \frac{\hbar k|A|^2}{m}');
    expect(stripCitations(r'E = mc^2 [1][3]'), 'E = mc^2');
    expect(stripCitations(r'x[2] + y'), r'x[2] + y'); // an index mid-formula stays
    expect(eqKey(r'a = b \quad [4]'), eqKey('a = b'));
  });

  test('captions: \$5 and \$10 stay text next to real maths', () {
    final segs = parseMath(r'Area $x^2$ costs $5 and $10', strict: true);
    expect(segs.where((s) => s.isMath).map((s) => s.text).toList(), ['x^2']);
  });
}
