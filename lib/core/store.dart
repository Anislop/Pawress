import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum ThemeChoice {
  plum('Plum'),
  amoled('AMOLED'),
  light('Light'),

  /// Light or Plum, following Android's dark theme setting.
  system('Auto');

  const ThemeChoice(this.label);

  final String label;
}

/// When images and videos hold back to save mobile data.
enum DataSaver {
  off('Off'),
  mobile('Mobile data'),
  always('Always');

  const DataSaver(this.label);

  final String label;
}

/// What the sidebar's Random picks.
enum RandomKind { post, artist }

/// How much of For You comes from followed artists.
enum ForYouMix {
  following('Following', .85),
  balanced('Balanced', .65),
  discover('Discover', .4);

  const ForYouMix(this.label, this.followingShare);

  final String label;

  /// The share of each page taken from followed and liked artists; the rest
  /// is site-wide recent posts ranked by taste.
  final double followingShare;
}

class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.plum,
    this.notificationsEnabled = true,
    this.notifyBanners = true,
    this.inAppAlerts = true,
    this.defaultNotify = NotifyLevel.push,
    this.checkIntervalMinutes = 60,
    this.forYouMix = ForYouMix.balanced,
    this.autoplayVideos = true,
    this.downloadFolderUri,
    this.downloadFolderName,
    this.askDownloadFolder = false,
    this.checkUpdates = true,
    this.randomKind,
    this.dataSaver = DataSaver.off,
    this.keepHistory = true,
  });

  final ThemeChoice theme;

  /// Background checks for followed artists' new posts.
  final bool notificationsEnabled;

  /// Push notifications pop up over other apps (Android's high importance
  /// channel) instead of only appearing in the shade.
  final bool notifyBanners;

  /// A banner inside Pawress when the background check finds new posts
  /// while the app is open.
  final bool inAppAlerts;

  /// The bell setting a new follow starts with.
  final NotifyLevel defaultNotify;

  final ForYouMix forYouMix;

  /// How often Android runs the background check; 15 is its minimum.
  final int checkIntervalMinutes;
  final bool autoplayVideos;

  /// A storage access framework tree URI the app holds write access to.
  final String? downloadFolderUri;
  final String? downloadFolderName;

  /// Pick a folder for every download instead of using the saved one.
  final bool askDownloadFolder;

  /// Look for a newer GitHub release when the app starts.
  final bool checkUpdates;

  /// Null until Random is first opened and asks.
  final RandomKind? randomKind;

  /// While saving data, feed videos and GIFs don't autoplay and the viewer
  /// shows thumbnails until a full file is asked for.
  final DataSaver dataSaver;

  /// Record opened posts and artists in History.
  final bool keepHistory;

  static const intervals = [15, 30, 60, 180, 360, 720];

  AppSettings copyWith({
    ThemeChoice? theme,
    bool? notificationsEnabled,
    bool? notifyBanners,
    bool? inAppAlerts,
    NotifyLevel? defaultNotify,
    int? checkIntervalMinutes,
    ForYouMix? forYouMix,
    bool? autoplayVideos,
    ({String uri, String name})? downloadFolder,
    bool clearDownloadFolder = false,
    bool? askDownloadFolder,
    bool? checkUpdates,
    RandomKind? randomKind,
    DataSaver? dataSaver,
    bool? keepHistory,
  }) => AppSettings(
    theme: theme ?? this.theme,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    notifyBanners: notifyBanners ?? this.notifyBanners,
    inAppAlerts: inAppAlerts ?? this.inAppAlerts,
    defaultNotify: defaultNotify ?? this.defaultNotify,
    checkIntervalMinutes: checkIntervalMinutes ?? this.checkIntervalMinutes,
    forYouMix: forYouMix ?? this.forYouMix,
    autoplayVideos: autoplayVideos ?? this.autoplayVideos,
    downloadFolderUri: clearDownloadFolder
        ? null
        : downloadFolder?.uri ?? downloadFolderUri,
    downloadFolderName: clearDownloadFolder
        ? null
        : downloadFolder?.name ?? downloadFolderName,
    askDownloadFolder: askDownloadFolder ?? this.askDownloadFolder,
    checkUpdates: checkUpdates ?? this.checkUpdates,
    randomKind: randomKind ?? this.randomKind,
    dataSaver: dataSaver ?? this.dataSaver,
    keepHistory: keepHistory ?? this.keepHistory,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    theme: ThemeChoice.values.asNameMap()[json['theme']] ?? ThemeChoice.plum,
    notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    notifyBanners: json['notifyBanners'] as bool? ?? true,
    inAppAlerts: json['inAppAlerts'] as bool? ?? true,
    defaultNotify:
        NotifyLevel.values.asNameMap()[json['defaultNotify']] ??
        NotifyLevel.push,
    checkIntervalMinutes: json['checkIntervalMinutes'] as int? ?? 60,
    forYouMix:
        ForYouMix.values.asNameMap()[json['forYouMix']] ?? ForYouMix.balanced,
    autoplayVideos: json['autoplayVideos'] as bool? ?? true,
    downloadFolderUri: json['downloadFolderUri'] as String?,
    downloadFolderName: json['downloadFolderName'] as String?,
    askDownloadFolder: json['askDownloadFolder'] as bool? ?? false,
    checkUpdates: json['checkUpdates'] as bool? ?? true,
    randomKind: RandomKind.values.asNameMap()[json['randomKind']],
    dataSaver: DataSaver.values.asNameMap()[json['dataSaver']] ?? DataSaver.off,
    keepHistory: json['keepHistory'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'notificationsEnabled': notificationsEnabled,
    'notifyBanners': notifyBanners,
    'inAppAlerts': inAppAlerts,
    'defaultNotify': defaultNotify.name,
    'checkIntervalMinutes': checkIntervalMinutes,
    'forYouMix': forYouMix.name,
    'autoplayVideos': autoplayVideos,
    'downloadFolderUri': downloadFolderUri,
    'downloadFolderName': downloadFolderName,
    'askDownloadFolder': askDownloadFolder,
    'checkUpdates': checkUpdates,
    'randomKind': randomKind?.name,
    'dataSaver': dataSaver.name,
    'keepHistory': keepHistory,
  };
}

/// Persistent app data. It uses [SharedPreferencesAsync], which never caches,
/// because the background update check writes follows and notices from
/// another isolate. The session cookie lives in secure storage.
class Store {
  Store({SharedPreferencesAsync? prefs, FlutterSecureStorage? secure})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      _secure = secure ?? const FlutterSecureStorage();

  final SharedPreferencesAsync _prefs;
  final FlutterSecureStorage _secure;

  static const _onboarded = 'onboarded';
  static const _settings = 'settings';
  static const _follows = 'follows';
  static const _favorites = 'favorites';
  static const _likes = 'likes';
  static const _notices = 'notices';
  static const _accountName = 'accountName';
  static const _session = 'session';
  static const _blocklist = 'blocklist';
  static const _dislikes = 'dislikes';
  static const _history = 'history';
  static const _followingSeen = 'followingSeenAt';

  /// The newest notices kept; older ones are dropped.
  static const maxNotices = 200;

  /// The newest likes kept; older taste fades out of For You anyway.
  static const maxLikes = 1000;

  /// The newest History entries kept.
  static const maxHistory = 300;

  Future<bool> onboarded() async => await _prefs.getBool(_onboarded) ?? false;
  Future<void> setOnboarded(bool value) => _prefs.setBool(_onboarded, value);

  Future<AppSettings> settings() async {
    final raw = await _prefs.getString(_settings);
    return raw == null
        ? const AppSettings()
        : AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings settings) =>
      _prefs.setString(_settings, jsonEncode(settings.toJson()));

  Future<List<Follow>> follows() async => _list(_follows, Follow.fromJson);

  Future<void> saveFollows(List<Follow> follows) => _prefs.setString(
    _follows,
    jsonEncode([for (final follow in follows) follow.toJson()]),
  );

  Future<List<Favorite>> favorites() async =>
      _list(_favorites, Favorite.fromJson);

  Future<void> saveFavorites(List<Favorite> favorites) => _prefs.setString(
    _favorites,
    jsonEncode([for (final favorite in favorites) favorite.toJson()]),
  );

  Future<List<Like>> likes() async => _list(_likes, Like.fromJson);

  Future<void> saveLikes(List<Like> likes) => _prefs.setString(
    _likes,
    jsonEncode([for (final like in likes.take(maxLikes)) like.toJson()]),
  );

  Future<Blocklist> blocklist() async {
    final raw = await _prefs.getString(_blocklist);
    if (raw == null) return Blocklist();
    try {
      return Blocklist.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Blocklist();
    }
  }

  Future<void> saveBlocklist(Blocklist blocklist) =>
      _prefs.setString(_blocklist, jsonEncode(blocklist.toJson()));

  /// "Not interested" marks, kept in the same shape as likes.
  Future<List<Like>> dislikes() async => _list(_dislikes, Like.fromJson);

  Future<void> saveDislikes(List<Like> dislikes) => _prefs.setString(
    _dislikes,
    jsonEncode([for (final like in dislikes.take(maxLikes)) like.toJson()]),
  );

  Future<List<Visit>> history() async {
    final raw = await _prefs.getString(_history);
    if (raw == null) return [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>) ?Visit.tryParse(item),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<Visit> history) => _prefs.setString(
    _history,
    jsonEncode([for (final visit in history.take(maxHistory)) visit.toJson()]),
  );

  /// The newest Following post the user had scrolled past when they last
  /// left that tab.
  Future<DateTime?> followingSeenAt() async =>
      parseDate(await _prefs.getString(_followingSeen));

  Future<void> saveFollowingSeenAt(DateTime value) =>
      _prefs.setString(_followingSeen, value.toIso8601String());

  Future<List<UpdateNotice>> notices() async =>
      _list(_notices, UpdateNotice.fromJson);

  Future<void> saveNotices(List<UpdateNotice> notices) => _prefs.setString(
    _notices,
    jsonEncode([
      for (final notice in notices.take(maxNotices)) notice.toJson(),
    ]),
  );

  Future<String?> session() async {
    try {
      return await _secure.read(key: _session);
    } catch (_) {
      return null;
    }
  }

  Future<String?> accountName() => _prefs.getString(_accountName);

  Future<void> saveAccount(String? session, String? name) async {
    if (session == null) {
      await _secure.delete(key: _session);
      await _prefs.remove(_accountName);
      return;
    }
    await _secure.write(key: _session, value: session);
    if (name == null) {
      await _prefs.remove(_accountName);
    } else {
      await _prefs.setString(_accountName, name);
    }
  }

  Future<List<T>> _list<T>(
    String key,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final raw = await _prefs.getString(key);
    if (raw == null) return [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>) parse(item),
      ];
    } catch (_) {
      return [];
    }
  }
}
