/// Build-time configuration from `--dart-define-from-file=config/<flavor>.json`.
/// Every value here is public (it ends up in the APK); secrets never go in config/.
abstract final class Env {
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'staging');
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://outsie-staging-mgenvq5gwa-an.a.run.app',
  );
  static const webBase = String.fromEnvironment('WEB_BASE', defaultValue: 'https://aryan.cfd/outstagram');

  /// The *Web application* OAuth client that Supabase's Google provider uses. Google puts it in the
  /// ID token's `aud`, which is what Supabase checks. (Not the Android client, not a Desktop client.)
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// URL scheme of the browser sign-in callback; equals the Android applicationId of the flavor.
  static const authScheme = String.fromEnvironment('AUTH_SCHEME', defaultValue: 'com.cyto.outstagram.staging');

  /// Where this APK is distributed: `sideload` (default: test APKs for friends) or `play`.
  /// Build a Play bundle with `--dart-define=STORE=play`.
  static const store = String.fromEnvironment('STORE', defaultValue: 'sideload');

  static bool get isStaging => flavor == 'staging';

  /// Razorpay Checkout is only allowed outside the Play Store (Play requires Play Billing for digital goods).
  static bool get razorpayAllowed => store != 'play';
}
