import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small on-disk cache of API responses (the first page of the feed, explore and profiles), so screens
/// show the last known content instantly on a cold start and refresh it in the background
/// (stale-while-revalidate). Cleared when the signed-in account changes.
abstract final class JsonCache {
  static const _prefix = 'json_cache_v1:';
  static const _maxChars = 400000; // keep shared_preferences small; bigger answers just aren't cached

  static Future<Object?> read(String key) async {
    try {
      final s = (await SharedPreferences.getInstance()).getString('$_prefix$key');
      return s == null ? null : jsonDecode(s);
    } catch (e) {
      debugPrint('json cache read $key: $e');
      return null;
    }
  }

  static Future<void> write(String key, Object? value) async {
    try {
      final s = jsonEncode(value);
      if (s.length > _maxChars) return;
      await (await SharedPreferences.getInstance()).setString('$_prefix$key', s);
    } catch (e) {
      debugPrint('json cache write $key: $e');
    }
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}
