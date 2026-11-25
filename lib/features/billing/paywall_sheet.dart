import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/net/api_error.dart';
import '../tutor/tutor_api.dart';
import 'billing_api.dart';
import 'razorpay_checkout.dart';

/// Why the sheet opened: a server paywall code (`ai_quota`, `tutor_threads`, `tutor_storage`,
/// `media_too_large`, `video_not_allowed`, `posts_limit`) or `manual` (opened from the profile menu).
const _headline = {
  'ai_quota': "You've used this hour's AI prompts",
  'tutor_threads': 'Your tutor history is full',
  'tutor_storage': 'Your tutor history is full',
  'media_too_large': 'That file is too big for your plan',
  'video_not_allowed': 'Videos come with Pro',
  'posts_limit': "You've reached your post limit",
  'manual': 'Outstagram plans',
};

var _open = false;

/// Opens the upgrade sheet for a paywall [ApiException] (or [code] directly). Only one at a time.
/// [needs] (from the server's `detail.needs`) highlights the plan that lifts the limit.
/// Resolves to true if the user bought a pass.
Future<bool> showPaywall(BuildContext context, {String code = 'manual', String? message, String? needs}) async {
  if (_open || !context.mounted) return false;
  _open = true;
  try {
    HapticFeedback.mediumImpact();
    final bought = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PaywallSheet(code: code, message: message, needs: needs),
    );
    return bought ?? false;
  } finally {
    _open = false;
  }
}

/// [showPaywall] for an error from the API; false (and nothing shown) if it isn't a paywall error.
bool showPaywallFor(BuildContext context, Object error) {
  if (error is! ApiException || !error.isPaywall) return false;
  final d = error.detail;
  showPaywall(
    context,
    code: error.code ?? 'manual',
    message: error.message,
    needs: d is Map ? d['needs'] as String? : null,
  );
  return true;
}

class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key, required this.code, this.message, this.needs});

  final String code;
  final String? message;
  final String? needs;

  @override
  ConsumerState<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<PaywallSheet> {
  String? _paying; // plan id being bought
  String? _error;

  @override
  void initState() {
    super.initState();
    // Always fresh: the plan may have changed on the web.
    Future.microtask(() => ref.invalidate(billingStatusProvider));
  }

  bool get _history => widget.code == 'tutor_threads' || widget.code == 'tutor_storage';

  Future<void> _pay(PlanInfo plan) async {
    final color = Theme.of(context).colorScheme.primary;
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    setState(() {
      _paying = plan.id;
      _error = null;
    });
    try {
      final api = ref.read(billingApiProvider);
      final order = await api.order(widget.code, plan: plan.id);
      final result = await openRazorpay(order, themeColor: hex, reason: widget.code);
      if (result == null) return; // backed out of Checkout
      final got = await api.verify(result);
      ref.invalidate(billingStatusProvider);
      ref.read(tutorQuotaProvider.notifier).refresh();
      if (!mounted) return;
      if (got == plan.id) {
        HapticFeedback.heavyImpact();
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        messenger.showSnackBar(SnackBar(content: Text('Welcome to ${plan.short}! Your limits are raised.')));
      } else {
        setState(() => _error = "The payment went through but ${plan.short} isn't active yet. Try again in a minute.");
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _paying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = ref.watch(billingStatusProvider);
    final s = status.value;
    return PopScope(
      canPop: _paying == null,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: cs.primary.withValues(alpha: 0.15),
                child: Icon(Icons.workspace_premium_rounded, color: cs.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(_headline[widget.code] ?? _headline['manual']!, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              widget.message ??
                  (s == null || !s.isPro
                      ? 'More posts, bigger photos, videos and more AI help.'
                      : 'Your ${s.current?.short ?? 'paid'} pass is active.'),
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            switch (status) {
              AsyncData(:final value) => _body(value),
              AsyncError(:final error) => _Note(ApiException.from(error).message),
              _ => Container(
                height: 180,
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
            },
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
            ],
            if (_history) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _paying != null
                    ? null
                    : () {
                        final router = GoRouter.of(context);
                        Navigator.pop(context, false);
                        router.push('/tutor');
                      },
                child: const Text('Delete old tutor chats instead'),
              ),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: _paying != null ? null : () => Navigator.pop(context, false),
              child: Text(s?.upgrades.isEmpty ?? false ? 'Close' : 'Maybe later'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BillingStatus s) {
    final cs = Theme.of(context).colorScheme;
    final small = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final plans = s.plans;
    String videos(Limits l) => !l.videosAllowed ? '—' : fmtLimit(l.videoBytes, fmtBytes);
    final rows = <(String, String Function(Limits))>[
      ('Posts', (l) => fmtLimit(l.posts)),
      ('Photos/videos per post', (l) => fmtLimit(l.mediaPerPost)),
      ('Photo size', (l) => fmtBytes(l.mediaBytes)),
      ('Video size', videos),
      ('AI tutor messages / hour', (l) => fmtLimit(l.aiPromptsPerHour)),
      ('Saved tutor chats', (l) => fmtLimit(l.tutorThreads)),
    ];
    final highlight = widget.needs ?? (s.upgrades.isEmpty ? s.plan : s.upgrades.first.id);
    final until = s.validUntil == null ? '' : ' until ${DateFormat.yMMMd().format(s.validUntil!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.isPro) ...[
          _Note(
            s.upgrades.isEmpty
                ? "You're on ${s.current?.short ?? 'Contributor'}$until, the top plan. Thanks for supporting Outstagram!"
                : "You're on ${s.current?.short ?? 'Pro'}$until.",
            highlight: true,
          ),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: {
              0: const FlexColumnWidth(),
              for (var i = 1; i <= plans.length; i++) i: const IntrinsicColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(color: cs.surfaceContainerHighest),
                children: [
                  const SizedBox(),
                  for (final p in plans)
                    _cell(Column(children: [
                      Text(
                        p.short,
                        style: small.copyWith(
                          color: p.id == highlight ? cs.primary : null,
                          fontWeight: p.id == highlight || p.id == s.plan ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      Text(p.id == 'free' ? '' : p.price.label, style: small.copyWith(fontSize: 11)),
                    ])),
                ],
              ),
              for (final (label, value) in rows)
                TableRow(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
                  children: [
                    _cell(Text(label, style: const TextStyle(fontSize: 12.5)), left: true),
                    for (final p in plans)
                      _cell(Text(
                        value(p.limits),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: p.id == highlight ? FontWeight.w800 : FontWeight.w500,
                          color: p.id == highlight ? null : cs.onSurfaceVariant,
                        ),
                      )),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _Check("Tutor answers grounded in every subject's books"),
        _Check('One payment, no auto-renewal: ${s.price.days} days per pass. Upgrading to Contributor starts it now.'),
        const SizedBox(height: 12),
        if (s.upgrades.isEmpty)
          const SizedBox.shrink()
        else if (!Env.razorpayAllowed)
          const _Note("Passes can't be bought in this version of the app yet.")
        else if (!s.paymentsEnabled)
          const _Note("Payments aren't set up on this server yet.")
        else ...[
          for (final p in s.upgrades) ...[
            p.id == highlight
                ? FilledButton.icon(
                    onPressed: _paying != null ? null : () => _pay(p),
                    icon: _paying == p.id ? const _Spinner() : const Icon(Icons.auto_awesome_rounded),
                    label: Text('Get ${p.short} · ${p.price.label}'),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: _paying != null ? null : () => _pay(p),
                    icon: _paying == p.id ? const _Spinner() : const Icon(Icons.workspace_premium_outlined),
                    label: Text('Get ${p.short} · ${p.price.label}'),
                  ),
            const SizedBox(height: 8),
          ],
          Text.rich(
            TextSpan(
              style: small,
              children: [
                const TextSpan(text: 'By paying you agree to the '),
                _link('Terms', 'terms'),
                const TextSpan(text: ' and '),
                _link('Refund policy', 'refunds'),
                const TextSpan(text: ' (full refund within 7 days).'),
              ],
            ),
          ),
          if (s.testMode) ...[
            const SizedBox(height: 8),
            Text(
              'Test mode: no real money moves. Pick Netbanking, any bank, then Success (or Failure) '
              'on the demo bank page. Test card: 4111 1111 1111 1111, any future date and CVV.',
              style: small,
            ),
          ],
        ],
      ],
    );
  }

  InlineSpan _link(String label, String page) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: GestureDetector(
      onTap: () => launchUrl(Uri.parse('${Env.webBase}/$page/'), mode: LaunchMode.externalApplication),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  );

  Widget _cell(Widget child, {bool left = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: Align(alignment: left ? Alignment.centerLeft : Alignment.centerRight, child: child),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5));
}

class _Check extends StatelessWidget {
  const _Check(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? cs.primary.withValues(alpha: 0.1) : cs.surfaceContainerHighest,
        border: highlight ? Border.all(color: cs.primary.withValues(alpha: 0.4)) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(fontSize: 14, color: highlight ? null : cs.onSurfaceVariant)),
    );
  }
}
