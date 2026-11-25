import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/api_error.dart';
import '../../core/ui/feedback.dart';
import 'engine/engine.dart';
import 'exam_session.dart';

/// The theme's filled buttons are full-width (Size.fromHeight); dialogs and rows need a compact one.
final compactButton = FilledButton.styleFrom(minimumSize: const Size(64, 44));

/// Starts an exam: asks before discarding an unfinished one, loads it ([onLoading] true/false around
/// the download), then opens the runner. Returns once the runner is closed.
Future<void> launchExam(
  BuildContext context,
  WidgetRef ref,
  Future<ExamConfig> Function() load, {
  String? examId,
  void Function(bool loading)? onLoading,
}) async {
  final saved = await ref.read(savedSessionProvider.future);
  if (saved != null && context.mounted) {
    final replace = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard your unfinished exam?'),
        content: Text('"${saved.config.name}" is still in progress. Starting a new exam discards it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(style: compactButton, onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
        ],
      ),
    );
    if (replace != true) return;
  }
  onLoading?.call(true);
  try {
    final config = await load();
    final n = normalizeExamConfig(config).sections!.fold(0, (a, s) => a + s.questions.length);
    if (n == 0) throw ApiException('No questions could be loaded for this exam. Try again in a moment.');
    ref.read(examSessionProvider.notifier).start(config, examId: examId);
    HapticFeedback.mediumImpact();
    onLoading?.call(false);
    if (context.mounted) await context.push('/exam/run');
  } catch (e) {
    if (context.mounted) showError(context, e);
  } finally {
    onLoading?.call(false);
    ref.invalidate(savedSessionProvider);
  }
}
