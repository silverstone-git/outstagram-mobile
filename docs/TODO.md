# TODO: Outstagram mobile

Ordered roughly by priority. Each item says *what*, *why*, and *how* so a fresh session can pick it up.
Tick items off here (and in `AGENTS.md` §1) when done. Last updated: 2026-11-25.

## 0. Verify right now (quick)

- [x] **Google sign-in on device (prod flavor).** Works (2026-11-24): Web client as `serverClientId`, Android
      OAuth client with the debug SHA-1 (`docs/auth.md` §5).
- [x] **OAuth consent screen**: published (External) and brand-verified by the user, 2026-11-25.
- [x] **Supabase email templates** (user, 2026-11-25): Magic Link + Confirm signup must contain `{{ .Token }}`, OTP length 6, on **both**
      projects (`docs/auth.md` §6). Email codes, password reset and confirming emails all depend on it.
- [x] **On-device QA of streak, gate, profile photo** (S22, prod, 2026-11-25; `docs/qa.md` §4 lists what it found).
- [ ] **Email codes on device** (needs the user's inbox): register → confirm step (code arrives), email-code sign-in with a new
      address, forgot password, change email. Also still unseen: a streak reminder actually firing (set "Remind me at" a few
      minutes ahead on `/streak` on a day the quiz isn't done).
- [ ] **Supabase Redirect URLs** for the browser fallback (`docs/auth.md` §4).
- [ ] **Clean prod test data before release:** QA account `qa_tester1` (user_id 7, created 2026-11-24 by Claude for adb QA).
- [ ] **On-device QA of P2**: feed/explore, like/double-tap, comments, search → follow → approve (two accounts),
      post with 1 and several photos, text-only post, delete, profile counts, theme toggle, sign-out/in.

## 1. Email sign-in with a 6-digit code (+ custom SMTP) ✅ built 2026-11-25

Done as planned below, plus password reset, confirm email (with a gate on posting/uploads/tutor) and change email;
see `docs/auth.md` §6 and `docs/api.md` → Auth. The web got the same (login: email code / forgot password; confirm banner).
Still open: the Supabase template step in §0; setting a password from the profile for Google-only accounts can use
"Change password" (reset flow) already. The original plan, kept for reference:

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

## 2. Media links (decided 2026-11-25)

The `outstagram` bucket is **private by design** (user, 2026-11-25: `pariksha` = public, `outstagram` = private user
content). Posts store 7-day presigned URLs and the server re-signs them on every read (`media.fresh_media_url`,
cached per key so a link stays stable for ~3 days), so old images keep working. The app caches images by object path
(`Avatar.cacheKey`), so re-signed links don't re-download. Don't set `S3_PUBLIC_BASE_URL` for this bucket.
- [ ] Optional: a stable `GET /media/{key}` on outsie that 302s to a fresh presigned URL, stored instead of the
      presigned URL at upload time (links never expire in the DB; still unguessable-key access, like presigned links).
- [x] Question images (public `pariksha` bucket) moved to `https://outsiebucket.aryan.cfd` in web, app and pariksha
      (2026-11-25) after the r2.dev URL was disabled. The **web needs a redeploy** (`outstagram-web/scripts/preview.sh deploy`
      on the portfolio box); pariksha too wherever it's served.

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

- [x] Profile photo (2026-11-25): `PUT/DELETE /me/avatar`, shown on profiles, posts, comments, search, requests (app + web).
- [x] **Mutual-follow bug** (2026-11-25, server PR #9): approving the second half of a mutual follow 400'd
      "Friendship already exists", so that request stayed pending (qa_tester1 1 follower / 0 following, cyto the
      reverse). Fixed; the stuck request goes through when it's approved again from Activity.
- [x] Social basics (2026-11-25; server PR #9, app branch `feat/social-basics`): unfollow / cancel request (tap
      Following/Requested), Decline on Activity, followers/following lists (tap the counts; Remove on your own
      followers), Edit profile (name, bio), long-press to delete a comment (yours, or any on your post),
      `/p/:id` post page + "Share link" / "Open post" in the post ⋮ menu, tap a photo → full-screen pinch/double-tap
      zoom, video playback (`video_player`, tap to play, muted until unmuted). Needs on-device QA.
- [ ] Web: same features (unfollow, decline, lists, edit profile, delete comment) and a `/p/<id>` page (also needed for App Links).
- [ ] "liked by" list UI (`/posts/{id}/likes/{page}` exists).

## 7. P6: Mobile extras (`PLAN.md` §5)

Done 2026-11-24 (verified on the S22, prod):
- [x] **Result cards:** share icon on any result → 4:5 branded card → "Share image" (Android share sheet, caption + link)
      or "Post to your feed" (composer prefilled: image, caption, Exam Result). Only topics above 0% are listed.
- [x] **Share to Outstagram:** photos/text from other apps open the composer (`share_intent.dart`); waits for sign-in.
- [x] **Launcher shortcuts:** New post, Practice exam, AI tutor (long-press the icon). Cold start goes to the route.

Next, needs the user:
- [ ] ~~**Push notifications (FCM):**~~ dropped for now (user, 2026-11-25: no Firebase). Original notes: needs a Firebase project linked to GCP `top-athlete-472606-v4` and the two Android
      apps registered (`com.cyto.outstagram`, `.staging`) → `google-services.json` per flavor. Then server: `POST /me/devices`,
      a `devicetoken` table (re-run supabase-lockdown.sql), sends on follow request/approval/like/comment via FCM HTTP v1
      (service account on Cloud Run); app: `firebase_messaging`, notification permission (Android 13+), tap → deep link.
- [ ] **App Links** for post/profile URLs: `https://aryan.cfd/.well-known/assetlinks.json` at the **domain root** (portfolio
      server, not this repo) with the signing SHA-256; post detail route `/p/:id` first (`docs/TODO.md` §6).
- [x] **Daily streak** (2026-11-25): any finished exam with an answer counts the day (user's time zone); 5-question
      pop quizzes from the chosen subject; streak screen (flame, week strip, 6-week calendar, milestones, 250-day reward
      card), chips in the Feed/Exams app bars, full-screen celebration with confetti; local reminders at the chosen time,
      21:00 and 22:30 on at-risk days, come-back messages after. 250 days = 60 AI prompts/hour + 1000 saved chats for good.
- [ ] Streak ideas for later: streak freeze (skip one day), friends' streaks on profiles, a home-screen widget.
- [ ] Local notifications: "5 minutes left" when leaving a running exam; "your tutor is back" when the quota resets
      (flutter_local_notifications is in now; reuse `StreakReminders`' plugin instance).
- [ ] Offline exam packs, home-screen widget, video posts in share-target.

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
- [x] CI job `publish-apk` (2026-11-25): pushes to `main` build the prod APK and **replace** `apps/outstagram.apk`
      in the public `pariksha` bucket (one object, overwritten). Needs the secrets in `docs/environments.md` → "Friends' APK link".
- [ ] Point the web landing's `APPS.androidApk` (`outstagram-web/src/features/public/routes.ts`, now a Drive link) at `https://outsiebucket.aryan.cfd/apps/outstagram.apk` once the first upload exists.
- Add the mobile app to the cross-project roadmap in `outstagram-web/TODO.md`.
- Upgrade plugins that warn about "Built-in Kotlin" when new versions exist (build output lists them).
