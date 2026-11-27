import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tutor/models.dart';
import '../../features/tutor/tutor_api.dart';
import '../net/api_error.dart';
import '../platform.dart';

/// Where an equation was long-pressed, so "Saved equations" can jump back there (outsie
/// `FavoriteEquationCreate`: source tutor | question | option | explanation | post).
class EquationSource {
  const EquationSource({
    required this.source,
    this.attemptId,
    this.questionId,
    this.messageId,
    this.postId,
    this.skill,
    this.context,
  });

  final String source;
  final String? attemptId;
  final String? questionId;
  final int? messageId;
  final String? postId;
  final String? skill;
  final String? context;
}

/// Called by [MathText] / TutorMarkdown when an equation is long-pressed.
typedef EquationPick = void Function(String latex, bool display);

/// The long-pressed equation lifted over a blurred screen, with Save / Copy LaTeX / Copy for Markdown.
Future<void> showEquationMenu(BuildContext context, WidgetRef ref, String latex, bool display, EquationSource src) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => _EquationMenu(latex: stripCitations(latex), display: display, src: src),
    transitionBuilder: (ctx, anim, _, child) {
      final t = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            child: AnimatedBuilder(
              animation: anim,
              builder: (_, _) => BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12 * anim.value, sigmaY: 12 * anim.value),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.45 * anim.value)),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(t), child: child),
        ),
      ]);
    },
  );
}

/// Strips trailing citation markers the tutor writes inside display maths (`… = x \quad [2]`), so
/// saved equations and copies hold just the maths.
String stripCitations(String latex) =>
    latex.replaceFirst(RegExp(r'(\s|~|\\[,;:!]|\\q?quad|\\text\{\s*\})*(\[\d+(\s*,\s*\d+)*\]\s*)+$'), '').trimRight();

class _EquationMenu extends ConsumerStatefulWidget {
  const _EquationMenu({required this.latex, required this.display, required this.src});

  final String latex;
  final bool display;
  final EquationSource src;

  @override
  ConsumerState<_EquationMenu> createState() => _EquationMenuState();
}

class _EquationMenuState extends ConsumerState<_EquationMenu> {
  var _busy = false;

  FavoriteEquation? _saved(List<FavoriteEquation>? list) =>
      list?.where((f) => eqKey(f.latex) == eqKey(widget.latex)).firstOrNull;

  Future<void> _toggle(FavoriteEquation? saved) async {
    setState(() => _busy = true);
    final api = ref.read(tutorApiProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (saved != null) {
        await api.deleteFavorite(saved.id);
      } else {
        final s = widget.src;
        await api.addFavorite(
          latex: widget.latex,
          display: widget.display,
          skill: s.skill,
          context: s.context,
          attemptId: s.attemptId,
          questionId: s.questionId,
          messageId: s.messageId,
          postId: s.postId,
          source: s.source,
        );
      }
      HapticFeedback.mediumImpact();
      ref.invalidate(favoriteEquationsProvider);
      messenger?.showSnackBar(SnackBar(content: Text(saved != null ? 'Removed from saved equations' : 'Equation saved')));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    // Android 13+ shows its own "Copied" confirmation; a snackbar on top of it doubled it up.
    if (!systemConfirmsCopy) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$what copied')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final favs = ref.watch(favoriteEquationsProvider);
    final saved = _saved(favs.value);
    final loading = favs.isLoading && !favs.hasValue;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(color: cs.primary.withValues(alpha: 0.25), blurRadius: 30, spreadRadius: 2),
                        const BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 10)),
                      ],
                    ),
                    // long equations shrink to fit (a sideways scroll here wasn't discoverable: it looked cut off)
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Math.tex(
                        widget.latex,
                        mathStyle: MathStyle.display,
                        textStyle: TextStyle(fontSize: 22, color: cs.onSurface),
                        onErrorFallback: (_) => SelectableText(widget.latex),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                        enabled: !_busy && !loading,
                        leading: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(saved != null ? Icons.star_rounded : Icons.star_outline_rounded, color: cs.primary),
                        title: Text(loading ? 'Checking…' : saved != null ? 'Saved · tap to remove' : 'Save equation'),
                        onTap: () => _toggle(saved),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.copy_rounded),
                        title: const Text('Copy LaTeX'),
                        onTap: () => _copy(widget.latex, 'LaTeX'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.data_object_rounded),
                        title: const Text(r'Copy for Markdown ($…$)'),
                        onTap: () => _copy(widget.display ? '\$\$${widget.latex}\$\$' : '\$${widget.latex}\$', 'Markdown'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                        title: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Normalised LaTeX for matching a saved equation against a rendered one.
String eqKey(String latex) => stripCitations(latex).replaceAll(RegExp(r'\s+'), '');

/// Scrolls itself into view once and pulses (opened from "Saved equations").
class EquationPulse extends StatefulWidget {
  const EquationPulse({super.key, required this.child});

  final Widget child;

  @override
  State<EquationPulse> createState() => _EquationPulseState();
}

class _EquationPulseState extends State<EquationPulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  var _rounds = 0;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && ++_rounds < 3) _c.forward(from: 0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Scrollable.ensureVisible(context, alignment: 0.4, duration: const Duration(milliseconds: 400));
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final v = _rounds >= 3 ? 0.0 : Curves.easeInOut.transform(_c.value < 0.5 ? _c.value * 2 : (1 - _c.value) * 2);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.28 * v),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [if (v > 0) BoxShadow(color: cs.primary.withValues(alpha: 0.4 * v), blurRadius: 8 * v, spreadRadius: 2 * v)],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
