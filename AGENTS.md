# AGENTS.md: Outstagram mobile (Flutter) guide

Entry point for any agent or human working in `outstagram_mobile/`. It holds the rules, the current
status, the repository map and the commands. Deep dives live in `docs/`:

| File | What's in it |
|---|---|
| `docs/auth.md` | Every sign-in flow, sessions and refresh, Google Cloud + Supabase setup, troubleshooting |
| `docs/api.md` | The outsie endpoints the app uses, their exact shapes and quirks |
| `docs/environments.md` | Staging vs prod, flavors, configs, deploys, databases, devices, release signing |
| `docs/TODO.md` | Roadmap and open work |
| `docs/qa.md` | On-device QA loop, rules (the phone is the user's), what can't be tested, lessons (helpers: `tool/qa/qa.sh`) |
| `PLAN.md` | The original product/architecture plan (phases P0–P7, mobile-only extras). Background, not status |

Last updated: 2026-11-26 (equation menu everywhere + jump-back, tutor model/thinking/BYOK, follow-request badge and
notifications, account export/delete, cached first pages and stable image cache keys; social basics, App Links, streak freezes/friends/widget, offline packs, local alerts, videos,
Free/Pro/Contributor plans, friends' APK link).

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
- Don't use the Desktop OAuth client (the `client_secret_*.json` / `.env` value) anywhere. The app's `serverClientId` is the **Web** client (`docs/auth.md`).
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
| P1b Email | 6-digit email codes: sign-in, forgot/change password, confirm email (onboarding step with "Do it later"), change email; posting/uploads/tutor need a confirmed email | ✅ built 2026-11-25 (unit/widget tested; needs the Supabase email templates with `{{ .Token }}`, `docs/auth.md` §6; on-device QA pending) |
| P2 Social | Feed/Explore, post card, likes, comments, search, profiles, follow requests, composer; unfollow, decline, follower lists, edit profile, delete comment, post page, zoom, video (2026-11-25) | ✅ done (needs on-device QA) |
| P3 Exams | Dart port of the Pariksha engine, presets, practice, community exams, runner, results, history | ✅ done 2026-11-24 (verified on device; leftovers in `docs/TODO.md` §3) |
| P4 AI tutor | SSE streaming, Markdown + LaTeX, skills, quota, library, saved equations, voice input | ✅ built 2026-11-24 (unit/widget tested; on-device QA pending, `docs/TODO.md` §4) |
| P5 Paywall | 429/402/403/413 → upgrade sheet, Razorpay test; Free / Pro ₹99 / Contributor ₹499 | ✅ built 2026-11-24, three tiers 2026-11-25 (limits table in `docs/TODO.md` §5; prod on Razorpay test keys) |
| P6 Mobile extras | Push, share-target, result cards, App Links, offline packs | ✅ built 2026-11-25: result cards, share-target (photos, text, videos), shortcuts, streak + freezes + friends + home widget, local alerts (exam time left, tutor back), offline packs, App Links (needs `assetlinks.json` uploaded, `docs/TODO.md` §7); push dropped (no Firebase). On-device QA pending |
| P7 Release | Upload key, Play Billing, account deletion, Play listing | ⏳ (account deletion + data export built 2026-11-26) |

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
    config/device_tz.dart        phone's IANA time zone (flutter_timezone) → X-Timezone header + tz.local for reminders
    auth/
      session.dart               AppUser, Session (access, refresh, expiresAt)
      session_store.dart         flutter_secure_storage persistence (key outsie_session_v1)
      auth_repository.dart       /login, /register, /auth/google, PKCE /auth/supabase, /auth/refresh, /auth/logout (bare Dio)
      auth_controller.dart       AsyncNotifier<Session?>; single-flight refresh(); providers
      google_auth.dart           google_sign_in 7 (Credential Manager) + nonce; SignInCancelled
    net/
      api_client.dart            dioProvider + AuthInterceptor (pre-expiry refresh, 401 → refresh → retry once), Api wrapper
      api_error.dart             ApiException (FastAPI detail parsing, isPaywall, isNetwork)
      json_cache.dart            JsonCache: first page of feed/explore/profile posts on disk (stale-while-revalidate), cleared on account change
    ui/
      math_text.dart             MathText: inline/display LaTeX (flutter_math_fork), web-compatible clean-up; onPickEquation, highlight
      equation_menu.dart         long-press equation menu (blurred backdrop, lifted equation: save / copy LaTeX / copy Markdown),
                                 EquationSource (tutor | question | option | explanation | post), EquationPulse (jump-back highlight)
      avatar.dart                Avatar: profile photo (cached by object path, re-signed URLs share a cache entry) over a letter avatar
      feedback.dart              showError(context, e): snackbar, the upgrade sheet for paywall errors, the confirm-email sheet for 403 email_unverified
      code_field.dart            CodeField (6 boxes over one hidden field, autofill + paste, auto-submit), ResendButton (60 s)
  features/
    auth/                        sign-in, register, splash, BrandMark (SVG mark + "Outsta"/"gram" text) and BrandSymbol,
                                 email_code_screen.dart (/sign-in/email), email_link_screen.dart (/email-link: magic links, App Links),
                                 forgot_password_screen.dart (/forgot-password, /account/password)
    account/                     your_data.dart (/account: download my data = GET /me/export shared as JSON, delete my account = POST /me/delete),
                                 account_api.dart (GET /me → meProvider, confirm/change email), verify_email_screen.dart (/verify-email),
                                 account_screen.dart (/account, /account/email, VerifyEmailBanner), verify_gate.dart (403 → sheet)
    streak/                      streak_api.dart (StreakStatus incl. freezes, streakProvider, friendStreaksProvider),
                                 streak_widget.dart (home-screen widget data), local_alerts.dart (exam time left, tutor back),
                                 streak_screen.dart (/streak, pop quiz, freezes, friends, StreakHomeCard),
                                 streak_visuals.dart (animated flame, chip, confetti, week strip, calendar, reward, milestones),
                                 streak_celebration.dart (full-screen "Day N" after an exam), streak_reminders.dart (local notifications + copy)
    shell/                       AppShell (NavigationBar), ComingSoon placeholder
    feed/                        models.dart (Post, Comment, Profile, …), social_api.dart, post_card.dart,
                                 post_list.dart (infinite + pull-to-refresh), comments_sheet.dart (long-press delete), home_screen.dart,
                                 post_detail_screen.dart (/p/:id), media_viewer.dart (full-screen pinch zoom, PostVideo)
    social/search_screen.dart    debounced /users/search
    profile/                     profile_view.dart (header + posts, follow button, stats), profile_screen.dart,
                                 profile_photo.dart (tap your avatar: gallery / camera / remove → PUT|DELETE /me/avatar),
                                 follow_list_screen.dart (/u/:u/followers|following, unfollow, remove follower),
                                 edit_profile_screen.dart (/profile/edit: name, bio → PUT /me)
    activity/activity_screen.dart follow requests + approve
    activity/follow_requests.dart followRequestsProvider (polled every minute in the foreground by AppShell, on resume),
                                 badge count, local notification for requests this phone hasn't seen (no push server)
    compose/compose_screen.dart  pick/camera → WebP (plan's media limit) → /media-upload/bulk → /posts; postsVersionProvider
    compose/compose_draft.dart   composeDraftProvider: images/caption/category the composer takes when it opens
    compose/share_intent.dart    ShareIntentListener ("Share to Outstagram", receive_sharing_intent) → draft → /create
    exams/
      engine/                    pure Dart port of outstagram-web engine.ts: models (raw-JSON questions), scoring, presets
      exam_api.dart              question bank sampling, community exams, /exam-attempts
      exam_session.dart          running exam (Notifier) autosaved to shared_preferences (exam_session_v1); resume
      exams_home_screen.dart     streak card, resume card, quick practice, mocks, attempts, community
      exam_launcher.dart         launchExam(): discard-unfinished dialog → load → runner (Exams tab and pop quiz); compactButton
      offline_packs.dart         OfflinePacks (saved subjects), offlineAwareSampler, PendingAttempts (upload later, taken_at)
      offline_packs_screen.dart  /exams/offline: save/refresh/remove packs, pending uploads
      exam_runner_screen.dart    /exam/run full-screen: PageView, palette, timer + auto-submit, wakelock, PopScope
      exam_result_screen.dart    /exam/result (fresh, saves attempt) and /exam/attempt/:id; score, topics, SWOT, review,
                                 "Ask the AI tutor" per question (needs the saved attempt id); share button
      result_card.dart           ResultCard (4:5, 1080×1350 PNG via RepaintBoundary) + sheet: share_plus / post to feed
    billing/
      billing_api.dart           BillingStatus/Limits/Price, /billing/status|razorpay/order|razorpay/verify, billingStatusProvider
      razorpay_checkout.dart     openRazorpay(order): native Checkout → RazorpayResult | null (cancelled) | ApiException
      paywall_sheet.dart         showPaywall / showPaywallFor: Free vs Pro table, pay button, "delete old chats" for history limits
    tutor/
      models.dart                ChatMessage, Citation, Quota, Skill(List), ChatThread, ThreadUsage, FavoriteEquation, TutorEvent
      sse.dart                   decodeSse: byte stream → SSE events (chunk-boundary/CRLF/UTF-8 safe)
      tutor_api.dart             chat history, ask() stream, skills/quota/threads/favourites; providers; streamError()
      tutor_markdown.dart        TutorMarkdown (flutter_markdown_plus + $ math syntaxes), normalizeMath (web port), long-press pick
      tutor_chat_screen.dart     /tutor/:attemptId/:questionId[?eq=&mid=]: header, skill chips, streaming bubbles, citations, voice, quota
      ai_options.dart            Pro/Contributor tutor settings (GET /ai/options): model, thinking level, BYOK (key in the keystore)
      tutor_library_screen.dart  /tutor: Chats (usage bar, delete) and Equations (copy, delete, open chat)
test/auth_test.dart              interceptor/refresh/sign-in/ApiException tests with a fake Dio adapter
test/exam_engine_test.dart       golden tests: must match outstagram-web's engine.ts exactly (fixtures/exam_golden.json)
test/math_text_test.dart         LaTeX clean-up/parsing
test/billing_test.dart           status parsing, price format, paywall error → sheet, no keys / Pro states
test/p6_share_test.dart          result card layout/summary, shared files → draft, own deep links ignored
test/tutor_test.dart             SSE decoding, stream errors (429/402/404 bodies), normalizeMath, TutorMarkdown widget
test/avatar_test.dart            avatar_url parsing in every model, cache key, Avatar widget
test/email_streak_test.dart      email-code/reset sign-in, register → confirm step, /me + 403 email_unverified, CodeField,
                                 streak parsing, reminder copy, streak widgets
test/social_basics_test.dart     follow/unfollow/reject/lists/PUT /me/comment delete/post endpoints, edit form, Activity decline
tool/exam_golden.ts              regenerates the golden fixtures with bun from ../outstagram-web (run after engine.ts changes)
assets/brand/                    mark.svg (the logo symbol, from ../assets/01-icon-gradient.svg) + the logo kit README
config/{staging,prod}.json       public build config (dart-define-from-file)
android/                         Flutter-generated; flavors in app/build.gradle.kts
.github/workflows/ci.yml         analyze, test, staging APK artifact; publish-apk (main: prod APK → one fixed R2 object)
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

Host specifics (Windows): device ids, tool paths, cloud project ids and the QA account live in `../LOCAL.md`
(workspace root, not in git). Read it before driving the phone or the cloud.
- The user's phone is an Android 16 Samsung on wireless or USB adb. **Ask before driving the phone's UI.** The user may
  be using it. `adb install -r` without launching is fine.
- `gh` is **not** on Git Bash's PATH; call it by full path (PowerShell `& $gh …`).
- `gcloud` is logged in. No local Postgres/Docker; server tests run in GitHub Actions.
- Python for scripts: `python` (3.14). `psycopg2-binary` is installed for one-off DB scripts.

---

## 4. Architecture rules

- **State:** Riverpod 3 *without* codegen (`Provider`, `FutureProvider.autoDispose`, `NotifierProvider`, `AsyncNotifierProvider`).
  No codegen (`build_runner` was removed 2026-11-25; add it back with freezed/drift if ever needed).
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
    (`media.fresh_media_url`), so old images work again. The `outstagram` bucket is **private by design**; public things
    (question images, the APK) live in `pariksha` at `https://outsiebucket.aryan.cfd` (`docs/environments.md`, `docs/TODO.md` §2).
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

24. Launcher shortcuts (`res/xml/shortcuts.xml`) open `outstagram://app/<route>` on MainActivity; Flutter deep linking hands
    the path to go_router. The router remembers that target while the session loads / until sign-in (`pending` in
    `router.dart`). receive_sharing_intent also reports such VIEW intents as a "shared URL" on cold start, so
    `draftFromShared` drops `outstagram://` links. The shortcut's `targetPackage` comes from the per-flavor `application_id` resValue.
25. receive_sharing_intent 1.9 needs **compileSdk 37** (set in `app/build.gradle.kts`, with
    `android.suppressUnsupportedCompileSdk=37` because AGP 9.0 knows 36). 1.8.1 doesn't build (JVM target mismatch).
26. **flutter_local_notifications 23** pulls androidx.core 1.19, which needs **AGP 9.1.1 → Gradle 9.3.1**
    (`android/settings.gradle.kts`, `gradle-wrapper.properties`) and **core library desugaring** (`app/build.gradle.kts`).
    Its receivers (scheduled, boot, action) are in the manifest; the status icon `drawable/ic_stat_streak.xml` is only
    referenced from Dart, so `res/raw/keep.xml` keeps it in shrunk release builds.
27. Streak reminders are **local** (no push server, user decision 2026-11-25: no Firebase). They're re-planned every time
    the app learns the streak (launch, resume, finished exam) and cancelled on sign-out. Inexact alarms only (no
    SCHEDULE_EXACT_ALARM). Off until the user says yes (celebration button or the switch on `/streak`), which asks
    for POST_NOTIFICATIONS on Android 13+. Tapping one opens `/streak?quiz=1`, which starts the pop quiz.
28. Running `dart format` over `lib/` reflows files written in the older style; format only the files you touch
    (`dart format -l 120 <files>`). Reverting the churn afterwards needs a `git checkout` the sandbox may refuse.
29. **Schema drift between DBs:** `create_all` never alters existing tables or enums. Prod (older) lacked 5 of the
    10 `postcategory` labels until 2026-11-25 while CI/staging (fresh) had them, so tests were green and prod 500'd.
    New columns → `main._add_missing_columns`; enum labels → `main._add_missing_enum_values`. Check prod logs
    (`tool/qa/qa.sh errors`) after every deploy.
30. **Editing files from scripts:** shell heredocs break on apostrophes inside `bash -c`; write the Python edit script
    to a file first. Files with CRLF endings don't match `
`-joined patterns, so use the Edit tool for them. A
    multi-file edit script should check every pattern before writing any file (one run left `App.tsx` edited and
    `Login.tsx` not).
31. **`gh` prints hints on stderr.** In PowerShell, `2>$null` plus the non-zero exit made a successful
    `gh pr create` look failed. Don't suppress stderr; confirm with `gh pr list --head <branch>` or `gh pr view`.
32. **Long waits:** CI runs (app CI ~15 min with the APK build) and `flutter build apk` (~6–13 min) exceed the 10-min
    foreground limit. Start them with `run_in_background` and wait for the notification instead of re-running or polling.
33. **Widget tests:** `ListView` builds lazily, so off-screen children aren't found; put test fixtures in a
    `SingleChildScrollView` + `Column`. Importing another test file (e.g. `auth_test.dart` helpers) also imports its `main`.
34. **CI memory:** `android/gradle.properties` asks for an 8 GB heap; on GitHub's 16 GB runner Gradle + Kotlin daemon +
    R8 got killed (exit 143, "The operation was canceled"). CI writes a smaller `~/.gradle/gradle.properties` and builds
    arm64 only for the staging check (arm + arm64 for the published APK).
35. **Python edits from bash heredocs:** `'\\n'` inside a heredoc'd Python string becomes a real newline in the
    written file (it broke Dart strings and a YAML block twice). Write edit scripts with the Write tool, or use `chr(10)`.
36. **Buckets:** `pariksha` is public (`https://outsiebucket.aryan.cfd`: question images, the APK); `outstagram` is
    private user media (presigned links only). Don't make user media public.
37. **CI signing:** AGP on the GitHub runner ignored `~/.android/debug.keystore` and signed each APK with a new
    random key (builds 1038/1041 couldn't update anything). `build.gradle.kts` names the keystore explicitly
    (`OUTSTAGRAM_KEYSTORE` on CI), and `publish-apk` refuses to upload unless `apksigner` shows SHA-256 `E3:6F…5E:59`.
38. **Pages opened from outside the app** (App Link, widget, shortcut, notification) are the only route on the stack.
    Wrap top-level detail routes in `Rooted` (`lib/app/rooted.dart`): it puts `/feed` underneath and pushes the page
    again, so there's a back arrow and BACK goes to the tabs. Exams and sign-in routes don't use it.
39. **No `PopScope(canPop: false)` in modal sheets** to return a result: after a dialog opened on top, BACK skipped it
    and closed the app. Pass a `ValueNotifier` instead (`showCommentsSheet`).
40. **Exam alerts without the exact-alarm permission** can arrive ~20 min late, so "5 minutes left" is only scheduled
    when exact alarms are allowed (`alertAt(exactOnly: true)`); "Time's up" is always scheduled.
41. **README screenshots** are the real app rendered in a test on demo data (`test/screenshots/`, skipped unless
    `--dart-define=SCREENSHOTS=true`), then framed by `tool/screenshots/compose.py` into `docs/screenshots/`.
    Tests draw text with no family in a box font, so the theme takes `debugFontFamily` / `debugFontFamilyFallback`
    (null in the app). Package fonts (KaTeX) and plugins (share intent, home widget, wakelock) are stubbed in the
    harness. Never use real users' posts or photos there.
43. **Presigned media URLs change on every fetch** (the server re-signs them), so `CachedNetworkImage` must use
    `cacheKey: Avatar.cacheKey(url)` (the object path) or every image is downloaded again on each refresh.
44. **Jumping to a saved equation** needs the target built: screens that pulse one (`EquationPulse`) set a huge
    `cacheExtent` on their ListView while focusing, because ListView only builds what's near the viewport.

42. **Question-bank LaTeX doubles every backslash.** `cleanLatex` collapses `\\` before letters and the spacing commands
    (`\\,` `\\;` `\\:` `\\!`), the same as the web's `Latex.tsx`. A leftover `\\,` reads as a row break and made
    `texBreak` throw (now caught in `MathText`).

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
