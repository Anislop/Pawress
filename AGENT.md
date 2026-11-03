# Pawress

Android client for [Pawchive](https://pawchive.pw), a Kemono-style archive
of Patreon, Pixiv Fanbox, Discord and other creator posts. It's built with Flutter,
is Android only (there's no `ios/` or other platform folder), and is laid out like
X on Android. The only bottom bar is the Popular tab's Artists / Posts switch. Its structure and intro follow
[BooruPlus](https://github.com/Anislop/BooruPlus).

Read [docs/pawchive-api.md](docs/pawchive-api.md) before touching anything
that talks to the network. It records the hosts, rate limits and API quirks
the code depends on.

## Commands

```bash
flutter pub get
flutter analyze            # must report "No issues found!"
flutter test               # unit tests in test/
dart format lib test       # the repo is formatted with dart format
flutter build apk --debug  # build/app/outputs/flutter-apk/app-debug.apk
flutter run                # on a connected device
dart run flutter_launcher_icons   # after changing assets/AppIcon.png
```

On Windows, `android/gradle.properties` sets `kotlin.incremental=false`
because the pub cache (C:) and the project (G:) are on different drives,
which breaks Kotlin incremental caches for plugin modules. Leave it.

## Layout

```
lib/
  main.dart            App root: splash -> onboarding -> home, revealed from the bottom
  core/                No widgets (except updates.dart's Flutter binding); safe for the background isolate
    config.dart        Hosts, user agent, page size
    models.dart        Creator, Post, MediaFile, Poll, Favorite, Like, Follow + NotifyLevel, Community*, UpdateNotice, ... and JSON parsing; threadComments
    api.dart           PawchiveApi (all HTTP); scrapers for DMs, popular posts, similar artists, community chats
    store.dart         Store: SharedPreferencesAsync + secure storage (session cookie); AppSettings
    backup.dart        Backup file (follows, likes, sign-in sealed with AES-GCM + PBKDF2), mergeFollows / mergeFavorites
    feeds.dart         Feed (paged ChangeNotifier), OffsetFeed, PopularFeed, FollowingFeed (k-way merge)
    for_you.dart       ForYouFeed: Taste (follows, likes, favorites), pickSources, takeBest, blendForYou
    creators.dart      CreatorDirectory: cached, throttled profile lookups (feed posts carry only ids)
    updates.dart       UpdateChecker, pushable, Notifier (local notifications, banner channel), BackgroundUpdates (WorkManager)
    downloads.dart     DownloadManager queue (2 at once, 1 s apart) writing to a SAF folder via DownloadTarget
    app_update.dart    AppUpdater: GitHub releases check (AppRelease.newest) and install via the pawress/updater channel
    app_state.dart     AppState: settings, account, follows + bells, likes, favorites, notices + in-app alerts, sync, backup
  ui/
    app_scope.dart     AppScope.of(context) / AppScope.read(context) give AppState
    theme.dart         Palette (from assets), buildTheme(), BrandMark, SectionLabel
    widgets.dart       NetImage, CreatorAvatar, ServiceBadge, HtmlContent, FeedView, StatusView, time helpers
    splash.dart        BooruPlus-style splash + revealFromBottom transition
    onboarding.dart    Four parallax slides (art lags, text leads), notification permission, optional sign-in
    home.dart          HomeScreen (floating SliverAppBar + For You / Following / Popular tabs, Popular's bottom bar) and Sidebar (drawer)
    popular.dart       PopularTab: popular artists (from /creators, sorted on device) and PopularFeed posts
    post_card.dart     X-style post row, PostActions (comments / thumbs up / favorite), MediaGrid, openPost/openCreator/openViewer helpers
    notify_bell.dart   NotifyBell (X-style bell beside Following) and showNotifySheet
    comments.dart      CommentList (threaded, left-aligned) and showComments (bottom sheet)
    poll.dart          PollView: a Patreon poll's results as bars
    autoplay.dart      FeedAutoplay (picks the one playing tile) and AutoplayMedia (muted video / GIF tile)
    downloads.dart     downloadFiles() (folder choice + enqueue), pickDownloadFolder(), DownloadsPage
    update_dialog.dart showUpdateDialog: changelog, progress, install errors
    post_page.dart     Full post: text, poll, actions, media, attachments, tags, comments
    media_viewer.dart  Full-screen viewer: every image and video in one vertical scroll, zoomable images, Chewie video
    creator_page.dart  Artist profile (banner, site, links, Follow, Similar artists sheet) + tabs; FollowButton, ArtistTile
    community_page.dart CommunityChatPage: a Patreon community channel as a chat log, newest at the bottom
    backup.dart        Export / import dialogs (SAF folder and file pickers)
    settings_cards.dart BooruPlus-style settings panels (SettingsGroup, SettingsSwitchCard, SettingsChoiceCard, ...)
    settings_page.dart  Settings, laid out like BooruPlus's but applied instantly (no save button)
    notification_settings.dart  X-style notification preferences and per-artist bells
    favorites_page.dart, following_page.dart, notifications_page.dart, search_page.dart, login_page.dart
test/
  for_you_test.dart         Taste, source sampling, blending and ForYouFeed over fake fetches
  core_test.dart            Parsing, URLs, entity decoding, polls, fancards, comment threads, DM / popular / similar-artist / community scraping
  backup_test.dart          Backup encoding and sealing, merges, AppState likes and their account sync
  update_checker_test.dart  UpdateChecker against a fake Pawchive (MockClient + in-memory prefs)
  downloads_test.dart       DownloadManager: URL resolution, naming, failure and retry (in-memory target)
  app_update_test.dart      Release picking, nightly notes, AppUpdater over a mocked channel and GitHub
android/app/src/main/kotlin/.../MainActivity.kt   pawress/updater channel: appVersion, installUpdate, notificationSettings
.github/workflows/          ci.yml (PRs, and called by CD) and cd.yml (nightly / tagged releases)
docs/pawchive-api.md        API reference and quirks
```

## How things work

- **State.** One `AppState` (`ChangeNotifier`) is provided by `AppScope`. There's
  no state-management package. Pages own their `Feed`s and dispose them.
- **Network.** Everything goes through `PawchiveApi`, and every image and
  video uses `NetImage`, `netImageProvider` or `mediaHeaders` so the Pawress
  user agent is sent. A plain `Image.network` without headers gets a 403 from
  the file host.
- **Full files.** `MediaFile.fullUrl` gives `temp_url` or the file host URL,
  or null when the post must be fetched again; the viewer does that.
  Thumbnails exist only for images.
- **Likes (thumbs up).** The thumbs up on a post stores a `Like` (post key,
  creator, tags, time) on the device only; Pawchive has no likes. It only
  feeds For You, and Settings can reset them. They go into backups.
- **Favorites.** The heart on a post (`PostActions`) stores the whole
  `Post` locally (`Favorite`, without `temp_url`s, which expire) and, when
  signed in, syncs with the account's favorite posts the same way follows do
  (`Favorite.synced`). The Favorites page in the sidebar lists them with no
  requests. Like counts exist only on popular posts.
- **Comments.** `threadComments` puts each reply under its parent with its
  depth; `CommentList` indents replies (up to 4 levels) and keeps every row
  left-aligned. The comments button opens them in a sheet (`showComments`),
  or on the post page loads them inline and scrolls there.
- **Community.** Patreon creators get a Community tab listing channels from
  the scraped page; a channel opens `CommunityChatPage`, a reversed list that
  loads older pages (25 messages, `o` increasing) as you scroll up.
- **Backup.** Settings exports follows and likes as readable JSON in a folder
  picked with SAF, plus the session cookie and account name sealed with a
  password (PBKDF2-HMAC-SHA256, run in an isolate, then AES-256-GCM).
  Importing merges: existing follows and likes stay, imported follows start
  without update state (so the first check only records a baseline) and
  unsynced (so the account sync adds them). Importing a sign-in while signed
  in signs out first so old synced marks can't delete anything.
- **Following.** Follows are stored locally. When signed in, they sync both ways
  with Pawchive favorite creators (`AppState.syncFavorites`): `Follow.synced`
  marks follows already seen on the account, so a missing synced follow means
  it was removed on the website.
- **Notification levels.** Each `Follow` has a `NotifyLevel` (the bell on
  the profile and in Following): `push` (Android notification, on the
  `artist_updates_banner` high-importance channel when
  `AppSettings.notifyBanners` is on, otherwise `artist_updates`), `inApp`
  (Notifications page, badge and an in-app alert snackbar) or `off` (not
  checked, no requests). New follows start at `AppSettings.defaultNotify`.
  Turning a bell on from off clears `seenPostIds` so the next check only
  records a baseline. HomeScreen polls the store each minute while
  resumed (`AppState.pollNotices`, no network) to raise in-app alerts.
- **Notifications.** `UpdateChecker.check()` polls each follow's profile
  `updated` stamp, fetches the first page only when it changed, and treats
  post ids not in `Follow.seenPostIds` as new. A creator's first check only
  records a baseline. It runs from the Notifications page (pull to refresh)
  and from WorkManager (`backgroundDispatcher`, interval in Settings, 15 min
  minimum). The background isolate builds its own `Store` and `PawchiveApi`,
  so keep `core/` free of UI dependencies. The app reloads follows and notices
  from the store on resume.
- **For You.** The API has no recommendations; `ForYouFeed` builds them.
  `Taste` weighs creators, sites and tags from follows, thumbs-up likes
  (half-life 30 days) and favorites (60 days). Each page takes
  `ForYouMix.followingShare` (Settings) of its 30 posts from followed and
  liked artists, whose first pages are fetched a few at a time
  (`pickSources`: weighted random by affinity and recent activity; at most
  6 creator requests per page), and the rest from `/posts`. Both pools are
  ranked by `Taste.score` (freshness + taste + jitter), capped per creator,
  blended and spread so no artist fills consecutive rows.
- **Popular.** There's no API for it. Popular posts are scraped from
  `/posts/popular` (`parsePopularPage`); those posts only carry a thumbnail
  path, so their file is marked preview-only and the viewer and downloads
  fetch the post for real URLs. Week and month need the range start date the
  page links to, which `PopularFeed` reads from the first page. Popular
  artists are the `/creators` list sorted on the device. Similar artists are
  scraped from `/{service}/user/{id}/recommended`.
- **Sidebar gesture.** `HomeScreen._onOverscroll` opens the drawer when the
  For You tab is dragged past its left edge; the drawer closes with its own
  drag.
- **Media viewer.** One `CustomScrollView` centered on the tapped item, so
  earlier items grow upward without moving it. Each item reports its
  visibility; the one filling most of the screen is "current" (top bar count,
  download, the video that may play). Images show the thumbnail at once and
  load the full file only while on screen, through `_FullFileGate` (two at a
  time, one second apart). The list stops scrolling while an image is
  zoomed.
- **Autoplay.** Each GIF or video tile reports its visibility (visibility_detector)
  to `FeedAutoplay.instance`, which picks one tile at 60%+ visibility. The tile
  waits 400 ms, then loads the full file (fetching the post first for
  preview-only files), muted and looping, and pauses when its route is
  covered. Only one full file loads at a time.
- **Downloads.** `downloadFiles` uses the saved folder (a persisted SAF tree
  URI in `AppSettings`), or asks with `SafUtil().pickDirectory`. The
  `DownloadManager` on `AppState` streams each file with the Pawress user
  agent into the folder through saf_stream, `<post id>_<name>`; Android
  numbers duplicates. `AppState` shows a snackbar when the queue empties.
- **App updates.** Modeled on BooruPlus. CD builds with
  `--build-number=<run number>` and `--dart-define=UPDATE_REPOSITORY=<repo>`
  and attaches `pawress-<version>-<build>.apk` to the `nightly` prerelease
  (each push to `main`) or a `v*` release. `AppUpdater.check()` asks the
  native side for the installed versionCode, lists the repository's
  releases, and `AppRelease.newest` picks the highest build above it. The
  dialog shows the nightly's commit message (up to `AppRelease.commitEnd`).
  `installUpdate` in `MainActivity.kt` downloads only from `github.com` /
  `*.githubusercontent.com` over HTTPS, checks the APK is this package, a
  higher versionCode and signed with the installed key, then opens the
  installer through a FileProvider (`res/xml/update_paths.xml`). Keep the
  CD workflow's name and the APK name pattern stable; the run number is the
  build number. HomeScreen checks once per launch when
  `AppSettings.checkUpdates` is on; Settings has "Check now".
- **CI/CD.** `ci.yml` (format check, analyze, test, debug build) runs on PRs
  and is called by `cd.yml` before building. Release signing comes from the
  `ANDROID_KEYSTORE_*` / `ANDROID_KEY_*` secrets via `android/key.properties`;
  without them builds fall back to the debug key and can't update installs.
  CI runs `dart format --set-exit-if-changed`, so format before pushing.
- **Sign-in.** The website's login form runs in a WebView. The `session` cookie is
  read with `WebViewCookieManager`, checked against `/account/favorites`, and
  stored in secure storage.
- **Theme.** `setPalette()` changes the global colors (`canvas`, `panel`,
  `ink()`, `hairline`) and the whole app rebuilds, as in BooruPlus. The brand
  colors are constants at the top of `theme.dart`, sampled from
  `assets/AppIcon.png` and the logos. Use `LogoFlatBlack.png` (pink) on dark
  surfaces.

## Conventions

- Match the existing style: `dart format`, single quotes, trailing commas,
  short `///` doc comments that say why, and no narration comments.
- Read API JSON leniently (`_str`, `_int`, `parseDate`, `parseTags`). Pawchive
  mixes types between endpoints, and a parse error in a feed shows an error
  state instead of crashing (`Feed.loadMore`).
- Respect the rate limits in `docs/pawchive-api.md`: no prefetching of full
  files, and throttle any new per-creator fan-out (see `CreatorDirectory`,
  `FollowingFeed._parallel`, `UpdateChecker._spacing`).
- New Pawchive behavior you discover goes into `docs/pawchive-api.md`.
- Add unit tests for parsing and core logic in `test/`. UI is verified on a
  device (see below).

## Testing on a device

`adb devices` lists the connected phone. Install with `adb install -r
build/app/outputs/flutter-apk/app-debug.apk`. The package is
`com.example.pawress`; `adb shell pm clear com.example.pawress` resets it
to the onboarding.

When driving the UI with `adb shell input`, first check that Pawress is
the foreground app (`adb shell dumpsys activity activities | grep
topResumedActivity`). A Back press on the home screen exits to the
launcher, and a later tap then lands in the owner's other apps.

WorkManager won't run the periodic job early, even with `cmd jobscheduler
run -f`. `adb shell dumpsys jobscheduler | grep pawress` shows that it's
scheduled.

## Not done yet / ideas

- iOS and other platforms (only `android/` exists).
- Blocked tags and a light theme.
- A "not interested" signal for For You (only positive likes exist).
- Downloads run only while the app is open (no foreground service or
  download notification).
- Older popular ranges (the page's "prev" links are parsed into
  `PopularPage.ranges` but not offered in the UI).
- Background checks for many follows make one profile request per follow; a
  batched source (e.g. `/creators` `updated` fields) could replace it.
- `applicationId` is still `com.example.pawress`.
