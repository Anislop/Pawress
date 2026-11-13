import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_state.dart';
import '../core/config.dart';
import '../core/store.dart';
import 'app_scope.dart';
import 'backup.dart';
import 'blocked_page.dart';
import 'downloads.dart';
import 'history_page.dart';
import 'login_page.dart';
import 'notification_settings.dart';
import 'settings_cards.dart';
import 'share.dart';
import 'theme.dart';
import 'update_dialog.dart';
import 'widgets.dart';

/// Settings in BooruPlus's layout: rounded panels under section labels.
/// Every change applies at once.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static String _notificationSummary(AppSettings settings) {
    if (!settings.notificationsEnabled) return 'Off';
    return [
      settings.notifyBanners ? 'Push with banners' : 'Push without banners',
      if (settings.inAppAlerts) 'in-app alerts',
      'new follows: ${settings.defaultNotify.label.toLowerCase()}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final settings = state.settings;
    void update(AppSettings value) => state.updateSettings(value);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SettingsList(
        children: [
          const SettingsHeadline(
            kicker: 'Pawress preferences',
            title: 'Check your settings and preferences!',
          ),
          const SettingsSection('Account'),
          SettingsGroup(
            children: state.signedIn
                ? [
                    SettingsTile(
                      icon: Icons.verified_user_outlined,
                      iconColor: pawPink,
                      title: state.accountName ?? 'Pawchive account',
                      subtitle:
                          'Follows and favorites sync with your Pawchive '
                          'favorites',
                    ),
                    SettingsTile(
                      icon: Icons.sync_rounded,
                      title: 'Sync now',
                      trailing: const SizedBox.shrink(),
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await state.syncFavorites();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Following ${state.follows.length} artists, '
                              '${state.favorites.length} favorites.',
                            ),
                          ),
                        );
                      },
                    ),
                    SettingsTile(
                      icon: Icons.logout_rounded,
                      title: 'Sign out',
                      subtitle:
                          'Your follows and favorites stay on this device',
                      trailing: const SizedBox.shrink(),
                      onTap: () async {
                        // Forget the website login too, or signing in again
                        // would skip straight back into the old session.
                        await WebViewCookieManager().clearCookies();
                        await state.signOut();
                      },
                    ),
                  ]
                : [
                    SettingsTile(
                      icon: Icons.login_rounded,
                      title: 'Sign in to Pawchive',
                      subtitle:
                          'Optional. Syncs follows and favorites with your '
                          'account.',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginPage(),
                        ),
                      ),
                    ),
                  ],
          ),
          const SettingsSection('Notifications'),
          SettingsTileCard(
            tile: SettingsTile(
              icon: settings.notificationsEnabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              title: 'Notifications',
              subtitle: _notificationSummary(settings),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationSettingsPage(),
                ),
              ),
            ),
          ),
          const SettingsSection('For You'),
          SettingsChoiceCard<ForYouMix>(
            icon: Icons.auto_awesome_outlined,
            title: 'Timeline mix',
            subtitle: switch (settings.forYouMix) {
              ForYouMix.following =>
                'Almost everything comes from artists you follow or like, '
                    'with a little discovery.',
              ForYouMix.balanced =>
                'Mostly your artists, with recent posts that match your '
                    'likes mixed in.',
              ForYouMix.discover =>
                'More new artists picked by your likes, with your artists '
                    'still in the mix.',
            },
            values: ForYouMix.values,
            label: (mix) => mix.label,
            selected: settings.forYouMix,
            onChanged: (mix) => update(settings.copyWith(forYouMix: mix)),
          ),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.thumb_up_alt_outlined,
                title: state.likes.length == 1
                    ? '1 like'
                    : '${state.likes.length} likes',
                subtitle:
                    'The thumbs up on a post teaches For You. Likes stay on '
                    'this device.',
                trailing: TextButton(
                  onPressed: state.likes.isEmpty
                      ? null
                      : () => _confirmClearLikes(context),
                  child: const Text('Reset'),
                ),
              ),
              SettingsTile(
                icon: Icons.block_rounded,
                title: 'Blocked artists and tags',
                subtitle: _blockedSummary(state),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BlockedPage()),
                ),
              ),
            ],
          ),
          const SettingsSection('History'),
          SettingsGroup(
            children: [
              SettingsSwitch(
                icon: Icons.history_rounded,
                title: 'Keep history',
                subtitle: 'Remember the posts and artists you open.',
                value: settings.keepHistory,
                onChanged: (value) =>
                    update(settings.copyWith(keepHistory: value)),
              ),
              SettingsTile(
                icon: Icons.manage_history_rounded,
                title: 'History',
                subtitle: state.history.length == 1
                    ? '1 entry'
                    : '${state.history.length} entries',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
                ),
              ),
            ],
          ),
          const SettingsSection('Appearance'),
          SettingsChoiceCard<ThemeChoice>(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: switch (settings.theme) {
              ThemeChoice.plum => 'The Pawress dark palette.',
              ThemeChoice.amoled => 'Pure black, easy on OLED screens.',
              ThemeChoice.light => 'Soft pink paper for bright rooms.',
              ThemeChoice.system =>
                "Light or Plum, following Android's dark theme.",
            },
            values: ThemeChoice.values,
            label: (choice) => choice.label,
            selected: settings.theme,
            onChanged: (choice) => update(settings.copyWith(theme: choice)),
          ),
          const SettingsSection('Playback'),
          SettingsSwitchCard(
            icon: Icons.play_circle_outline_rounded,
            title: 'Autoplay videos and GIFs',
            subtitle:
                'Muted in feeds, one at a time; with sound in the viewer.',
            value: settings.autoplayVideos,
            onChanged: (value) =>
                update(settings.copyWith(autoplayVideos: value)),
          ),
          const SettingsSection('Data and storage'),
          SettingsChoiceCard<DataSaver>(
            icon: Icons.data_saver_on_rounded,
            title: 'Data saver',
            subtitle: switch (settings.dataSaver) {
              DataSaver.off => 'Images and videos load as usual.',
              DataSaver.mobile =>
                'On mobile data, feeds don\'t autoplay and the viewer shows '
                    'thumbnails until you ask for the full image.',
              DataSaver.always =>
                'Feeds never autoplay and the viewer shows thumbnails until '
                    'you ask for the full image.',
            },
            values: DataSaver.values,
            label: (saver) => saver.label,
            selected: settings.dataSaver,
            onChanged: (saver) => update(settings.copyWith(dataSaver: saver)),
          ),
          const _CacheCard(),
          const SettingsSection('Downloads'),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.folder_outlined,
                title: 'Download folder',
                subtitle:
                    settings.downloadFolderName ??
                    'Chosen on the first download',
                onTap: () async {
                  final folder = await pickDownloadFolder();
                  if (folder != null) {
                    await state.updateSettings(
                      state.settings.copyWith(downloadFolder: folder),
                    );
                  }
                },
              ),
              SettingsSwitch(
                icon: Icons.drive_folder_upload_outlined,
                title: 'Ask where to save each time',
                subtitle: 'Pick a folder for every download.',
                value: settings.askDownloadFolder,
                onChanged: (value) =>
                    update(settings.copyWith(askDownloadFolder: value)),
              ),
              SettingsTile(
                icon: Icons.download_rounded,
                title: 'Downloads',
                subtitle: 'Progress and finished files',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DownloadsPage(),
                  ),
                ),
              ),
            ],
          ),
          const SettingsSection('Backup'),
          SettingsActionsCard(
            text:
                'Save your follows (with their notification settings), '
                'favorites, likes and blocks to a readable JSON file, or '
                'restore them from one. Importing adds to what is already '
                'here. With a '
                'password, your Pawchive sign-in is included, encrypted.',
            actions: [
              OutlinedButton.icon(
                onPressed: () => exportBackup(context),
                icon: const Icon(Icons.upload_file_outlined, size: 17),
                label: const Text('Export backup'),
              ),
              OutlinedButton.icon(
                onPressed: () => importBackup(context),
                icon: const Icon(Icons.restore_rounded, size: 17),
                label: const Text('Import backup'),
              ),
            ],
          ),
          const SettingsSection('Updates'),
          const _VersionCard(),
          SettingsSwitchCard(
            icon: Icons.system_update_outlined,
            title: 'Check for updates at launch',
            subtitle:
                'Look for a newer GitHub release when Pawress starts and offer '
                'to install it.',
            value: settings.checkUpdates,
            onChanged: (value) =>
                update(settings.copyWith(checkUpdates: value)),
          ),
          const SettingsSection('About'),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.replay_rounded,
                title: 'Show the introduction again',
                onTap: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  state.replayOnboarding();
                },
              ),
              SettingsTile(
                icon: Icons.public_rounded,
                title: 'Open Pawchive',
                subtitle: Provider.pawchive.host,
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => openExternal(Provider.pawchive.siteUrl),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _blockedSummary(AppState state) {
    final blocklist = state.blocklist;
    if (blocklist.isEmpty) return 'Hide artists and tags from your feeds';
    String count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';
    return [
      if (blocklist.creators.isNotEmpty)
        count(blocklist.creators.length, 'artist'),
      if (blocklist.tags.isNotEmpty) count(blocklist.tags.length, 'tag'),
    ].join(', ');
  }

  static Future<void> _confirmClearLikes(BuildContext context) async {
    final state = AppScope.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Reset likes?'),
        content: const Text(
          'For You forgets what you liked and goes back to your follows and '
          'favorites. Favorites are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.clearLikes();
  }
}

/// How much the image cache holds, with a button to empty it.
class _CacheCard extends StatefulWidget {
  const _CacheCard();

  @override
  State<_CacheCard> createState() => _CacheCardState();
}

class _CacheCardState extends State<_CacheCard> {
  late Future<int> _size = imageCacheBytes();
  bool _clearing = false;

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await clearImageCache();
    } finally {
      if (mounted) {
        setState(() {
          _clearing = false;
          _size = imageCacheBytes();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _size,
    builder: (context, snapshot) => SettingsGroup(
      children: [
        SettingsTile(
          icon: Icons.storage_rounded,
          title: 'Image cache',
          subtitle: snapshot.hasData
              ? '${formatBytes(snapshot.data!)} of thumbnails, avatars and '
                    'viewed images'
              : 'Measuring…',
          trailing: TextButton(
            onPressed: _clearing || (snapshot.data ?? 0) == 0 ? null : _clear,
            child: Text(_clearing ? 'Clearing…' : 'Clear'),
          ),
        ),
      ],
    ),
  );
}

/// The installed version and build, with "Check now" for a newer release.
class _VersionCard extends StatefulWidget {
  const _VersionCard();

  @override
  State<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends State<_VersionCard> {
  late final _installed = AppScope.read(context).updater.installedVersion();
  bool _checking = false;

  Future<void> _check() async {
    final updater = AppScope.read(context).updater;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    try {
      final release = await updater.check();
      if (!mounted) return;
      if (release == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Pawress is up to date.')),
        );
      } else {
        await showUpdateDialog(context, updater: updater, release: release);
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not check for updates. Try again later.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _installed,
    builder: (context, snapshot) => SettingsGroup(
      children: [
        ListTile(
          leading: const BrandMark(size: 28),
          title: Text(
            snapshot.data == null
                ? appName
                : '$appName ${snapshot.data!.label}',
          ),
          subtitle: const Text(
            'An unofficial client for Pawchive and Coomer. Updates come '
            'from GitHub releases.',
          ),
          trailing: TextButton(
            onPressed: _checking ? null : _check,
            child: Text(_checking ? 'Checking…' : 'Check now'),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
    ),
  );
}
