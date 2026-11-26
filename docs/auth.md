# Authentication

outsie keeps **its own users table and its own JWTs**. Supabase Auth is only used as an identity broker
for Google (and later email codes / GitHub). The app never holds a Supabase session.

## 1. Flows at a glance

| Flow | App code | Server endpoint | Notes |
|---|---|---|---|
| Username + password | `AuthRepository.login` | `POST /login` (form-encoded `username`, `password`) | Works on any account that has a password |
| Register | `AuthRepository.register` → then login | `POST /register` (JSON) | `date_of_birth` is **required** (`YYYY-MM-DD`); username must be unique (else 4xx/5xx) |
| Google, native (default) | `AuthRepository.googleNative` → `GoogleAuth.idToken()` | `POST /auth/google {id_token, nonce}` | Android Credential Manager account sheet, no browser |
| Google, browser fallback | `AuthRepository.googleBrowser` (long-press the Google button, or automatic if native is unsupported) | `POST /auth/supabase {auth_code, code_verifier}` | Supabase PKCE in a Custom Tab, back via `<scheme>://auth-callback` |
| Refresh | `AuthController.refresh` (single-flight) | `POST /auth/refresh {refresh_token}` | Rotates the refresh token |
| Sign out | `AuthController.signOut` | `POST /auth/logout {refresh_token}` | Best effort; local sign-out always happens |
| Email code | `AuthController.sendEmailCode` / `signInWithEmailCode` (`EmailCodeScreen`, `/sign-in/email`) | `POST /auth/email/start`, `/auth/email/verify` | Creates the account for a new address (username from the email, like Google) |
| Forgot / change password | `sendPasswordResetCode` / `resetPassword` (`ForgotPasswordScreen`: `/forgot-password`, signed in `/account/password`) | `POST /auth/password/forgot`, `/auth/password/reset` | Signs every other device out |
| Confirm email | `AccountApi.sendVerifyCode` / `verify` (`VerifyEmailScreen`, `/verify-email`) | `POST /me/email/verify/start`, `/me/email/verify` | After registering the app lands on `/verify-email?onboarding=1` ("Do it later" allowed) |
| Change email | `AccountApi.sendChangeCode` / `changeEmail` (`ChangeEmailScreen`, `/account/email`) | `POST /me/email/change/start`, `/me/email/change` | The code proves the new address |

Every sign-in response has the same shape:

```json
{"access_token": "<HS256 JWT, 30 min>", "token_type": "bearer", "expires_in": 1800,
 "refresh_token": "<opaque, 60 days>", "user": {"user_id": 1, "username": "asha", "fullname": "Asha", "bio": null}}
```

`/auth/google` and `/auth/supabase` **find or create** the outsie user by the identity's verified email. A user who
registered with a password and later uses Google with the same email lands on the **same** account. New Google users
get a username from their email prefix (`[a-z0-9_.]`, max 20, a random number appended on clash) and a random unknown
password.

## 2. Native Google sign-in in detail

```
app                                  Google (Play services)          outsie                        Supabase Auth
 | initialize(serverClientId=WEB,       |                              |                               |
 |            nonce=sha256(rawNonce))   |                              |                               |
 | authenticate() ------------------->  | account sheet                |                               |
 | <----------------- ID token (aud = WEB client, nonce claim = sha256(rawNonce))                      |
 | POST /auth/google {id_token, nonce: rawNonce} --------------------> |                               |
 |                                      |                              | POST /auth/v1/token?grant_type=id_token
 |                                      |                              |  {provider: google, id_token, nonce} -> verifies
 |                                      |                              | <------- {user: {email, email_confirmed_at, ...}}
 | <------------------------------------------ outsie tokens + user --|                               |
```

- `Env.googleServerClientId` = the **Web** client ID from `config/*.json`. Google puts it in the token's `aud`.
  Supabase accepts the token because that ID is its Google provider's client ID.
- The nonce is generated once per app launch (`google_sign_in` 7 allows `initialize` only once per process).
- Cancel → `SignInCancelled` → no error shown.
- `GoogleSignIn.instance.supportsAuthenticate() == false` → the controller falls back to the browser flow.

## 3. Sessions and refresh

- `Session` (`core/auth/session.dart`) = access token, refresh token, `expiresAt` (now + `expires_in`), user.
- Stored as JSON in `flutter_secure_storage` (Android Keystore) under `outsie_session_v1`. If it can't be read or
  decrypted (e.g. restored onto a new device), it's wiped and the user starts signed out.
- `AuthInterceptor` (`core/net/api_client.dart`):
  1. **Before** each request: if the access token expires within 60 s, `await auth.refresh()`.
  2. On **401** for a request that carried a bearer: if that bearer is still the current token, refresh; then retry
     the request **once** (`extra['retried']`). Otherwise another request already refreshed, so just retry with the new token.
- `AuthController.refresh()` is **single-flight**: concurrent callers share one `/auth/refresh`.
  - 401 from refresh → local sign-out (router shows sign-in).
  - Network error → keep the session (the request fails on its own; the user stays signed in offline).
- **Server rules** (`outstagram-server/src/repository/refresh_tokens.py`): the table `refreshtoken` stores only
  sha256(token). Each refresh revokes the old row and issues a new one in the same `family_id`. Presenting an
  already-revoked token **revokes the whole family** (theft detection). Lifetime `OUTSIE_REFRESH_TOKEN_DAYS` (default 60).
  Expired rows for a user are purged when that user signs in again.
- Tests: `test/auth_test.dart` (client) and `outstagram-server/tests/test_mobile_auth.py` (server).

## 4. Browser fallback (PKCE)

`googleBrowser()` reads `supabase_url` from `GET /auth/providers`, makes a verifier (32 random bytes, base64url) and
`challenge = base64url(sha256(verifier))`, and opens:

```
{supabase_url}/auth/v1/authorize?provider=google&redirect_to=<AUTH_SCHEME>://auth-callback&code_challenge=…&code_challenge_method=s256
```

`flutter_web_auth_2` catches the redirect (Android `CallbackActivity` with `android:scheme="${authScheme}"`,
per flavor in `build.gradle.kts`). The `code` goes to `POST /auth/supabase`.

**Requires** these URLs in Supabase → Authentication → URL Configuration → Redirect URLs, otherwise Supabase
redirects to the web Site URL and the app never gets the code:
- prod project (`outsie`): `com.cyto.outstagram://auth-callback`
- staging project (`outsie-staging`): `com.cyto.outstagram.staging://auth-callback`

As of 2026-11-24 it's **unverified** whether these were added. Check them before relying on the fallback.

## 5. Google Cloud + Supabase configuration

The outsie GCP project (id and number in `../LOCAL.md`):

| OAuth client | Type | ID | Used by |
|---|---|---|---|
| Web client | Web application | `595282356777-ppkjuihespj58af8htp4nivg2ife0dbk.apps.googleusercontent.com` | Supabase Google provider (both projects) **and** the app's `serverClientId` (`GOOGLE_SERVER_CLIENT_ID` in `config/*.json`). Verified on device 2026-11-24 |
| Desktop client | Desktop ("installed") | (in `../LOCAL.md`) | **Nothing.** It's in `.env` / `client_secret_*.json` from early setup; not needed |
| Android client(s) | Android | (no secret) | Lets Google issue tokens to the app: package + SHA-1 |

The Web client ID was confirmed by reading the `client_id` that Supabase's `/auth/v1/authorize?provider=google`
redirects to (both projects use the same one).

**Android clients needed** (Credentials → Create OAuth client ID → Android):

| Package | SHA-1 | When |
|---|---|---|
| `com.cyto.outstagram` | `06:DB:60:E1:94:44:88:54:08:85:47:54:58:4A:5A:AA:55:3E:F7:4F` (debug keystore; current release APKs are debug-signed) | created; **verified working** on device 2026-11-24 |
| `com.cyto.outstagram.staging` | same | now |
| `com.cyto.outstagram` | upload key SHA-1 | when a real upload key exists (P7) |
| `com.cyto.outstagram` | Play App Signing key SHA-1 (Play Console → App integrity) | after the first Play upload |

Get a SHA-1: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
(keytool: `C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe`).

**OAuth consent screen:** **published (External), brand verification done** (user, 2026-11-25), so any Google
account can sign in. Basic scopes (email, profile, openid) need no further review.

**Supabase (each project) → Authentication → Providers → Google:** Client ID = the Web client (already),
"Client IDs" list may hold extra IDs (not required for this flow). Skip-nonce-check must stay **off**; the app sends nonces.

## 6. Email codes and confirmed emails

outsie asks **Supabase Auth** to send and check 6-digit codes (`POST {SUPABASE_URL}/auth/v1/otp` with `create_user: true`,
then `/auth/v1/verify` with `type: "email"`); Supabase's **custom SMTP** delivers them. outsie never holds a Supabase
session: a correct code only proves the person reads that inbox, and outsie then signs in / resets / confirms.
Server code: `outstagram-server/src/repository/email_auth.py`.

Supabase dashboard, **both** projects:
- Project Settings → Authentication → SMTP: custom SMTP on (done by the user 2026-11-25).
- Authentication → Providers → Email: enabled, **Email OTP Length = 6** (or set `OUTSIE_EMAIL_OTP_LENGTH` on outsie to match).
- Authentication → Email Templates: **Magic Link** (sent to addresses Supabase already knows) and **Confirm signup**
  (sent to new addresses) must show `{{ .Token }}`, e.g. `<h2>Your Outstagram code: {{ .Token }}</h2><p>It expires in 10 minutes.</p>`.
  Without it the email only has a link and the app can't use it.
- **Magic links** (2026-11-26): the same templates also link to `{{ .RedirectTo }}?h={{ .TokenHash }}`. outsie sends
  `redirect_to = OUTSIE_EMAIL_LINK_URL`: prod `https://outstagram.aryan.cfd/signin/`, staging
  `https://aryan.cfd/outstagram/signin/`. That URL must be in **Authentication → URL Configuration → Redirect URLs**, or
  Supabase falls back to the Site URL (the web still handles `?h=` there, but the app won't open).
- Authentication → Rate Limits: every call comes from outsie's IP, so "Token verifications" and "emails sent" are shared by all
  users; raise them as usage grows. outsie adds its own per-address limits (5 codes / 5 wrong codes per 15 min).

### Magic links

The link opens the app through App Links (prod: host `outstagram.aryan.cfd` path `/signin/`; staging: host `aryan.cfd`
path `/outstagram/signin/`; per-flavor `webLinkHost`/`webLinkBase` manifest placeholders). Both hosts serve
`/.well-known/assetlinks.json` with both packages (outstagram.aryan.cfd from `outstagram-web/public/.well-known/`).
Without the app, the web's `/signin/` page opens instead and waits for a tap (mail scanners open links on their own).

`router.dart` sends `/signin/?h=…` and `/outstagram/signin/?h=…` to `/email-link?h=…` (`EmailLinkScreen`), signed in or
out and before the stored session loads. The screen posts the hash to `POST /auth/email/link`; what happens depends on
the newest email outsie sent to that address:
- sign-in / confirm email → signed in (as that address, even if someone else was signed in), on to the feed;
- forgot password → signed in, plus a 15-minute `reset_token` → "Set a new password" → `POST /auth/password/reset-link`;
- change email → that account's email changes, no session ("Email changed").
Using the link spends the code in the same email, and the other way round. Wrong links are limited per IP (20 / 15 min)
plus 200 / 15 min overall, since Supabase's verify limit is shared by all users.

`user.email_verified_at` (added 2026-11-25) is set by Google and email-code sign-ins, the confirm flow, a password reset and
an email change. Accounts that existed before were back-filled from Supabase `auth.users.email_confirmed_at` (Google users).
Until it's set, posting, media upload and the AI tutor answer 403 `email_unverified` (`OUTSIE_REQUIRE_VERIFIED_EMAIL=0` on
outsie turns the gate off). The profile shows an "Unverified" badge and a banner; the web shows a banner with the code field.

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Google sheet errors immediately, or `GoogleSignInException` `[16]`/`[10]` / "developer console is not set up correctly" / "No credentials available" | No Android OAuth client for this package + SHA-1, or it's in another GCP project | Create it (§5); wait a few minutes |
| Sheet works, then "Google sign-in could not be verified" (401 from `/auth/google`) | Supabase rejected the token: `aud` isn't a client ID Supabase knows, or nonce mismatch | Check `GOOGLE_SERVER_CLIENT_ID` in `config/*.json` is the Web client; Supabase Google provider client ID |
| "Access blocked: app not completed verification" / user not allowed | Consent screen in Testing and the account isn't a test user | Add the test user or publish |
| "Your account has no verified email address" | Identity has no confirmed email | Expected; use another sign-in |
| Browser fallback ends on the website instead of the app | Callback URL missing from Supabase Redirect URLs | §4 |
| Signed out every ~30 min | Server without refresh tokens (old deploy) → `refresh_token` null | Deploy `outstagram-server` ≥ `fdecac2` |
| "Session expired, please sign in again" right after reinstalling | Old refresh token was rotated elsewhere / family revoked | Sign in again (by design) |
| The email arrives but has no code, only a link | The Supabase template lacks `{{ .Token }}` | §6: edit **Magic Link** and **Confirm signup** |
| Tapping the email link opens the website, not the app | App Link not verified: link host/path not this flavor's, `assetlinks.json` missing the package/SHA-256, or Supabase used the Site URL (redirect not allowed) | §6 Magic links; `adb shell pm get-app-links com.cyto.outstagram` |
| The link page says the link expired or was already used | Older email (a newer one replaces it), the code from it was used, or a mail scanner opened it | Ask for a new email or type the code |
| "We couldn't send the email right now" (502) | Supabase `/otp` failed: SMTP settings, sender domain, or Supabase's hourly email limit | Supabase → Logs → Auth; outsie logs `supabase /otp failed` |
| "Please wait a minute before asking for another code" | Supabase's per-address 60 s limit | Wait; the app's Resend button already counts down 60 s |
