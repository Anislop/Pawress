import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'config.dart';
import 'downloads.dart';
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

  /// Checks every follow whose bell isn't off and returns the new notices,
  /// newest first. A creator's first check only records what exists, so
  /// following someone never notifies about their back catalogue.
  Future<List<UpdateNotice>> check() async {
    final follows = await store.follows();
    final updated = <String, Follow>{};
    final found = <UpdateNotice>[];
    for (final follow in follows) {
      if (follow.notify == NotifyLevel.off) continue;
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
            excerpt: htmlExcerpt(post.content),
            thumbnailPath: post.media.where((m) => m.isImage).firstOrNull?.path,
          ),
      ],
    );
  }
}

/// The notices whose creator's bell is set to push, for Android
/// notifications; the rest stay in the app.
List<UpdateNotice> pushable(List<UpdateNotice> notices, List<Follow> follows) {
  final push = {
    for (final follow in follows)
      if (follow.notify == NotifyLevel.push) follow.key,
  };
  return [
    for (final notice in notices)
      if (push.contains(notice.creator.key)) notice,
  ];
}

/// System notifications for new posts, and the progress notification that
/// keeps downloads running in the background.
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

  /// The same notifications as pop-up banners. Android fixes a channel's
  /// importance when it is created, so banners need a channel of their own.
  static const _bannerChannel = AndroidNotificationDetails(
    'artist_updates_banner',
    'Artist updates (pop-up)',
    channelDescription: 'New posts from artists you follow, as banners',
    importance: Importance.high,
    priority: Priority.high,
  );

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

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
      await _android?.requestNotificationsPermission() ?? false;

  /// Whether Android lets Pawress post notifications at all.
  static Future<bool> permitted() async {
    await init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Opens Pawress in Android's notification settings, where sound,
  /// vibration and the lock screen are chosen. Returns false if it could
  /// not.
  static Future<bool> openSystemSettings() async {
    try {
      return await const MethodChannel('pawress/updater')
              .invokeMethod<bool>('notificationSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Largest picture put in a notification; Android passes it through a
  /// binder call that fails above about 1 MB.
  static const _maxPicture = 900 * 1024;

  /// Pause between picture downloads, for the file host's one a second.
  static const _pictureSpacing = Duration(seconds: 1);

  /// One notification per creator, replacing that creator's previous one,
  /// showing their newest post: `artist - title`, the start of its text and,
  /// when it has an image, that image's thumbnail. With [banners], they pop
  /// up over the screen.
  static Future<void> show(
    List<UpdateNotice> notices, {
    bool banners = false,
    http.Client? client,
  }) async {
    await init();
    final byCreator = <String, List<UpdateNotice>>{};
    for (final notice in notices) {
      byCreator.putIfAbsent(notice.creator.key, () => []).add(notice);
    }
    final fetcher = client ?? http.Client();
    var fetched = false;
    try {
      for (final group in byCreator.values) {
        final text = notificationText(group);
        final url = group.first.thumbnailUrl;
        Uint8List? picture;
        if (url != null) {
          if (fetched) await Future<void>.delayed(_pictureSpacing);
          fetched = true;
          picture = await _picture(fetcher, url);
        }
        final creator = group.first.creator;
        final id = creator.key.hashCode & 0x7fffffff;
        try {
          await _plugin.show(
            id: id,
            title: text.title,
            body: text.body,
            notificationDetails: NotificationDetails(
              android: _details(text, picture: picture, banners: banners),
            ),
            payload: creator.key,
          );
        } on PlatformException {
          if (picture == null) rethrow;
          // Android could not take the picture; post the text alone.
          await _plugin.show(
            id: id,
            title: text.title,
            body: text.body,
            notificationDetails: NotificationDetails(
              android: _details(text, banners: banners),
            ),
            payload: creator.key,
          );
        }
      }
    } finally {
      if (client == null) fetcher.close();
    }
  }

  static AndroidNotificationDetails _details(
    NotificationText text, {
    Uint8List? picture,
    required bool banners,
  }) {
    final channel = banners ? _bannerChannel : _channel;
    final bitmap = picture == null ? null : ByteArrayAndroidBitmap(picture);
    return AndroidNotificationDetails(
      channel.channelId,
      channel.channelName,
      channelDescription: channel.channelDescription,
      importance: channel.importance,
      priority: channel.priority,
      subText: text.count,
      largeIcon: bitmap,
      styleInformation: bitmap == null
          ? BigTextStyleInformation(text.body, contentTitle: text.title)
          : BigPictureStyleInformation(
              bitmap,
              contentTitle: text.title,
              summaryText: text.body,
              hideExpandedLargeIcon: true,
            ),
    );
  }

  /// The payload of the download notifications, which open Downloads.
  static const downloadsPayload = 'downloads';
  static const _downloadId = 7101;
  static const _downloadDoneId = 7102;
  static const _downloadChannel = AndroidNotificationDetails(
    'downloads',
    'Downloads',
    channelDescription: 'Progress while Pawress saves files',
    importance: Importance.low,
    priority: Priority.low,
  );

  static AndroidNotificationDetails _downloadDetails({
    int done = 0,
    int total = 0,
    bool ongoing = true,
  }) => AndroidNotificationDetails(
    _downloadChannel.channelId,
    _downloadChannel.channelName,
    channelDescription: _downloadChannel.channelDescription,
    importance: _downloadChannel.importance,
    priority: _downloadChannel.priority,
    ongoing: ongoing,
    autoCancel: !ongoing,
    onlyAlertOnce: true,
    showWhen: false,
    showProgress: ongoing,
    maxProgress: total,
    progress: done,
    indeterminate: ongoing && total == 0,
    category: AndroidNotificationCategory.progress,
  );

  /// Starts or updates the foreground service that keeps the process (and
  /// so the download queue) alive while Pawress is in the background.
  static Future<void> showDownloads({
    required int done,
    required int total,
    required String body,
    bool start = false,
  }) async {
    await init();
    final title = total == 1
        ? 'Downloading 1 file'
        : 'Downloading ${done + 1} of $total files';
    final details = _downloadDetails(done: done, total: total);
    if (start) {
      await _android?.startForegroundService(
        id: _downloadId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: downloadsPayload,
        startType: AndroidServiceStartType.startNotSticky,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
    } else {
      await _plugin.show(
        id: _downloadId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
        payload: downloadsPayload,
      );
    }
  }

  /// Stops the service; with [summary], says how the queue went.
  static Future<void> stopDownloads({String? summary}) async {
    await init();
    await _android?.stopForegroundService();
    await _plugin.cancel(id: _downloadId);
    if (summary == null) return;
    await _plugin.show(
      id: _downloadDoneId,
      title: 'Downloads finished',
      body: summary,
      notificationDetails: NotificationDetails(
        android: _downloadDetails(ongoing: false),
      ),
      payload: downloadsPayload,
    );
  }

  /// A thumbnail's bytes, or null when it can't be had quickly or is too big
  /// for a notification.
  static Future<Uint8List?> _picture(http.Client client, String url) async {
    try {
      final response = await client
          .get(Uri.parse(url), headers: mediaHeaders)
          .timeout(const Duration(seconds: 15));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          bytes.isEmpty ||
          bytes.length > _maxPicture) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

/// Mirrors the download queue in a progress notification. Posting it starts
/// a foreground service, so Android keeps Pawress running (and saving)
/// after it leaves the screen; the service stops when the queue empties.
/// Swiping Pawress out of recent apps still ends it.
class DownloadNotification {
  DownloadNotification(this._downloads) {
    _downloads.addListener(_update);
  }

  final DownloadManager _downloads;
  bool _shown = false;
  int _lastDone = -1;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Progress updates are kept to about one a second.
  static const _interval = Duration(seconds: 1);

  void _update() {
    final active = _downloads.active;
    if (active == 0) return;
    final done = _downloads.finishedInBatch;
    final now = DateTime.now();
    if (_shown && done == _lastDone && now.difference(_last) < _interval) {
      return;
    }
    final start = !_shown;
    _shown = true;
    _last = now;
    _lastDone = done;
    final task = _downloads.current;
    final percent = task?.progress == null
        ? ''
        : ' · ${(task!.progress! * 100).round()}%';
    unawaited(
      _quietly(
        () => Notifier.showDownloads(
          done: done,
          total: done + active,
          body: task == null ? 'Waiting…' : '${task.name}$percent',
          start: start,
        ),
      ),
    );
  }

  /// Called when the queue empties. The summary is only posted while
  /// Pawress is in the background; on screen a snackbar says it.
  void finish(int saved, int failed) {
    if (!_shown) return;
    _shown = false;
    _lastDone = -1;
    final away =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    String files(int n) => n == 1 ? '1 file' : '$n files';
    final summary = failed == 0
        ? 'Saved ${files(saved)}.'
        : 'Saved ${files(saved)}; ${files(failed)} failed.';
    unawaited(
      _quietly(() => Notifier.stopDownloads(summary: away ? summary : null)),
    );
  }

  /// Downloads go on whether or not the notification can be shown.
  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Download notification failed: $e');
    }
  }
}

/// What a push notification for one creator's new posts says.
typedef NotificationText = ({String title, String body, String? count});

/// `artist - title` and the start of the text of the newest post in
/// [group] (one creator's notices, newest first), and how many there are
/// when more than one.
NotificationText notificationText(List<UpdateNotice> group) {
  final newest = group.first;
  final creator = newest.creator;
  final postTitle = newest.postTitle.trim();
  return (
    title: postTitle.isEmpty ? creator.name : '${creator.name} - $postTitle',
    body: newest.excerpt.isNotEmpty
        ? newest.excerpt
        : postTitle.isEmpty
        ? 'New post on ${creator.site.label}'
        : 'Tap to see it on ${creator.site.label}',
    count: group.length > 1 ? '${group.length} new posts' : null,
  );
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
      final notices = pushable(
        await UpdateChecker(api, store).check(),
        await store.follows(),
      );
      if (notices.isNotEmpty) {
        await Notifier.show(notices, banners: settings.notifyBanners);
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}
