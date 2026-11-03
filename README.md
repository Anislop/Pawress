<p align="center">
  <img src="assets/AppIcon.png" width="96" alt="Pawress icon"><br>
  <img src="assets/LogoFlatBlack.png" width="260" alt="Pawress">
</p>

An unofficial Android client for [Pawchive](https://pawchive.pw), the archive
of Patreon, Pixiv Fanbox, Discord and other creator posts. It's built with
Flutter and laid out like X on Android.

> Pawchive hosts adult content. Pawress asks users to confirm they're 18 or
> older during onboarding.

## Features

- **Intro.** A splash that reveals the app from the bottom, then four swipeable
  onboarding slides with parallax art. They can ask for notification permission
  and offer an optional sign-in.
- **Home.** A top bar that hides as you scroll, with **For You**, **Following**
  and **Popular** tabs.
  - **For You:** site-wide recent posts, ranked toward the artists and sites you
    follow.
  - **Following:** posts from the artists you follow, merged newest first.
  - **Popular:** a bottom bar switches between **Artists** (every creator,
    ranked by favorites, filterable by site and sortable) and **Posts** (the
    most favorited posts today, this week or this month).
- **Sidebar.** Your account, follow count, Following, Favorites,
  Notifications, Explore, Downloads and Settings. Swipe right on For You to open it, left to close it.
- **Artist pages.** Banner, avatar, original site (Patreon, Pixiv Fanbox,
  Discord, Fantia and more) with a link, linked accounts, **Follow** and
  **Similar artists**. Tabs for Posts, Announcements, Tags (tap one to filter
  posts), DMs, Community chats (Patreon) and Fancards (Fanbox).
- **Posts.** Full text, every image and video, Patreon poll results, other
  attachments, tags and threaded comments. Every post has a comments button
  (a sheet over the feed) and a like button, with the favorite count on
  popular posts.
- **Favorites.** Liked posts, kept on the device and synced with your Pawchive
  favorite posts when signed in.
- **Media viewer.** Full screen, with a post's images and videos one under
  another in a single vertical scroll, pinch and double-tap zoom. GIFs
  animate, and videos play inline with controls.
- **Autoplay.** In feeds, the most visible GIF or video plays muted and looping,
  one at a time. It can be turned off in Settings.
- **Downloads.** Save one file from the viewer, every file of a post, or a
  single attachment. You pick the folder once (Android's folder picker) or
  every time. A Downloads page shows progress and lets you retry failures.
- **Notifications.** New posts from followed artists show up in the
  Notifications page and as Android notifications. A background check runs
  every 15 minutes to 12 hours.
- **Search.** Find artists by name across services, or search post text.
- **Account sync.** Optional sign-in through Pawchive's own login page. Follows
  and likes then sync with your Pawchive favorite artists and posts.
- **Backup.** Export follows and likes to a JSON file, optionally with your
  sign-in encrypted by a password, and import them on another device.
- **Themes.** Plum (the brand palette) or AMOLED black.
- **Updates.** At launch (or from Settings, "Check now"), Pawress looks for a
  newer build in this repository's GitHub releases and offers to install it.
  It only installs an APK of this app that is newer and signed with the same
  key.

## Building

Requires Flutter 3.47+ (Dart 3.13) and the Android SDK.

```bash
flutter pub get
flutter run                    # on a connected device or emulator
flutter build apk --release
```

Checks:

```bash
flutter analyze
flutter test
```

The launcher icon is generated from `assets/AppIcon.png`:

```bash
dart run flutter_launcher_icons
```

## Releases and CI/CD

- **CI** (`.github/workflows/ci.yml`) runs on pull requests: format check,
  `flutter analyze`, `flutter test`, and a debug build.
- **CD** (`.github/workflows/cd.yml`) runs CI on every push to `main` and on
  `v*` tags, then builds release and debug APKs with the run number as the
  build number. A push to `main` replaces the `nightly` prerelease; a tag
  creates a versioned release. The release APK is named
  `pawress-<version>-<build>.apk`, which is what the in-app updater looks for.
- **Signing.** Set the repository secrets `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.
  Without them the release APK is signed with a throwaway debug key, and
  installed copies can't update to it. Locally, an `android/key.properties`
  with `storeFile`, `storePassword`, `keyAlias` and `keyPassword` does the
  same (it's gitignored).

To cut a versioned release, bump `version:` in `pubspec.yaml` (the part
before `+`) and push a tag such as `v1.1.0`.

## Project layout

- `lib/core`: API client, models, storage, feeds and the update checker
  (no UI).
- `lib/ui`: screens and widgets.
- `docs/pawchive-api.md`: the Pawchive endpoints, hosts, rate limits and
  quirks the app relies on.
- `AGENT.md`: architecture and conventions for contributors and coding agents.

## Notes

- Pawress identifies itself to Pawchive with a `Pawress/<version>` user agent
  and keeps to the site's download limits (about 1 per second, 5 at once).
- Pawress isn't affiliated with Pawchive or any of the archived services.
