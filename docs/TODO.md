# TODO: Outstagram mobile

Ordered roughly by priority. Each item says *what*, *why*, and *how* so a fresh session can pick it up.
Tick items off here (and in `AGENTS.md` §1) when done. Last updated: 2026-11-24.

## 0. Verify right now (quick)

- [x] **Google sign-in on device (prod flavor).** Works (2026-11-24): Web client as `serverClientId`, Android
      OAuth client with the debug SHA-1 (`docs/auth.md` §5).
- [ ] **OAuth consent screen**: published, or friends added as test users (`docs/auth.md` §5).
- [ ] **Supabase Redirect URLs** for the browser fallback (`docs/auth.md` §4).
- [ ] **Clean prod test data before release:** QA account `qa_tester1` (user_id 7, created 2026-11-24 by Claude for adb QA).
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
**Mitigated 2026-11-24** (outstagram-server PR #3): listings and post view re-sign stored URLs on read. Still worth
doing for permanent, CDN-cacheable links:
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

## 3. P3: Exams ✅ (2026-11-24)

Done and verified on device (S22, prod): quick practice, mocks, community exams, runner, kill-and-resume, results,
review, attempts history (opens attempts made on the web too). Leftovers:
- [ ] Server exam presets (`/api/exam_presets`, 0 on prod) aren't listed yet.
- [ ] "Share to feed" from results (composer prefilled, category Exam Result) and result cards (P6).
- [ ] Community exams: only page 1 (10) is shown; add paging.
- [ ] Topic chart is plain bars (no `fl_chart`); fine for now.
- [ ] Web label says GATE "65 Qs" but the pattern sums to 61 (`outstagram-web` `PRESETS`); the app says 61.

## 4. P4: AI tutor ✅ built (2026-11-24)

Built: `lib/features/tutor/` (see `AGENTS.md` §2). Entry points: "Ask the AI tutor" in each expanded review card
(results and past attempts) and the ✨ button on the Exams tab (library). Open items:
- [x] **On-device QA (S22, prod, 2026-11-24):** review card → tutor; history reloads; live ask → "Checking the textbooks…"
      → streamed answer (~10 s) with display/inline LaTeX + citations; quota pill 9→8/10; long-press equation → saved
      (snackbar auto-hides); library chats (usage bar) and equations (render, delete) work.
- [ ] Not yet tried on device: voice input (mic permission prompt), skill chips (prod has a single skill, so they're
      hidden), deleting a chat, leaving mid-answer.
- [ ] One answer rendered "x(A cos(ωt+φ₁)" where "x(t) = A cos…" was expected. A widget test renders that LaTeX
      correctly, so it's most likely the model's text; check the stored message if it shows up again.
- [ ] Limit errors (429/402) currently show inline text only. P5 turns them into the paywall sheet.
- [ ] Local notification when the hourly quota resets (PLAN §5), pinch-zoom on long equations.

Original notes:

Server side verified 2026-11-24: `/chat/stream` answers in ~15 s with citations and knows the user's answer.
Entry point in the app: a "Ask the AI tutor" button on each review card (`exam_result_screen.dart` `_ReviewCard`);
the attempt id comes from `saveAttempt` (fresh) or the route (`/exam/attempt/:id`).

SSE client over Dio `ResponseType.stream` for `POST /exam-attempts/{id}/chat/stream` (`status`, `meta`, `delta`, `done`,
`error` events; limit errors arrive as normal HTTP errors before the stream). Markdown + LaTeX rendering with citations,
skill chips (`/ai/skills`), quota pill (`/ai/quota`), tutor library (`/ai/chats`, delete), saved equations
(long-press → haptic → `POST /favorites/equations`), voice input (`speech_to_text`). Reference: `QuestionChat.tsx`,
`TutorMarkdown.tsx`, `TutorLibrary.tsx`.

## 5. P5: Paywall ✅ built (2026-11-24)

`lib/features/billing/`: `showError` opens the upgrade sheet for any paywall error (429/402/413 with
`detail.upgrade`); the tutor opens it on a quota/history limit (and on send when the cached quota is already out);
"Outstagram Pro" in the profile ⋮ menu opens it manually (shows the pass for Pro users). Free vs Pro table and price
from `/billing/status`; Razorpay native Checkout → `/billing/razorpay/verify` → plan + quota refreshed. The composer's
per-photo limit follows the plan (`limits.media_bytes`). The button is hidden when `STORE=play` or the server has no keys.
- [x] **Prod has Razorpay test keys** (2026-11-24): the `razorpay-test-*` secrets are attached to `outsie` too, so the
      pay button is live on prod app **and web** in test mode (no real money). Swap to live keys before charging anyone.
- [ ] **Razorpay dashboard webhook for prod** (Test mode → Webhooks): URL `https://outsie-mgenvq5gwa-an.a.run.app/billing/razorpay/webhook`
      (direct Cloud Run URL: Cloudflare in front of outsie.aryan.cfd blocked a non-browser user agent with 403),
      secret = `RAZORPAY_WEBHOOK_SECRET` in `env.razorpay.txt`, events `payment.captured`, `order.paid`, `payment.failed`.
      Only a safety net: the app's verify call already grants Pro. Signed requests verified with a self-test on 2026-11-24.
- [x] On-device QA (S22, prod, 2026-11-24): menu → sheet (live limits/price) → Checkout (email prefilled, brand colour);
      back out → sheet unchanged; Netbanking demo bank Failure → Checkout's own retry screen; Success → "Welcome to Pro",
      sheet shows "Pro until Dec 24, 2026". This account's test Checkout offers no UPI, so `success@razorpay` doesn't apply.
- [ ] Not yet tried on device: paywall from a real tutor 429 (needs 10 prompts in an hour on a free account), Pro photo size.
- [ ] `outstagram-web` Paywall still says "Pay by UPI with success@razorpay"; same fix as the app's hint.
- [ ] Clean test `payment`/`userplan` rows off prod before the public release (qa_tester1 is Pro until 2026-12-24).

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
app icon and splash done 2026-11-24 (vector, from the new logo kit); Play needs a 512×512 PNG icon and a 1024×500 feature graphic (export from `../assets/`; `icon-1024.png` there is transparent and off-centre, so re-export it centred on the navy tile).

## 9. Housekeeping

- **Flutter 3.47 migration:** 3.47 deprecates `package:flutter/material.dart` in favour of `package:material_ui/material_ui.dart`,
  which fails `flutter analyze` on every file. CI is pinned to 3.44.8 (`.github/workflows/ci.yml`) to match the local SDK.
  Upgrade locally, switch the imports, then bump the pin.

- Delete unused platform folders (`ios/ linux/ macos/ windows/ web/`) or keep them deliberately.
- Remove `build_runner` from dev deps if codegen is never adopted.
- Add a prod-APK artifact (or GitHub Release) job to CI, signed consistently, so friends can download builds.
- Add the mobile app to the cross-project roadmap in `outstagram-web/TODO.md`.
- Upgrade plugins that warn about "Built-in Kotlin" when new versions exist (build output lists them).
