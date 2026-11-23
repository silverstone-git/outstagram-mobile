import 'package:flutter/material.dart';

/// Placeholder for tabs whose phase hasn't landed yet (see PLAN.md §7).
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.icon, required this.phase});

  final String title;
  final IconData icon;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: cs.primary),
          const SizedBox(height: 12),
          Text('Arrives in $phase', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
