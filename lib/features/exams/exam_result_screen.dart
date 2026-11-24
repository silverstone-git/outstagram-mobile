import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/api_error.dart';
import '../../core/ui/math_text.dart';
import 'engine/engine.dart';
import '../tutor/tutor_chat_screen.dart';
import 'exam_api.dart';
import 'exam_session.dart';
import 'exams_home_screen.dart';
import 'result_card.dart';

/// A past attempt, loaded from the server (`/exam/attempt/:id`).
class AttemptScreen extends ConsumerWidget {
  const AttemptScreen({super.key, required this.attemptId});

  final String attemptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(attemptProvider(attemptId));
    return a.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(padding: const EdgeInsets.all(32), child: Text(ApiException.from(e).message)),
        ),
      ),
      data: (a) => ResultView(result: a.result, maxScore: a.summary.maxScore, attemptId: a.summary.id),
    );
  }
}

/// Straight after submitting (`/exam/result`): saves the attempt, then shows it.
class FreshResultScreen extends ConsumerStatefulWidget {
  const FreshResultScreen({super.key, required this.finished});

  final FinishedExam finished;

  @override
  ConsumerState<FreshResultScreen> createState() => _FreshResultScreenState();
}

class _FreshResultScreenState extends ConsumerState<FreshResultScreen> {
  _Save _save = _Save.saving;
  String? _attemptId;

  @override
  void initState() {
    super.initState();
    _persist();
  }

  Future<void> _persist() async {
    setState(() => _save = _Save.saving);
    final f = widget.finished;
    try {
      final saved = await ref.read(examApiProvider).saveAttempt(f.examId, f.result, f.maxScore);
      if (mounted) {
        setState(() {
          _save = _Save.saved;
          _attemptId = saved.id;
        });
      }
      ref.invalidate(attemptsProvider);
    } catch (e) {
      debugPrint('save attempt failed: $e');
      if (mounted) setState(() => _save = _Save.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.finished;
    final cs = Theme.of(context).colorScheme;
    return ResultView(
      result: f.result,
      maxScore: f.maxScore,
      attemptId: _attemptId,
      leftApp: f.leftApp,
      banner: switch (_save) {
        _Save.saving => const _Banner(icon: Icons.cloud_upload_outlined, text: 'Saving to your attempts…'),
        _Save.saved => null,
        _Save.failed => _Banner(
          icon: Icons.cloud_off_rounded,
          text: "Couldn't save this attempt. The review below still works.",
          color: cs.error,
          action: TextButton(onPressed: _persist, child: const Text('Retry')),
        ),
      },
      onRetake: () {
        ref.read(examSessionProvider.notifier).start(f.config, examId: f.examId);
        context.pushReplacement('/exam/run');
      },
    );
  }
}

enum _Save { saving, saved, failed }

enum _Filter { all, wrong, skipped, flagged }

class ResultView extends StatefulWidget {
  const ResultView({
    super.key,
    required this.result,
    required this.maxScore,
    this.attemptId,
    this.leftApp = 0,
    this.banner,
    this.onRetake,
  });

  final ExamResult result;
  final double maxScore;

  /// The saved attempt; the AI tutor needs it (null while saving or if saving failed).
  final String? attemptId;
  final int leftApp;
  final Widget? banner;
  final VoidCallback? onRetake;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  _Filter _filter = _Filter.all;
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final cs = Theme.of(context).colorScheme;
    final byId = {for (final a in r.answers) a.questionId: a};
    final skipped = r.originalQuestions.where((q) => !(byId[q.id]?.isAttempted ?? false)).length;
    final wrong = r.originalQuestions.length - r.correctAnswers - skipped;
    final topics = r.accuracyPerTopic.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final pct = widget.maxScore > 0 ? (r.score / widget.maxScore).clamp(0.0, 1.0) : r.accuracy / 100;
    final items =
        [
          for (var i = 0; i < r.originalQuestions.length; i++)
            (i, r.originalQuestions[i], byId[r.originalQuestions[i].id]),
        ].where((e) {
          final a = e.$3;
          return switch (_filter) {
            _Filter.all => true,
            _Filter.wrong => (a?.isAttempted ?? false) && !a!.isCorrect,
            _Filter.skipped => !(a?.isAttempted ?? false),
            _Filter.flagged => a?.isFlagged ?? false,
          };
        }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(r.examName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Share result card',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => showResultCardSheet(context, r, widget.maxScore),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          ?widget.banner,
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SCORE', style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: cs.onSurfaceVariant)),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: fmtScore(r.score),
                          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
                        ),
                        TextSpan(
                          text: ' / ${fmtScore(widget.maxScore)}',
                          style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: pct.toDouble(), minHeight: 8),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Stat(
                        icon: Icons.check_rounded,
                        color: cs.primary,
                        label: 'Correct',
                        value: '${r.correctAnswers}',
                      ),
                      _Stat(icon: Icons.close_rounded, color: cs.error, label: 'Wrong', value: '$wrong'),
                      _Stat(
                        icon: Icons.remove_rounded,
                        color: cs.onSurfaceVariant,
                        label: 'Skipped',
                        value: '$skipped',
                      ),
                      _Stat(
                        icon: Icons.timer_outlined,
                        color: cs.tertiary,
                        label: 'Time',
                        value: formatTime(r.totalTimeTaken),
                      ),
                    ],
                  ),
                  if (widget.leftApp > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      'You left the app ${widget.leftApp}× during this exam.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (topics.length > 1) ...[
            const _H('By topic', hint: 'weakest first'),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final t in topics)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  '${(t.value * 100).round()}%',
                                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: t.value,
                                minHeight: 5,
                                color: t.value < 0.5
                                    ? cs.error
                                    : t.value < 0.8
                                    ? cs.tertiary
                                    : cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (r.swot.strengths.isNotEmpty) ...[
            const _H('Analysis'),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                title: const Text('Strengths, weaknesses, opportunities, threats', style: TextStyle(fontSize: 14)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (title, list, color) in [
                    ('Strengths', r.swot.strengths, cs.primary),
                    ('Weaknesses', r.swot.weaknesses, cs.error),
                    ('Opportunities', r.swot.opportunities, cs.tertiary),
                    ('Threats', r.swot.threats, cs.onSurfaceVariant),
                  ]) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13),
                      ),
                    ),
                    for (final line in list) Text('• $line', style: const TextStyle(fontSize: 13, height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
          _H(
            'Review',
            trailing: widget.onRetake == null
                ? null
                : TextButton.icon(
                    onPressed: widget.onRetake,
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const Text('Retake'),
                  ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (f, label) in [
                  (_Filter.all, 'All'),
                  (_Filter.wrong, 'Wrong ($wrong)'),
                  (_Filter.skipped, 'Skipped ($skipped)'),
                  (_Filter.flagged, 'Flagged'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('Nothing here.', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ),
          for (final (i, q, a) in items)
            _ReviewCard(
              number: i + 1,
              question: q,
              answer: a,
              open: _open.contains(q.id),
              onAskTutor: widget.attemptId == null
                  ? null
                  : () => context.push(
                      tutorPath(widget.attemptId!, q.id),
                      extra: TutorQuestion(text: q.question, topic: q.topic, examTitle: r.examName),
                    ),
              onToggle: () => setState(() => _open.contains(q.id) ? _open.remove(q.id) : _open.add(q.id)),
            ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.number,
    required this.question,
    required this.answer,
    required this.open,
    required this.onToggle,
    this.onAskTutor,
  });

  final int number;
  final Question question;
  final UserAnswer? answer;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback? onAskTutor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = question, a = answer;
    final attempted = a?.isAttempted ?? false;
    final (badgeBg, badgeFg) = !attempted
        ? (cs.surfaceContainerHighest, cs.onSurfaceVariant)
        : a!.isCorrect
        ? (cs.primary.withValues(alpha: 0.2), cs.primary)
        : (cs.error.withValues(alpha: 0.2), cs.error);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
                    child: Text(
                      '$number',
                      style: TextStyle(color: badgeFg, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: MathText(q.question, maxLines: open ? null : 2, style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                  if (a?.isFlagged ?? false) Icon(Icons.flag_rounded, size: 18, color: cs.tertiary),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (q.imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ColoredBox(
                        color: Colors.white,
                        child: Image.network(resolveImagePath(q.imagePath), height: 200),
                      ),
                    ),
                  if (q.type == QuestionType.nat)
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 13),
                        children: [
                          TextSpan(
                            text: 'Answer: ',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          TextSpan(
                            text: q.answerRange != null
                                ? '${fmtScore(q.answerRange!.min)} – ${fmtScore(q.answerRange!.max)}'
                                : q.answerValue ?? '—',
                            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: '   Yours: ',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          TextSpan(text: (a?.enteredAnswer ?? '').isEmpty ? '—' : a!.enteredAnswer),
                        ],
                      ),
                    )
                  else
                    for (final o in q.displayOptions)
                      Builder(
                        builder: (_) {
                          final right = q.type == QuestionType.msq
                              ? (q.answerLabels ?? const []).contains(o.label)
                              : q.answerLabel == o.label;
                          final mine = q.type == QuestionType.msq
                              ? (a?.selectedOptionLabels ?? const []).contains(o.label)
                              : a?.selectedOptionLabel == o.label;
                          final border = right
                              ? cs.primary
                              : mine
                              ? cs.error
                              : cs.outlineVariant;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: right
                                  ? cs.primary.withValues(alpha: 0.1)
                                  : mine
                                  ? cs.error.withValues(alpha: 0.1)
                                  : null,
                              border: Border.all(color: border.withValues(alpha: 0.7)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: right
                                      ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
                                      : mine
                                      ? Icon(Icons.close_rounded, size: 18, color: cs.error)
                                      : null,
                                ),
                                Expanded(child: MathText(o.value, style: const TextStyle(fontSize: 14))),
                                if (mine)
                                  Text(
                                    'YOURS',
                                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, letterSpacing: 0.8),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                  if (q.explanation.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Explanation',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          MathText(q.explanation, style: const TextStyle(fontSize: 14, height: 1.4)),
                        ],
                      ),
                    ),
                  if (onAskTutor != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton.icon(
                        onPressed: onAskTutor,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('Ask the AI tutor'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.label, required this.value});

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.title, {this.hint, this.trailing});

  final String title;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (hint != null) Text('  ($hint)', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.color, this.action});

  final IconData icon;
  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: c)),
          ),
          ?action,
        ],
      ),
    );
  }
}
