# Implementation backlog 1

Features and QoL ideas from the November 2026 review that are not built yet.
The rest of that list shipped: post-to-post navigation, artist search,
opening pawchive.pw links, older popular ranges, more haptics, blocked
artists and tags with "not interested", History with the Following "caught
up" line, the light and Auto themes, data saver and cache controls, sharing
and "Set as" in the viewer, and background downloads.

Each entry says what it is, why it's worth doing, and where it would go.
Read [pawchive-api.md](pawchive-api.md) before anything that adds requests.

## Pawchive features

### Post revisions

- **What.** An "Edited · N versions" row on a post that opens earlier
  versions of its text and files, for example when an artist swaps a
  censored image.
- **API.** `GET /{service}/user/{id}/post/{post}/revisions` is in the
  schema. It returned `[]` for a recent Patreon post (2026-11-05), so the
  item shape is unknown. Find a post that has revisions, write the format
  into `pawchive-api.md`, and add a `Revision` model with lenient parsing.
- **Where.** `ArchiveApi.revisions`, a section on `PostPage` below the
  attachments, loaded only when tapped (like comments) so opening a post
  costs no extra request.

### Report broken files (flag for re-import)

- **What.** "Report broken files" in the post menu, offered when a
  preview-only file can't be resolved or a file 404s.
- **API.** `POST /{service}/user/{id}/post/{post}/flag` is in the schema. On
  Kemono it queues the post for a re-import and may need the session
  cookie. Confirm the method, auth and response before shipping, and
  confirm with the user before every flag (it reaches the site's queue).
- **Where.** `showPostMenu` in `post_card.dart`, and an action on the
  viewer's "This file is not available" state.

## Privacy

### Discreet mode

- **What.** Three switches under a new Privacy section in Settings:
  - Hide Pawress's preview in recent apps (`FLAG_SECURE`). This also blocks
    screenshots, so say so.
  - Lock with fingerprint or the device PIN when the app comes back after a
    set time.
  - Private notifications: no big picture, and
    `NotificationVisibility.private` with a public version that just says
    "New posts", so nothing shows on the lock screen.
- **Where.** `FLAG_SECURE` through a `setSecure` call on the
  `pawress/intents` channel (`window.addFlags` in `MainActivity.kt`).
  The lock would need `local_auth` (or a BiometricPrompt call on the
  channel) and a lock screen route shown from `HomeScreen`'s lifecycle
  observer. `Notifier._details` in `updates.dart` reads the setting; the
  background isolate already loads `AppSettings`.

### Blur thumbnails until tapped

- **What.** A setting that blurs every feed thumbnail until it's tapped
  once, for browsing in public.
- **Where.** `_MediaTile` in `post_card.dart` and the media grid in
  `creator_media.dart`: an `ImageFiltered` blur with a per-session set of
  revealed post keys on `AppState`. Autoplay should wait until the tile is
  revealed.

## Feeds

### Compact and grid layouts

- **What.** A Settings choice between the current X-style rows, a compact
  row (small square thumbnail beside the text) and a two-column grid of
  first images.
- **Where.** `FeedView` takes an item builder already; add a layout enum to
  `AppSettings` and switch builders in `HomeScreen._Tab`, `PopularTab` and
  `TagPostsPage`. The grid needs `SliverGrid` and the same "hidden posts"
  filtering `FeedView` does.

### Search History

- **What.** A filter field on the History page.
- **Where.** `history_page.dart`, matching post titles, excerpts and artist
  names on the device.

## Following and notifications

### Snooze a bell

- **What.** "Mute for a day / a week" in the bell sheet, gentler than
  switching notifications off. Sort Following by last updated, site or
  unread.
- **Where.** A `snoozedUntil` on `Follow`. `UpdateChecker` still records
  new posts while snoozed (so nothing is reported in a burst afterwards)
  but `pushable` and the in-app alert skip them. Sorting goes in
  `following_page.dart`.

### Grouped notifications with actions

- **What.** When one check finds several artists, post an Android summary
  notification (group key) over the per-artist ones. Add "Mark read" and
  "Open artist" actions.
- **Where.** `Notifier.show` in `updates.dart`: `groupKey` on each
  notification plus one summary with `setAsGroupSummary`. Actions use
  `AndroidNotificationAction`; "Mark read" has to work from the background
  isolate, so it edits notices through `Store`.

### Batched update checks

- **What.** One request for every follow's `updated` stamp instead of one
  profile request per follow.
- **Where.** `/creators` has `updated` for every creator but is about
  16 MB, too heavy for every check. Look for a lighter source (the
  `/artists` page sorted by update, or a schema endpoint with filters)
  before replacing `UpdateChecker._checkOne`'s profile request. This
  matters more as follow counts grow.

## Downloads

### Download all from an artist

- **What.** "Download all" on a profile with filters (images, GIFs,
  videos, a date range) and a preview of the count first.
- **Where.** Page the artist with `OffsetFeed` (as `CreatorMediaTab` does)
  and enqueue into `DownloadManager`, which already keeps to 2 at once and
  1 s apart. Remember saved file keys (`<post key>/<path>`) in `Store` so a
  second run skips what's already saved, and mark saved files in
  Downloads. A large run should confirm first and show its size estimate.

## Polish

### Accessibility labels

- **What.** No widget sets a `semanticsLabel`, and many buttons are
  icon-only, so TalkBack can't name them.
- **Where.** Tooltips on every `IconButton` (most have one; `_ActionButton`
  does), `Semantics` labels on `MediaGrid` tiles ("Image 2 of 4",
  "Video"), `CreatorAvatar` ("Artist's avatar"), and the viewer's pages.
  Check with TalkBack on a device.

### Automatic backups

- **What.** Write a backup into the saved folder on a schedule (weekly,
  keeping the last few files).
- **Where.** The WorkManager job in `updates.dart` (`backgroundDispatcher`)
  can run a second task. `exportBackup` lives on `AppState`, so move the
  encoding to a function over `Store` that both can call, and write through
  `saf_stream` with the persisted tree URI. It must never include the
  sealed sign-in, since that needs a password typed in.

## Smaller follow-ups from this round

- Unverified app links: pawchive.pw links only open in Pawress after
  "Open supported links" is allowed in Android's app settings. A Settings
  row could open that page (`Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS`
  on Android 12+).
- Data saver could also lower the thumbnail work in feeds (smaller decode
  sizes through `memCacheWidth`), and stop the Media tab's automatic
  "load up to 4 more pages".
- Popular range labels for days ("November 4, 2026") come straight from the
  page heading; a date picker could jump further back than one step at a
  time.
- The light theme reuses the dark onboarding art; onboarding could follow
  the theme too.
