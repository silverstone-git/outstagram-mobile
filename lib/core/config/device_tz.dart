import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The phone's IANA time zone (e.g. `Asia/Kolkata`). Sent to outsie as `X-Timezone` so streak days
/// follow the user's calendar, and used to schedule local reminders.
abstract final class DeviceTimezone {
  static String name = 'UTC';

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      name = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (e) {
      debugPrint('time zone lookup failed: $e');
    }
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      name = 'UTC';
      tz.setLocalLocation(tz.UTC);
    }
  }
}
