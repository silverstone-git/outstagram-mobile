import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'streak_api.dart';

/// Feeds the home-screen streak widget (android/.../StreakWidgetProvider.kt). The widget derives
/// "done today / at risk / ended" from the last counted day itself, so it stays right overnight.
abstract final class StreakWidget {
  static const _provider = 'com.cyto.outstagram.StreakWidgetProvider';

  /// [s] null = signed out.
  static Future<void> update(StreakStatus? s) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await HomeWidget.saveWidgetData<bool>('signed_in', s != null);
      await HomeWidget.saveWidgetData<int>('streak_days', s?.current ?? 0);
      await HomeWidget.saveWidgetData<int>('streak_freezes', s?.freezes ?? 0);
      await HomeWidget.saveWidgetData<String>('streak_last_day', s?.lastDay);
      await HomeWidget.saveWidgetData<String>('streak_tz', s?.tz);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (e) {
      debugPrint('streak widget not updated: $e');
    }
  }
}
