import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import 'streak_api.dart';
import 'streak_reminders.dart';
import 'streak_visuals.dart';

/// Full-screen "🔥 Day N!" after an exam extends the streak: the flame pops in, the number rolls
/// from N-1 to N, confetti bursts, and haptics thump in time. Milestones and the 250-day reward get
/// their own headline. Offers reminders the first time.
Future<void> showStreakCelebration(BuildContext context, StreakStatus s) async {
  final askReminders = !await StreakReminders.instance.asked;
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => _Celebration(status: s, askReminders: askReminders),
    transitionBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}

class _Celebration extends StatefulWidget {
  const _Celebration({required this.status, required this.askReminders});

  final StreakStatus status;
  final bool askReminders;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late int _shown = (widget.status.current - 1).clamp(0, 1 << 30);
  var _confetti = false;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _timers.add(
      Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() {
          _shown = widget.status.current;
          _confetti = true;
        });
        HapticFeedback.heavyImpact();
      }),
    );
    _timers.add(Timer(const Duration(milliseconds: 820), HapticFeedback.heavyImpact));
    if (widget.status.milestone != null || widget.status.rewardUnlocked) {
      _timers.add(Timer(const Duration(milliseconds: 1000), HapticFeedback.heavyImpact));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _pop.dispose();
    super.dispose();
  }

  (String, String) get _copy {
    final s = widget.status;
    final n = s.current;
    if (s.rewardUnlocked) {
      return (
        '$n days. Legendary. 👑',
        'You unlocked ${s.reward.aiPromptsPerHour} AI messages an hour and ${s.reward.tutorThreads} saved chats. They\'re yours for good.',
      );
    }
    if (s.milestone != null) {
      return ('🏆 $n-day milestone!', _milestoneLine(n, s));
    }
    if (n == 1) {
      return (
        'Day 1. The flame is lit!',
        s.lost > 1
            ? 'Fresh start. Your best is ${s.longest} days. Come back tomorrow and beat it.'
            : 'Come back tomorrow for day 2. Every day you finish one quiz, the flame grows.',
      );
    }
    final next = s.nextMilestone;
    return (
      '$n-day streak!',
      next != null
          ? '${next - n} more ${next - n == 1 ? 'day' : 'days'} to your $next-day badge.'
          : 'You show up every single day.',
    );
  }

  String _milestoneLine(int n, StreakStatus s) {
    final left = s.reward.unlocked ? 0 : s.reward.goal - n;
    return switch (n) {
      3 => 'Three days in a row. A habit is forming.',
      7 => 'A full week. Only a few people get here.',
      14 => 'Two weeks of showing up. Seriously impressive.',
      30 => 'A month without missing a day. You\'re unstoppable.',
      _ => left > 0 ? '$left days to unlock 60 AI messages an hour.' : 'Way past the reward. Pure discipline.',
    };
  }

  Future<void> _remind() async {
    final ok = await StreakReminders.instance.enable(widget.status);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? "Reminders on. We'll nudge you before your streak ends."
              : 'Notifications are off for Outstagram in Android settings.',
        ),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final (title, line) = _copy;
    final s = widget.status;
    final scale = CurvedAnimation(parent: _pop, curve: Curves.elasticOut);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (_confetti) const Positioned.fill(child: ConfettiBurst()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(scale: scale, child: const StreakFlame(size: 170)),
                    const SizedBox(height: 4),
                    RollingNumber(
                      value: _shown,
                      style: const TextStyle(fontSize: 84, fontWeight: FontWeight.w900, height: 1, letterSpacing: -2),
                    ),
                    Text(
                      'DAY STREAK',
                      style: const TextStyle(color: Brand.flameYellow, letterSpacing: 4, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      line,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 15, height: 1.35),
                    ),
                    const SizedBox(height: 24),
                    Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          onSurface: Colors.white,
                          onSurfaceVariant: Colors.white70,
                          surfaceContainerHighest: Colors.white12,
                        ),
                      ),
                      child: WeekStrip(status: s, dense: true),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(colors: [Brand.flameOrange, Brand.flameMagenta]),
                        boxShadow: [BoxShadow(color: Brand.flameOrange.withValues(alpha: 0.5), blurRadius: 18)],
                      ),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Keep it going 🔥'),
                      ),
                    ),
                    if (widget.askReminders) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: _remind,
                        icon: const Icon(Icons.notifications_active_rounded),
                        label: const Text("Remind me so I don't lose it"),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
