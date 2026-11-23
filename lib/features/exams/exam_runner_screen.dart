import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/ui/math_text.dart';
import 'engine/engine.dart';
import 'exam_session.dart';
import 'exams_home_screen.dart' show compactButton;

const _letters = 'ABCDEFGH';

/// Full-screen exam runner (outside the tab shell). State lives in [examSessionProvider] and is
/// autosaved, so leaving the app or a crash loses nothing.
class ExamRunnerScreen extends ConsumerStatefulWidget {
  const ExamRunnerScreen({super.key});

  @override
  ConsumerState<ExamRunnerScreen> createState() => _ExamRunnerScreenState();
}

class _ExamRunnerScreenState extends ConsumerState<ExamRunnerScreen> with WidgetsBindingObserver {
  late final PageController _pages;
  Timer? _tick;
  bool _submitting = false;
  bool _warned = false;

  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: ref.read(examSessionProvider)?.index ?? 0);
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = ref.read(examSessionProvider.notifier);
    if (s == AppLifecycleState.paused) c.paused();
    if (s == AppLifecycleState.resumed) c.resumed();
  }

  void _onTick() {
    final s = ref.read(examSessionProvider);
    if (s == null || !mounted) return;
    final left = s.remainingSeconds();
    if (left <= 0) {
      _submit(auto: true);
      return;
    }
    if (left <= 300 && !_warned && s.totalSeconds > 600) {
      _warned = true;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('5 minutes left')));
    }
    setState(() {});
  }

  void _goTo(int i) {
    final s = ref.read(examSessionProvider);
    if (s == null || i < 0 || i >= s.questions.length) return;
    _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  void _submit({bool auto = false}) {
    if (_submitting) return;
    _submitting = true;
    _tick?.cancel();
    final done = ref.read(examSessionProvider.notifier).submit();
    if (done == null) return;
    HapticFeedback.heavyImpact();
    if (auto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Time's up. Your exam was submitted.")));
    }
    context.pushReplacement('/exam/result', extra: done);
  }

  Future<void> _confirmSubmit(ExamSession s) async {
    final left = s.questions.length - s.answeredCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Submit exam?'),
        content: Text(
          'You answered ${s.answeredCount} of ${s.questions.length}.${left > 0 ? ' $left unanswered.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep going')),
          FilledButton(style: compactButton, onPressed: () => Navigator.pop(c, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok == true) _submit();
  }

  Future<void> _leave() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Leave the exam?', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('The clock keeps running while you are away, like in a real exam.'),
            ),
            ListTile(
              leading: const Icon(Icons.pause_circle_outline_rounded),
              title: const Text('Save and exit'),
              subtitle: const Text('Resume it from the Exams tab'),
              onTap: () => Navigator.pop(c, 'save'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error),
              title: Text('Discard', style: TextStyle(color: Theme.of(c).colorScheme.error)),
              subtitle: const Text('Your answers are thrown away'),
              onTap: () => Navigator.pop(c, 'discard'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'discard') ref.read(examSessionProvider.notifier).discard();
    context.pop();
  }

  void _palette(ExamSession s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => _Palette(
        onPick: (i) {
          Navigator.pop(c);
          _goTo(i);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(examSessionProvider);
    final cs = Theme.of(context).colorScheme;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No exam is running.')),
      );
    }
    final left = s.remainingSeconds();
    final low = left < 300;
    final last = s.index == s.questions.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Leave exam', onPressed: _leave),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.config.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
              Text(
                '${s.answeredCount}/${s.questions.length} answered',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            Semantics(
              label: 'Time remaining',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: low ? cs.error.withValues(alpha: 0.18) : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  formatTime(left),
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                    color: low ? cs.error : null,
                  ),
                ),
              ),
            ),
            TextButton(onPressed: () => _confirmSubmit(s), child: const Text('Finish')),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: LinearProgressIndicator(value: s.answeredCount / s.questions.length, minHeight: 3),
          ),
        ),
        body: PageView.builder(
          controller: _pages,
          itemCount: s.questions.length,
          onPageChanged: (i) {
            HapticFeedback.selectionClick();
            ref.read(examSessionProvider.notifier).goTo(i);
          },
          itemBuilder: (_, i) => _QuestionPage(index: i, key: ValueKey(s.questions[i].id)),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: s.index == 0 ? null : () => _goTo(s.index - 1),
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Prev'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _palette(s),
                    icon: const Icon(Icons.grid_view_rounded, size: 18),
                    label: Text('${s.index + 1}/${s.questions.length}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: last
                      ? FilledButton(onPressed: () => _confirmSubmit(s), child: const Text('Finish'))
                      : FilledButton.icon(
                          onPressed: () => _goTo(s.index + 1),
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: const Text('Next'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestionPage extends ConsumerStatefulWidget {
  const _QuestionPage({super.key, required this.index});

  final int index;

  @override
  ConsumerState<_QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends ConsumerState<_QuestionPage> {
  late final TextEditingController _nat;

  @override
  void initState() {
    super.initState();
    final s = ref.read(examSessionProvider)!;
    _nat = TextEditingController(text: s.answerFor(s.questions[widget.index].id).text ?? '');
  }

  @override
  void dispose() {
    _nat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(examSessionProvider);
    if (s == null) return const SizedBox.shrink();
    final c = ref.read(examSessionProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final q = s.questions[widget.index];
    final a = s.answerFor(q.id);
    final section = sectionOf(s.config, q.id);
    final isCurrent = s.index == widget.index;

    // Inputs only act on the page that is showing (the controller edits the current question).
    void guard(VoidCallback f) {
      if (isCurrent) f();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Q${widget.index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  TextSpan(
                    text: '/${s.questions.length}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (section != null && s.config.sections!.length > 1) _Chip(section.name),
            _Chip(switch (q.type) {
              QuestionType.msq => 'Multiple select',
              QuestionType.nat => 'Numerical',
              QuestionType.mcq => 'Single choice',
            }),
            if (section != null)
              Text(
                '+${_n(section.marking.positive)}${section.marking.negative > 0 ? ' / −${_n(section.marking.negative)}' : ''}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => guard(() {
              HapticFeedback.lightImpact();
              c.toggleFlag();
            }),
            style: TextButton.styleFrom(foregroundColor: a.isFlagged ? cs.tertiary : cs.onSurfaceVariant),
            icon: Icon(a.isFlagged ? Icons.flag_rounded : Icons.outlined_flag_rounded, size: 20),
            label: Text(a.isFlagged ? 'Flagged' : 'Flag for review'),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MathText(q.question, style: const TextStyle(fontSize: 16, height: 1.45)),
                if (q.imagePath != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: Colors.white,
                      child: CachedNetworkImage(
                        imageUrl: resolveImagePath(q.imagePath),
                        fit: BoxFit.contain,
                        height: 240,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (q.type == QuestionType.nat)
          TextField(
            controller: _nat,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9eE+\-.]'))],
            style: const TextStyle(fontSize: 20, fontFeatures: [FontFeature.tabularFigures()]),
            decoration: const InputDecoration(labelText: 'Your numerical answer', hintText: 'e.g. 0.25'),
            onChanged: (v) => guard(() => c.enterText(v)),
          )
        else ...[
          for (var i = 0; i < q.shuffledOptions.length; i++)
            _OptionTile(
              letter: i < _letters.length ? _letters[i] : '${i + 1}',
              option: q.shuffledOptions[i],
              multi: q.type == QuestionType.msq,
              selected: q.type == QuestionType.msq
                  ? (a.labels ?? const []).contains(q.shuffledOptions[i].label)
                  : a.label == q.shuffledOptions[i].label,
              onTap: () => guard(() {
                HapticFeedback.lightImpact();
                c.pick(q.shuffledOptions[i].label);
              }),
            ),
          if (q.type == QuestionType.msq)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Select all that apply.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ),
        ],
        if (a.isAttempted)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => guard(() {
                _nat.clear();
                c.clear();
              }),
              child: const Text('Clear response'),
            ),
          ),
      ],
    );
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.option,
    required this.multi,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final Option option;
  final bool multi;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        checked: multi ? selected : null,
        inMutuallyExclusiveGroup: !multi,
        button: true,
        child: Material(
          color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(multi ? 7 : 15),
                      ),
                      child: Text(
                        letter,
                        style: TextStyle(fontWeight: FontWeight.w800, color: selected ? cs.onPrimary : cs.onSurface),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: MathText(option.value, style: const TextStyle(fontSize: 15, height: 1.35)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Palette extends ConsumerWidget {
  const _Palette({required this.onPick});

  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(examSessionProvider);
    if (s == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final multi = s.config.sections!.length > 1;
    Widget legend(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const Text('Questions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              legend(cs.primary, 'answered'),
              legend(cs.tertiary, 'flagged'),
              legend(cs.surfaceContainerHighest, 'not answered'),
            ],
          ),
          for (final sec in s.config.sections!)
            Builder(
              builder: (_) {
                final ids = {for (final q in sec.questions) q.id};
                final items = [
                  for (var i = 0; i < s.questions.length; i++)
                    if (ids.contains(s.questions[i].id)) i,
                ];
                if (items.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    if (multi)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${sec.name}${sec.maxAttempts != null ? ' · best ${sec.maxAttempts} count' : ''}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final i in items)
                          Builder(
                            builder: (_) {
                              final a = s.answers[s.questions[i].id];
                              final bg = (a?.isFlagged ?? false)
                                  ? cs.tertiary
                                  : (a?.isAttempted ?? false)
                                  ? cs.primary
                                  : cs.surfaceContainerHighest;
                              final fg = (a?.isFlagged ?? false)
                                  ? cs.onTertiary
                                  : (a?.isAttempted ?? false)
                                  ? cs.onPrimary
                                  : cs.onSurface;
                              return Semantics(
                                button: true,
                                label: 'Question ${i + 1}',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => onPick(i),
                                  child: Container(
                                    width: 46,
                                    height: 42,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: i == s.index ? Border.all(color: cs.onSurface, width: 2) : null,
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
