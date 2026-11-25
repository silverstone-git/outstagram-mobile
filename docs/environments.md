# Environments, builds, deploys

## Flavors and configs

| | staging | prod |
|---|---|---|
| Android applicationId | `com.cyto.outstagram.staging` | `com.cyto.outstagram` |
| Launcher name | Outstagram β | Outstagram |
| Config | `config/staging.json` | `config/prod.json` |
| API | `outsie-staging` (Cloud Run) | `outsie` via `https://outsie.aryan.cfd` |
| Database | Supabase project `outsie-staging` (ref `lopedbgspeddbyoolamo`, Tokyo) | Supabase project `outsie` (ref `naovuyiqqosopuihctbk`, Tokyo) |
| Browser-auth callback | `com.cyto.outstagram.staging://auth-callback` | `com.cyto.outstagram://auth-callback` |

Both flavors install side by side. `config/*.json` keys (all **public**): `FLAVOR`, `API_BASE`, `WEB_BASE`,
`GOOGLE_SERVER_CLIENT_ID`, `AUTH_SCHEME`. They're read via `String.fromEnvironment` in `lib/core/config/env.dart`.
Flavors are defined in `android/app/build.gradle.kts` (`productFlavors`, `manifestPlaceholders["authScheme"]`,
`resValue app_name`).

**Friends test on prod** (user decision 2026-11-24). Staging is for risky server changes. Staging has the same
question bank as prod and a copy of prod's 49 community exams (copied 2026-11-24 via the public API).
It has no `pg_physics` group and no posts or users of note.

## Server deploys (`../outstagram-server`, GitHub `silverstone-git/outstagram`)

- **Prod** (`outsie`, Cloud Run, `asia-northeast1`, port 8671): a Cloud Build trigger deploys every push to `main`.
  Normal path: feature branch → CI green → PR → `gh pr merge N --merge` → watch
  `gcloud builds list --limit 2` until `SUCCESS` (~6–8 min). Then smoke-test (e.g. `curl -s -o /dev/null -w '%{http_code}' https://outsie.aryan.cfd/explore` → `401`).
- **Staging** (`outsie-staging`): manual, from any branch:
  `gcloud run deploy outsie-staging --source . --region asia-northeast1 --port 8671 --quiet` (~5 min).
  Env vars carry over between deploys.
- **After any new table** (SQLModel `create_all` makes it at startup): run `scripts/supabase-lockdown.sql` on that
  environment's DB, so Supabase's Data API roles can't read it. One-off pattern (never print the URL):

  ```python
  import psycopg2
  url = next(l.split('=',1)[1].strip() for l in open('../env.supabase.txt') if l.startswith('POSTGRES_URL_STAGING='))  # or POSTGRES_URL= for prod
  c = psycopg2.connect(url); c.autocommit = True
  c.cursor().execute(open('outstagram-server/scripts/supabase-lockdown.sql').read())
  ```
  Last applied: staging and prod, 2026-11-24 (for `refreshtoken`).
- Server env vars worth knowing (non-secret): `OUTSIE_ENV=staging` on staging; `S3_ENDPOINT` = Cloudflare R2;
  `OUTSTAGRAM_SOCIAL_PROVIDERS=google`; optional `OUTSIE_REFRESH_TOKEN_DAYS`, `S3_PUBLIC_BASE_URL` (unset as of 2026-11-24).
  Read them with `gcloud run services describe <svc> --region asia-northeast1 --format=json` and print **names only**
  unless a value is known to be non-secret.

## App CI (`.github/workflows/ci.yml`)

On every push: `flutter pub get` → `analyze` → `test` → `build apk --release --flavor staging` → artifact
`outstagram-staging-apk` (14 days).

### Friends' APK link (`publish-apk` job)

On pushes to `main` (and manual runs on `main`), after `build` passes: build the **prod** APK with build number
`1000 + run_number`, then `aws s3 cp` it over **the same key** every time (`apps/outstagram.apk`, override with the
repo variable `APK_KEY`), plus a sidecar `apps/outstagram.json` `{build, commit, built_at, bytes}`. R2 has no
versioning, so the bucket only ever holds one APK (~55 MB). It goes to the **public** bucket `pariksha`, so the link is
**`https://outsiebucket.aryan.cfd/apps/outstagram.apk`**.

**Buckets (user, 2026-11-25):** `pariksha` = public things (question images under `pariksha/`, the APK), custom domain
`https://outsiebucket.aryan.cfd` (its r2.dev URL is disabled). `outstagram` = private user content (post media and
avatars under `outstagram/`), no public domain: the server hands out presigned links, re-signed on read. Don't make it
public and don't set `S3_PUBLIC_BASE_URL` to a public domain for it. Both buckets also hold some old copies of each
other's objects. `../env.r2api.txt` has a separate R2 token (S3 API only, no Cloudflare API rights).

Secrets (repo → Settings → Secrets → Actions); the job is skipped with a notice until they exist:
| Secret | Value |
|---|---|
| `ANDROID_SIGNING_KEYSTORE_B64` | `base64 -w0 ~/.android/debug.keystore` from **this machine**: same SHA-1 as local builds, so CI and local APKs update each other and Google sign-in keeps working |
| `APK_S3_ENDPOINT` | `R2_S3_ENDPOINT` from `../env.r2api.txt` (account root, **without** a bucket path) |
| `APK_S3_BUCKET` | `pariksha` |
| `APK_S3_ACCESS_KEY_ID` / `APK_S3_SECRET_ACCESS_KEY` | `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` from `../env.r2api.txt` (separate from the server's key) |

Because CI build numbers start at 1001, a local build (`+1`) is a "downgrade": install it with `adb install -r -d`.

## Signing and sharing APKs

- Release builds are currently signed with the **debug key** (`signingConfig = signingConfigs.getByName("debug")`).
  Fine for sideloading to friends; Google sign-in works for them because the Android OAuth client is registered
  with the debug SHA-1. Every build from this machine has the same SHA-1, so updates install over each other.
  A build made on another machine/CI has a **different debug key**: it can't update an installed app and Google
  sign-in breaks.
- Share: `flutter build apk --release --flavor prod --dart-define-from-file=config/prod.json`, send
  `build/app/outputs/flutter-apk/app-prod-release.apk` (~55 MB). Friends must allow "install unknown apps".
- `STORE` dart-define: `sideload` (default) shows the Razorpay button; a Play build must pass
  `--dart-define=STORE=play`, which hides it (Play requires Play Billing for digital goods). Remove the
  `razorpay_flutter` dependency from the Play build once Play Billing exists (P7).
- Release builds use R8 with `android/app/proguard-rules.pro` (Razorpay's keep rules: Checkout's WebView JS bridge).
- Before Play (P7): create an upload keystore (`keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`),
  `android/key.properties` (git-ignored), a `release` signingConfig, enrol in Play App Signing, then register both new
  SHA-1s as Android OAuth clients (`docs/auth.md` §5).

## Devices

User's phone: Samsung S22 `SM S901E`, Android 16, wireless adb id `adb-R5CT31BJ23N-qLOs5E._adb-tls-connect._tcp`.
`adb -s <id> install -r <apk>` is safe. **Don't launch or tap** without asking; the user may be using the phone.
Screenshot: `adb -s <id> exec-out screencap -p > shot.png`. The phone may also be on **USB** (`R5CT31BJ23N`).
The QA loop, its rules and helpers are in `docs/qa.md` / `tool/qa/qa.sh`.

Database access: the auto-mode sandbox refuses direct connections to the prod/staging Postgres unless the user
grants it in the conversation (they did on 2026-11-25). Prefer self-healing server code (startup migrations,
lazy back-fills such as `email_auth.sync_from_supabase`) over one-off scripts, so a deploy fixes every environment.
