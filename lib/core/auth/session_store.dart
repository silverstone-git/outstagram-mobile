import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session.dart';

/// Persists the session in the Android Keystore-backed secure storage.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'outsie_session_v1';
  final FlutterSecureStorage _storage;

  Future<Session?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt or undecryptable (e.g. restored backup on a new device): start signed out.
      await clear();
      return null;
    }
  }

  Future<void> write(Session s) => _storage.write(key: _key, value: jsonEncode(s.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
