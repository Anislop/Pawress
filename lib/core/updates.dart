import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'models.dart';
import 'store.dart';

/// Finds new posts from followed creators. Shared by the in-app refresh and
/// the Android background task, so it only talks to [PawchiveApi] and
/// [Store].
class UpdateChecker {
  UpdateChecker(this.api, this.store);

  final PawchiveApi api;
  final Store store;

  /// Most notices recorded per creator per check, so a bulk import does not
  /// flood the list.
  static const _maxPerCreator = 10;

  /// Pause between creators to stay well under Pawchive's rate limits.
  static const _spacing = Duration(milliseconds: 350);

  /// Checks every follow and returns the new notices, newest first. A
  /// creator's first check only records what exists, so following someone
  /// never notifies about their back catalogue.
  Future<List<UpdateNotice>> check() async {
    final follows = await store.follows();
    final updated = <String, Follow>{};
    final found = <UpdateNotice>[];
    for (final follow in follows) {
      try {
        final result = await _checkOne(follow);
        updated[follow.key] = result.follow;
        found.addAll(result.notices);
      } catch (_) {
        // Skip this creator (unreachable or unreadable); the next check
        // tries again.
      }
      await Future<void>.delayed(_spacing);
    }
    if (updated.isEmpty) return const [];

    // The app may have followed, unfollowed or read during the check; apply
    // the results only to follows that still exist, adding the new posts to
    // their current unread count.
    final fresh = <String, int>{};
    for (final notice in found) {
      fresh[notice.creator.key] = (fresh[notice.creator.key] ?? 0) + 1;
    }
    final current = await store.follows();
    await store.saveFollows([
      for (final follow in current)
        if (updated[follow.key] case final checked?)
          checked.copyWith(unread: follow.unread + (fresh[follow.key] ?? 0))
        else
          follow,
    ]);
    if (found.isNotEmpty) {
      found.sort((a, b) => b.at.compareTo(a.at));
      await store.saveNotices([...found, ...await store.notices()]);
    }
    return found;
  }

  Future<({Follow follow, List<UpdateNotice> notices})> _checkOne(
    Follow follow,
  ) async {
    final creator = follow.creator;
    final profile = await api.creator(creator.service, creator.id);
    final stamp = profile.updated?.toIso8601String();
    if (follow.seenPostIds.isNotEmpty &&
        stamp != null &&
        stamp == follow.seenUpdated) {
      return (
        follow: follow.copyWith(creator: profile),
        notices: const <UpdateNotice>[],
      );
    }
    final posts = await api.creatorPosts(creator.service, creator.id);
    final ids = [for (final post in posts) post.id];
    if (follow.seenPostIds.isEmpty) {
      return (
        follow: follow.copyWith(
          creator: profile,
          seenPostIds: ids,
          seenUpdated: stamp,
        ),
        notices: const <UpdateNotice>[],
      );
    }
    final seen = follow.seenPostIds.toSet();
    final fresh = posts
        .where((post) => !seen.contains(post.id))
        .take(_maxPerCreator)
        .toList();
    final now = DateTime.now().toUtc();
    return (
      follow: follow.copyWith(
        creator: profile,
        seenPostIds: ids,
        seenUpdated: stamp,
      ),
      notices: [
        for (final post in fresh)
          UpdateNotice(
            id: '${profile.key}/${post.id}',
            creator: profile,
            postId: post.id,
            postTitle: post.title,
            at: post.added ?? post.published ?? now,
            thumbnailPath: post.media.where((m) => m.isImage).firstOrNull?.path,
          ),
      ],
    );
  }
}

/// System notifications for new posts.
class Notifier {
  Notifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Creator keys from tapped notifications, for the app to open.
  static final taps = StreamController<String>.broadcast();

  static const _channel = AndroidNotificationDetails(
    'artist_updates',
    'Artist updates',
    channelDescription: 'New posts from artists you follow',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_paw'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) taps.add(payload);
        },
      );
    } catch (_) {
      // Let a later call try again.
      _ready = false;
      rethrow;
    }
  }

  /// The creator key of the notification that launched the app, if any.
  static Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp == true
        ? details?.notificationResponse?.payload
        : null;
  }

  static Future<bool> requestPermission() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission() ??
      false;

  /// One notification per creator, replacing that creator's previous one.
  static Future<void> show(List<UpdateNotice> notices) async {
    await init();
    final byCreator = <String, List<UpdateNotice>>{};
    for (final notice in notices) {
      byCreator.putIfAbsent(notice.creator.key, () => []).add(notice);
    }
    for (final group in byCreator.values) {
      final creator = group.first.creator;
      final title = group.length == 1
          ? 'New post from ${creator.name}'
          : '${group.length} new posts from ${creator.name}';
      final body = group.first.postTitle.isEmpty
          ? 'Tap to see it on ${creator.site.label}'
          : group.first.postTitle;
      await _plugin.show(
        id: creator.key.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel),
        payload: creator.key,
      );
    }
  }
}

/// Schedules the periodic background check.
class BackgroundUpdates {
  BackgroundUpdates._();

  static const _uniqueName = 'pawress-artist-updates';
  static const _taskName = 'checkArtistUpdates';
  static bool _initialized = false;

  static Future<void> apply(
    AppSettings settings, {
    required bool hasFollows,
  }) async {
    final workmanager = Workmanager();
    if (!_initialized) {
      await workmanager.initialize(backgroundDispatcher);
      _initialized = true;
    }
    if (!settings.notificationsEnabled || !hasFollows) {
      await workmanager.cancelByUniqueName(_uniqueName);
      return;
    }
    await workmanager.registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: Duration(minutes: settings.checkIntervalMinutes),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}

/// Runs in a background isolate started by WorkManager.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final store = Store();
    final settings = await store.settings();
    if (!settings.notificationsEnabled) return true;
    final api = PawchiveApi(session: await store.session());
    try {
      final notices = await UpdateChecker(api, store).check();
      if (notices.isNotEmpty) await Notifier.show(notices);
      return true;
    } catch (_) {
      return false;
    }
  });
}
