import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'app_update.dart';
import 'backup.dart';
import 'config.dart';
import 'creators.dart';
import 'downloads.dart';
import 'for_you.dart';
import 'intents.dart';
import 'models.dart';
import 'store.dart';
import 'updates.dart';

/// App-wide state: settings, the signed-in account, follows, liked posts
/// and update notices. Screens listen to it and call its methods; it persists every
/// change through [Store].
class AppState extends ChangeNotifier {
  AppState({Store? store, ArchiveApi? api})
    : store = store ?? Store(),
      api = api ?? ArchiveApi() {
    this.api.onUnauthorized = () => unawaited(_expireSession());
    directory = CreatorDirectory(this.api);
    downloads = DownloadManager(this.api)
      ..onIdle = (saved, failed) {
        _downloadNotification?.finish(saved, failed);
        _say(
          failed == 0
              ? 'Saved ${_files(saved)}.'
              : 'Saved ${_files(saved)}; ${_files(failed)} failed.',
        );
      };
  }

  DownloadNotification? _downloadNotification;

  /// Shows download progress in a notification that keeps the queue running
  /// in the background. Left out of tests, which have no plugins.
  void notifyDownloads() =>
      _downloadNotification ??= DownloadNotification(downloads);

  final Store store;
  final ArchiveApi api;
  late final CreatorDirectory directory;
  late final DownloadManager downloads;
  final updater = AppUpdater();

  bool initialized = false;
  bool onboarded = false;
  AppSettings settings = const AppSettings();
  String? accountName;
  List<Follow> follows = [];
  List<Favorite> favorites = [];
  List<UpdateNotice> notices = [];

  /// Thumbs-up likes, newest first; they only feed For You.
  List<Like> likes = [];
  Set<String> _favoriteKeys = {};
  Set<String> _likeKeys = {};

  /// Blocked artists and tags, left out of feeds.
  Blocklist blocklist = Blocklist();

  /// "Not interested" marks, newest first: the post is hidden and its
  /// artist and tags count against For You.
  List<Like> dislikes = [];
  Set<String> _dislikeKeys = {};

  /// Opened posts and artists, newest first.
  List<Visit> history = [];
  Set<String> _viewedPosts = {};

  /// The newest Following post seen when the user last left that tab; the
  /// feed marks where newer posts end.
  DateTime? followingSeenAt;

  /// A foreground update check is running.
  bool checking = false;

  /// Shown once by the home screen, e.g. after a session expired.
  String? message;

  /// New posts the background check found while the app was open, shown
  /// once by the home screen as an in-app alert.
  List<UpdateNotice>? _alert;

  Future<List<Creator>>? _allCreators;
  final _popularTags = <Provider, Future<List<CreatorTag>>>{};

  bool get signedIn => api.session != null;

  /// Signed in, and [service] is on the provider the account belongs to;
  /// only Pawchive has accounts in Pawress so far.
  bool _syncs(String service) =>
      signedIn && Provider.of(service) == Provider.pawchive;

  // Providers.

  bool providerEnabled(Provider provider) => api.isEnabled(provider);

  /// More than one provider is on, so pages that show one site's popular
  /// posts, tags or random picks offer a choice.
  bool get manyProviders => api.enabled.length > 1;

  /// The provider those pages show.
  Provider get browse => api.browse;

  void setBrowse(Provider provider) {
    if (provider == api.browse) return;
    api.browse = provider;
    notifyListeners();
  }

  /// Changes when the enabled providers or their hosts do; feeds built
  /// from them are rebuilt when it differs.
  String get sourceKey => [
    for (final provider in Provider.all)
      if (providerEnabled(provider)) provider.host,
  ].join(',');

  /// Follows on enabled providers: the ones shown in Following, mixed
  /// into For You and checked for new posts.
  List<Follow> get activeFollows => [
    for (final follow in follows)
      if (providerEnabled(follow.creator.provider)) follow,
  ];

  /// Switches a provider on or off in the sidebar. The last one stays on.
  /// A provider's follows, likes and favorites are kept while it is off.
  Future<void> setProviderEnabled(Provider provider, bool enabled) async {
    final ids = {...settings.providers};
    enabled ? ids.add(provider.id) : ids.remove(provider.id);
    if (ids.isEmpty || ids.length == settings.providers.length) return;
    await updateSettings(settings.copyWith(providers: ids));
  }

  /// Points [provider] at a mirror, or back at its default host with null.
  Future<void> setMirror(Provider provider, String? host) async {
    final mirrors = {...settings.mirrors}..remove(provider.id);
    if (host != null && host != provider.defaultHost) {
      mirrors[provider.id] = host;
    }
    await updateSettings(settings.copyWith(mirrors: mirrors));
  }

  void _applyProviders() {
    settings.applyMirrors();
    final enabled = settings.enabledProviders;
    api.enabled = enabled.isEmpty ? {Provider.pawchive} : enabled;
    if (_sources != sourceKey) {
      _sources = sourceKey;
      _allCreators = null;
      _popularTags.clear();
    }
  }

  String? _sources;
  int get unreadNotices => notices.where((n) => !n.read).length;

  Future<void> init() async {
    onboarded = await store.onboarded();
    settings = await store.settings();
    _applyProviders();
    api.session = await store.session();
    accountName = await store.accountName();
    follows = await store.follows();
    _setFavorites(await store.favorites());
    _setLikes(await store.likes());
    notices = await store.notices();
    blocklist = await store.blocklist();
    _setDislikes(await store.dislikes());
    _setHistory(await store.history());
    followingSeenAt = await store.followingSeenAt();
    directory.remember(follows.map((f) => f.creator));
    initialized = true;
    notifyListeners();
    unawaited(_schedule());
    if (signedIn) unawaited(syncFavorites());
  }

  /// Picks up follows and notices the background check wrote. With
  /// [alert], notices that are new since the last load become an in-app
  /// alert when that is turned on.
  Future<void> reload({bool alert = false}) async {
    final known = {for (final notice in notices) notice.id};
    follows = await store.follows();
    notices = await store.notices();
    if (alert && settings.notificationsEnabled && settings.inAppAlerts) {
      final levels = {for (final follow in follows) follow.key: follow.notify};
      final fresh = [
        for (final notice in notices)
          if (!notice.read &&
              !known.contains(notice.id) &&
              (levels[notice.creator.key] ?? NotifyLevel.off) !=
                  NotifyLevel.off)
            notice,
      ];
      if (fresh.isNotEmpty) _alert = fresh;
    }
    notifyListeners();
  }

  /// Reloads only when the stored notices changed, so the open app can look
  /// for the background check's results cheaply.
  Future<void> pollNotices() async {
    final stored = await store.notices();
    if (stored.length == notices.length &&
        stored.firstOrNull?.id == notices.firstOrNull?.id) {
      return;
    }
    await reload(alert: true);
  }

  List<UpdateNotice>? takeAlert() {
    final alert = _alert;
    _alert = null;
    return alert;
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
    _applyProviders();
    notifyListeners();
    await store.saveSettings(value);
    await _schedule();
  }

  Future<void> _schedule() async {
    try {
      await BackgroundUpdates.apply(
        settings,
        hasFollows: activeFollows.any((f) => f.notify != NotifyLevel.off),
      );
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
      Follow(
        creator: creator,
        followedAt: DateTime.now().toUtc(),
        notify: settings.defaultNotify,
      ),
      ...follows,
    ];
    await _saveFollows();
    unawaited(_baseline(creator.key));
    if (_syncs(creator.service)) {
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
    if (_syncs(creator.service)) {
      try {
        await api.removeFavoriteCreator(creator.service, creator.id);
      } on ApiException catch (e) {
        _say('Unfollowed here, but not on your Pawchive account: ${e.message}');
      }
    }
  }

  /// Sets the bell for a followed creator. Coming back from off, posts
  /// made meanwhile weren't checked, so the next check only records a new
  /// baseline instead of reporting them all.
  Future<void> setNotify(String key, NotifyLevel level) async {
    final follow = followOf(key);
    if (follow == null || follow.notify == level) return;
    _replace(key, (f) => _withNotify(f, level));
    await _saveFollows();
  }

  /// Sets every follow's bell at once.
  Future<void> setNotifyAll(NotifyLevel level) async {
    follows = [for (final f in follows) _withNotify(f, level)];
    await _saveFollows();
  }

  static Follow _withNotify(Follow follow, NotifyLevel level) =>
      follow.notify == NotifyLevel.off && level != NotifyLevel.off
      ? follow.copyWith(notify: level, seenPostIds: const [])
      : follow.copyWith(notify: level);

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

  // Favorites (the heart), synced with the account's favorite posts.

  bool isFavorite(Post post) => _favoriteKeys.contains(post.key);

  Future<void> toggleFavorite(Post post) =>
      isFavorite(post) ? unfavorite(post) : favorite(post);

  Future<void> favorite(Post post) async {
    if (isFavorite(post)) return;
    _setFavorites([
      Favorite(post: post, favoritedAt: DateTime.now().toUtc()),
      ...favorites,
    ]);
    await _saveFavorites();
    if (_syncs(post.service)) {
      try {
        await api.addFavoritePost(post);
        _setFavorites([
          for (final f in favorites)
            f.key == post.key ? f.copyWith(synced: true) : f,
        ]);
        await _saveFavorites();
      } on ApiException catch (e) {
        _say('Favorited here, but not on your Pawchive account: ${e.message}');
      }
    }
  }

  Future<void> unfavorite(Post post) async {
    _setFavorites(favorites.where((f) => f.key != post.key).toList());
    await _saveFavorites();
    if (_syncs(post.service)) {
      try {
        await api.removeFavoritePost(post);
      } on ApiException catch (e) {
        _say(
          'Removed here, but not from your Pawchive favorites: ${e.message}',
        );
      }
    }
  }

  void _setFavorites(List<Favorite> value) {
    favorites = value;
    _favoriteKeys = {for (final favorite in value) favorite.key};
  }

  Future<void> _saveFavorites() async {
    notifyListeners();
    await store.saveFavorites(favorites);
  }

  // Likes (thumbs up).

  bool isLiked(Post post) => _likeKeys.contains(post.key);

  Future<void> toggleLike(Post post) async {
    _setLikes(
      isLiked(post)
          ? likes.where((like) => like.key != post.key).toList()
          : [Like.of(post, DateTime.now().toUtc()), ...likes],
    );
    notifyListeners();
    await store.saveLikes(likes);
  }

  Future<void> clearLikes() async {
    _setLikes([]);
    notifyListeners();
    await store.saveLikes(likes);
  }

  void _setLikes(List<Like> value) {
    likes = value;
    _likeKeys = {for (final like in value) like.key};
  }

  /// What For You learns from, read for each page.
  ForYouSignals forYouSignals() => (
    follows: activeFollows,
    likes: manyProviders
        ? likes
        : [
            for (final like in likes)
              if (providerEnabled(Provider.of(like.service))) like,
          ],
    favorites: manyProviders
        ? favorites
        : [
            for (final favorite in favorites)
              if (providerEnabled(favorite.post.provider)) favorite,
          ],
    dislikes: dislikes,
    blocklist: blocklist,
    followingShare: settings.forYouMix.followingShare,
  );

  // Blocking and "not interested".

  /// Whether feeds leave [post] out. On [creatorKey]'s own profile their
  /// posts still show, but blocked tags don't.
  bool hides(Post post, {String? creatorKey}) =>
      _dislikeKeys.contains(post.key) ||
      (post.creatorKey == creatorKey
          ? blocklist.blocksTags(post)
          : blocklist.hides(post));

  bool isBlocked(String creatorKey) => blocklist.blocksCreator(creatorKey);

  /// Blocks [creator] and unfollows them, as blocking on X does.
  Future<void> block(Creator creator) async {
    await _saveBlocklist(blocklist.withCreator(creator));
    if (isFollowing(creator.key)) await unfollow(creator);
  }

  Future<void> unblock(String creatorKey) =>
      _saveBlocklist(blocklist.withoutCreator(creatorKey));

  Future<void> blockTag(String tag) => _saveBlocklist(blocklist.withTag(tag));

  Future<void> unblockTag(String tag) =>
      _saveBlocklist(blocklist.withoutTag(tag));

  Future<void> _saveBlocklist(Blocklist value) async {
    blocklist = value;
    notifyListeners();
    await store.saveBlocklist(value);
  }

  bool isDisliked(Post post) => _dislikeKeys.contains(post.key);

  /// Hides [post] and teaches For You to show less like it. A like on the
  /// same post goes, since the two contradict.
  Future<void> notInterested(Post post) async {
    if (isDisliked(post)) return;
    _setDislikes([Like.of(post, DateTime.now().toUtc()), ...dislikes]);
    if (isLiked(post)) {
      _setLikes(likes.where((like) => like.key != post.key).toList());
      await store.saveLikes(likes);
    }
    notifyListeners();
    await store.saveDislikes(dislikes);
  }

  Future<void> undoNotInterested(Post post) async {
    if (!isDisliked(post)) return;
    _setDislikes(dislikes.where((like) => like.key != post.key).toList());
    notifyListeners();
    await store.saveDislikes(dislikes);
  }

  Future<void> clearDislikes() async {
    _setDislikes([]);
    notifyListeners();
    await store.saveDislikes(dislikes);
  }

  void _setDislikes(List<Like> value) {
    dislikes = value;
    _dislikeKeys = {for (final like in value) like.key};
  }

  // History.

  bool wasViewed(Post post) => _viewedPosts.contains(post.key);

  /// Records an opened post. Its text is cut short: the post page fetches
  /// the full post anyway, and History only shows a preview.
  Future<void> recordPost(Post post) => _record(
    Visit.post(
      post.copyWith(content: htmlExcerpt(post.content, max: 400)),
      DateTime.now().toUtc(),
    ),
  );

  Future<void> recordCreator(Creator creator) =>
      _record(Visit.creator(creator, DateTime.now().toUtc()));

  Future<void> _record(Visit visit) async {
    if (!settings.keepHistory) return;
    _setHistory([
      visit,
      for (final old in history)
        if (old.key != visit.key) old,
    ]);
    notifyListeners();
    await store.saveHistory(history);
  }

  Future<void> removeVisit(Visit visit) async {
    _setHistory([
      for (final old in history)
        if (old.key != visit.key) old,
    ]);
    notifyListeners();
    await store.saveHistory(history);
  }

  Future<void> clearHistory() async {
    _setHistory([]);
    notifyListeners();
    await store.saveHistory(history);
  }

  void _setHistory(List<Visit> value) {
    history = value.take(Store.maxHistory).toList();
    _viewedPosts = {
      for (final visit in history)
        if (visit.post != null) visit.post!.key,
    };
  }

  /// Moves the Following marker up to [newest], the newest post loaded
  /// there, once the user has seen the tab.
  Future<void> markFollowingSeen(DateTime newest) async {
    final seen = followingSeenAt;
    if (seen != null && !newest.isAfter(seen)) return;
    followingSeenAt = newest;
    notifyListeners();
    await store.saveFollowingSeenAt(newest);
  }

  // Data saver.

  /// Whether images and videos should hold back right now.
  Future<bool> savingData() async => switch (settings.dataSaver) {
    DataSaver.off => false,
    DataSaver.always => true,
    DataSaver.mobile => await AndroidIntents.isMetered(),
  };

  // Backup.

  /// Follows and likes, plus the sign-in sealed with [password] when one is
  /// given and the user is signed in.
  Future<Backup> exportBackup({String? password}) async => Backup(
    follows: follows,
    favorites: favorites,
    likes: likes,
    blocklist: blocklist,
    credentials: password == null || password.isEmpty || !signedIn
        ? null
        : await SealedCredentials.seal(
            session: api.session!,
            accountName: accountName,
            password: password,
          ),
  );

  /// Adds the follows and likes in [backup] that aren't here yet, signs in
  /// with [account] when given, then syncs with the account. Returns how
  /// many follows and likes were added.
  Future<({int follows, int favorites})> importBackup(
    Backup backup, {
    ({String session, String? name})? account,
  }) async {
    final followCount = follows.length;
    final favoriteCount = favorites.length;
    follows = mergeFollows(follows, backup.follows);
    _setFavorites(mergeFavorites(favorites, backup.favorites));
    _setLikes(mergeLikes(likes, backup.likes));
    await store.saveLikes(likes);
    blocklist = blocklist.merge(backup.blocklist);
    await store.saveBlocklist(blocklist);
    directory.remember(follows.map((f) => f.creator));
    await _saveFollows();
    await _saveFavorites();
    if (account != null) {
      // Synced marks belong to the old account; keeping them would make
      // the sync remove whatever the new account lacks.
      if (signedIn) await signOut();
      await signIn(account.session, account.name);
    } else {
      await syncFavorites();
    }
    return (
      follows: follows.length - followCount,
      favorites: favorites.length - favoriteCount,
    );
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
    _setFavorites([for (final f in favorites) f.copyWith(synced: false)]);
    await store.saveAccount(null, null);
    await _saveFollows();
    await _saveFavorites();
  }

  Future<void> _expireSession() async {
    if (!signedIn) return;
    await signOut();
    _say('Your Pawchive session expired. Sign in again to sync follows.');
  }

  /// Two-way sync of follows with the account's favorite creators and of
  /// likes with its favorite posts. Anything synced before and now missing
  /// on the account was removed on the website, so it is removed here too;
  /// anything never synced is added to the account.
  Future<void> syncFavorites() async {
    if (!signedIn || !providerEnabled(Provider.pawchive)) return;
    await _syncFollows();
    if (signedIn) await _syncLikes();
  }

  Future<void> _syncFollows() async {
    try {
      final remote = {
        for (final creator in await api.favoriteCreators())
          creator.key: creator,
      };
      final merged = <Follow>[];
      for (final follow in follows) {
        if (!_syncs(follow.creator.service)) {
          merged.add(follow);
        } else if (remote.containsKey(follow.key)) {
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

  Future<void> _syncLikes() async {
    try {
      final remote = {
        for (final post in await api.favoritePosts()) post.key: post,
      };
      final merged = <Favorite>[];
      for (final favorite in favorites) {
        if (!_syncs(favorite.post.service)) {
          merged.add(favorite);
        } else if (remote.containsKey(favorite.key)) {
          merged.add(favorite.copyWith(synced: true));
        } else if (!favorite.synced) {
          await api.addFavoritePost(favorite.post);
          merged.add(favorite.copyWith(synced: true));
        }
      }
      final local = {for (final favorite in merged) favorite.key};
      final now = DateTime.now().toUtc();
      _setFavorites([
        ...merged,
        for (final post in remote.values)
          if (!local.contains(post.key))
            Favorite(post: post, favoritedAt: now, synced: true),
      ]);
      await _saveFavorites();
    } on ApiException catch (e) {
      if (!e.unauthorized) _say('Could not sync favorites: ${e.message}');
    }
  }

  // Creator search.

  /// Every enabled provider's creators, downloaded once per session for the
  /// search page.
  Future<List<Creator>> allCreators() {
    final pending = _allCreators ??= api.allCreators();
    pending.catchError((Object _) {
      _allCreators = null;
      return <Creator>[];
    });
    return pending;
  }

  /// The browsed site's popular tags, read once per session for Explore.
  Future<List<CreatorTag>> popularTags() {
    final provider = browse;
    final pending = _popularTags[provider] ??= api.popularTags(provider);
    pending.catchError((Object _) {
      _popularTags.remove(provider);
      return <CreatorTag>[];
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
