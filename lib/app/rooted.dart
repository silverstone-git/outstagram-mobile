import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A detail page opened from outside the app (App Link, home-screen widget, launcher shortcut, notification)
/// is the only page on the stack: no back arrow, and BACK closes the app (QA 2026-11-25). When that happens
/// this puts the feed underneath and pushes the page again, so back goes to the tabs like any in-app visit.
/// Pages opened from inside the app are left alone.
class Rooted extends StatefulWidget {
  const Rooted({super.key, required this.location, required this.child});

  /// The page's own location (`state.uri.toString()`), pushed again on top of the feed.
  final String location;
  final Widget child;

  @override
  State<Rooted> createState() => _RootedState();
}

class _RootedState extends State<Rooted> {
  bool? _alone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_alone != null) return;
    _alone = ModalRoute.of(context)?.isFirst ?? false;
    if (_alone!) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final router = GoRouter.of(context);
        router.go('/feed');
        router.push(widget.location);
      });
    }
  }

  // While re-rooting, don't build the page (it would start its work twice, e.g. the pop quiz).
  @override
  Widget build(BuildContext context) => _alone == true ? const Scaffold() : widget.child;
}
