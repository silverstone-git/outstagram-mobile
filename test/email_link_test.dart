import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/app/router.dart' show emailLinkTarget;
import 'package:outstagram/core/auth/auth_controller.dart';
import 'package:outstagram/core/net/api_error.dart';
import 'package:outstagram/features/compose/share_intent.dart';

import 'auth_test.dart' show authBody, setUpApp, session;

void main() {
  group('email sign-in links', () {
    test('App Link paths map to /email-link (prod host and staging path, with or without the slash)', () {
      expect(emailLinkTarget(Uri.parse('https://outstagram.aryan.cfd/signin/?h=abc123')), '/email-link?h=abc123');
      expect(emailLinkTarget(Uri.parse('/signin?h=abc123')), '/email-link?h=abc123');
      expect(emailLinkTarget(Uri.parse('https://aryan.cfd/outstagram/signin/?h=ff00')), '/email-link?h=ff00');
      expect(emailLinkTarget(Uri.parse('/signin/')), '/email-link?h=');
      expect(emailLinkTarget(Uri.parse('/sign-in')), isNull);
      expect(emailLinkTarget(Uri.parse('/outstagram/p/?id=x')), isNull);
    });

    test('sign-in links are navigation, not shared text', () {
      expect(isOwnDeepLink('https://outstagram.aryan.cfd/signin/?h=abc'), isTrue);
      expect(isOwnDeepLink('https://aryan.cfd/outstagram/signin/?h=abc'), isTrue);
      expect(isOwnDeepLink('https://example.com/signin/?h=abc'), isFalse);
    });

    test('a link signs in, replacing whoever was signed in', () async {
      final seen = <String, Object?>{};
      final (c, _, store) = await setUpApp(session('old'), (o) {
        seen[o.path] = o.data;
        return (200, {...authBody('a1', 'r1'), 'created': false, 'next': null});
      });
      final r = await c.read(authControllerProvider.notifier).signInWithEmailLink('ab12');
      expect(seen['/auth/email/link'], {'token_hash': 'ab12'});
      expect(r.session?.accessToken, 'a1');
      expect(r.resetToken, isNull);
      expect(store.saved?.accessToken, 'a1');
    });

    test('a forgot-password link signs in and hands back the reset token; the password call uses it', () async {
      final seen = <String, Object?>{};
      final (c, _, store) = await setUpApp(null, (o) {
        seen[o.path] = o.data;
        return switch (o.path) {
          '/auth/email/link' => (200, {...authBody('a1', 'r1'), 'next': 'password', 'reset_token': 'rt'}),
          '/auth/password/reset-link' => (200, authBody('a2', 'r2')),
          _ => (404, {'detail': 'nope'}),
        };
      });
      final auth = c.read(authControllerProvider.notifier);
      final r = await auth.signInWithEmailLink('ab12');
      expect(r.resetToken, 'rt');
      expect(store.saved?.accessToken, 'a1');
      await auth.resetPasswordWithLink('rt', 'new-password');
      expect(seen['/auth/password/reset-link'], {'reset_token': 'rt', 'new_password': 'new-password'});
      expect(store.saved?.refreshToken, 'r2');
    });

    test('a change-email link changes the email and keeps the current session', () async {
      final (c, _, store) = await setUpApp(session('mine'), (o) => (200, {'changed_email': 'new@example.com'}));
      final r = await c.read(authControllerProvider.notifier).signInWithEmailLink('ab12');
      expect(r.changedEmail, 'new@example.com');
      expect(r.session, isNull);
      expect(c.read(authControllerProvider).value?.accessToken, 'mine');
      expect(store.saved?.accessToken, 'mine');
    });

    test('an expired link shows the server message', () async {
      final (c, _, _) = await setUpApp(null, (o) => (401, {'detail': 'This sign-in link has expired or was already used.'}));
      await expectLater(
        c.read(authControllerProvider.notifier).signInWithEmailLink('ab12'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('expired'))),
      );
    });
  });
}
