import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/config.dart';
import '../core/store.dart';
import '../core/updates.dart';
import 'app_scope.dart';
import 'downloads.dart';
import 'update_dialog.dart';
import 'login_page.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static String _interval(int minutes) => minutes < 60
      ? 'Every $minutes minutes'
      : minutes == 60
      ? 'Every hour'
      : 'Every ${minutes ~/ 60} hours';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final settings = state.settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          const SectionLabel('Account'),
          if (state.signedIn) ...[
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(state.accountName ?? 'Pawchive account'),
              subtitle: const Text(
                'Follows sync with your Pawchive favorite artists',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Sync follows now'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await state.syncFavorites();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Following ${state.follows.length} artists.'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              subtitle: const Text('Your follows stay on this device'),
              onTap: () async {
                // Forget the website login too, or signing in again would
                // skip straight back into the old session.
                await WebViewCookieManager().clearCookies();
                await state.signOut();
              },
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.login_rounded),
              title: const Text('Sign in to Pawchive'),
              subtitle: const Text(
                'Optional. Syncs follows with your favorite artists.',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginPage()),
              ),
            ),
          const SectionLabel('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('New post notifications'),
            subtitle: const Text(
              'Checks your followed artists in the background',
            ),
            value: settings.notificationsEnabled,
            onChanged: (value) async {
              if (value) await Notifier.requestPermission();
              await state.updateSettings(
                settings.copyWith(notificationsEnabled: value),
              );
            },
          ),
          ListTile(
            enabled: settings.notificationsEnabled,
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Check for new posts'),
            subtitle: Text(_interval(settings.checkIntervalMinutes)),
            onTap: () async {
              final minutes = await showDialog<int>(
                context: context,
                builder: (context) => RadioGroup<int>(
                  groupValue: settings.checkIntervalMinutes,
                  onChanged: (value) => Navigator.pop(context, value),
                  child: SimpleDialog(
                    title: const Text('Check for new posts'),
                    children: [
                      for (final minutes in AppSettings.intervals)
                        RadioListTile<int>(
                          value: minutes,
                          title: Text(_interval(minutes)),
                        ),
                    ],
                  ),
                ),
              );
              if (minutes != null) {
                await state.updateSettings(
                  settings.copyWith(checkIntervalMinutes: minutes),
                );
              }
            },
          ),
          const SectionLabel('Appearance'),
          RadioGroup<ThemeChoice>(
            groupValue: settings.theme,
            onChanged: (value) =>
                state.updateSettings(settings.copyWith(theme: value)),
            child: const Column(
              children: [
                RadioListTile<ThemeChoice>(
                  value: ThemeChoice.plum,
                  title: Text('Plum'),
                  subtitle: Text('The Pawress dark palette'),
                ),
                RadioListTile<ThemeChoice>(
                  value: ThemeChoice.amoled,
                  title: Text('AMOLED black'),
                  subtitle: Text('Pure black background'),
                ),
              ],
            ),
          ),
          const SectionLabel('Playback'),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: const Text('Autoplay videos and GIFs'),
            subtitle: const Text(
              'Muted in feeds, one at a time; with sound in the viewer',
            ),
            value: settings.autoplayVideos,
            onChanged: (value) =>
                state.updateSettings(settings.copyWith(autoplayVideos: value)),
          ),
          const SectionLabel('Downloads'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Download folder'),
            subtitle: Text(
              settings.downloadFolderName ?? 'Chosen on the first download',
            ),
            onTap: () async {
              final folder = await pickDownloadFolder();
              if (folder != null) {
                await state.updateSettings(
                  state.settings.copyWith(downloadFolder: folder),
                );
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.drive_folder_upload_outlined),
            title: const Text('Ask where to save each time'),
            value: settings.askDownloadFolder,
            onChanged: (value) => state.updateSettings(
              settings.copyWith(askDownloadFolder: value),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Downloads'),
            subtitle: const Text('Progress and finished files'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DownloadsPage()),
            ),
          ),
          const SectionLabel('About'),
          ListTile(
            leading: const Icon(Icons.replay_rounded),
            title: const Text('Show the introduction again'),
            onTap: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              state.replayOnboarding();
            },
          ),
          ListTile(
            leading: const Icon(Icons.public_rounded),
            title: const Text('Open Pawchive'),
            subtitle: const Text(siteHost),
            onTap: () => openExternal(siteUrl),
          ),
          const _VersionTile(),
          SwitchListTile(
            secondary: const Icon(Icons.system_update_outlined),
            title: const Text('Check for updates at launch'),
            subtitle: const Text(
              'Look for a newer GitHub release when Pawress starts',
            ),
            value: settings.checkUpdates,
            onChanged: (value) =>
                state.updateSettings(settings.copyWith(checkUpdates: value)),
          ),
        ],
      ),
    );
  }
}

/// The installed version and build, with "Check now" for a newer release.
class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
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
    builder: (context, snapshot) => ListTile(
      leading: const BrandMark(size: 28),
      title: Text(
        snapshot.data == null ? appName : '$appName ${snapshot.data!.label}',
      ),
      subtitle: Text(
        'An unofficial client for $siteHost. Updates come from GitHub '
        'releases.',
        style: TextStyle(color: ink(.5)),
      ),
      trailing: TextButton(
        onPressed: _checking ? null : _check,
        child: Text(_checking ? 'Checking…' : 'Check now'),
      ),
    ),
  );
}
