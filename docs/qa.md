# On-device QA

How to test a build on the user's phone, and what past QA sessions taught us. Helpers: `tool/qa/qa.sh`.

## 1. The loop

1. **Green first:** `flutter analyze`, `flutter test`, server CI. QA is for what tests can't see (layout, real
   data, permissions, OS behaviour), not a substitute.
2. **Check prod before touching the phone:** `tool/qa/qa.sh errors` (5xx and tracebacks in the last hour).
   This found the 2026-11-25 enum bug (below) faster than tapping did.
   The counts cover the whole hour, so compare the printed "latest 5xx" time with your deploy/fix time.
3. **Install without launching:** `adb install -r build/app/outputs/flutter-apk/app-prod-release.apk`
   (keeps the signed-in session).
4. **One action, then look:** `qa.sh tap X Y` (screenshot coordinates) → `qa.sh shot NAME` → read the image →
   decide the next action. **Never chain several taps or BACKs blind**: the screen may not be where you think.
5. **Check the system side too:** scheduled reminders with `qa.sh alarms`, notification channels with
   `adb shell dumpsys notification`, server state with a read-only SQL query.
6. **Clean up:** delete test posts from the app (also tests delete), remove pushed test images, and note
   any prod test data in `docs/TODO.md` §0.

## 2. Rules

- **The phone is the user's.** Ask before driving its UI. The user may tap at the same time (on 2026-11-25 they
  picked the photo while queued taps opened the camera). Announce what you're about to do; keep steps short.
- **Never upload the user's own photos or content.** The system photo picker shows their gallery: run
  `qa.sh testimage` first and pick that image. Don't read or describe what's in their gallery.
- **Signed-out screens:** use the **staging** app (`com.cyto.outstagram.staging`, separate install) so the prod
  session isn't lost; you don't know the QA account's password.
- **Password managers** (Keepass) pop "save?" sheets after text fields; dismiss with "No, thanks".
- **BACK twice** can leave the app and land in another (it did: staging → prod app). Use one BACK and look.
- Samsung blanks screenshots while a secure keyboard or Google's account sheet is up (AGENTS.md gotcha 13).

## 3. What can't be tested from here

- **Emailed codes** (sign-in, reset, confirm, change email): no inbox is readable, and creating a disposable inbox
  on an external service is blocked by the sandbox. Ask the user to run those steps with their own email, or to
  give a test inbox they can read codes from. Don't send codes to `@example.com` (they bounce and hurt the sender
  domain's reputation).
- **A reminder actually firing:** reminders are inexact (Android may deliver up to ~1 h late). Verify the plan with
  `qa.sh alarms` instead; to see one fire, set "Remind me at" a few minutes ahead on a day the quiz isn't done.
- To test features behind a confirmed email on the QA account, set `email_verified_at` on the QA account (`../LOCAL.md`) with SQL
  (it's an `@example.com` address). Only with the user's DB permission.

## 4. Lessons from past sessions

| Found by QA (2026-11-25) | Why tests missed it | Now |
|---|---|---|
| Prod `postcategory` enum had 5 of 10 labels: posts in Academic/Achievement/… and `/me/stats` failed (500) | CI and staging DBs are created fresh, so they have every label | Server adds missing labels at startup; check `qa.sh errors` every QA |
| Profile post count stale after posting/deleting | No widget test covers cross-screen refresh | `profileProvider` watches `postsVersionProvider`; delete invalidates it |
| Celebration text unreadable over the results page | Visual only | Backdrop 94% black |
| "60 minutes left" reminder could arrive after midnight | Inexact alarm window only visible in `dumpsys alarm` | Reminders at 21:00 / 22:30, wording without exact times |

Rule of thumb: **when prod and staging differ, suspect schema drift** (`create_all` never alters existing tables or
enums). New columns go in `main._add_missing_columns`, enum labels are handled by `main._add_missing_enum_values`.
