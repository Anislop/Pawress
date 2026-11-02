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
    models.dart        Creator, Post, MediaFile, Follow, UpdateNotice, ... and JSON parsing
    api.dart           PawchiveApi (all HTTP); scrapers for DMs, popular posts, similar artists
    store.dart         Store: SharedPreferencesAsync + secure storage (session cookie); AppSettings
    feeds.dart         Feed (paged ChangeNotifier), OffsetFeed, PopularFeed, ForYouFeed + rankForYou, FollowingFeed (k-way merge)
    creators.dart      CreatorDirectory: cached, throttled profile lookups (feed posts carry only ids)
    updates.dart       UpdateChecker, Notifier (local notifications), BackgroundUpdates (WorkManager)
    downloads.dart     DownloadManager queue (2 at once, 1 s apart) writing to a SAF folder via DownloadTarget
    app_update.dart    AppUpdater: GitHub releases check (AppRelease.newest) and install via the pawress/updater channel
    app_state.dart     AppState: settings, account, follows, notices, favorites sync
  ui/
    app_scope.dart     AppScope.of(context) / AppScope.read(context) give AppState
    theme.dart         Palette (from assets), buildTheme(), BrandMark, SectionLabel
    widgets.dart       NetImage, CreatorAvatar, ServiceBadge, HtmlContent, FeedView, StatusView, time helpers
    splash.dart        BooruPlus-style splash + revealFromBottom transition
    onboarding.dart    Four parallax slides (art lags, text leads), notification permission, optional sign-in
    home.dart          HomeScreen (floating SliverAppBar + For You / Following / Popular tabs, Popular's bottom bar) and Sidebar (drawer)
    popular.dart       PopularTab: popular artists (from /creators, sorted on device) and PopularFeed posts
    post_card.dart     X-style post row, MediaGrid, openPost/openCreator/openViewer helpers
    autoplay.dart      FeedAutoplay (picks the one playing tile) and AutoplayMedia (muted video / GIF tile)
    downloads.dart     downloadFiles() (folder choice + enqueue), pickDownloadFolder(), DownloadsPage
    update_dialog.dart showUpdateDialog: changelog, progress, install errors
    post_page.dart     Full post: text, media, attachments, tags, comments
    media_viewer.dart  Full-screen swipe viewer: zoomable images, Chewie video
    creator_page.dart  Artist profile (banner, site, links, Follow, Similar artists sheet) + tabs; FollowButton, ArtistTile
    following_page.dart, notifications_page.dart, search_page.dart, settings_page.dart, login_page.dart
test/
  core_test.dart            Parsing, URLs, ranking, entity decoding, DM / popular / similar-artist scraping
  update_checker_test.dart  UpdateChecker against a fake Pawchive (MockClient + in-memory prefs)
  downloads_test.dart       DownloadManager: URL resolution, naming, failure and retry (in-memory target)
  app_update_test.dart      Release picking, nightly notes, AppUpdater over a mocked channel and GitHub
android/app/src/main/kotlin/.../MainActivity.kt   pawress/updater channel: appVersion, installUpdate
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
- **Following.** Follows are stored locally. When signed in, they sync both ways
  with Pawchive favorite creators (`AppState.syncFavorites`): `Follow.synced`
  marks follows already seen on the account, so a missing synced follow means
  it was removed on the website.
- **Notifications.** `UpdateChecker.check()` polls each follow's profile
  `updated` stamp, fetches the first page only when it changed, and treats
  post ids not in `Follow.seenPostIds` as new. A creator's first check only
  records a baseline. It runs from the Notifications page (pull to refresh)
  and from WorkManager (`backgroundDispatcher`, interval in Settings, 15 min
  minimum). The background isolate builds its own `Store` and `PawchiveApi`,
  so keep `core/` free of UI dependencies. The app reloads follows and notices
  from the store on resume.
- **For You.** The API has no recommendations. Each page of `/posts` is
  reordered by `rankForYou` (recency, plus boosts for followed creators and
  sites, without long runs from one creator).
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
- Downloads run only while the app is open (no foreground service or
  download notification).
- Older popular ranges (the page's "prev" links are parsed into
  `PopularPage.ranges` but not offered in the UI).
- Background checks for many follows make one profile request per follow; a
  batched source (e.g. `/creators` `updated` fields) could replace it.
- `applicationId` is still `com.example.pawress`.
