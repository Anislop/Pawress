import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum ThemeChoice { plum, amoled }

class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.plum,
    this.notificationsEnabled = true,
    this.checkIntervalMinutes = 60,
    this.autoplayVideos = true,
    this.downloadFolderUri,
    this.downloadFolderName,
    this.askDownloadFolder = false,
    this.checkUpdates = true,
  });

  final ThemeChoice theme;

  /// Background checks for followed artists' new posts.
  final bool notificationsEnabled;

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

  static const intervals = [15, 30, 60, 180, 360, 720];

  AppSettings copyWith({
    ThemeChoice? theme,
    bool? notificationsEnabled,
    int? checkIntervalMinutes,
    bool? autoplayVideos,
    ({String uri, String name})? downloadFolder,
    bool clearDownloadFolder = false,
    bool? askDownloadFolder,
    bool? checkUpdates,
  }) => AppSettings(
    theme: theme ?? this.theme,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    checkIntervalMinutes: checkIntervalMinutes ?? this.checkIntervalMinutes,
    autoplayVideos: autoplayVideos ?? this.autoplayVideos,
    downloadFolderUri: clearDownloadFolder
        ? null
        : downloadFolder?.uri ?? downloadFolderUri,
    downloadFolderName: clearDownloadFolder
        ? null
        : downloadFolder?.name ?? downloadFolderName,
    askDownloadFolder: askDownloadFolder ?? this.askDownloadFolder,
    checkUpdates: checkUpdates ?? this.checkUpdates,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    theme: ThemeChoice.values.asNameMap()[json['theme']] ?? ThemeChoice.plum,
    notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    checkIntervalMinutes: json['checkIntervalMinutes'] as int? ?? 60,
    autoplayVideos: json['autoplayVideos'] as bool? ?? true,
    downloadFolderUri: json['downloadFolderUri'] as String?,
    downloadFolderName: json['downloadFolderName'] as String?,
    askDownloadFolder: json['askDownloadFolder'] as bool? ?? false,
    checkUpdates: json['checkUpdates'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'notificationsEnabled': notificationsEnabled,
    'checkIntervalMinutes': checkIntervalMinutes,
    'autoplayVideos': autoplayVideos,
    'downloadFolderUri': downloadFolderUri,
    'downloadFolderName': downloadFolderName,
    'askDownloadFolder': askDownloadFolder,
    'checkUpdates': checkUpdates,
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
  static const _notices = 'notices';
  static const _accountName = 'accountName';
  static const _session = 'session';

  /// The newest notices kept; older ones are dropped.
  static const maxNotices = 200;

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
