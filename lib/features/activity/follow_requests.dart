import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../feed/models.dart';
import '../feed/social_api.dart';
import '../streak/streak_reminders.dart';

/// Pending follow requests for the signed-in user. The app keeps it fresh while it's open
/// ([FollowRequestsPoller]: every minute in the foreground and on resume); it drives the badge on the
/// Activity tab and a local notification for each request this phone hasn't seen yet. There's no push
/// server, so nothing arrives while the app is fully closed: it shows up the next time the app opens.
final followRequestsProvider = AsyncNotifierProvider<FollowRequestsNotifier, List<FollowRequest>>(
  FollowRequestsNotifier.new,
);

const _seenKey = 'follow_requests_notified_v1';
const _notificationBase = 7300; // + request id % 1000; outside the streak/exam/tutor ranges

class FollowRequestsNotifier extends AsyncNotifier<List<FollowRequest>> {
  /// Answered on this screen; the tile shows "Approved"/"Declined" until the next reload.
  final answered = <int>{};

  @override
  Future<List<FollowRequest>> build() => _fetch();

  Future<List<FollowRequest>> _fetch() async {
    final list = await ref.read(socialApiProvider).followRequests();
    answered.retainWhere((id) => list.any((r) => r.id == id));
    unawaited(_notifyNew(list));
    return list;
  }

  /// Refetch without flashing a spinner (the old list stays up meanwhile).
  Future<void> reload() async {
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      if (!state.hasValue) state = AsyncError(e, st);
    }
  }

  void markAnswered(int id) {
    answered.add(id);
    final list = state.value;
    if (list != null) state = AsyncData([...list]); // the badge recounts
  }

  Future<void> _notifyNew(List<FollowRequest> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
      final fresh = [for (final r in list) if (!seen.contains('${r.id}')) r];
      final init = prefs.getBool('${_seenKey}_init') ?? false;
      // remember only the pending ones, so the list can't grow forever
      await prefs.setStringList(_seenKey, [for (final r in list) '${r.id}']);
      await prefs.setBool('${_seenKey}_init', true);
      // first run on this phone: just remember what was already waiting
      if (!init || fresh.isEmpty) return;
      for (final r in fresh.take(3)) {
        await StreakReminders.instance.showNow(
          _notificationBase + r.id % 1000,
          title: '@${r.username} wants to follow you',
          body: 'Tap to approve or decline.',
          route: '/activity',
        );
      }
    } catch (e) {
      debugPrint('follow request notification skipped: $e');
    }
  }
}

/// The badge number on the Activity tab: pending requests not answered yet.
final pendingFollowRequestsProvider = Provider<int>((ref) {
  final list = ref.watch(followRequestsProvider).value ?? const [];
  final answered = ref.read(followRequestsProvider.notifier).answered;
  return list.where((r) => !answered.contains(r.id)).length;
});

/// Polls [followRequestsProvider] once a minute while the app is in the foreground (started by the
/// tab shell, so only while signed in).
class FollowRequestsPoller {
  FollowRequestsPoller(this._reload);

  final Future<void> Function() _reload;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _reload());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
