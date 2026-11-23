import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/env.dart';

/// The user closed the Google sheet / browser: not an error worth showing.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

String randomUrlSafe(int bytes) {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
}

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// Native Google sign-in (Android Credential Manager account sheet).
///
/// Google gets sha256(rawNonce) and embeds it in the ID token; outsie forwards the raw nonce to
/// Supabase, which hashes it and checks it against the token. `initialize` may only run once per
/// process, so the nonce is per app launch.
class GoogleAuth {
  static final String rawNonce = randomUrlSafe(32);
  static Future<void>? _init;

  static bool get configured => Env.googleServerClientId.isNotEmpty;

  /// Returns a Google ID token whose audience is the Web client ID.
  static Future<String> idToken() async {
    _init ??= GoogleSignIn.instance.initialize(
      serverClientId: Env.googleServerClientId,
      nonce: sha256Hex(rawNonce),
    );
    await _init;
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw UnsupportedError('Native Google sign-in is not available on this device');
    }
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const ['email', 'profile']);
      final token = account.authentication.idToken;
      if (token == null) throw StateError('Google returned no ID token');
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const SignInCancelled();
      rethrow;
    }
  }

  static Future<void> signOut() async {
    if (_init == null) return;
    try {
      await GoogleSignIn.instance.signOut(); // next sign-in shows the account picker again
    } catch (_) {}
  }
}
