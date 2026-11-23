# TODO: Outstagram mobile

Ordered roughly by priority. Each item says *what*, *why*, and *how* so a fresh session can pick it up.
Tick items off here (and in `AGENTS.md` §1) when done. Last updated: 2026-11-24.

## 0. Verify right now (quick)

- [ ] **Google sign-in on device (prod flavor).** The user reports creating the Android OAuth client. Tap
      "Continue with Google" in the installed prod app. If it fails, see `docs/auth.md` §6. Note the Desktop client
      (`…41rf…`, in `.env` / `client_secret_*.json`) is *not* an Android client.
- [ ] **OAuth consent screen**: published, or friends added as test users (`docs/auth.md` §5).
- [ ] **Supabase Redirect URLs** for the browser fallback (`docs/auth.md` §4).
- [ ] **On-device QA of P2**: feed/explore, like/double-tap, comments, search → follow → approve (two accounts),
      post with 1 and several photos, text-only post, delete, profile counts, theme toggle, sign-out/in.

## 1. Email sign-in with a 6-digit code (+ custom SMTP)  ← requested

**Why:** friends without Google, or who don't want passwords. A code beats a magic link on mobile: no deep links,
the link can't open in the wrong browser or app, and Android can autofill the code from the notification. The same
email can still contain a link for desktop users.

**Prerequisite: custom SMTP in Supabase.** Supabase's built-in mailer only delivers to the project's team members
and is rate-limited to a few emails per hour, so it's unusable for friends.
1. Pick a provider. Recommendation: **Resend** (free tier ~3,000 emails/month, 100/day).
   Alternatives: Brevo, AWS SES, Postmark.
2. Verify a sending domain (e.g. `aryan.cfd`, or a subdomain like `mail.aryan.cfd`). Add the DNS records the provider
   gives you (SPF `TXT`, DKIM `TXT`/`CNAME`, optionally DMARC `TXT _dmarc`) wherever `aryan.cfd` DNS is hosted.
3. Supabase → **both** projects → Project Settings → Authentication → SMTP Settings → enable custom SMTP:
   host `smtp.resend.com`, port `465`, user `resend`, password = a Resend API key (store it nowhere else),
   sender `Outstagram <no-reply@aryan.cfd>`.
4. Supabase → Authentication → Rate Limits: raise "emails per hour" (e.g. 60), keep the OTP verify limits.
5. Supabase → Authentication → Providers → **Email**: enabled; "Confirm email" on; **Email OTP length 6**;
   OTP expiry e.g. 600 s.
6. Supabase → Authentication → Email Templates → **Magic Link** template: include the code, e.g.
   `<h2>Your Outstagram code: {{ .Token }}</h2><p>It expires in 10 minutes.</p>`
   (`{{ .Token }}` is the 6-digit code; `{{ .ConfirmationURL }}` is the link, which can stay for desktop).
   Do the same for the **Confirm signup** template (first-time emails use it).

**Server (`outstagram-server`, new module `src/repository/email_auth.py` + routes in `main.py`):**
- `POST /auth/email/start {email}` → server calls Supabase `POST {SUPABASE_URL}/auth/v1/otp`
  `{"email": email, "create_user": true}` with header `apikey: SUPABASE_PUBLISHABLE_KEY`. Always return `204`
  (don't reveal whether the email exists). Validate the email format; per-email + per-IP rate limit
  (e.g. 5 per 15 min; a small table or reuse the `aiusage` pattern), plus Supabase's own limits.
- `POST /auth/email/verify {email, code}` → Supabase `POST /auth/v1/verify` `{"type": "email", "email": email, "token": code}`.
  200 → `user` (with `email_confirmed_at`) → `social_auth.find_or_create_user(db, user)` → `_session(db, user)`
  (same response as other sign-ins, with refresh token). Non-200 → `401 "That code is wrong or expired"`.
- Tests in `tests/test_mobile_auth.py`: monkeypatch the two Supabase calls (like `exchange_id_token`); check
  204-always on start, the user is created and linked by email, a wrong code → 401, and refresh-token issuance.
- README "Sessions and mobile sign-in" section: document both endpoints.
- Deploy: staging first, then PR → `main` → prod (`docs/environments.md`).

**App:**
- `AuthRepository.emailStart(email)` / `emailVerify(email, code)`; `AuthController.signInWithEmailCode`.
- Sign-in screen: a third option "Continue with email" → screen 1 email field → screen 2 six boxes or one
  `TextField` with `autofillHints: [AutofillHints.oneTimeCode]`, `keyboardType: number`, auto-submit at 6 digits,
  "Resend code" with a 30–60 s countdown, "Wrong email?" back link.
- Tests: extend `test/auth_test.dart` with the fake adapter.

**Optional later:** set a password from the profile (needs `PUT /me/password`); account linking UI.

## 2. Permanent media URLs  ← important, affects web too

Posts store presigned R2 URLs that **expire after 7 days**, so images on older posts break (web and app).
- Find the bucket's public address: Cloudflare → R2 → bucket `outstagram` → Settings → Public access
  (an `r2.dev` subdomain, or connect a custom domain such as `media.aryan.cfd`, which is better: cacheable, no rate limits).
  The question-image bucket the web uses is `https://pub-682f1a94c94443278f61ec7ca3dadaec.r2.dev`; confirm whether
  it's the same bucket before reusing it.
- Set `S3_PUBLIC_BASE_URL=<that origin>` on `outsie` and `outsie-staging`
  (`gcloud run services update outsie --region asia-northeast1 --update-env-vars S3_PUBLIC_BASE_URL=…`). The server
  then returns `public_url` and the app already prefers it.
- Update the web (`outstagram-web/src/services/api.ts` `uploadImages`) to prefer `public_url` too.
- Backfill: a one-off script that rewrites `mediaurl.url` from presigned → `<base>/<object_key>`
  (object key = last path segment before `?`). Take a DB backup first; test on staging.

## 3. P3: Exams (next big feature)

Port `outstagram-web/src/features/exams/` to `lib/features/exams/`:
- `engine/` pure Dart (no Flutter imports): `normalizeExamConfig`, `prepareQuestions` (shuffle), `isQuestionCorrect`
  (MCQ / MSQ / NAT range-or-exact), `scoreExam` (sections, negative marks, `maxAttempts` = best N count),
  SWOT, per-topic accuracy/time, presets (`SUBJECT_GROUPS`, `PATTERNS`), quick practice.
  **Golden tests:** a small Bun script runs the TS `scoreExam` over fixture exams/answers and writes JSON; Dart tests
  must produce identical numbers.
- Exams home: presets (GATE, CSIR NET, TIFR, BARC), server presets (`/api/exam_presets`, currently 0 on prod),
  quick practice by subject, community exams (`/pariksha?page=`, 49 on prod), my attempts (`/exam-attempts`).
- Runner: full-screen route outside the shell; sticky timer; swipe between questions; bottom-sheet palette
  (answered / flagged / unseen); MCQ/MSQ/NAT inputs; LaTeX via `flutter_math_fork`; `wakelock_plus`; `PopScope`
  confirm on back; haptics; auto-submit at 0. **Autosave** every change (drift or JSON in app documents dir) so an
  attempt survives the app being killed; offer "Resume" on the Exams tab.
- Results: score, accuracy, time, section scores, topic chart (`fl_chart`), SWOT, filtered review with explanations;
  `POST /exam-attempts` (result JSON ≤ 2 MB); "Share to feed" → composer prefilled with category Exam Result.
- Question images: `resolveImagePath` in `engine.ts` (R2 public endpoint for relative paths).

## 4. P4: AI tutor

SSE client over Dio `ResponseType.stream` for `POST /exam-attempts/{id}/chat/stream` (`status`, `meta`, `delta`, `done`,
`error` events; limit errors arrive as normal HTTP errors before the stream). Markdown + LaTeX rendering with citations,
skill chips (`/ai/skills`), quota pill (`/ai/quota`), tutor library (`/ai/chats`, delete), saved equations
(long-press → haptic → `POST /favorites/equations`), voice input (`speech_to_text`). Reference: `QuestionChat.tsx`,
`TutorMarkdown.tsx`, `TutorLibrary.tsx`.

## 5. P5: Paywall

One interceptor or helper: `ApiException.isPaywall` → bottom sheet with plan info from `/billing/status`
(Free vs Pro limits, price). Razorpay **test mode** (`razorpay_flutter`) only in sideloaded builds;
`POST /billing/razorpay/order` → checkout → `POST /billing/razorpay/verify`. Hide the purchase button in Play builds
until Play Billing exists.

## 6. Social gaps (server + app)

- Server: unfollow (`DELETE /users/{u}/follow`), reject request, followers/following lists, `PUT /me` (fullname, bio),
  profile photo (upload + `avatar_url` column), `/posts/{id}` with counts, delete a comment,
  "liked by" list UI (`/posts/{id}/likes/{page}` exists).
- App: profile edit screen, followers/following sheets, post detail route `/p/:id` (for share links), video playback
  (`video_player`; the card shows a placeholder today), image pinch-zoom, share post (`share_plus`).

## 7. P6: Mobile extras (`PLAN.md` §5)

Push notifications (FCM + `POST /me/devices`, sends on follow request/approval/like/comment), share-target
("Share to Outstagram", `receive_sharing_intent`), result cards as images to WhatsApp/Instagram Stories, App Links
(`/.well-known/assetlinks.json` on the web host) for post/profile URLs, launcher shortcuts, offline exam packs,
local notifications (exam time left, quota reset), home-screen widget.

## 8. P7: Release to Play

Upload keystore + `key.properties`; Play App Signing; register upload and app-signing SHA-1s as Android OAuth clients;
**Google Play Billing** for Pro (server verifies purchase tokens, grants the same `pro_until`) replacing Razorpay;
**account deletion** in-app + web page (`DELETE /me`, Play requirement); data safety form; privacy URL (`/privacy`
exists on the web); OAuth consent screen published; internal testing track; clean test posts and accounts off prod;
real app icon and splash (currently the Flutter default icon).

## 9. Housekeeping

- Delete unused platform folders (`ios/ linux/ macos/ windows/ web/`) or keep them deliberately.
- Remove `build_runner` from dev deps if codegen is never adopted.
- Add a prod-APK artifact (or GitHub Release) job to CI, signed consistently, so friends can download builds.
- Add the mobile app to the cross-project roadmap in `outstagram-web/TODO.md`.
- Upgrade plugins that warn about "Built-in Kotlin" when new versions exist (build output lists them).
