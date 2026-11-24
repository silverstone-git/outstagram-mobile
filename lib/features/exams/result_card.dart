import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../core/config/env.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/feedback.dart';
import '../auth/brand_mark.dart';
import '../compose/compose_draft.dart';
import '../feed/models.dart';
import 'engine/models.dart';
import 'exams_home_screen.dart' show fmtScore;

/// The numbers a result card shows, computed once from an [ExamResult].
class ResultSummary {
  ResultSummary(this.r, this.maxScore)
    : skipped = r.originalQuestions.where((q) {
        final a = r.answers.where((a) => a.questionId == q.id).firstOrNull;
        return !(a?.isAttempted ?? false);
      }).length,
      // only topics worth showing off: some correct answers
      bestTopics = (r.accuracyPerTopic.entries.where((e) => e.value > 0).toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(3)
          .toList();

  final ExamResult r;
  final double maxScore;
  final int skipped;
  final List<MapEntry<String, double>> bestTopics;

  int get wrong => r.originalQuestions.length - r.correctAnswers - skipped;
  double get pct => maxScore > 0 ? (r.score / maxScore).clamp(0.0, 1.0) : r.accuracy / 100;
  int get percent => (pct * 100).round();

  String get caption {
    final total = r.originalQuestions.length;
    // "7/10 correct" only adds information when marks aren't one per question
    final correct = fmtScore(r.score) == '${r.correctAnswers}' && fmtScore(maxScore) == '$total'
        ? ''
        : ', ${r.correctAnswers}/$total correct';
    return 'Scored ${fmtScore(r.score)}/${fmtScore(maxScore)} ($percent%) on ${r.examName}$correct. '
        '#outstagram #practice';
  }
}

/// The shareable result image: 4:5 (fits Instagram feed and Stories), always in the dark logo colours
/// whatever the app theme. Laid out at 360×450 and captured at 3× (1080×1350 px).
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.s});

  static const size = Size(360, 450);

  final ResultSummary s;

  static const _dim = TextStyle(color: Brand.lavender, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final r = s.r;
    return MediaQuery(
      // fixed layout: ignore the user's text scaling so the image always looks the same
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox.fromSize(
        size: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF181A38), Brand.logoNavy, Color(0xFF0A0A16)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -80,
                top: -80,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Brand.logoGreen.withValues(alpha: 0.22), Brand.logoGreen.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Theme(
                      data: ThemeData(
                        colorScheme: const ColorScheme.dark(onSurface: Colors.white, primary: Brand.logoGreen),
                      ),
                      child: const BrandMark(size: 20),
                    ),
                    const SizedBox(height: 22),
                    const Text('EXAM RESULT', style: _dim),
                    const SizedBox(height: 4),
                    Text(
                      r.examName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700, height: 1.2),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _Ring(pct: s.pct, label: '${s.percent}%'),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('SCORE', style: _dim),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: fmtScore(r.score),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 44,
                                          fontWeight: FontWeight.w900,
                                          height: 1.05,
                                        ),
                                      ),
                                      TextSpan(
                                        text: ' / ${fmtScore(s.maxScore)}',
                                        style: const TextStyle(color: Brand.lavender, fontSize: 18),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _Pill('${r.correctAnswers}', 'correct', Brand.logoGreen),
                        const SizedBox(width: 8),
                        _Pill('${s.wrong}', 'wrong', const Color(0xFFFF5C7A)),
                        const SizedBox(width: 8),
                        _Pill('${s.skipped}', 'skipped', Brand.lavender),
                      ],
                    ),
                    if (s.bestTopics.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text('STRONGEST TOPICS', style: _dim),
                      const SizedBox(height: 6),
                      for (final t in s.bestTopics)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ),
                              Text(
                                '${(t.value * 100).round()}%',
                                style: const TextStyle(
                                  color: Brand.logoGreen,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(r.date)),
                          style: const TextStyle(color: Brand.lavender, fontSize: 11),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              'STUDY SMARTER WITH AI',
                              style: TextStyle(color: Brand.lavender, fontSize: 9.5, letterSpacing: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.pct, required this.label});

  final double pct;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 96,
    child: CustomPaint(
      painter: _RingPainter(pct),
      child: Center(
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.pct);

  final double pct;

  static const _start = -1.5708; // 12 o'clock
  static const _full = 6.2832;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      _full,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    if (pct <= 0) return;
    canvas.drawArc(
      rect,
      _start,
      _full * pct,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [Brand.logoLime, Brand.logoGreen, Brand.logoTeal, Brand.logoLime],
          transform: GradientRotation(_start),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

class _Pill extends StatelessWidget {
  const _Pill(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Brand.lavender, fontSize: 10.5)),
        ],
      ),
    ),
  );
}

/// Preview sheet with the card, "Share image" (any app) and "Post to your feed" (prefilled composer).
Future<void> showResultCardSheet(BuildContext context, ExamResult r, double maxScore) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ResultCardSheet(s: ResultSummary(r, maxScore)),
);

class ResultCardSheet extends ConsumerStatefulWidget {
  const ResultCardSheet({super.key, required this.s});

  final ResultSummary s;

  @override
  ConsumerState<ResultCardSheet> createState() => _ResultCardSheetState();
}

class _ResultCardSheetState extends ConsumerState<ResultCardSheet> {
  final _key = GlobalKey();
  var _busy = false;

  Future<Uint8List> _png() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1080 / ResultCard.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) showError(context, e is ApiException ? e : ApiException('Could not make the card: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _run(() async {
    final png = await _png();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/outstagram-result-${widget.s.r.id}.png');
    await file.writeAsBytes(png, flush: true);
    HapticFeedback.mediumImpact();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: '${widget.s.caption}\n${Env.webBase}/'),
    );
  });

  Future<void> _post() => _run(() async {
    final png = await _png();
    ref
        .read(composeDraftProvider.notifier)
        .set(ComposeDraft(images: [png], caption: widget.s.caption, category: PostCategory.examResult));
    if (!mounted) return;
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.go('/create');
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: FittedBox(
              child: RepaintBoundary(key: _key, child: ResultCard(s: widget.s)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('Share image'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _post,
          icon: const Icon(Icons.dynamic_feed_rounded),
          label: const Text('Post to your feed'),
        ),
      ],
    ),
  );
}
