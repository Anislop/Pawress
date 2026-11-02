import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'app_update.dart';
import 'creators.dart';
import 'downloads.dart';
import 'models.dart';
import 'store.dart';
import 'updates.dart';

/// App-wide state: settings, the signed-in account, follows and update
/// notices. Screens listen to it and call its methods; it persists every
/// change through [Store].
class AppState extends ChangeNotifier {
  AppState({Store? store, PawchiveApi? api})
    : store = store ?? Store(),
      api = api ?? PawchiveApi() {
    this.api.onUnauthorized = () => unawaited(_expireSession());
    directory = CreatorDirectory(this.api);
    downloads = DownloadManager(this.api)
      ..onIdle = (saved, failed) => _say(
        failed == 0
            ? 'Saved ${_files(saved)}.'
            : 'Saved ${_files(saved)}; ${_files(failed)} failed.',
      );
  }

  final Store store;
  final PawchiveApi api;
  late final CreatorDirectory directory;
  late final DownloadManager downloads;
  final updater = AppUpdater();

  bool initialized = false;
  bool onboarded = false;
  AppSettings settings = const AppSettings();
  String? accountName;
  List<Follow> follows = [];
  List<UpdateNotice> notices = [];

  /// A foreground update check is running.
  bool checking = false;

  /// Shown once by the home screen, e.g. after a session expired.
  String? message;

  Future<List<Creator>>? _allCreators;

  bool get signedIn => api.session != null;
  int get unreadNotices => notices.where((n) => !n.read).length;

  Future<void> init() async {
    onboarded = await store.onboarded();
    settings = await store.settings();
    api.session = await store.session();
    accountName = await store.accountName();
    follows = await store.follows();
    notices = await store.notices();
    directory.remember(follows.map((f) => f.creator));
    initialized = true;
    notifyListeners();
    unawaited(_schedule());
    if (signedIn) unawaited(syncFavorites());
  }

  /// Picks up follows and notices the background check wrote.
  Future<void> reload() async {
    follows = await store.follows();
    notices = await store.notices();
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    onboarded = true;
    await store.setOnboarded(true);
    notifyListeners();
  }

  Future<void> replayOnboarding() async {
    onboarded = false;
    await store.setOnboarded(false);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings value) async {
    settings = value;
    notifyListeners();
    await store.saveSettings(value);
    await _schedule();
  }

  Future<void> _schedule() async {
    try {
      await BackgroundUpdates.apply(settings, hasFollows: follows.isNotEmpty);
    } catch (e) {
      debugPrint('Could not schedule background updates: $e');
    }
  }

  // Following.

  Follow? followOf(String key) =>
      follows.where((f) => f.key == key).firstOrNull;

  bool isFollowing(String key) => followOf(key) != null;

  Future<void> follow(Creator creator) async {
    if (isFollowing(creator.key)) return;
    follows = [
      Follow(creator: creator, followedAt: DateTime.now().toUtc()),
      ...follows,
    ];
    await _saveFollows();
    unawaited(_baseline(creator.key));
    if (signedIn) {
      try {
        await api.addFavoriteCreator(creator.service, creator.id);
        _replace(creator.key, (f) => f.copyWith(synced: true));
        await _saveFollows();
      } on ApiException catch (e) {
        _say('Followed here, but not on your Pawchive account: ${e.message}');
      }
    }
  }

  Future<void> unfollow(Creator creator) async {
    follows = follows.where((f) => f.key != creator.key).toList();
    await _saveFollows();
    if (signedIn) {
      try {
        await api.removeFavoriteCreator(creator.service, creator.id);
      } on ApiException catch (e) {
        _say('Unfollowed here, but not on your Pawchive account: ${e.message}');
      }
    }
  }

  /// Records a new follow's current posts so only later ones notify.
  Future<void> _baseline(String key) async {
    final follow = followOf(key);
    if (follow == null) return;
    try {
      final creator = follow.creator;
      final profile = await api.creator(creator.service, creator.id);
      final posts = await api.creatorPosts(creator.service, creator.id);
      _replace(
        key,
        (f) => f.copyWith(
          creator: profile,
          seenPostIds: [for (final post in posts) post.id],
          seenUpdated: profile.updated?.toIso8601String(),
        ),
      );
      await _saveFollows();
    } on ApiException {
      // The first update check sets the baseline instead.
    }
  }

  /// Clears a creator's unread count and their notices.
  Future<void> markCreatorSeen(String key) async {
    final follow = followOf(key);
    var changed = false;
    if (follow != null && follow.unread > 0) {
      _replace(key, (f) => f.copyWith(unread: 0));
      await store.saveFollows(follows);
      changed = true;
    }
    if (notices.any((n) => n.creator.key == key && !n.read)) {
      notices = [
        for (final n in notices)
          n.creator.key == key && !n.read ? n.markRead() : n,
      ];
      await store.saveNotices(notices);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> markAllNoticesRead() async {
    notices = [for (final n in notices) n.read ? n : n.markRead()];
    follows = [for (final f in follows) f.copyWith(unread: 0)];
    notifyListeners();
    await store.saveNotices(notices);
    await store.saveFollows(follows);
  }

  Future<void> clearNotices() async {
    notices = [];
    notifyListeners();
    await store.saveNotices(notices);
  }

  /// Runs the update check now. Returns the number of new posts.
  Future<int> checkForUpdates() async {
    if (checking || follows.isEmpty) return 0;
    checking = true;
    notifyListeners();
    try {
      final found = await UpdateChecker(api, store).check();
      await reload();
      return found.length;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  void _replace(String key, Follow Function(Follow) change) {
    follows = [for (final f in follows) f.key == key ? change(f) : f];
  }

  Future<void> _saveFollows() async {
    notifyListeners();
    await store.saveFollows(follows);
    await _schedule();
  }

  // Account.

  Future<void> signIn(String session, String? name) async {
    api.session = session;
    accountName = name;
    await store.saveAccount(session, name);
    notifyListeners();
    await syncFavorites();
  }

  Future<void> signOut() async {
    api.session = null;
    accountName = null;
    follows = [for (final f in follows) f.copyWith(synced: false)];
    await store.saveAccount(null, null);
    await _saveFollows();
  }

  Future<void> _expireSession() async {
    if (!signedIn) return;
    await signOut();
    _say('Your Pawchive session expired. Sign in again to sync follows.');
  }

  /// Two-way sync between local follows and the account's favorite
  /// creators. A follow that was synced before and is now missing on the
  /// account was removed on the website, so it is removed here too; one
  /// never synced is added to the account.
  Future<void> syncFavorites() async {
    if (!signedIn) return;
    try {
      final remote = {
        for (final creator in await api.favoriteCreators())
          creator.key: creator,
      };
      final merged = <Follow>[];
      for (final follow in follows) {
        if (remote.containsKey(follow.key)) {
          merged.add(follow.copyWith(synced: true));
        } else if (!follow.synced) {
          await api.addFavoriteCreator(
            follow.creator.service,
            follow.creator.id,
          );
          merged.add(follow.copyWith(synced: true));
        }
      }
      final local = {for (final follow in merged) follow.key};
      final added = [
        for (final creator in remote.values)
          if (!local.contains(creator.key))
            Follow(
              creator: creator,
              followedAt: DateTime.now().toUtc(),
              synced: true,
            ),
      ];
      follows = [...merged, ...added];
      await _saveFollows();
      for (final follow in added) {
        unawaited(_baseline(follow.key));
      }
    } on ApiException catch (e) {
      if (!e.unauthorized) _say('Could not sync follows: ${e.message}');
    }
  }

  // Creator search.

  /// Every creator, downloaded once per session for the search page.
  Future<List<Creator>> allCreators() {
    final pending = _allCreators ??= api.allCreators();
    pending.catchError((Object _) {
      _allCreators = null;
      return <Creator>[];
    });
    return pending;
  }

  static String _files(int count) => count == 1 ? '1 file' : '$count files';

  void _say(String text) {
    message = text;
    notifyListeners();
  }

  String? takeMessage() {
    final text = message;
    message = null;
    return text;
  }
}
