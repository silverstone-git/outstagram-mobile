import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/net/api_error.dart';
import 'engine/engine.dart';
import 'exam_api.dart';
import 'exam_launcher.dart';
import '../streak/streak_api.dart';
import '../streak/streak_screen.dart';
import '../streak/streak_visuals.dart';

export 'exam_launcher.dart' show compactButton;
import 'exam_session.dart';

final attemptsProvider = FutureProvider.autoDispose<List<AttemptSummary>>(
  (ref) => ref.watch(examApiProvider).attempts(),
);
final communityExamsProvider = FutureProvider.autoDispose<List<CommunityExam>>(
  (ref) => ref.watch(examApiProvider).communityExams(),
);

String fmtScore(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : double.parse(v.toStringAsFixed(2)).toString();

class ExamsHomeScreen extends ConsumerStatefulWidget {
  const ExamsHomeScreen({super.key});

  @override
  ConsumerState<ExamsHomeScreen> createState() => _ExamsHomeScreenState();
}

class _ExamsHomeScreenState extends ConsumerState<ExamsHomeScreen> {
  String? _busy; // key of the item being loaded

  Future<void> _start(String key, Future<ExamConfig> Function() load, {String? examId}) async {
    if (_busy != null) return;
    await launchExam(
      context,
      ref,
      load,
      examId: examId,
      onLoading: (on) {
        if (mounted) setState(() => _busy = on ? key : null);
      },
    );
    ref.invalidate(attemptsProvider);
  }

  Future<void> _refresh() async {
    ref.invalidate(savedSessionProvider);
    ref.read(streakProvider.notifier).reload();
    try {
      await Future.wait([ref.refresh(attemptsProvider.future), ref.refresh(communityExamsProvider.future)]);
    } catch (_) {
      // each list shows its own error
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(examApiProvider);
    final cs = Theme.of(context).colorScheme;
    final saved = ref.watch(savedSessionProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exams'),
        actions: [
          StreakChip(status: ref.watch(streakProvider).value),
          IconButton(
            tooltip: 'Offline packs',
            icon: const Icon(Icons.offline_pin_outlined),
            onPressed: () => context.push('/exams/offline'),
          ),
          IconButton(
            tooltip: 'Tutor library',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push('/tutor'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              'Practice, review every answer, and see where you lose marks.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const StreakHomeCard(),
            if (saved != null) ...[const SizedBox(height: 16), _ResumeCard(session: saved)],
            _Section(icon: Icons.bolt_rounded, title: 'Quick practice', hint: '10 questions · 30 min'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in subjects)
                  ActionChip(
                    avatar: _busy == 'practice:$s' ? const _Spinner() : null,
                    label: Text(s),
                    onPressed: _busy != null ? null : () => _start('practice:$s', () => api.practice(s)),
                  ),
              ],
            ),
            _Section(icon: Icons.timer_outlined, title: 'Full mock tests'),
            for (final p in ExamPreset.values)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${p.blurb} · ${p.minutes ~/ 60}h'),
                  trailing: _busy == 'preset:${p.id}' ? const _Spinner() : const Icon(Icons.chevron_right_rounded),
                  enabled: _busy == null,
                  onTap: () => _start('preset:${p.id}', () => api.preset(p)),
                ),
              ),
            _Section(icon: Icons.history_rounded, title: 'Your attempts'),
            _AsyncList(
              value: ref.watch(attemptsProvider),
              empty: 'No attempts yet. Finished exams show up here for review.',
              builder: (list) => [
                for (final a in list.take(20))
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${DateFormat.yMMMd().format(a.takenAt)} · ${a.totalQuestions} Qs · ${a.accuracy.round()}% accuracy',
                    ),
                    trailing: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: fmtScore(a.score),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: '/${fmtScore(a.maxScore)}',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    onTap: () => context.push('/exam/attempt/${a.id}'),
                  ),
              ],
            ),
            _Section(icon: Icons.groups_rounded, title: 'Community exams'),
            _AsyncList(
              value: ref.watch(communityExamsProvider),
              empty: 'No community exams yet.',
              builder: (list) => [
                for (final e in list)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: _busy == 'community:${e.id}' ? const _Spinner() : const Icon(Icons.chevron_right_rounded),
                    enabled: _busy == null,
                    onTap: () => _start('community:${e.id}', () => api.communityExam(e.id), examId: e.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.session});

  final ExamSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final left = session.remainingSeconds();
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.play_circle_fill_rounded, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Exam in progress', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(session.config.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              '${session.answeredCount}/${session.questions.length} answered · '
              '${left > 0 ? '${formatTime(left)} left' : 'time is up'}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Discard this exam?'),
                        content: const Text('Your answers will be lost.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          FilledButton(
                            style: compactButton,
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Discard'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      ref.read(examSessionProvider.notifier).discard();
                      ref.invalidate(savedSessionProvider);
                    }
                  },
                  child: const Text('Discard'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: compactButton,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(left > 0 ? 'Resume' : 'See result'),
                    onPressed: () async {
                      ref.read(examSessionProvider.notifier).resume(session);
                      await context.push('/exam/run');
                      ref.invalidate(savedSessionProvider);
                      ref.invalidate(attemptsProvider);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, this.hint});

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (hint != null) Text('  ·  $hint', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }
}

class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({required this.value, required this.empty, required this.builder});

  final AsyncValue<List<T>> value;
  final String empty;
  final List<Widget> Function(List<T>) builder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return value.when(
      loading: () => Container(
        height: 64,
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(16)),
      ),
      error: (e, _) => Text(ApiException.from(e).message, style: TextStyle(color: cs.error)),
      data: (list) => list.isEmpty
          ? Text(empty, style: TextStyle(color: cs.onSurfaceVariant))
          : Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(children: builder(list)),
            ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
}
