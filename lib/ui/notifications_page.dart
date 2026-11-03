import 'package:flutter/material.dart';

import '../core/models.dart';
import 'app_scope.dart';
import 'notification_settings.dart';
import 'post_card.dart';
import 'post_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// New posts from followed artists, newest first. Pull down to check now.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  Future<void> _check(BuildContext context) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final found = await state.checkForUpdates();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          state.follows.isEmpty
              ? 'Follow artists to get notifications.'
              : found == 0
              ? 'No new posts.'
              : found == 1
              ? '1 new post.'
              : '$found new posts.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final notices = state.notices;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (state.checking)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationSettingsPage(),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'read' => state.markAllNoticesRead(),
              'clear' => state.clearNotices(),
              _ => _check(context),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'check', child: Text('Check now')),
              PopupMenuItem(value: 'read', child: Text('Mark all as read')),
              PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _check(context),
        child: notices.isEmpty
            ? ListView(
                children: [
                  StatusView(
                    icon: Icons.notifications_none_rounded,
                    title: 'Nothing to see here yet',
                    body: state.follows.isEmpty
                        ? 'Follow artists and you will be notified here when they post.'
                        : 'New posts from the ${state.follows.length == 1 ? 'artist' : '${state.follows.length} artists'} you follow will show up here.',
                  ),
                ],
              )
            : ListView.separated(
                itemCount: notices.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) => _NoticeTile(notices[index]),
              ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile(this.notice);

  final UpdateNotice notice;

  @override
  Widget build(BuildContext context) {
    final c = notice.creator;
    return Material(
      color: notice.read ? Colors.transparent : pawPink.withValues(alpha: .07),
      child: InkWell(
        onTap: () {
          AppScope.read(context).markCreatorSeen(c.key);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PostPage(
                service: c.service,
                creatorId: c.id,
                postId: notice.postId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 10),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: pawPink,
                  size: 26,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => openCreator(context, c),
                      child: CreatorAvatar(c, size: 34),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: c.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: ' posted on '),
                          TextSpan(text: c.site.label),
                          TextSpan(
                            text: '  ·  ${shortTime(notice.at)}',
                            style: TextStyle(color: ink(.5)),
                          ),
                        ],
                      ),
                    ),
                    if (notice.postTitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(notice.postTitle, style: TextStyle(color: ink(.7))),
                    ],
                  ],
                ),
              ),
              if (notice.thumbnailUrl != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: NetImage(
                      notice.thumbnailUrl!,
                      width: 64,
                      height: 64,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
