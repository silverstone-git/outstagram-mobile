# outsie API as used by the app

Base URLs: prod `https://outsie.aryan.cfd` (= `https://outsie-mgenvq5gwa-an.a.run.app`),
staging `https://outsie-staging-mgenvq5gwa-an.a.run.app`. Auth: `Authorization: Bearer <access_token>` on
everything except sign-in, `/auth/*`, `/billing/plans`, `/api/exam_presets`, `/api/question_bank/*` reads and `/pariksha` reads.

The authoritative server reference is `outstagram-server/README.md`. This file records what the **app** relies on,
including quirks that aren't obvious from the code.

## Errors

FastAPI puts the reason in `detail`, which can be:
- a string: `{"detail": "Already following this user"}`
- a list (422 validation): `[{"loc": ["body","email"], "msg": "…"}]` → shown as `email: …`
- an object: **paywall** `{"code": "ai_quota" | "tutor_threads" | "tutor_storage" | "media_too_large", "message": "…", "upgrade": true, …}`
  with status 429 / 402 / 402 / 413.

`ApiException.from` handles all three (`isPaywall`, `code`, `message`).

**Unconfirmed email:** `POST /posts`, `/media-upload(/bulk)` and the tutor chat endpoints answer
`403 {"detail": {"code": "email_unverified", "verify": true, "message": "…"}}` until the account's email is confirmed.
`showError` (and the tutor) open the confirm-email sheet for it (`features/account/verify_gate.dart`).

**`X-Timezone`:** the app's Dio sends the phone's IANA zone (e.g. `Asia/Kolkata`) on every request
(`core/config/device_tz.dart`). The server counts streak days in it.

## Auth

See `docs/auth.md`. `POST /login` is **form-encoded** (the `username` field also takes an email); everything else is JSON.

| Call | Notes |
|---|---|
| `GET /auth/email/config` | `{enabled, code_length}` (6 unless `OUTSIE_EMAIL_OTP_LENGTH` says otherwise) |
| `POST /auth/email/start {email}` | 204; emails a code. 429 when asked too often (5 per address per 15 min) |
| `POST /auth/email/verify {email, code}` | sign-in response + `created` (true = a new account was made). 401 wrong/expired code; 429 after 5 wrong codes |
| `POST /auth/password/forgot {email}` | 204 always (a code is sent only if an account has the address) |
| `POST /auth/password/reset {email, code, new_password}` | sets the password (8+ chars), revokes every refresh token, returns a sign-in response |
| `GET /me` | `{user_id, username, fullname, bio, email, email_verified, email_verified_at, verification_required}` |
| `POST /me/email/verify/start` → `POST /me/email/verify {code}` | confirm the current email; returns `/me` |
| `POST /me/email/change/start {email}` → `POST /me/email/change {email, code}` | 409 if another account has it; the new email counts as confirmed; returns `/me` |
| `POST /register` | now 409 with a readable `detail` for a taken username or email (was a 500) |

## Social (implemented in the app)

| Call | Shape | Page size |
|---|---|---|
| `GET /feed?page=&category=` | `[Post]`: **own posts + accepted follows**, newest first | 20 |
| `GET /explore?page=&category=` | `[Post]`: everyone, newest first | 20 |
| `GET /users/{username}/posts/{page}` | `[Post]`: one author (404 if no such user) | 10 |
| `GET /posts/{id}` | `Post` (older shape: no counts yet) | n/a |
| `POST /posts` | `{media_urls: [{url, media_type}], caption, post_category, highlighted_by_author}` | n/a |
| `DELETE /posts/{id}` | own posts only (403 otherwise) | n/a |
| `POST` / `DELETE /posts/{id}/like` | 201 / 204; unlike of a not-liked post → 404 | n/a |
| `GET /posts/{id}/comments/{page}` | `[{comment_id, post_id, content, author_user_id, author, datetime_commented}]`, oldest first | 20 |
| `POST /posts/{id}/comment` | `{content}` → the comment (without `author`) | n/a |
| `GET /posts/{id}/likes/{page}` | `[{post_id, liker_user_id, liker_username, datetime_liked}]` (not used yet) | 10 |
| `GET /users/search?q=&limit=` | `[{user_id, username, fullname, bio}]`: username prefix or name substring, not yourself | ≤50 |
| `GET /users/{username}` | `{user_id, username, fullname, bio, posts_count, followers_count, following_count, you_follow_them, they_follow_you}` | n/a |
| `POST /users/{username}/follow` | creates a **pending** request; 400 if already pending/following or yourself | n/a |
| `GET /follow-requests` | pending requests **to** you: `[{request_id, requester_user_id, requester_username, datetime_requested, status, …}]` | n/a |
| `POST /request-approve/{request_id}` | accept | n/a |
| `GET /me/stats` | `{posts, posts_this_week, achievements, …, followers, following, exams_taken, avg_accuracy, best_score_pct, …}` | n/a |
| `GET /trending?days=30` | `[{tag, posts}]` | n/a |

**Post** (listing endpoints):
```json
{"post_id": "uuid", "caption": "…", "post_category": "Exam Result", "datetime_posted": "2026-11-24T03:12:00.123",
 "author_user_id": 7, "author": "asha", "highlighted_by_author": false, "is_liked": true,
 "media_urls": [{"url": "https://…", "media_type": "image"}], "like_count": 3, "comment_count": 1}
```

Quirks:
- `datetime_*` are **naive UTC**. Append `Z` before parsing.
- `you_follow_them` / `they_follow_you`: `0` none, `0.5` pending, `1` accepted (floats).
- `post_category` filter accepts the label (`Exam Result`) or the slug (`exam_result`); invalid → 400.
  Labels: Technology, Entertainment, Business, Vlog, Lifestyle, Academic, Achievement, Study Group, Exam Result, Project.
- **Missing on the server** (not built yet): unfollow, reject a request, followers/following lists, edit profile,
  profile photos, notifications. See `docs/TODO.md`.

## Media

`POST /media-upload/bulk` multipart, repeated field **`files`** (single: `POST /media-upload`, field `file`):
```json
[{"object_key": "1732….webp", "presigned_url": "https://…r2.cloudflarestorage.com/…?X-Amz-…", "public_url": null,
  "bytes": 183211, "media_type": "image"}]
```
- Store `public_url ?? presigned_url` in the post. **`presigned_url` expires after 7 days**; `public_url` is only
  non-null once the server has `S3_PUBLIC_BASE_URL` (the R2 bucket's public domain) set. See `docs/TODO.md` §2.
- Free plan: 200 kB per file **after** compression (server re-compresses big images to WebP too); over → 413 `media_too_large`.
  Pro: 15 MB. The app compresses to WebP ≤200 kB on device (`compose_screen.dart`) regardless of plan, for now.
- Storage is Cloudflare R2 (bucket `outstagram`).

## Exams (implemented in the app, `lib/features/exams/exam_api.dart`)

| Call | Notes |
|---|---|
| `GET /api/question_bank/sample?topic=<slug>&count=n` | no auth needed; slug = topic name lower-cased, spaces → `_` |
| `GET /pariksha?page=n` | community exams, 10 per page: `{exam_id, exam_title, datetime_uploaded}` |
| `GET /pariksha/{id}` | `sections` (newer) or `exam_json_str` (a question list or a full config) |
| `POST /exam-attempts` | `{exam_id?, exam_title, score, max_score, accuracy, total_questions, total_time_seconds, result}`; `result` is the web's `ExamResult` JSON (≤ 2 MB). The app writes the same shape, so attempts open on both clients |
| `GET /exam-attempts?page=n`, `GET /exam-attempts/{id}` | summaries; full attempt adds `result` |
| `POST /exam-attempts` response `streak` | the daily streak after this attempt, plus `extended` (this attempt counted a new day), `milestone` (3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 365, …) and `reward_unlocked`. `null` when the attempt doesn't count (no answered question) |
| `GET /me/streak` | `{current, longest, today_done, at_risk, broken, lost, last_day, today, day_ends_at, tz, subject, days[] (last 42 local days), milestones, next_milestone, prev_milestone, reward{goal, unlocked, unlocked_at, days_left, ai_prompts_per_hour, tutor_threads}}`. The first read rebuilds the streak from past attempts |
| `PUT /me/streak {subject?, tz?}` | pop-quiz subject (a `subjectGroups` key in the app) |

Streak rules (server `src/repository/streaks.py`): a day counts when an exam with at least one answered question
is saved; days are calendar days in `X-Timezone`; missing a whole day resets to 0. 250 days unlocks 60 AI prompts/hour,
1000 saved tutor chats and Pro-size tutor storage for good (`plans.plan_of` → `perks: ["streak_reward"]`).

Question text is LaTeX with **doubled backslashes** (`$\theta$` in the JSON); `MathText` collapses them like the web.

## Billing (implemented in the app, `lib/features/billing/`)

- `GET /billing/status` → `{plan: free|pro, valid_until (ISO Z or null), limits, free_limits, pro_limits, usage,
  payments_enabled, test_mode, price: {amount (paise), currency, days}}`. `payments_enabled` is false when the
  server has no Razorpay keys (both prod and staging have **test** keys since 2026-11-24).
- `POST /billing/razorpay/order {reason}` → `{key_id, order_id, amount, currency, name, description, prefill, test_mode}`;
  503 when payments aren't configured. The amount is fixed server-side.
- `POST /billing/razorpay/verify {razorpay_order_id, razorpay_payment_id, razorpay_signature}` → `{plan, valid_until, limits}`.
  Idempotent; the `payment.captured` webhook grants Pro too if the app dies mid-payment.
- Paywall responses: 429 `ai_quota`, 402 `tutor_threads`/`tutor_storage`, 413 `media_too_large`, all with
  `detail = {code, message, upgrade: true, …}`. `showError` opens the sheet for these automatically.

## Tutor (P4)

Same endpoints the web uses; see `outstagram-server/README.md` "Exam attempts and AI tutor API", "Stats",
"Billing", and the web implementation in `outstagram-web/src/features/exams/` (`engine.ts` is the scoring source
of truth, `examApi.ts`, `QuestionChat.tsx` for SSE parsing) and `src/features/billing/`.

Content on prod (2026-11-24): question bank 46 topics / ~1,105 questions (group `pg_physics`), 49 community exams
(`GET /pariksha?page=n`, 10 per page; each `exam_json_str` embeds its questions), 0 server exam presets.
Web presets (GATE, CSIR NET, TIFR, BARC) and quick practice sample by **topic name → slug**
(`'Hydrogen Atom'` → `hydrogen_atom`) from the `SUBJECT_GROUPS` map in `engine.ts`. Every topic in it exists on
prod and staging.
