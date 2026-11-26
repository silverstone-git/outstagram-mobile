import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/net/api_error.dart';
import '../account/verify_gate.dart';
import '../billing/paywall_sheet.dart';
import '../../core/ui/math_text.dart';
import '../exams/exam_api.dart';
import '../../core/ui/equation_menu.dart';
import 'ai_options.dart';
import 'models.dart';
import 'tutor_api.dart';
import 'tutor_markdown.dart';

const _suggestions = [
  'Why is my answer wrong?',
  'Walk me through the solution',
  'What concept is this testing?',
  'Give me a similar practice question',
];

/// What the chat header shows; passed as the route's `extra` when the caller already has it.
class TutorQuestion {
  const TutorQuestion({required this.text, this.topic, this.examTitle});
  final String text;
  final String? topic;
  final String? examTitle;
}

String tutorPath(String attemptId, String questionId) =>
    '/tutor/${Uri.encodeComponent(attemptId)}/${Uri.encodeComponent(questionId)}';

/// `/tutor/:attemptId/:questionId`: the AI tutor for one question of a saved attempt
/// (parity with outstagram-web `QuestionChat.tsx`).
class TutorChatScreen extends ConsumerStatefulWidget {
  const TutorChatScreen({
    super.key,
    required this.attemptId,
    required this.questionId,
    this.question,
    this.focusLatex,
    this.focusMessageId,
  });

  final String attemptId;
  final String questionId;
  final TutorQuestion? question;

  /// Opened from "Saved equations": scroll to this equation (in reply [focusMessageId]) and pulse it.
  final String? focusLatex;
  final int? focusMessageId;

  @override
  ConsumerState<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends ConsumerState<TutorChatScreen> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  final _stt = SpeechToText();

  bool _loading = true;
  bool _busy = false;
  String? _status;
  String? _error;
  List<String> _chosen = const [];
  bool _skillsPicked = false; // the user changed them; don't re-guess
  CancelToken? _cancel;
  Timer? _paint;
  bool _listening = false;
  String _beforeVoice = '';

  @override
  void initState() {
    super.initState();
    _load();
    ref.read(tutorQuotaProvider.notifier).refresh();
    _draft.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cancel?.cancel('left the chat');
    _paint?.cancel();
    if (_listening) _stt.stop();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await ref.read(tutorApiProvider).chat(widget.attemptId, widget.questionId);
      if (!mounted) return;
      setState(() => _messages.addAll(m));
      if (widget.focusLatex == null) _toBottom(jump: true); // else the equation scrolls itself into view
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  /// Follow the stream only while the user is at (or near) the bottom.
  bool get _nearBottom => !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 120;

  /// Deltas arrive every few ms; repaint at most ~16×/s.
  void _schedulePaint() {
    if (_paint?.isActive ?? false) return;
    _paint = Timer(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      final follow = _nearBottom;
      setState(() {});
      if (follow) _toBottom(jump: true);
    });
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _busy) return;
    final quota = ref.read(tutorQuotaProvider);
    if (quota != null && quota.isOut) {
      setState(() => _error = "You've used all ${quota.limit} AI prompts for this hour.${quota.resetHint}");
      if (quota.upgradeTo != null) {
        showPaywall(context, code: 'ai_quota', message: "You've used all your AI prompts for this hour.",
            needs: quota.upgradeTo);
      } else {
        HapticFeedback.heavyImpact();
      }
      return;
    }
    FocusScope.of(context).unfocus();
    if (_listening) await _stt.stop();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    final user = ChatMessage(role: 'user', content: msg);
    final bot = ChatMessage(role: 'assistant', content: '');
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
      _draft.clear();
      _messages.addAll([user, bot]);
    });
    _toBottom();
    final cancel = _cancel = CancelToken();
    try {
      final stream = ref
          .read(tutorApiProvider)
          .ask(
            widget.attemptId,
            widget.questionId,
            msg,
            skills: _chosen,
            choice: ref.read(tutorPrefsProvider).choice(ref.read(aiOptionsProvider).value),
            cancel: cancel,
          );
      await for (final ev in stream) {
        if (!mounted) return;
        switch (ev) {
          case TutorStatus(:final text):
            setState(() => _status = text);
          case TutorMeta(:final citations, :final model):
            bot.citations = citations;
            bot.model = model;
            _status = null;
            _schedulePaint();
          case TutorDelta(:final text):
            bot.content += text;
            _status = null;
            _schedulePaint();
          case TutorDone(:final message, :final quota, :final model):
            bot.content = message.content;
            bot.citations = message.citations;
            bot.id = message.id;
            bot.model = model ?? bot.model;
            if (quota != null && !quota.byok) ref.read(tutorQuotaProvider.notifier).set(quota); // BYOK: own cap
        }
      }
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted || cancel.isCancelled) return;
      final err = ApiException.from(e is TutorStreamError ? ApiException(e.message) : e);
      final detail = err.detail;
      var byokOut = false;
      if (err.code == 'ai_quota' && detail is Map && detail['quota'] is Map) {
        final q = Quota.fromJson(Map<String, dynamic>.from(detail['quota'] as Map));
        byokOut = q.byok;
        if (!q.byok) ref.read(tutorQuotaProvider.notifier).set(q);
      }
      final q = ref.read(tutorQuotaProvider);
      setState(() {
        _messages.removeRange(_messages.length - 2, _messages.length);
        _draft.text = msg;
        _error = byokOut
            ? 'Your own-key prompts for this hour are used up.'
            : err.code == 'ai_quota'
            ? '${err.message}${q?.resetHint ?? ''}'
            : err.message;
      });
      if (!showPaywallFor(context, err)) showVerifyEmailFor(context, err);
    } finally {
      _paint?.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
        if (_nearBottom) _toBottom();
      }
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  /// Long-press an equation in a reply: the equation menu (save remembers this reply).
  void _equation(PickedEquation eq, ChatMessage m, TutorQuestion? q) => showEquationMenu(
    context,
    ref,
    eq.latex,
    eq.display,
    EquationSource(
      source: 'tutor',
      attemptId: widget.attemptId,
      questionId: widget.questionId,
      messageId: m.id,
      skill: _chosen.firstOrNull,
      context: q == null ? null : (q.text.length > 300 ? q.text.substring(0, 300) : q.text),
    ),
  );

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await _stt.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
      },
      onError: (e) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice input needs microphone access and a speech service on this phone.')),
      );
      return;
    }
    HapticFeedback.lightImpact();
    _beforeVoice = _draft.text.trim().isEmpty ? '' : '${_draft.text.trim()} ';
    setState(() => _listening = true);
    await _stt.listen(
      onResult: (r) {
        _draft.value = TextEditingValue(
          text: '$_beforeVoice${r.recognizedWords}',
          selection: TextSelection.collapsed(offset: '$_beforeVoice${r.recognizedWords}'.length),
        );
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 4),
      ),
    );
  }

  void _toggleSkill(String s) {
    HapticFeedback.selectionClick();
    setState(() {
      _skillsPicked = true;
      if (_chosen.contains(s)) {
        if (_chosen.length > 1) _chosen = [..._chosen]..remove(s);
      } else {
        final next = [..._chosen, s];
        _chosen = next.length > 5 ? next.sublist(next.length - 5) : next;
      }
    });
  }

  Future<void> _openLink(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final question = widget.question ?? _questionFromAttempt();
    final skills = ref.watch(tutorSkillsProvider).value;
    if (skills != null && !_skillsPicked && _chosen.isEmpty) {
      _chosen = [skills.guess(question?.topic)];
    }
    final quota = ref.watch(tutorQuotaProvider);
    final out = quota?.isOut ?? false;
    final last = _messages.lastOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI tutor', style: TextStyle(fontWeight: FontWeight.w800)),
            if (question?.examTitle?.isNotEmpty ?? false)
              Text(
                question!.examTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Model, thinking, your own API key',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showTutorSettings(context),
          ),
          IconButton(
            tooltip: 'Tutor library',
            icon: const Icon(Icons.collections_bookmark_outlined),
            onPressed: () => context.push('/tutor'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (question != null) _QuestionHeader(question: question),
          if (ref.watch(tutorPrefsProvider).label(ref.watch(aiOptionsProvider).value) case final who?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: ActionChip(
                avatar: const Icon(Icons.tune_rounded, size: 16),
                label: Text(who),
                visualDensity: VisualDensity.compact,
                onPressed: () => showTutorSettings(context),
              ),
            ),
          if (skills != null && skills.skills.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.menu_book_rounded, size: 18, color: cs.onSurfaceVariant),
                  ),
                  for (final s in skills.skills)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(s.title),
                        selected: _chosen.contains(s.skill),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: _busy ? null : (_) => _toggleSkill(s.skill),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: _scroll,
                    // jumping to a saved equation: build every reply so it can scroll itself into view
                    // scrollCacheExtent replaces this; switch with the material_ui migration (docs/TODO.md §9)
                    // ignore: deprecated_member_use
                    cacheExtent: widget.focusLatex != null ? 100000 : null,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    children: [
                      if (_messages.isEmpty) _Intro(chosen: _chosen, busy: _busy, onPick: _send),
                      for (final m in _messages)
                        if (!(m == last && !m.isUser && m.content.isEmpty && _busy))
                          _Bubble(
                            message: m,
                            onPickEquation: (eq) => _equation(eq, m, question),
                            onTapLink: _openLink,
                            highlight: widget.focusLatex != null &&
                                    (widget.focusMessageId == null || widget.focusMessageId == m.id)
                                ? widget.focusLatex
                                : null,
                          ),
                      if (_busy && (last?.content.isEmpty ?? true))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            children: [
                              const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 10),
                              Text(_status ?? 'Thinking…', style: TextStyle(color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          _Composer(
            controller: _draft,
            busy: _busy,
            out: out,
            listening: _listening,
            error: _error,
            quota: quota,
            onSend: () => _send(_draft.text),
            onVoice: _busy ? null : _toggleVoice,
          ),
        ],
      ),
    );
  }

  TutorQuestion? _questionFromAttempt() {
    final a = ref.watch(attemptProvider(widget.attemptId)).value;
    if (a == null) return null;
    final q = a.result.originalQuestions.where((q) => q.id == widget.questionId).firstOrNull;
    if (q == null) return TutorQuestion(text: '', examTitle: a.summary.title);
    return TutorQuestion(text: q.question, topic: q.topic, examTitle: a.summary.title);
  }
}

class _QuestionHeader extends StatefulWidget {
  const _QuestionHeader({required this.question});
  final TutorQuestion question;

  @override
  State<_QuestionHeader> createState() => _QuestionHeaderState();
}

class _QuestionHeaderState extends State<_QuestionHeader> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = widget.question;
    if (q.text.isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: _open ? MediaQuery.sizeOf(context).height * 0.4 : double.infinity),
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (q.topic != null)
                      Text(
                        q.topic!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    MathText(q.text, maxLines: _open ? null : 2, style: const TextStyle(fontSize: 14, height: 1.35)),
                  ],
                ),
              ),
            ),
            Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.chosen, required this.busy, required this.onPick});

  final List<String> chosen;
  final bool busy;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final books = chosen.isEmpty ? 'subject' : chosen.map((c) => c.replaceAll('-', ' ')).join(' + ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ask anything about this question. Answers are grounded in the $books books. '
                  'Long-press an equation to save it.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _suggestions) ActionChip(label: Text(s), onPressed: busy ? null : () => onPick(s)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onPickEquation, required this.onTapLink, this.highlight});

  final ChatMessage message;
  final String? highlight;
  final ValueChanged<PickedEquation> onPickEquation;
  final void Function(String) onTapLink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = message;
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(m.content, style: TextStyle(color: cs.onPrimary, fontSize: 15, height: 1.35)),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TutorMarkdown(m.content, onPickEquation: onPickEquation, onTapLink: onTapLink, highlight: highlight),
          if (m.model != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(m.model!, style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
            ),
          if (m.citations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 6),
            for (final (j, c) in m.citations.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(Icons.menu_book_outlined, size: 14, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: MathText(
                        '[${c.n ?? j + 1}] ${c.title}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (m.content.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Copy answer',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                color: cs.onSurfaceVariant,
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: m.content));
                  HapticFeedback.lightImpact();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.out,
    required this.listening,
    required this.error,
    required this.quota,
    required this.onSend,
    required this.onVoice,
  });

  final TextEditingController controller;
  final bool busy;
  final bool out;
  final bool listening;
  final String? error;
  final Quota? quota;
  final VoidCallback onSend;
  final VoidCallback? onVoice;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = quota;
    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Text(error!, style: TextStyle(color: cs.error, fontSize: 13)),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: listening ? 'Stop listening' : 'Ask by voice',
                    onPressed: onVoice,
                    color: listening ? cs.primary : cs.onSurfaceVariant,
                    icon: Icon(listening ? Icons.mic_rounded : Icons.mic_none_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: listening ? 'Listening…' : (out ? 'Hourly AI limit reached' : 'Ask the tutor…'),
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: busy || controller.text.trim().isEmpty ? null : onSend,
                    icon: busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
              if (q != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    q.pill,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: q.isOut ? cs.error : cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
