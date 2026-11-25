# Outstagram Mobile: plan

> **Status and rules live in [`AGENTS.md`](AGENTS.md); open work is in [`docs/TODO.md`](docs/TODO.md).** This file is the original design plan (2026-11-24). Background, not status. Since it was written: P0–P2 are done, the app is wired to the prod API for friend testing, and S1/S2/S5 plus search/explore shipped to prod.

Flutter client for **outsie** (`outstagram-server`, FastAPI on Cloud Run). It aims for full parity with `outstagram-web` and uses what a phone can do that a browser can't.
Written 2026-11-24 from a read of `outstagram-server` (`feat/admin-google`) and `outstagram-web` (`feat/landing-legal`).

---

## 0. Problems in the scaffold (fix first)

| Problem | Why it matters | Fix |
|---|---|---|
| `android/` was overwritten by a `gradle init` Kotlin JVM template (`mainClass = "org.example.AppKt"`, no Flutter plugin) | The app cannot build for Android at all | Delete `android/` and run `flutter create --platforms=android --org <org> --project-name outstagram .`. Same for `ios/` later if needed. Drop `linux/ macos/ windows/ web/` unless wanted |
| Not a git repo | — | `git init`, then `gh repo create silverstone-git/outstagram-app --private` (the roadmap already names it "outstagram-app") |
| `.gitignore` misses `.env` and `client_secret_*.json` | Secrets would be committed on the first `git add .` | Add `.env*`, `client_secret_*.json`, `*.jks`, `key.properties`, `android/local.properties` |
| `client_secret_…json` is an **"installed" (Desktop) OAuth client** | The app doesn't need it (see §2). An Android app never holds a client secret | Move it out of the project, or delete it if that client has no other use |
| `.env` read at runtime (e.g. flutter_dotenv) | Ships as a plain asset in the APK anyway | Use `--dart-define-from-file=config/staging.json` / `prod.json`. These hold only public values: API base, Supabase URL, publishable key, Google **web** client ID |

---

## 1. What has to be matched (web feature inventory)

**Social:** password register/login, Google sign-in. Feed (reverse-chronological, category filter, paging), like/unlike, comments, post view, create post (multi-image/video, client-side compression, category, exam-result fields, hashtags with trending suggestions), edit and delete own post. Profile (posts grid, counts, follow state), follow requests and approval, dashboard (`/me/stats`, `/trending`). Session-expired dialog, light/dark theme.

**Exams (Pariksha engine, `engine.ts`):** presets (GATE, CSIR NET, TIFR, BARC), server exam types (`/api/exam_presets`), quick practice by subject (`/api/question_bank/sample`), community exams (`/pariksha`). Question types MCQ/MSQ/NAT, sections, negative marking, `maxAttempts`, timer, flagging, palette, auto-submit. Results: score, topic breakdown, SWOT, filtered review. Attempts history (`/exam-attempts`). Share a result to the feed.

**AI tutor:** per-question chat streamed over SSE (`/exam-attempts/{id}/chat/stream`: `status`, `meta`, `delta`, `done`, `error`). Markdown + KaTeX with citations, skill chips (`/ai/skills`), quota (`/ai/quota`), tutor library (`/ai/chats`), long-press an equation to save it (`/favorites/equations`).

**Billing:** paywall sheet raised from `429 ai_quota`, `402 tutor_threads|tutor_storage` and `413 media_too_large` (all share `detail.upgrade: true`). Razorpay Pro pass (`/billing/*`). Public pricing and legal pages.

---

## 2. Auth: the key design decision

What the server does today: outsie issues its **own HS256 JWT, valid for 30 minutes, with no refresh token**. Google sign-in only works through `POST /auth/supabase {auth_code, code_verifier}`, a PKCE code produced by a *browser redirect* through Supabase.

### Recommended: native Google sign-in (Credential Manager bottom sheet) plus a small server addition

1. The app calls `google_sign_in` with `serverClientId = <Web client ID>`. Android shows the system account picker, with no browser.
2. The app receives a Google **ID token** (audience = the web client ID) and sends `POST /auth/google {id_token, nonce}` to outsie.
3. **New server endpoint:** outsie posts it to Supabase `POST /auth/v1/token?grant_type=id_token {provider:"google", id_token, nonce}` with the publishable key. Supabase verifies it and returns the same `user` object that `exchange_code` returns today. The server then reuses `find_or_create_user` and links accounts by verified email. That is about 25 lines in `social_auth.py`.

### Fallback (zero server change, worse UX)

Run the same PKCE flow as the web, in a Custom Tab (`flutter_web_auth_2`), with `redirect_to=outstagram://auth-callback`. Then POST the code to the existing `/auth/supabase`. This needs `outstagram://auth-callback` (and the staging scheme) in the Supabase **Redirect URLs**. It also covers GitHub later at no extra cost.

### Google Cloud and Supabase setup

- **Web application** OAuth client: the one Supabase's Google provider already uses for the web flow. Its ID is the app's `serverClientId`. A Desktop/"installed" client **cannot** serve as `serverClientId`.
- One **Android** OAuth client per package name × signing cert (SHA-1): debug keystore, upload key, and the Play App Signing key. These have no secret and never appear in the code. They only let Google issue tokens to this app.
- Supabase → Auth → Google → **Client IDs** (the authorized list): include the web client ID (comma-separated with any others). If the client ID you pasted was the Desktop one, swap it for the web one there.
- The consent screen is still in **Testing**: only listed test users can sign in until it's published (already on the web roadmap).
- Use the same GCP project as the existing web client (check that it really owns the web client).

### Sessions on mobile: server change needed

A 30-minute token with no refresh means re-login several times a day. Add:
- `refresh_token`: opaque, stored hashed per device, rotating, about 60 days. Returned by `/login`, `/auth/supabase` and `/auth/google`.
- `POST /auth/refresh`, `POST /auth/logout` (revokes the device's token).
- The web keeps working unchanged because the field is additive.

The client keeps tokens in `flutter_secure_storage`. A Dio interceptor runs a single-flight refresh on 401, then retries. If the refresh fails, the app returns to sign-in and keeps any exam draft.

---

## 3. Other server work (`outstagram-server`, branch `feat/mobile-api`)

| # | Change | Needed for |
|---|---|---|
| S1 | `POST /auth/google` (ID token via Supabase) | Native sign-in |
| S2 | Refresh tokens, `/auth/refresh`, `/auth/logout` | Usable mobile sessions |
| S3 | `DELETE /me` (and its data) + a web page explaining deletion | **Play Store requirement** for apps with accounts |
| S4 | `POST/DELETE /me/devices {fcm_token}` + FCM sends on follow request, approval, like, comment | Push notifications |
| S5 | `like_count`, `comment_count` on `PostPublic` | Instagram-grade feed without N+1 calls |
| S6 | Unfollow, reject request, followers/following lists, user search, edit profile (name/bio/avatar) | Gaps on web too; cheap to add, and both clients gain |
| S7 | Play Billing purchase verification (only if decision D2 = Play Billing) | Pro on Android |
| S8 | `/.well-known/assetlinks.json` on the web host | App Links (open post/profile URLs in the app) |

Every new table must keep the RLS lockdown (`scripts/supabase-lockdown.sql`).

---

## 4. Client architecture

| Concern | Choice | Why |
|---|---|---|
| State | `flutter_riverpod` (+ codegen) | Testable and async-first. Fits paging and streaming |
| Routing | `go_router` with `StatefulShellRoute` | Tabs keep their own back stacks. Deep links / App Links come free |
| HTTP | `dio` | Interceptors (auth refresh, paywall detection), multipart upload **progress**, streamed responses for SSE |
| Models | `freezed` + `json_serializable` | Immutable models matching `schemas.py` |
| Local DB | `drift` (SQLite) | Exam drafts survive the app being killed, offline cache, upload queue |
| Secrets | `flutter_secure_storage` | Tokens in the Android Keystore |
| Images | `cached_network_image`, `image_picker`, `image_cropper`, `flutter_image_compress` (WebP), `photo_view` | Native compression before the 200 kB free limit; pinch-zoom |
| Video | `video_player` | Feed video |
| Math / Markdown | `flutter_math_fork` + a Markdown renderer with `$…$`/`$$…$$` support (e.g. `gpt_markdown`) | KaTeX parity, incremental rendering while streaming |
| Charts | `fl_chart` | Topic accuracy and time breakdown |
| Fonts/theme | Material 3, brand tokens ported from `index.css` (dark `#0f0f23` / neon `#00ff88`; light `#f6f7fb` / emerald `#047857`; accent amber) | Same identity, dark by default |

```
lib/
  main.dart                 # flavor bootstrap, ProviderScope
  app/                      # router, theme, shell (bottom nav)
  core/
    config/                 # dart-define env (apiBase, supabaseUrl, googleWebClientId)
    net/                    # dio client, auth interceptor, paywall interceptor, SSE parser
    auth/                   # session store, refresh, google + password + pkce fallback
    db/                     # drift schema: exam_drafts, cached_feed, upload_queue, equations
    ui/                     # design system: buttons, sheets, skeletons, avatar, latex, markdown
  features/
    auth/  feed/  post/  compose/  profile/  social/  activity/
    exams/ (engine/, home/, runner/, results/, history/)
    tutor/ (chat/, library/, equations/)
    billing/  settings/
test/  integration_test/
```

**Exam engine port:** `engine.ts` becomes pure Dart (`features/exams/engine/`) with no Flutter imports. To guarantee identical scoring, a small Bun script runs the TS `scoreExam` over a set of fixture exams and answers and writes golden JSON. The Dart tests assert the same scores, SWOT and topic stats.

**Navigation:** bottom bar with **Home** (feed), **Exams**, **＋ Create**, **Activity** (requests, likes, comments), **Profile** (the web "dashboard" stats live on top of the profile). The exam runner and the tutor open as full-screen immersive routes outside the shell.

---

## 5. Beyond the web (the reasons to install the app)

**Exams**
- **Crash-proof attempts:** every answer, flag and timer tick is written to drift. If the app is killed or the phone reboots, the attempt resumes where it stopped.
- **Offline mode:** download a preset or practice pack, take it without network, and the submission queues and syncs later.
- **Focus mode:** `wakelock_plus`, `PopScope` guard against an accidental back, and app switches counted and shown in results ("left the app 3×"). Optional: DND prompt, `FLAG_SECURE`.
- Haptics on select/flag/submit, swipe between questions, palette as a draggable bottom sheet.
- A local notification "5 minutes left" if you leave the app mid-exam.

**Tutor**
- **Voice questions** (`speech_to_text`), with streaming replies rendered as they arrive.
- Long-press an equation: haptic feedback, then save or copy the LaTeX. Pinch-zoom on figures.
- A local notification when the hourly AI quota resets ("Your tutor is back").

**Social**
- **Share-target:** "Share to Outstagram" from Gallery or any app (`receive_sharing_intent`) opens the composer prefilled.
- Camera capture → crop → native WebP compress → upload with a progress ring. A failed upload stays queued and retries on reconnect.
- **Result cards:** the exam result is rendered into a styled image (`RepaintBoundary` → PNG) and shared via `share_plus` to WhatsApp or Instagram Stories, or posted to the feed.
- Double-tap to like, comments in a bottom sheet, pull to refresh, cached feed offline.
- **Push** (needs S4) for follow requests, approvals, likes and comments, with deep links to the post.
- **App Links** (needs S8): post and profile URLs open in the app.

**Platform**
- Launcher shortcuts ("Quick practice", "New post"), a later home-screen widget (study streak, quota), predictive back, edge-to-edge, Material You surfaces kept on brand.
- Optional biometric app lock.

---

## 6. Payments: decision needed (D2)

Pro unlocks digital features *inside the app*. Google Play policy requires Play Billing for that. In India an alternative-billing option also exists ("user choice billing", Play shows its own choice screen and charges a reduced fee). **Opening Razorpay Checkout inside a Play-distributed app for Pro would likely get the app rejected.**

Options:
1. **Play Billing** for Pro on Android (`in_app_purchase`). The server verifies purchases (S7) and grants the same `pro_until`. This is the safest path.
2. **User choice billing** keeping Razorpay. It needs Play enrollment and the extra choice-screen integration.
3. **No in-app purchase for v1:** the paywall explains the limit and Pro is bought on the web. Only allowed without steering language or buttons; check the current policy wording before relying on it.

Recommendation: ship v1 with option 3 (or hide the upsell), and add option 1 in a later phase.

---

## 7. Phases

| Phase | Scope | Exit criteria |
|---|---|---|
| **P0 Foundation** | Regenerate `android/`, git + GitHub repo, flavors `staging` (`.staging` suffix, outsie-staging) and `prod`, dart-define configs, theme, router shell, Dio client, CI (analyze, test, build staging APK as an artifact) | A staging APK from CI installs next to prod |
| **P1 Auth** | Password login/register; S1 + S2 on the server; native Google sign-in; PKCE fallback; secure session plus refresh; session-expired handling | Google and password sign-in on a real device against staging; the session survives a day |
| **P2 Social parity** | Feed, post view, likes, comments, composer with native compression/crop/progress, profile + stats + trending, follow requests, edit/delete post | Every web social flow works on the phone |
| **P3 Exams parity** | Dart engine with golden tests, exams home (presets, server presets, practice, community), runner with drift autosave, results + charts + review, history, share to feed | Golden tests green; an exam resumes after the app is force-stopped |
| **P4 Tutor** | SSE client, Markdown + LaTeX streaming, skills, quota UI, library, saved equations, voice input | Parity with `QuestionChat.tsx` + `TutorLibrary.tsx` |
| **P5 Paywall** | Paywall interceptor + sheet according to D2 | 429/402/413 all land on the sheet |
| **P6 Mobile extras** | Push (S4), share-target, result-card sharing, App Links (S8), shortcuts, offline packs, local notifications, S5/S6 social gaps | — |
| **P7 Release** | Upload keystore + Play App Signing (add its SHA-1 to Google), `DELETE /me` (S3), data-safety form, privacy URL (`/privacy` exists), publish the OAuth consent screen, internal testing track. Later: `gh` workflow uploads the AAB to Play | Internal testers install from Play |

**Testing:** unit tests (engine, SSE parser, interceptors), widget tests, and an `integration_test` run against a fake API built from the same fixtures as `outstagram-web/e2e/fixtures.mjs`, with screenshots on CI to mirror the web pipeline.

---

## 8. Decisions (2026-11-24)

- **D1** Application ID `com.cyto.outstagram` (staging: `com.cyto.outstagram.staging`).
- **D2** Razorpay **test mode** for now; Google Play Billing is added before the public release (P7 gate).
- **D3** iOS out of scope for now.
- **D4** Server changes approved. S1 + S2 are done on `outstagram-server` `feat/mobile-api` (CI green), not deployed yet.

## 9. Setup checklist (manual, consoles)

- [ ] Google Cloud (the outsie project) → Credentials → **Android** OAuth client: package `com.cyto.outstagram.staging`, SHA-1 of the debug keystore. Add one for `com.cyto.outstagram` too, and later the upload / Play App Signing SHA-1s.
- [ ] Supabase (both projects) → Auth → Google → Client IDs: the Web client `595282356777-ppkjuihe…` must be in the list (it already is the main client ID). The Desktop client is not needed.
- [ ] Supabase → Auth → URL configuration → Redirect URLs: `com.cyto.outstagram.staging://auth-callback` (staging project) and `com.cyto.outstagram://auth-callback` (prod). This is only for the browser fallback (long-press the Google button).
- [ ] Deploy `feat/mobile-api` to `outsie-staging`, then re-run `scripts/supabase-lockdown.sql` (new `refreshtoken` table).

## Build

```
flutter run --flavor staging --dart-define-from-file=config/staging.json
flutter build apk --flavor prod --dart-define-from-file=config/prod.json
```
