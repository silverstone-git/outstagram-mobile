import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/net/api_error.dart';
import '../../core/platform.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/math_text.dart';
import '../exams/exams_home_screen.dart' show compactButton;
import 'models.dart';
import 'tutor_api.dart';
import 'tutor_chat_screen.dart';

String _kb(int b) => b >= 1000000 ? '${(b / 1000000).toStringAsFixed(1)} MB' : '${(b / 1000).round().clamp(1, 999)} kB';

/// `/tutor`: saved tutor chats (one per exam question) and saved equations
/// (parity with outstagram-web `TutorLibrary.tsx`).
class TutorLibraryScreen extends StatelessWidget {
  const TutorLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          // Opened from the launcher shortcut there's nothing to pop back to: go to the Exams tab.
          leading: context.canPop()
              ? null
              : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/exams')),
          title: const Text('Tutor library'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chats'),
              Tab(text: 'Equations'),
            ],
          ),
        ),
        body: const TabBarView(children: [_Chats(), _Equations()]),
      ),
    );
  }
}

class _Chats extends ConsumerWidget {
  const _Chats();

  Future<void> _delete(BuildContext context, WidgetRef ref, ChatThread t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this tutor chat?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: compactButton, onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tutorApiProvider).deleteThread(t.attemptId, t.questionId);
      HapticFeedback.mediumImpact();
      ref.invalidate(tutorThreadsProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(tutorThreadsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(tutorThreadsProvider.future).catchError((_) => const ThreadList([], ThreadUsage(threads: 0, bytes: 0, maxThreads: 0, maxBytes: 0, plan: 'free'))),
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(ApiException.from(e).message))),
          ],
        ),
        data: (d) {
          final u = d.usage;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${u.threads}/${u.maxThreads} chats · ${_kb(u.bytes)} of ${_kb(u.maxBytes)}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                          Text(
                            u.plan == 'pro' ? 'Pro' : 'Free plan',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: u.fill,
                          minHeight: 6,
                          color: u.fill >= 1 ? cs.error : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (d.threads.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No tutor chats yet. Open a finished exam and tap "Ask the AI tutor" on a question.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              for (final t in d.threads)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push(
                      tutorPath(t.attemptId, t.questionId),
                      extra: TutorQuestion(text: t.question, topic: t.topic, examTitle: t.examTitle),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.chat_bubble_outline_rounded, size: 14, color: cs.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        [
                                          if (t.examTitle.isNotEmpty) t.examTitle,
                                          '${t.messages} msgs',
                                          if (t.lastAt != null) DateFormat.MMMd().format(t.lastAt!),
                                        ].join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                MathText(
                                  t.question.isEmpty ? '(question)' : t.question,
                                  maxLines: 2,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete chat',
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: cs.onSurfaceVariant,
                            onPressed: () => _delete(context, ref, t),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Where a saved equation came from, as a route that scrolls to it and pulses it; null if unknown.
String? equationLocation(FavoriteEquation f) {
  final eq = Uri.encodeQueryComponent(f.latex);
  if (f.source == 'post' && f.postId != null) return '/p/${Uri.encodeComponent(f.postId!)}?eq=$eq';
  if (f.attemptId == null || f.questionId == null) return null;
  if (f.source == 'question' || f.source == 'option' || f.source == 'explanation') {
    return '/exam/attempt/${Uri.encodeComponent(f.attemptId!)}?q=${Uri.encodeQueryComponent(f.questionId!)}&eq=$eq';
  }
  return '${tutorPath(f.attemptId!, f.questionId!)}?eq=$eq${f.messageId != null ? '&mid=${f.messageId}' : ''}';
}

class _Equations extends ConsumerWidget {
  const _Equations();

  /// Deletes right away (one tap, like the rest of the list) with an Undo that saves it again.
  Future<void> _remove(BuildContext context, WidgetRef ref, FavoriteEquation f) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(tutorApiProvider);
    try {
      await api.deleteFavorite(f.id);
      HapticFeedback.lightImpact();
    } catch (e) {
      if (context.mounted) showError(context, e);
      return;
    } finally {
      ref.invalidate(favoriteEquationsProvider);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Equation removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await api.addFavorite(latex: f.latex, display: f.display, skill: f.skill, context: f.context,
                  attemptId: f.attemptId, questionId: f.questionId, messageId: f.messageId, postId: f.postId, source: f.source);
            } catch (_) {}
            ref.invalidate(favoriteEquationsProvider);
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(favoriteEquationsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(favoriteEquationsProvider.future).catchError((_) => <FavoriteEquation>[]),
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(ApiException.from(e).message))),
          ],
        ),
        data: (favs) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (favs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.star_outline_rounded, color: cs.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text(
                      'Long-press any equation in a tutor answer, an exam review or a post to save it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            for (final f in favs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: equationLocation(f) == null ? null : () => context.push(equationLocation(f)!),
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Math.tex(
                          f.latex,
                          mathStyle: f.display ? MathStyle.display : MathStyle.text,
                          textStyle: const TextStyle(fontSize: 17),
                          onErrorFallback: (_) => Text(f.latex),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                if (f.from.isNotEmpty) f.from,
                                if (f.skill != null) f.skill!.replaceAll('-', ' '),
                                if (f.context != null) f.context!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                          if (equationLocation(f) case final loc?)
                            IconButton(
                              tooltip: 'Open where you saved it',
                              icon: const Icon(Icons.open_in_new_rounded, size: 20),
                              color: cs.onSurfaceVariant,
                              onPressed: () => context.push(loc),
                            ),
                          IconButton(
                            tooltip: 'Copy LaTeX',
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            color: cs.onSurfaceVariant,
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: f.latex));
                              if (!systemConfirmsCopy) {
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(const SnackBar(content: Text('LaTeX copied')));
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline_rounded, size: 20),
                            color: cs.onSurfaceVariant,
                            onPressed: () => _remove(context, ref, f),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
