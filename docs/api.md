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

## Auth

See `docs/auth.md`. `POST /login` is **form-encoded**; everything else is JSON.

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

## Exams, tutor, billing (to build in P3–P5)

Same endpoints the web uses; see `outstagram-server/README.md` "Exam attempts and AI tutor API", "Stats",
"Billing", and the web implementation in `outstagram-web/src/features/exams/` (`engine.ts` is the scoring source
of truth, `examApi.ts`, `QuestionChat.tsx` for SSE parsing) and `src/features/billing/`.

Content on prod (2026-11-24): question bank 46 topics / ~1,105 questions (group `pg_physics`), 49 community exams
(`GET /pariksha?page=n`, 10 per page; each `exam_json_str` embeds its questions), 0 server exam presets.
Web presets (GATE, CSIR NET, TIFR, BARC) and quick practice sample by **topic name → slug**
(`'Hydrogen Atom'` → `hydrogen_atom`) from the `SUBJECT_GROUPS` map in `engine.ts`. Every topic in it exists on
prod and staging.
