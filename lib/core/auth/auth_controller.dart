import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../net/api_error.dart';
import 'auth_repository.dart';
import 'google_auth.dart';
import 'session.dart';
import 'session_store.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// Dio without the auth interceptor: sign-in, refresh, logout.
final bareDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      baseUrl: Env.apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(bareDioProvider)));

/// `null` = signed out. Loading only during the first read from secure storage.
final authControllerProvider = AsyncNotifierProvider<AuthController, Session?>(AuthController.new);

class AuthController extends AsyncNotifier<Session?> {
  Future<Session?>? _refreshing;

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  SessionStore get _store => ref.read(sessionStoreProvider);

  Session? get current => state.value;

  /// Where to go right after this sign-in instead of the feed (e.g. the confirm-email step after
  /// registering). The router takes it once.
  String? _landing;
  String? takeLanding() {
    final l = _landing;
    _landing = null;
    return l;
  }

  @override
  Future<Session?> build() => ref.read(sessionStoreProvider).read();

  Future<void> _set(Session s) async {
    await _store.write(s);
    state = AsyncData(s);
  }

  Future<void> signInWithPassword(String username, String password) async =>
      _set(await _repo.login(username.trim(), password));

  Future<void> register({
    required String fullname,
    required String username,
    required String email,
    required String password,
    required DateTime dateOfBirth,
    String? bio,
  }) async {
    await _repo.register(
      fullname: fullname.trim(),
      username: username.trim(),
      email: email.trim(),
      password: password,
      dateOfBirth: dateOfBirth,
      bio: bio,
    );
    _landing = '/verify-email?onboarding=1';
    await signInWithPassword(username, password);
  }

  Future<void> sendEmailCode(String email) => _repo.emailStart(email.trim().toLowerCase());

  Future<void> signInWithEmailCode(String email, String code) async {
    final (s, _) = await _repo.emailVerify(email.trim().toLowerCase(), code);
    await _set(s);
  }

  /// Magic link: signs in when the link does (whoever was signed in before), returns what happened.
  Future<EmailLinkResult> signInWithEmailLink(String tokenHash) async {
    final r = await _repo.emailLink(tokenHash);
    if (r.session != null) await _set(r.session!);
    return r;
  }

  Future<void> resetPasswordWithLink(String resetToken, String newPassword) async =>
      _set(await _repo.resetPasswordWithLink(resetToken, newPassword));

  Future<void> sendPasswordResetCode(String email) => _repo.forgotPassword(email.trim().toLowerCase());

  /// Works signed in or out; either way this device ends up signed in with the new password.
  Future<void> resetPassword(String email, String code, String newPassword) async =>
      _set(await _repo.resetPassword(email.trim().toLowerCase(), code, newPassword));

  /// Native sheet first; the browser flow if the device can't do it.
  Future<void> signInWithGoogle() async {
    Session s;
    try {
      s = await _repo.googleNative();
    } on UnsupportedError {
      s = await _repo.googleBrowser();
    }
    await _set(s);
  }

  Future<void> signInWithGoogleInBrowser() async => _set(await _repo.googleBrowser());

  /// Single-flight refresh shared by every request that finds the token stale.
  /// Returns the new session, or null when the user must sign in again.
  Future<Session?> refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<Session?> _doRefresh() async {
    final s = current;
    if (s == null) return null;
    final token = s.refreshToken;
    if (token == null) {
      await _localSignOut();
      return null;
    }
    try {
      final next = await _repo.refresh(token);
      await _set(next);
      return next;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _localSignOut();
        return null;
      }
      return s; // offline or server hiccup: keep the session, the request will fail on its own
    }
  }

  Future<void> signOut() async {
    final token = current?.refreshToken;
    await _localSignOut();
    if (token != null) await _repo.logout(token);
  }

  Future<void> _localSignOut() async {
    await _store.clear();
    await GoogleAuth.signOut();
    state = const AsyncData(null);
  }
}
