# AGENTS.md: Outstagram mobile (Flutter) guide

Entry point for any agent or human working in `outstagram_mobile/`. It holds the rules, the current
status, the repository map and the commands. Deep dives live in `docs/`:

| File | What's in it |
|---|---|
| `docs/auth.md` | Every sign-in flow, sessions and refresh, Google Cloud + Supabase setup, troubleshooting |
| `docs/api.md` | The outsie endpoints the app uses, their exact shapes and quirks |
| `docs/environments.md` | Staging vs prod, flavors, configs, deploys, databases, devices, release signing |
| `docs/TODO.md` | Roadmap and open work, including the email sign-in code + SMTP plan |
| `PLAN.md` | The original product/architecture plan (phases P0–P7, mobile-only extras). Background, not status |

Last updated: 2026-11-24 (P5 paywall built; needs on-device QA with Razorpay test mode).

---

## 0. Quick contract

**Do**
- Run `flutter analyze` (must print "No issues found!") and `flutter test` before every commit.
- Build with a flavor **and** its matching config: `--flavor prod --dart-define-from-file=config/prod.json` (or `staging`). A flavor with the wrong config silently talks to the wrong server.
- Put every network call behind `Api` (`lib/core/net/api_client.dart`) or `AuthRepository`, and surface failures with `ApiException` + `showError(context, e)`.
- Keep server changes additive. The web client (`outstagram-web`) uses the same API. Add fields, don't rename or remove them.
- When you add a server table, re-run `outstagram-server/scripts/supabase-lockdown.sql` on **both** Supabase projects (see `docs/environments.md`).
- When you add or change a server endpoint, add a check to `outstagram-server/tests/test_*.py` and a CI step in `.github/workflows/test.yml`.
- Keep this file and `docs/` current when you change behaviour. Future sessions rely on them.

**Don't**
- Don't commit `.env`, `client_secret_*.json`, keystores or `key.properties` (all git-ignored). `config/*.json` must only ever hold **public** values; they end up inside the APK.
- Don't print or paste secrets: the workspace root holds `env.supabase.txt`, `.env.outstagram*` and `env.razorpay.txt` with real DB passwords and keys. Read them inside scripts only, never `cat` them.
- Don't push to `silverstone-git/outstagram-app`. It's the user's **old public** Kotlin/Compose app (Feb 2025). This app lives in **`silverstone-git/outstagram-mobile`** (private).
- Don't use the Desktop OAuth client (`595282356777-41rf…`, the `client_secret_*.json` / `.env` value) anywhere. The app's `serverClientId` is the **Web** client (`docs/auth.md`).
- Don't add a Razorpay checkout to a Play Store build. Razorpay **test mode** is fine for sideloaded test APKs; Google Play Billing must replace it before a Play release (user decision, `docs/TODO.md`).
- Don't add iOS work. It's out of scope until the user has an Apple device.

---

## 1. What this is and where it stands

Android app (Flutter) for **outsie**, the FastAPI backend in `../outstagram-server`
(GitHub `silverstone-git/outstagram`). It's a student social network (posts, follows, exam results) plus
**Pariksha** exams and an AI tutor. Goal: everything the web app (`../outstagram-web`) does, plus phone-only
advantages (see `PLAN.md` §5).

| Phase | Scope | Status |
|---|---|---|
| P0 Foundation | Flavors, configs, theme, router shell, Dio client, CI | ✅ done |
| P1 Auth | Password + register, native Google, PKCE browser fallback, refresh tokens | ✅ done (Google sign-in verified on device 2026-11-24: Web client as `serverClientId` + Android client with the debug SHA-1) |
| P2 Social | Feed/Explore, post card, likes, comments, search, profiles, follow requests, composer | ✅ done (needs on-device QA) |
| P3 Exams | Dart port of the Pariksha engine, presets, practice, community exams, runner, results, history | ✅ done 2026-11-24 (verified on device; leftovers in `docs/TODO.md` §3) |
| P4 AI tutor | SSE streaming, Markdown + LaTeX, skills, quota, library, saved equations, voice input | ✅ built 2026-11-24 (unit/widget tested; on-device QA pending, `docs/TODO.md` §4) |
| P5 Paywall | 429/402/413 → upgrade sheet, Razorpay test | ✅ built 2026-11-24 (widget tested; prod on Razorpay test keys; payment verified on device 2026-11-24, `docs/TODO.md` §5) |
| P6 Mobile extras | Push, share-target, result cards, App Links, offline packs | ⏳ |
| P7 Release | Upload key, Play Billing, account deletion, Play listing | ⏳ |

**Testing setup decided by the user (2026-11-24):** the *prod* flavor talks to the **production** outsie +
database, and friends test on prod. Test posts and accounts get cleaned up by hand before the public release.
The *staging* flavor talks to `outsie-staging` for risky work.

---

## 2. Repository map

```
lib/
  main.dart                      edge-to-edge, ProviderScope
  app/
    app.dart                     MaterialApp.router (themes, router)
    router.dart                  go_router: auth redirect, 5-tab StatefulShellRoute, /search, /u/:username
    theme.dart                   brand tokens (from outstagram-web index.css), dark default, ThemeMode persisted
  core/
    config/env.dart              compile-time config (FLAVOR, API_BASE, GOOGLE_SERVER_CLIENT_ID, AUTH_SCHEME, WEB_BASE, STORE)
    auth/
      session.dart               AppUser, Session (access, refresh, expiresAt)
      session_store.dart         flutter_secure_storage persistence (key outsie_session_v1)
      auth_repository.dart       /login, /register, /auth/google, PKCE /auth/supabase, /auth/refresh, /auth/logout (bare Dio)
      auth_controller.dart       AsyncNotifier<Session?>; single-flight refresh(); providers
      google_auth.dart           google_sign_in 7 (Credential Manager) + nonce; SignInCancelled
    net/
      api_client.dart            dioProvider + AuthInterceptor (pre-expiry refresh, 401 → refresh → retry once), Api wrapper
      api_error.dart             ApiException (FastAPI detail parsing, isPaywall, isNetwork)
    ui/
      math_text.dart             MathText: inline/display LaTeX (flutter_math_fork), web-compatible clean-up
      avatar.dart                letter avatar coloured by username (the API has no profile photos)
      feedback.dart              showError(context, e): snackbar, or the upgrade sheet for paywall errors
  features/
    auth/                        sign-in, register, splash, BrandMark (SVG mark + "Outsta"/"gram" text) and BrandSymbol
    shell/                       AppShell (NavigationBar), ComingSoon placeholder
    feed/                        models.dart (Post, Comment, Profile, …), social_api.dart, post_card.dart,
                                 post_list.dart (infinite + pull-to-refresh), comments_sheet.dart, home_screen.dart
    social/search_screen.dart    debounced /users/search
    profile/                     profile_view.dart (header + posts, follow button, stats), profile_screen.dart
    activity/activity_screen.dart follow requests + approve
    compose/compose_screen.dart  pick/camera → WebP ≤200 kB → /media-upload/bulk → /posts; postsVersionProvider
    exams/
      engine/                    pure Dart port of outstagram-web engine.ts: models (raw-JSON questions), scoring, presets
      exam_api.dart              question bank sampling, community exams, /exam-attempts
      exam_session.dart          running exam (Notifier) autosaved to shared_preferences (exam_session_v1); resume
      exams_home_screen.dart     resume card, quick practice, mocks, attempts, community
      exam_runner_screen.dart    /exam/run full-screen: PageView, palette, timer + auto-submit, wakelock, PopScope
      exam_result_screen.dart    /exam/result (fresh, saves attempt) and /exam/attempt/:id; score, topics, SWOT, review,
                                 "Ask the AI tutor" per question (needs the saved attempt id)
    billing/
      billing_api.dart           BillingStatus/Limits/Price, /billing/status|razorpay/order|razorpay/verify, billingStatusProvider
      razorpay_checkout.dart     openRazorpay(order): native Checkout → RazorpayResult | null (cancelled) | ApiException
      paywall_sheet.dart         showPaywall / showPaywallFor: Free vs Pro table, pay button, "delete old chats" for history limits
    tutor/
      models.dart                ChatMessage, Citation, Quota, Skill(List), ChatThread, ThreadUsage, FavoriteEquation, TutorEvent
      sse.dart                   decodeSse: byte stream → SSE events (chunk-boundary/CRLF/UTF-8 safe)
      tutor_api.dart             chat history, ask() stream, skills/quota/threads/favourites; providers; streamError()
      tutor_markdown.dart        TutorMarkdown (flutter_markdown_plus + $ math syntaxes), normalizeMath (web port), long-press pick
      tutor_chat_screen.dart     /tutor/:attemptId/:questionId: header, skill chips, streaming bubbles, citations, voice, quota
      tutor_library_screen.dart  /tutor: Chats (usage bar, delete) and Equations (copy, delete, open chat)
test/auth_test.dart              interceptor/refresh/sign-in/ApiException tests with a fake Dio adapter
test/exam_engine_test.dart       golden tests: must match outstagram-web's engine.ts exactly (fixtures/exam_golden.json)
test/math_text_test.dart         LaTeX clean-up/parsing
test/billing_test.dart           status parsing, price format, paywall error → sheet, no keys / Pro states
test/tutor_test.dart             SSE decoding, stream errors (429/402/404 bodies), normalizeMath, TutorMarkdown widget
tool/exam_golden.ts              regenerates the golden fixtures with bun from ../outstagram-web (run after engine.ts changes)
assets/brand/                    mark.svg (the logo symbol, from ../assets/01-icon-gradient.svg) + the logo kit README
config/{staging,prod}.json       public build config (dart-define-from-file)
android/                         Flutter-generated; flavors in app/build.gradle.kts
.github/workflows/ci.yml         analyze, test, staging APK artifact
```

Platform folders `ios/ linux/ macos/ windows/ web/` are the untouched scaffold. They're unused and can be deleted.

---

## 3. Commands

```bash
flutter pub get
flutter analyze
flutter test

# run on a device
flutter run --flavor staging --dart-define-from-file=config/staging.json
flutter run --flavor prod    --dart-define-from-file=config/prod.json

# build APKs (release builds are signed with the debug key for now, see docs/environments.md)
flutter build apk --release --flavor prod    --dart-define-from-file=config/prod.json
flutter build apk --debug   --flavor staging --dart-define-from-file=config/staging.json
# -> build/app/outputs/flutter-apk/app-<flavor>-<mode>.apk
```

Host specifics (Windows, user `karti`):
- `adb` is `~/dev/platform-tools/adb.exe` (Git Bash) / `C:\Users\karti\dev\platform-tools\adb.exe`. The user's phone is a
  Samsung S22 (`SM S901E`, Android 16) on **wireless** adb: `adb-R5CT31BJ23N-qLOs5E._adb-tls-connect._tcp`.
  **Ask before driving the phone's UI.** The user may be using it. `adb install -r` without launching is fine.
- `gh` is at `C:\Program Files\GitHub CLI\gh.exe`. It is **not** on Git Bash's PATH; call it by full path (PowerShell `& $gh …`).
- `gcloud` is logged in (`top-athlete-472606-v4`). No local Postgres/Docker; server tests run in GitHub Actions.
- Python for scripts: `python` (3.14). `psycopg2-binary` is installed for one-off DB scripts.

---

## 4. Architecture rules

- **State:** Riverpod 3 *without* codegen (`Provider`, `FutureProvider.autoDispose`, `NotifierProvider`, `AsyncNotifierProvider`).
  `build_runner` is in dev deps for later (freezed/drift), but nothing is generated today.
- **Navigation:** go_router. Auth gating lives only in `router.dart`'s `redirect` (listens to `authControllerProvider`).
  Screens never navigate on sign-in or sign-out themselves. Changing auth state is enough.
- **Networking:** `apiProvider` (`Api`) for app calls: `get/post/put/delete<T>` return decoded JSON and throw `ApiException`.
  Use `api.dio` directly only for multipart/streaming (see `SocialApi.upload`). Sign-in calls use `bareDioProvider` (no interceptor)
  so refresh can never recurse.
- **Sessions:** see `docs/auth.md` §3. Never read tokens from storage in feature code. Use `authControllerProvider`.
- **Lists:** `PostList` (feature/feed) owns paging state (`loader(page)`, `pageSize` must match the server page length,
  see `docs/api.md`). To force a reload, change its `key` (e.g. include `postsVersionProvider`).
- **Optimistic UI:** likes mutate the `Post` object in place and roll back on error. Follow mirrors the server via `ref.invalidate`.
- **Theme:** use `Theme.of(context).colorScheme`. Never hard-code brand colours outside `theme.dart`
  (exceptions: the like-heart pink, the Google "G").
- **Errors:** `showError(context, e)` (silent on `SignInCancelled`). Keep messages human; the server's `detail` is shown as-is.
- **Haptics:** light on like/select, medium on success actions, heavy on post published.

---

## 5. Gotchas (things that already bit someone)

1. **Kotlin incremental compile on Windows** fails when the pub cache (C:) and the project (D:) are on different drives
   ("this and base files have different roots"). Fixed by `kotlin.incremental=false` in `android/gradle.properties`. Keep it.
2. **AGP needs `buildFeatures { resValues = true }`** for the per-flavor `app_name` resValue. Keep it in `android/app/build.gradle.kts`.
3. **Writing files with non-ASCII via Python on Windows** uses cp1252 by default and can truncate the file mid-write
   (this zeroed `build.gradle.kts` once). Always `open(p, 'w', encoding='utf-8')`.
4. `android/` was once overwritten by a `gradle init` Kotlin template. If it ever looks like a plain JVM app again, regenerate:
   `flutter create --org com.cyto --project-name outstagram --platforms=android .` then re-apply flavors, manifest
   (INTERNET permission, `CallbackActivity` with `${authScheme}`), and the two gradle fixes above.
5. **Release manifest needs INTERNET explicitly.** The Flutter template only adds it to debug/profile. It's in `src/main/AndroidManifest.xml` now.
6. Server timestamps are **naive UTC** (no `Z`); parse with `_asUtc()` in `features/feed/models.dart`.
7. Post categories: the API stores labels (`"Exam Result"`); the web uses slugs (`exam_result`). The server accepts both since
   2026-11-24. The app always sends the label (`PostCategory.label`).
8. `GET /users/search` must stay declared **before** `GET /users/{username}` in `main.py`, or "search" is treated as a username.
9. `google_sign_in` 7: `GoogleSignIn.instance.initialize()` may only run once per process, so the nonce is per app launch (`GoogleAuth.rawNonce`).
10. The staging banner was removed on purpose (it covered the status bar edge-to-edge). Staging is marked by the app name "Outstagram β" and a chip on sign-in.
11. Two OAuth client IDs exist; only the **Web** one is used. See `docs/auth.md` §5 before touching Google sign-in.
12. Uploaded media URLs are stored as **7-day presigned** URLs. Since outstagram-server PR #3 the server re-signs them on read
    (`media.fresh_media_url`), so old images work again; `S3_PUBLIC_BASE_URL` would make them permanent (`docs/TODO.md` §2).
13. Samsung blanks `screencap` while a password field / secure keyboard or the Google account sheet is up. Close the keyboard
    before screenshotting; `adb shell input text` into a field the scrolled layout moved can land in the wrong field.
14. The theme's `FilledButton` has `minimumSize: Size.fromHeight(54)` (infinite min width). In a `Row` or dialog
    actions use `compactButton` (`exams_home_screen.dart`) or wrap it in `Expanded`, or it overflows/disappears.
15. `flutter_math_fork`'s `texBreak()` drops the space after the operator it splits at; `MathText` re-inserts one.
16. Exam scoring must stay identical to the web. Change `engine.ts` and `engine.dart` together and regenerate the
    golden fixtures (`bun tool/exam_golden.ts`).
17. With `ResponseType.stream`, an **error** response's body is still a byte stream, so `ApiException.from` can't see
    FastAPI's `detail`. Decode it first with `streamError()` (`tutor_api.dart`); paywall codes/quota depend on it.
18. flutter_markdown_plus wraps non-text inline widgets into a `Wrap`, which breaks paragraphs. Inline builders must return
    a `Text.rich(WidgetSpan…)` so they merge into the paragraph's RichText (`_MathBuilder`).
19. Tutor voice input needs `RECORD_AUDIO` and the `RecognitionService` `<queries>` entry in the manifest (both there).
20. CI pins Flutter **3.44.8** (same as local). Don't unpin until the `material_ui` migration is done (`docs/TODO.md` §9).
21. `showPaywall` allows one sheet at a time (a static guard reset when the sheet closes). Widget tests that open it
    must close it ("Maybe later") before the test ends, or the next test can't open one.
22. Razorpay needs the R8 keep rules in `android/app/proguard-rules.pro`; without them release Checkout can break silently.
23. Launcher icon, themed (monochrome) icon and splash are **vector drawables** generated from the mark's SVG path
    (`res/drawable/ic_launcher_*.xml`, `splash_mark.xml`; adaptive icon in `mipmap-anydpi-v26`, dark-tile vector for API 24–25
    in `mipmap-anydpi`). No PNG mipmaps. To change the logo, regenerate them from the new path (scale 0.23 keeps it inside
    the adaptive safe zone). Brand navy `#101020` is in `res/values/colors.xml`.

---

## 6. Server side you'll touch most

`../outstagram-server` (FastAPI, Python 3.12 in Docker):
- `main.py`: routes. `src/repository/*.py`: logic. `lib/models.py`: SQLModel tables (created at startup by `create_all`).
- Mobile-specific code: `src/repository/refresh_tokens.py`, `social_auth.exchange_id_token`, `src/repository/timeline.py`
  (feed/explore/user posts/search/comments).
- Tests: `tests/test_ai_exams.py` (existing), `tests/test_mobile_auth.py`, `tests/test_social.py`; run in CI on every push.
- **Deploys:** prod (`outsie`) deploys automatically when `main` changes (Cloud Build trigger). Merge via PR
  (`gh pr merge N --merge`). Staging (`outsie-staging`) is manual: `gcloud run deploy outsie-staging --source . --region asia-northeast1 --port 8671`.
- The user has authorised pushing/merging to `main` and prod changes (2026-11-24). Still say what you're deploying.
