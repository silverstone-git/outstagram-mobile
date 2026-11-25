import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import 'streak_api.dart';

const flameGradient = [Brand.flameYellow, Brand.flameOrange, Brand.flameRed, Brand.flameMagenta];

// --- the flame -------------------------------------------------------------------------------------

/// An animated, flickering flame. Grey and still when [lit] is false.
class StreakFlame extends StatefulWidget {
  const StreakFlame({super.key, this.size = 48, this.lit = true, this.glow = true});

  final double size;
  final bool lit;
  final bool glow;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.lit) _c.repeat();
  }

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    if (widget.lit && !_c.isAnimating) _c.repeat();
    if (!widget.lit) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(
        size: Size(widget.size * 0.82, widget.size),
        painter: _FlamePainter(t: _c.value, lit: widget.lit, glow: widget.glow),
      ),
    ),
  );
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({required this.t, required this.lit, required this.glow});

  final double t;
  final bool lit;
  final bool glow;

  static Path _shape(Size s, double sway) {
    final w = s.width, h = s.height;
    final tip = w * (0.52 + sway * 0.07);
    return Path()
      ..moveTo(w * 0.5, h)
      ..cubicTo(w * 0.12, h, w * 0.0, h * 0.74, w * 0.1, h * 0.52)
      ..cubicTo(w * 0.18, h * 0.36, w * 0.3, h * 0.3, w * (0.28 + sway * 0.03), h * 0.13)
      ..cubicTo(w * 0.42, h * 0.22, w * 0.46, h * 0.33, w * 0.47, h * 0.42)
      ..cubicTo(w * 0.52, h * 0.22, tip - w * 0.1, h * 0.12, tip, 0)
      ..cubicTo(w * 0.82, h * 0.2, w * 1.0, h * 0.46, w * 0.92, h * 0.68)
      ..cubicTo(w * 0.86, h * 0.92, w * 0.7, h, w * 0.5, h)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * pi;
    final sway = lit ? sin(a) : 0.0;
    final breathe = lit ? 1 + 0.045 * sin(a * 2) : 1.0;
    final w = size.width, h = size.height;

    if (glow && lit) {
      canvas.drawCircle(
        Offset(w / 2, h * 0.68),
        w * (0.55 + 0.04 * sin(a * 3)),
        Paint()
          ..color = Brand.flameOrange.withValues(alpha: 0.38)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    canvas.save();
    canvas.translate(w / 2, h);
    canvas.scale(1, breathe);
    canvas.translate(-w / 2, -h);
    final outer = _shape(size, sway);
    canvas.drawPath(
      outer,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w / 2, h),
          Offset(w / 2, 0),
          lit
              ? const [Brand.flameYellow, Brand.flameOrange, Brand.flameRed, Brand.flameMagenta]
              : [Brand.ash, Brand.ash.withValues(alpha: 0.55)],
          lit ? const [0.0, 0.35, 0.75, 1.0] : null,
        ),
    );

    // inner flame: the same shape, smaller, hotter
    final inner = Size(w * 0.56, h * 0.6);
    canvas.translate(w * 0.22, h * 0.4);
    canvas.drawPath(
      _shape(inner, -sway * 0.8),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(inner.width / 2, inner.height),
          Offset(inner.width / 2, 0),
          lit ? const [Brand.flameCore, Brand.flameYellow] : [Colors.white24, Colors.white10],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.t != t || old.lit != lit;
}

// --- app-bar chip ---------------------------------------------------------------------------------------

/// 🔥 N in the app bar. Pulses when today's quiz is still missing. Opens the streak screen.
class StreakChip extends StatefulWidget {
  const StreakChip({super.key, required this.status});

  final StreakStatus? status;

  @override
  State<StreakChip> createState() => _StreakChipState();
}

class _StreakChipState extends State<StreakChip> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final cs = Theme.of(context).colorScheme;
    final n = s?.current ?? 0;
    final risk = s?.atRisk ?? false;
    final lit = n > 0 && !(s?.broken ?? false);
    if (risk && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!risk && _pulse.isAnimating) _pulse.stop();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Transform.scale(scale: risk ? 1 + 0.06 * _pulse.value : 1, child: child),
        child: Material(
          color: lit ? Brand.flameOrange.withValues(alpha: 0.14) : cs.surfaceContainerHigh,
          shape: StadiumBorder(
            side: BorderSide(
              color: risk
                  ? Brand.flameRed
                  : (s?.todayDone ?? false)
                  ? Brand.gold
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => context.push('/streak'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreakFlame(size: 22, lit: lit, glow: false),
                  const SizedBox(width: 4),
                  Text(
                    '$n',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: lit ? Brand.flameOrange : cs.onSurfaceVariant,
                    ),
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

// --- number that rolls up ---------------------------------------------------------------------------------

class RollingNumber extends StatelessWidget {
  const RollingNumber({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 520),
    switchInCurve: Curves.easeOutBack,
    transitionBuilder: (child, anim) {
      final incoming = child.key == ValueKey(value);
      return ClipRect(
        child: SlideTransition(
          position: Tween(begin: Offset(0, incoming ? 0.8 : -0.8), end: Offset.zero).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
      );
    },
    child: ShaderMask(
      key: ValueKey(value),
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Brand.flameOrange, Brand.flameYellow],
      ).createShader(r),
      child: Text('$value', style: style.copyWith(color: Colors.white)),
    ),
  );
}

// --- confetti ------------------------------------------------------------------------------------------------

/// One burst of confetti from the top centre; plays once.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.count = 150});

  final int count;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Piece {
  _Piece(Random r)
    : angle = -pi / 2 + (r.nextDouble() - 0.5) * pi * 1.15,
      speed = 0.55 + r.nextDouble() * 0.85,
      spin = (r.nextDouble() - 0.5) * 18,
      size = 5 + r.nextDouble() * 7,
      color = const [
        Brand.neon,
        Brand.volt,
        Brand.flameOrange,
        Brand.flameMagenta,
        Brand.logoTeal,
        Brand.gold,
        Brand.flameYellow,
      ][r.nextInt(7)],
      round = r.nextDouble() < 0.3,
      delay = r.nextDouble() * 0.15;

  final double angle, speed, spin, size, delay;
  final Color color;
  final bool round;
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..forward();
  late final _pieces = List.generate(widget.count, (_) => _Piece(Random()));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_pieces, _c.value)),
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.36);
    final scale = size.height;
    for (final p in pieces) {
      final tt = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (tt <= 0) continue;
      final time = tt * 2.6;
      final dx = cos(p.angle) * p.speed * scale * 0.5 * time;
      final dy = sin(p.angle) * p.speed * scale * 0.55 * time + 0.5 * 0.55 * scale * time * time;
      final fade = tt > 0.75 ? (1 - (tt - 0.75) / 0.25) : 1.0;
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(p.spin * time);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2.4, paint);
      } else {
        // a fluttering rectangle: its width shrinks and grows as it turns
        final flutter = cos(p.spin * time * 1.7).abs() * 0.8 + 0.2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size * flutter, height: p.size * 0.5),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// --- week strip ---------------------------------------------------------------------------------------------

/// The last seven days ending today: flames for done days, a pulsing ring for today if pending.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.status, this.dense = false});

  final StreakStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime(status.today.year, status.today.month, status.today.day);
    final d = dense ? 34.0 : 40.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 6; i >= 0; i--)
          Builder(
            builder: (_) {
              final day = today.subtract(Duration(days: i));
              final done = status.done(day);
              final isToday = i == 0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat.E().format(day).substring(0, 1),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                      color: isToday ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (done)
                    Container(
                      width: d,
                      height: d,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Brand.flameYellow, Brand.flameOrange, Brand.flameRed],
                        ),
                        boxShadow: [BoxShadow(color: Brand.flameOrange.withValues(alpha: 0.45), blurRadius: 10)],
                      ),
                      child: Icon(Icons.local_fire_department_rounded, color: Colors.white, size: d * 0.6),
                    )
                  else if (isToday)
                    _PulseRing(size: d)
                  else
                    Container(
                      width: d,
                      height: d,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surfaceContainerHighest),
                      child: Icon(
                        Icons.close_rounded,
                        size: d * 0.4,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.size});

  final double size;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Brand.flameOrange.withValues(alpha: 0.5 + 0.5 * _c.value), width: 2.5),
        boxShadow: [BoxShadow(color: Brand.flameOrange.withValues(alpha: 0.35 * _c.value), blurRadius: 12)],
      ),
      child: Icon(Icons.bolt_rounded, size: widget.size * 0.5, color: Brand.flameOrange),
    ),
  );
}

// --- six-week calendar -----------------------------------------------------------------------------------

class StreakCalendar extends StatelessWidget {
  const StreakCalendar({super.key, required this.status});

  final StreakStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime(status.today.year, status.today.month, status.today.day);
    // columns Mon..Sun, last row holds today
    final end = today.add(Duration(days: 7 - today.weekday));
    final start = end.subtract(const Duration(days: 41));
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat.E().format(start.add(Duration(days: i))).substring(0, 2),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var w = 0; w < 6; w++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final day = start.add(Duration(days: w * 7 + i));
                        final future = day.isAfter(today);
                        final done = status.done(day);
                        final isToday = day == today;
                        return AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: done
                                  ? const LinearGradient(
                                      begin: Alignment.bottomLeft,
                                      end: Alignment.topRight,
                                      colors: [Brand.flameOrange, Brand.flameMagenta],
                                    )
                                  : null,
                              color: done ? null : (future ? Colors.transparent : cs.surfaceContainerHighest),
                              border: isToday ? Border.all(color: Brand.flameOrange, width: 2) : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: done || isToday ? FontWeight.w800 : FontWeight.w500,
                                color: done
                                    ? Colors.white
                                    : (future ? cs.onSurfaceVariant.withValues(alpha: 0.35) : cs.onSurfaceVariant),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// --- 250-day reward ------------------------------------------------------------------------------------------

class RewardCard extends StatelessWidget {
  const RewardCard({super.key, required this.status});

  final StreakStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = status.reward;
    final p = r.unlocked ? 1.0 : (status.current / r.goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(1.6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Brand.gold, Brand.flameOrange, Brand.flameMagenta]),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(18.4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.unlocked ? Icons.workspace_premium_rounded : Icons.card_giftcard_rounded,
                  color: Brand.gold,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.unlocked ? '${r.goal}-day reward unlocked' : 'The ${r.goal}-day reward',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                if (r.unlocked)
                  const Text(
                    'Yours to keep',
                    style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _perk(cs, Icons.bolt_rounded, '${r.aiPromptsPerHour} AI tutor messages every hour'),
            _perk(cs, Icons.forum_rounded, '${r.tutorThreads} saved tutor chats'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (_, c) => Stack(
                children: [
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: p),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Container(
                      height: 12,
                      width: max(12, c.maxWidth * v),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: const LinearGradient(
                          colors: [Brand.flameYellow, Brand.flameOrange, Brand.flameMagenta],
                        ),
                        boxShadow: [BoxShadow(color: Brand.flameOrange.withValues(alpha: 0.5), blurRadius: 8)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              r.unlocked
                  ? 'Earned for good. Keep the flame going anyway 🔥'
                  : '${status.current} / ${r.goal} days · ${r.daysLeft} to go',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _perk(ColorScheme cs, IconData i, String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(i, size: 18, color: Brand.flameOrange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

// --- milestones ------------------------------------------------------------------------------------------------

class MilestoneRow extends StatelessWidget {
  const MilestoneRow({super.key, required this.status});

  final StreakStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final best = max(status.longest, status.current);
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: status.milestones.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final m = status.milestones[i];
          final reached = best >= m;
          final next = m == status.nextMilestone;
          final big = m == status.reward.goal;
          return Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: reached
                      ? LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: big
                              ? const [Brand.flameOrange, Brand.gold]
                              : const [Brand.flameRed, Brand.flameYellow],
                        )
                      : null,
                  color: reached ? null : cs.surfaceContainerHighest,
                  border: next ? Border.all(color: Brand.flameOrange, width: 2) : null,
                  boxShadow: reached
                      ? [BoxShadow(color: Brand.flameOrange.withValues(alpha: 0.4), blurRadius: 10)]
                      : null,
                ),
                alignment: Alignment.center,
                child: reached || next
                    ? Text(
                        '$m',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: m >= 100 ? 17 : 20,
                          color: reached ? Colors.white : Brand.flameOrange,
                        ),
                      )
                    : Icon(Icons.lock_rounded, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 6),
              Text(
                big ? '$m 🎁' : (reached || next ? '$m days' : '$m'),
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ],
          );
        },
      ),
    );
  }
}
