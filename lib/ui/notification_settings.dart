import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/updates.dart';
import 'app_scope.dart';
import 'notify_bell.dart';
import 'post_card.dart';
import 'settings_cards.dart';
import 'theme.dart';
import 'widgets.dart';

String _interval(int minutes) => minutes < 60
    ? '$minutes min'
    : minutes == 60
    ? '1 hour'
    : '${minutes ~/ 60} hours';

/// Notification preferences, laid out like X's: push (Android) and in-app
/// delivery, the bell new follows start with, and each artist's bell.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  late Future<bool> _permitted = Notifier.permitted();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The user may have changed the permission in Android's settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _permitted = Notifier.permitted());
    }
  }

  Future<void> _allow() async {
    final granted = await Notifier.requestPermission();
    // Android stops asking after two refusals; only its settings can help.
    if (!granted) await Notifier.openSystemSettings();
    if (mounted) setState(() => _permitted = Notifier.permitted());
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final settings = state.settings;
    final on = settings.notificationsEnabled;
    void update(AppSettings value) => state.updateSettings(value);
    final counts = {for (final level in NotifyLevel.values) level: 0};
    for (final follow in state.follows) {
      counts[follow.notify] = counts[follow.notify]! + 1;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SettingsList(
        children: [
          const SettingsHeadline(
            kicker: 'Preferences',
            title: 'Choose what reaches you, and how.',
          ),
          FutureBuilder<bool>(
            future: _permitted,
            builder: (context, snapshot) => snapshot.data == false && on
                ? SettingsWarningCard(
                    title: 'Blocked by Android',
                    body:
                        'Pawress can\'t post notifications. In-app alerts '
                        'still work.',
                    action: FilledButton(
                      onPressed: _allow,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Allow'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SettingsSection('New posts'),
          SettingsSwitchCard(
            icon: Icons.notifications_active_outlined,
            title: 'New post notifications',
            subtitle:
                'Check the artists you follow for new posts, even while '
                'Pawress is closed.',
            value: on,
            onChanged: (value) async {
              if (value) await Notifier.requestPermission();
              update(settings.copyWith(notificationsEnabled: value));
              if (mounted) setState(() => _permitted = Notifier.permitted());
            },
          ),
          SettingsGroup(
            children: [
              ListTile(
                enabled: on,
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Check for new posts'),
                subtitle: const Text('Android may run it a little later.'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                trailing: DropdownButton<int>(
                  value: settings.checkIntervalMinutes,
                  underline: const SizedBox.shrink(),
                  onChanged: on
                      ? (minutes) => update(
                          settings.copyWith(checkIntervalMinutes: minutes),
                        )
                      : null,
                  items: [
                    for (final minutes in AppSettings.intervals)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(_interval(minutes)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SettingsSection('Push notifications'),
          SettingsGroup(
            children: [
              SettingsSwitch(
                icon: Icons.web_asset_rounded,
                title: 'Pop-up banners',
                subtitle:
                    'Push notifications slide down over whatever is on '
                    'screen instead of waiting in the shade.',
                value: settings.notifyBanners,
                onChanged: on
                    ? (value) => update(settings.copyWith(notifyBanners: value))
                    : null,
              ),
              SettingsTile(
                icon: Icons.tune_rounded,
                title: 'Sound, vibration and lock screen',
                subtitle: 'Opens Android\'s notification settings for Pawress',
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (!await Notifier.openSystemSettings()) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Could not open Android\'s settings.'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const SettingsSection('In app'),
          SettingsSwitchCard(
            icon: Icons.campaign_outlined,
            title: 'In-app alerts',
            subtitle:
                'A banner at the bottom of Pawress when new posts arrive '
                'while you\'re using it. Notifications always lists them.',
            value: settings.inAppAlerts,
            onChanged: on
                ? (value) => update(settings.copyWith(inAppAlerts: value))
                : null,
          ),
          const SettingsSection('Artists'),
          SettingsChoiceCard<NotifyLevel>(
            icon: Icons.person_add_alt_outlined,
            title: 'New follows start with',
            subtitle: switch (settings.defaultNotify) {
              NotifyLevel.push =>
                'Every new post from an artist you follow is a push '
                    'notification.',
              NotifyLevel.inApp =>
                'New posts only show in Notifications and as in-app alerts.',
              NotifyLevel.off =>
                'Turn on the bell on an artist\'s profile to hear from them.',
            },
            values: const [
              NotifyLevel.push,
              NotifyLevel.inApp,
              NotifyLevel.off,
            ],
            label: (level) => level.label,
            icons: notifyIcon,
            selected: settings.defaultNotify,
            onChanged: (level) =>
                update(settings.copyWith(defaultNotify: level)),
          ),
          SettingsTileCard(
            tile: SettingsTile(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications per artist',
              subtitle: state.follows.isEmpty
                  ? 'Follow artists to choose here'
                  : '${counts[NotifyLevel.push]} push · '
                        '${counts[NotifyLevel.inApp]} in app · '
                        '${counts[NotifyLevel.off]} off',
              onTap: state.follows.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _ArtistBellsPage(),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every followed artist with their bell, plus "set all".
class _ArtistBellsPage extends StatelessWidget {
  const _ArtistBellsPage();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final follows = [...state.follows]
      ..sort(
        (a, b) => a.creator.name.toLowerCase().compareTo(
          b.creator.name.toLowerCase(),
        ),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications per artist',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<NotifyLevel>(
            tooltip: 'Set all',
            icon: const Icon(Icons.done_all_rounded),
            onSelected: state.setNotifyAll,
            itemBuilder: (_) => [
              for (final level in const [
                NotifyLevel.push,
                NotifyLevel.inApp,
                NotifyLevel.off,
              ])
                PopupMenuItem(
                  value: level,
                  child: Row(
                    children: [
                      Icon(notifyIcon(level), size: 20),
                      const SizedBox(width: 12),
                      Text('All ${level.label.toLowerCase()}'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 40),
        itemCount: follows.length,
        itemBuilder: (context, index) {
          final follow = follows[index];
          final c = follow.creator;
          return ListTile(
            leading: CreatorAvatar(c, size: 42),
            title: Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${c.site.label} · ${follow.notify.label}',
              style: TextStyle(color: ink(.5)),
            ),
            trailing: NotifyBell(creator: c),
            onTap: () => openCreator(context, c),
          );
        },
      ),
    );
  }
}
