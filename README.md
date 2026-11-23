# Outstagram (Android)

Flutter app for **Outstagram**, a social network for students (posts, follows, exam results) with Pariksha mock
exams and an AI tutor. It talks to the **outsie** API ([`silverstone-git/outstagram`](https://github.com/silverstone-git/outstagram)),
the same backend as the web app ([`outstagram-web`](https://github.com/silverstone-git/outstagram-web)).

**Working on this repo (human or AI)? Start with [`AGENTS.md`](AGENTS.md).**

## Features so far

- Sign in with username/password, create an account, or **Continue with Google** (native Android account sheet).
  Sessions last 60 days and refresh themselves.
- **Home:** Following and Explore feeds, category filters, pull to refresh, infinite scroll.
- **Posts:** photo carousels, double-tap to like, comments, hashtags, text-only posts, delete your own.
- **People:** search, profiles, follow / follow back, approve follow requests (Activity tab).
- **Create:** pick several photos or use the camera. Photos are compressed on the phone (WebP ≤200 kB) before upload.
- **Profile:** your posts and exam stats; light/dark theme.

Coming next: exams (P3), AI tutor (P4), Pro paywall (P5). See [`docs/TODO.md`](docs/TODO.md).

## Run it

Requires Flutter (stable, Dart ≥3.12) and the Android SDK.

```bash
flutter pub get
flutter run --flavor staging --dart-define-from-file=config/staging.json   # talks to outsie-staging
flutter run --flavor prod    --dart-define-from-file=config/prod.json      # talks to production
```

Build a shareable APK:

```bash
flutter build apk --release --flavor prod --dart-define-from-file=config/prod.json
# build/app/outputs/flutter-apk/app-prod-release.apk
```

Checks: `flutter analyze` and `flutter test` (CI runs both and builds a staging APK on every push).

## Docs

| | |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Rules, status, repo map, commands, gotchas |
| [`docs/auth.md`](docs/auth.md) | Sign-in flows, sessions, Google/Supabase setup, troubleshooting |
| [`docs/api.md`](docs/api.md) | API endpoints and shapes the app uses |
| [`docs/environments.md`](docs/environments.md) | Staging vs prod, deploys, signing, devices |
| [`docs/TODO.md`](docs/TODO.md) | Roadmap, including email sign-in codes + SMTP |
| [`PLAN.md`](PLAN.md) | Original architecture and phase plan |
