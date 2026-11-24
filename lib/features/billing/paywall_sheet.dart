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
/// `media_too_large`) or `manual` (opened from the profile menu).
const _headline = {
  'ai_quota': "You've used this hour's AI prompts",
  'tutor_threads': 'Your tutor history is full',
  'tutor_storage': 'Your tutor history is full',
  'media_too_large': 'That file is too big for the free plan',
  'manual': 'Outstagram Pro',
};

var _open = false;

/// Opens the upgrade sheet for a paywall [ApiException] (or [code] directly). Only one at a time.
/// Resolves to true if the user bought Pro.
Future<bool> showPaywall(BuildContext context, {String code = 'manual', String? message}) async {
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
      builder: (_) => PaywallSheet(code: code, message: message),
    );
    return bought ?? false;
  } finally {
    _open = false;
  }
}

/// [showPaywall] for an error from the API; false (and nothing shown) if it isn't a paywall error.
bool showPaywallFor(BuildContext context, Object error) {
  if (error is! ApiException || !error.isPaywall) return false;
  showPaywall(context, code: error.code ?? 'manual', message: error.message);
  return true;
}

class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key, required this.code, this.message});

  final String code;
  final String? message;

  @override
  ConsumerState<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<PaywallSheet> {
  var _paying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Always fresh: the plan may have changed on the web.
    Future.microtask(() => ref.invalidate(billingStatusProvider));
  }

  bool get _history => widget.code == 'tutor_threads' || widget.code == 'tutor_storage';

  Future<void> _pay(BillingStatus s) async {
    final color = Theme.of(context).colorScheme.primary;
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final api = ref.read(billingApiProvider);
      final order = await api.order(widget.code);
      final result = await openRazorpay(order, themeColor: hex, reason: widget.code);
      if (result == null) return; // backed out of Checkout
      final plan = await api.verify(result);
      ref.invalidate(billingStatusProvider);
      ref.read(tutorQuotaProvider.notifier).refresh();
      if (!mounted) return;
      if (plan == 'pro') {
        HapticFeedback.heavyImpact();
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        messenger.showSnackBar(const SnackBar(content: Text('Welcome to Pro! Your limits are raised.')));
      } else {
        setState(() => _error = "The payment went through but Pro isn't active yet. Pull to refresh in a minute.");
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = ref.watch(billingStatusProvider);
    final isPro = status.value?.isPro ?? false;
    return PopScope(
      canPop: !_paying,
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
              widget.message ?? (isPro ? 'Your Pro pass is active.' : 'Upgrade to Pro for higher limits.'),
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
                onPressed: _paying
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
              onPressed: _paying ? null : () => Navigator.pop(context, false),
              child: Text(isPro ? 'Close' : 'Maybe later'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BillingStatus s) {
    final cs = Theme.of(context).colorScheme;
    if (s.isPro) {
      final until = s.validUntil == null ? '' : ' until ${DateFormat.yMMMd().format(s.validUntil!)}';
      return _Note(
        widget.code == 'manual'
            ? "You're on Pro$until. Thanks for supporting Outstagram!"
            : "You're on Pro$until and reached even the Pro limit. It resets soon.",
        highlight: true,
      );
    }
    final f = s.freeLimits, p = s.proLimits;
    final rows = [
      ('AI tutor prompts / hour', '${f.aiPromptsPerHour}', '${p.aiPromptsPerHour}'),
      ('Saved tutor chats', '${f.tutorThreads}', '${p.tutorThreads}'),
      ('Tutor history storage', fmtBytes(f.tutorBytes), fmtBytes(p.tutorBytes)),
      ('Photo / video size', fmtBytes(f.mediaBytes), fmtBytes(p.mediaBytes)),
    ];
    final small = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: const {0: FlexColumnWidth(), 1: IntrinsicColumnWidth(), 2: IntrinsicColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(color: cs.surfaceContainerHighest),
                children: [
                  const SizedBox(),
                  _cell(Text('Free', style: small)),
                  _cell(Text('Pro', style: small.copyWith(color: cs.primary, fontWeight: FontWeight.w600))),
                ],
              ),
              for (final (label, free, pro) in rows)
                TableRow(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
                  children: [
                    _cell(Text(label, style: const TextStyle(fontSize: 13)), left: true),
                    _cell(Text(free, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
                    _cell(Text(pro, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Check('Tutor answers grounded in every subject\'s books'),
        _Check('One payment, no auto-renewal: ${s.price.days} days of Pro'),
        const SizedBox(height: 16),
        if (!Env.razorpayAllowed)
          const _Note('Pro can\'t be bought in this version of the app yet.')
        else if (!s.paymentsEnabled)
          const _Note("Payments aren't set up on this server yet.")
        else ...[
          FilledButton.icon(
            onPressed: _paying ? null : () => _pay(s),
            icon: _paying
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.auto_awesome_rounded),
            label: Text('Pay ${s.price.label} with Razorpay'),
          ),
          const SizedBox(height: 10),
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
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Align(alignment: left ? Alignment.centerLeft : Alignment.centerRight, child: child),
  );
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
