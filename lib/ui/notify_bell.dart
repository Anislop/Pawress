import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/updates.dart';
import 'app_scope.dart';
import 'theme.dart';

IconData notifyIcon(NotifyLevel level) => switch (level) {
  NotifyLevel.off => Icons.notifications_off_outlined,
  NotifyLevel.inApp => Icons.notifications_none_rounded,
  NotifyLevel.push => Icons.notifications_active_rounded,
};

/// The bell beside Following, as on an X profile: what this artist's new
/// posts do. Nothing shows until the artist is followed.
class NotifyBell extends StatelessWidget {
  const NotifyBell({super.key, required this.creator});

  final Creator creator;

  @override
  Widget build(BuildContext context) {
    final follow = AppScope.of(context).followOf(creator.key);
    if (follow == null) return const SizedBox.shrink();
    final level = follow.notify;
    return IconButton.outlined(
      tooltip: 'Notifications: ${level.label}',
      visualDensity: VisualDensity.compact,
      onPressed: () => showNotifySheet(context, creator),
      icon: Icon(
        notifyIcon(level),
        size: 20,
        color: level == NotifyLevel.push ? pawPink : null,
      ),
    );
  }
}

Future<void> showNotifySheet(BuildContext context, Creator creator) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: panel,
      builder: (_) => _NotifySheet(creator),
    );

class _NotifySheet extends StatelessWidget {
  const _NotifySheet(this.creator);

  final Creator creator;

  Future<void> _choose(BuildContext context, NotifyLevel? level) async {
    if (level == null) return;
    final state = AppScope.read(context);
    if (level == NotifyLevel.push) await Notifier.requestPermission();
    await state.setNotify(creator.key, level);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final follow = state.followOf(creator.key);
    if (follow == null) return const SizedBox.shrink();
    final settings = state.settings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications from ${creator.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Choose what happens when they post.',
              style: TextStyle(color: ink(.55)),
            ),
            const SizedBox(height: 8),
            RadioGroup<NotifyLevel>(
              groupValue: follow.notify,
              onChanged: (level) => _choose(context, level),
              child: Column(
                children: [
                  for (final level in const [
                    NotifyLevel.push,
                    NotifyLevel.inApp,
                    NotifyLevel.off,
                  ])
                    RadioListTile<NotifyLevel>(
                      value: level,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: Icon(notifyIcon(level)),
                      title: Text(switch (level) {
                        NotifyLevel.push => 'All posts',
                        NotifyLevel.inApp => 'In app only',
                        NotifyLevel.off => 'Off',
                      }),
                      subtitle: Text(
                        level == NotifyLevel.push && !settings.notifyBanners
                            ? '${level.description}, without pop-ups'
                            : level.description,
                      ),
                    ),
                ],
              ),
            ),
            if (!settings.notificationsEnabled &&
                follow.notify != NotifyLevel.off)
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: ink(.55)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'New post checks are off, so nothing arrives yet.',
                      style: TextStyle(color: ink(.55), fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Notifier.requestPermission();
                      await state.updateSettings(
                        state.settings.copyWith(notificationsEnabled: true),
                      );
                    },
                    child: const Text('Turn on'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
