# Next plan: web parity + video compression (written 2026-11-25)

Two independent tracks. The server already has every endpoint the web needs (outstagram-server PRs #9–#14),
so track A is web-only. Track B is app-only (plus one optional server tweak). Each step lists files,
the approach, how to test, and how it ships. Rough sizes assume one focused session per track.

---

## A. Web gaps (outstagram-web) — ~1 session

Today the web can follow/unfollow, view profiles and lists (PR #8). Missing vs the app: a follow-request
inbox (approve/decline), editing name/bio, deleting comments, user search.

### A1. Follow-request inbox with Decline
- **Where:** new `src/components/Requests.tsx`; a bell button with a count badge in the Dashboard header
  (or a 6th tab if the bottom bar has room on 360 px phones — check the screenshot run first).
- **API (exists):** `GET /follow-requests`, `POST /request-approve/{id}`, `POST /request-reject/{id}` (204).
  Add `OutstagramAPI.rejectFollowRequest(id)`; `approveFollowRequest` exists.
- **UI:** list of `{avatar, username, time}` rows with Approve (primary) and ✕ Decline; row turns into
  "Approved"/"Declined"; tapping the name → `openProfile()`. Poll the count on app focus (no push).
- **Edge:** approving the second half of a mutual follow now works server-side (PR #9) — no special case.

### A2. Edit profile (name, bio)
- **Where:** `src/components/Profile.tsx` (own profile) → "Edit profile" button → small Dialog.
- **API (exists):** `PUT /me {fullname?, bio?}` → returns the `/me` body. Limits: name 1–60, bio ≤ 160 (422 otherwise).
- **UI:** two fields with counters, Save disabled while unchanged; on success update `currentUser` in
  `localStorage` (`outstagram_user`) so the header/name refresh without a re-login.

### A3. Delete comments
- **Where:** `src/components/PostView.tsx` comments list (and the comments sheet in `Feed.tsx` if it lists them).
- **API (exists):** `DELETE /posts/{post_id}/comments/{comment_id}` — the comment's author or the post's author.
- **UI:** a trash icon on hover/long-press for those comments only (compare `comment.author_user_id` / the
  post's `author_user_id` with the signed-in user); confirm; remove locally and decrement the count.
- **Check:** comments returned by `GET /posts/{id}/comments/{page}` carry `author_user_id` (they do since PR #9).

### A4. User search
- **Where:** a search field at the top of Explore (`src/components/Feed.tsx`), results in a dropdown list.
- **API (exists):** `GET /users/search?q=&limit=20` (username prefix or name substring, not yourself).
- **UI:** 250 ms debounce, min 1 char, results `{avatar, username, fullname}` → `openProfile()`; empty state
  "No one found"; Escape clears.

### A5. Ship
- One PR. CI type-checks and runs the Playwright screenshots (`e2e/screens.mjs`): add mocks for
  `/follow-requests`, `/users/search`, `PUT /me` and screens `requests`, `search`, `edit-profile`.
- Merge → `scripts/preview.sh deploy` on the portfolio box.
- Docs: `outstagram-web/README.md` feature list; tick `docs/TODO.md` §6 here.

---

## B. Video compression on the phone (outstagram_mobile) — ~1–1.5 sessions

Today videos are posted as they are, so Pro's 4 MB fits only a few seconds. Goal: shrink before upload so a
typical 30–60 s phone clip fits Pro, and Contributor uploads are fast.

### B1. Choose the encoder
| Option | Verdict |
|---|---|
| **AndroidX Media3 Transformer** via a small Kotlin MethodChannel | **Recommended.** Google-maintained, hardware H.264/HEVC encoders, handles rotation/HDR→SDR, no third-party Flutter plugin to break on AGP/compileSdk bumps (gotchas #25/#26). |
| `light_compressor` plugin | OK fallback; wraps a third-party Android library; check AGP 9 / compileSdk 37 compatibility first. |
| `video_compress` plugin | Older, uneven maintenance; skip. |
| `ffmpeg_kit_flutter` | Retired upstream (archived); don't adopt. |

### B2. Native side
- `android/app/build.gradle.kts`: `androidx.media3:media3-transformer` + `media3-effect` + `media3-common` (same version).
- New `android/app/src/main/kotlin/com/cyto/outstagram/VideoCompressor.kt` registered in `MainActivity`
  (`MethodChannel("outstagram/video")`):
  - `compress(path, targetBytes, maxHeight)` → output path in `cacheDir`. Pick a bitrate from duration:
    `videoBitrate = targetBytes*8*0.92/durationSec − audioBitrate` (audio AAC 96 kbps), clamp 300 kbps…8 Mbps;
    scale to ≤720p (≤1080p for Contributor); H.264 for compatibility. Report progress via an `EventChannel`
    (Transformer `getProgress`). Cancel on `cancel()`.
  - `probe(path)` → `{durationMs, width, height, rotation, bytes}` (MediaMetadataRetriever).
- R8: Media3 ships consumer rules; still check a release build plays/compresses (gotcha #22 pattern).

### B3. Dart side
- `lib/features/compose/video_compressor.dart`: `Future<CompressedVideo> compress(path, {targetBytes, onProgress})`.
- `compose_screen.dart` `_addVideo`: probe → if `bytes <= plan limit` keep as is (Contributor big clips stay
  full quality); else compress to `0.95 × limit` (Pro 4 MB) — and for Contributor compress anything > 100 MB
  to save upload time. Show a progress tile ("Compressing 42%") with cancel; then the existing size check.
- Free: still no videos (paywall), but compression lets the upgrade sheet say "your clip will fit Pro".
- Clean temp files after posting / on discard.

### B4. Limits & copy
- Composer note: "Videos are compressed on your phone to fit your plan."
- Paywall rows unchanged (limits are the same); docs: `docs/TODO.md` §7 "Videos via share-target" bullet.

### B5. Tests & QA
- Unit: bitrate math (duration → bitrate, clamps), the keep-or-compress decision per plan.
- Widget: progress tile + cancel.
- On device (S22): 10 s / 60 s / 3 min clips, portrait + landscape, a 4K HDR clip; check the posted video
  plays on web and app, size ≤ limit, orientation right.
- Release APK through CI (`publish-apk`), then friends test.

### B6. Optional server tweak
- None required (limits are checked on the presign request). Optional: reject `POST /posts` video URLs that
  weren't presigned by us (store issued `object_key`s for an hour) to stop hand-crafted links.

---

## Order
1. A (quick, visible to web users) → deploy.
2. B1–B3 behind a debug flag → on-device QA → B4/B5 → release APK.
