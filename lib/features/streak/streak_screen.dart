import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/feedback.dart';
import '../exams/engine/engine.dart';
import '../exams/exam_api.dart';
import '../exams/exam_launcher.dart';
import 'streak_api.dart';
import 'streak_reminders.dart';
import 'streak_visuals.dart';

/// Picks the pop-quiz subject if none is saved yet, then starts a 5-question quiz.
Future<void> startPopQuiz(BuildContext context, WidgetRef ref, {void Function(bool)? onLoading}) async {
  var subject = ref.read(streakProvider).value?.subject;
  if (subject == null || !subjects.contains(subject)) {
    subject = await pickSubject(context, current: subject);
    if (subject == null) return;
    try {
      await ref.read(streakProvider.notifier).setSubject(subject);
    } catch (_) {
      // still run the quiz; the choice is asked again next time
    }
  }
  if (!context.mounted) return;
  final s = subject;
  await launchExam(context, ref, () => ref.read(examApiProvider).popQuiz(s), onLoading: onLoading);
}

Future<String?> pickSubject(BuildContext context, {String? current}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your pop-quiz subject', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Daily quizzes pick 5 questions from it. Change it any time.',
            style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in subjects)
                ChoiceChip(label: Text(s), selected: s == current, onSelected: (_) => Navigator.pop(c, s)),
            ],
          ),
        ],
      ),
    ),
  ),
);

/// `/streak` (and `/streak?quiz=1` from a reminder, which starts the quiz straight away).
class StreakScreen extends ConsumerStatefulWidget {
  const StreakScreen({super.key, this.startQuiz = false});

  final bool startQuiz;

  @override
  ConsumerState<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends ConsumerState<StreakScreen> {
  var _loading = false;
  bool? _remindersOn;
  TimeOfDay? _time;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {}); // the "hours left" countdown
    });
    if (widget.startQuiz) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(streakProvider.future).catchError((_) => null);
        if (mounted && !(ref.read(streakProvider).value?.todayDone ?? false)) _quiz();
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final on = await StreakReminders.instance.enabled;
    final t = await StreakReminders.instance.time;
    if (mounted) {
      setState(() {
        _remindersOn = on;
        _time = t;
      });
    }
  }

  Future<void> _quiz() async {
    if (_loading) return;
    await startPopQuiz(
      context,
      ref,
      onLoading: (on) {
        if (mounted) setState(() => _loading = on);
      },
    );
  }

  Future<void> _toggleReminders(bool on) async {
    final s = ref.read(streakProvider).value;
    if (on) {
      final ok = await StreakReminders.instance.enable(s);
      if (!ok && mounted) {
        showError(context, ApiException('Allow notifications for Outstagram in Android settings first.'));
      }
    } else {
      await StreakReminders.instance.disable();
    }
    await _loadPrefs();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 19, minute: 0));
    if (t == null) return;
    await StreakReminders.instance.setTime(t, ref.read(streakProvider).value);
    await _loadPrefs();
  }

  @override
  Widget build(BuildContext context) {
    final streak = ref.watch(streakProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Daily streak')),
      body: streak.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ApiException.from(e).message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: () => ref.invalidate(streakProvider), child: const Text('Try again')),
              ],
            ),
          ),
        ),
        data: (s) => s == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: () => ref.read(streakProvider.notifier).reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    _Hero(status: s, loading: _loading, onQuiz: _quiz),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: WeekStrip(status: s),
                      ),
                    ),
                    const SizedBox(height: 16),
                    RewardCard(status: s),
                    const SizedBox(height: 24),
                    const _Title('Milestones'),
                    MilestoneRow(status: s),
                    const SizedBox(height: 16),
                    const _Title('Last six weeks'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: StreakCalendar(status: s),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _Title('Settings'),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.menu_book_rounded),
                            title: const Text('Pop-quiz subject'),
                            subtitle: Text(s.subject ?? 'Not chosen yet'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () async {
                              final pick = await pickSubject(context, current: s.subject);
                              if (pick == null) return;
                              try {
                                await ref.read(streakProvider.notifier).setSubject(pick);
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            secondary: const Icon(Icons.notifications_active_outlined),
                            title: const Text('Streak reminders'),
                            subtitle: const Text("A nudge on days you haven't done your quiz yet"),
                            value: _remindersOn ?? false,
                            onChanged: _remindersOn == null ? null : _toggleReminders,
                          ),
                          if (_remindersOn ?? false) ...[
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.schedule_rounded),
                              title: const Text('Remind me at'),
                              subtitle: const Text('Plus 21:30 and 23:00 if the streak is about to end'),
                              trailing: Text(
                                _time?.format(context) ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              onTap: _pickTime,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Finish any exam with at least one answer to count the day: a pop quiz, practice, a mock or a '
                      'community exam. Days follow your phone\'s time zone. Miss a day and the streak starts over; '
                      'the ${s.reward.goal}-day reward stays once you earn it.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
  );
}

String _timeLeft(DateTime? end) {
  if (end == null) return 'before midnight';
  final d = end.difference(DateTime.now());
  if (d.isNegative) return 'before midnight';
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m left' : '${m}m left';
}

class _Hero extends StatelessWidget {
  const _Hero({required this.status, required this.loading, required this.onQuiz});

  final StreakStatus status;
  final bool loading;
  final VoidCallback onQuiz;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final lit = s.current > 0;
    final (headline, sub) = s.todayDone
        ? ('You\'re on fire!', 'Today is done. Come back tomorrow to make it ${s.current + 1}.')
        : s.atRisk
        ? ('Your streak is at risk', '${_timeLeft(s.dayEndsAt)}. One 5-question quiz keeps all ${s.current} days.')
        : s.broken && s.lost > 1
        ? ('Your ${s.lost}-day streak ended', 'Start again today. Your best is ${s.longest} days.')
        : ('Light your flame', 'Finish one 5-question pop quiz a day to build a streak.');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: lit
              ? [
                  Brand.flameRed.withValues(alpha: 0.28),
                  Brand.flameMagenta.withValues(alpha: 0.18),
                  Brand.nightCard.withValues(alpha: 0.2),
                ]
              : [Brand.ash.withValues(alpha: 0.25), Brand.ash.withValues(alpha: 0.08)],
        ),
        border: Border.all(color: (lit ? Brand.flameOrange : Brand.ash).withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StreakFlame(size: 110, lit: lit),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RollingNumber(
                      value: s.current,
                      style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, height: 1, letterSpacing: -1.5),
                    ),
                    Text(
                      'day streak',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: lit ? Brand.flameOrange : Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Best: ${s.longest}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(headline, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(sub, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 18),
          PopQuizButton(done: s.todayDone, loading: loading, onPressed: onQuiz),
        ],
      ),
    );
  }
}

/// The glowing "Take today's pop quiz" button (outlined "Another quiz" once today is done).
class PopQuizButton extends StatelessWidget {
  const PopQuizButton({super.key, required this.done, required this.loading, required this.onPressed});

  final bool done;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
        : Text(done ? 'Another pop quiz' : "Take today's pop quiz · 5 Qs");
    if (done) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: loading ? null : onPressed,
        icon: const Icon(Icons.bolt_rounded),
        label: child,
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [Brand.flameOrange, Brand.flameRed, Brand.flameMagenta]),
        boxShadow: [
          BoxShadow(color: Brand.flameOrange.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.transparent,
        ),
        onPressed: loading
            ? null
            : () {
                HapticFeedback.lightImpact();
                onPressed();
              },
        icon: loading ? const SizedBox.shrink() : const Icon(Icons.local_fire_department_rounded),
        label: child,
      ),
    );
  }
}

/// Compact streak card for the top of the Exams tab.
class StreakHomeCard extends ConsumerStatefulWidget {
  const StreakHomeCard({super.key});

  @override
  ConsumerState<StreakHomeCard> createState() => _StreakHomeCardState();
}

class _StreakHomeCardState extends ConsumerState<StreakHomeCard> {
  var _loading = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(streakProvider).value;
    if (s == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final lit = s.current > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color:
              (s.atRisk
                      ? Brand.flameRed
                      : lit
                      ? Brand.flameOrange
                      : cs.outlineVariant)
                  .withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        onTap: () => context.push('/streak'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  StreakFlame(size: 52, lit: lit),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lit ? '${s.current}-day streak' : 'Daily pop quiz',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          s.todayDone
                              ? 'Done for today ✓'
                              : s.atRisk
                              ? 'At risk · ${_timeLeft(s.dayEndsAt)}'
                              : '5 questions a day builds a streak',
                          style: TextStyle(
                            color: s.atRisk ? Brand.flameRed : cs.onSurfaceVariant,
                            fontWeight: s.atRisk ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 14),
              WeekStrip(status: s, dense: true),
              if (!s.todayDone) ...[
                const SizedBox(height: 14),
                PopQuizButton(
                  done: false,
                  loading: _loading,
                  onPressed: () => startPopQuiz(
                    context,
                    ref,
                    onLoading: (on) {
                      if (mounted) setState(() => _loading = on);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
