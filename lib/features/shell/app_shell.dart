import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../activity/follow_requests.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.school_outlined, Icons.school_rounded, 'Exams'),
    (Icons.add_box_outlined, Icons.add_box_rounded, 'Create'),
    (Icons.favorite_outline_rounded, Icons.favorite_rounded, 'Activity'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];
  static const _activity = 3;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// The tabs exist only while signed in, so this is where follow requests are polled (badge + notification).
class _AppShellState extends ConsumerState<AppShell> {
  late final _poller = FollowRequestsPoller(() => ref.read(followRequestsProvider.notifier).reload());
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _poller.start();
    _life = AppLifecycleListener(
      onResume: () {
        ref.read(followRequestsProvider.notifier).reload();
        _poller.start();
      },
      onPause: _poller.stop,
    );
  }

  @override
  void dispose() {
    _poller.stop();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final pending = ref.watch(pendingFollowRequestsProvider);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          if (i == AppShell._activity) ref.read(followRequestsProvider.notifier).reload();
          // Tapping the current tab pops it to its root, like every big social app.
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: [
          for (final (i, (icon, selected, label)) in AppShell._tabs.indexed)
            NavigationDestination(
              icon: i == AppShell._activity && pending > 0
                  ? Badge(label: Text(pending > 9 ? '9+' : '$pending'), child: Icon(icon))
                  : Icon(icon),
              selectedIcon: i == AppShell._activity && pending > 0
                  ? Badge(label: Text(pending > 9 ? '9+' : '$pending'), child: Icon(selected))
                  : Icon(selected),
              label: label,
              tooltip: i == AppShell._activity && pending > 0 ? '$label, $pending follow requests' : null,
            ),
        ],
      ),
    );
  }
}
