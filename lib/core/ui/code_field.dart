import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Six (or [length]) digit boxes over one hidden text field: the keyboard's suggestion strip and
/// Android autofill fill it, paste works, and [onCompleted] fires as soon as every box is filled.
class CodeField extends StatefulWidget {
  const CodeField({
    super.key,
    required this.onCompleted,
    this.length = 6,
    this.enabled = true,
    this.error = false,
    this.controller,
    this.autofocus = true,
  });

  final ValueChanged<String> onCompleted;
  final int length;
  final bool enabled;
  final bool error;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  late final TextEditingController _c = widget.controller ?? TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    if (widget.controller == null) _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    final v = _c.text;
    if (v.length == widget.length) {
      HapticFeedback.lightImpact();
      widget.onCompleted(v);
    }
  }

  Future<void> _paste() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= widget.length) _c.text = digits.substring(0, widget.length);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = _c.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 62,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < widget.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: _box(cs, i < text.length ? text[i] : '', i == text.length && _focus.hasFocus)),
                  ],
                ],
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _c,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: widget.length,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(counterText: '', filled: false, border: InputBorder.none),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.enabled ? _paste : null,
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: const Text('Paste code'),
          ),
        ),
      ],
    );
  }

  Widget _box(ColorScheme cs, String ch, bool active) {
    final border = widget.error
        ? cs.error
        : active
        ? cs.primary
        : ch.isNotEmpty
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: active || widget.error ? 2 : 1.2),
      ),
      alignment: Alignment.center,
      child: AnimatedScale(
        scale: ch.isEmpty ? 0.6 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: Text(
          ch,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface),
        ),
      ),
    );
  }
}

/// "Resend code" that waits [seconds] between sends.
class ResendButton extends StatefulWidget {
  const ResendButton({super.key, required this.onResend, this.seconds = 60});

  final Future<void> Function() onResend;
  final int seconds;

  @override
  State<ResendButton> createState() => _ResendButtonState();
}

class _ResendButtonState extends State<ResendButton> {
  late int _left = widget.seconds;
  Timer? _t;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left = (_left - 1).clamp(0, widget.seconds));
      if (_left == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: _left > 0 || _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await widget.onResend();
              if (!mounted) return;
              setState(() => _left = widget.seconds);
              _tick();
            } catch (_) {
              // the caller showed the error; the button stays available
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
    child: Text(_left > 0 ? 'Resend code in ${_left}s' : 'Resend code'),
  );
}
