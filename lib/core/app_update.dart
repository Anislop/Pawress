import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// The GitHub repository (`owner/name`) whose releases this build updates
/// from. CD passes the repository that built it, since build numbers are
/// only comparable within one repository's release history.
const updateRepository = String.fromEnvironment(
  'UPDATE_REPOSITORY',
  defaultValue: 'Anislop/Pawress',
);

/// The installed app's version name and build number (Android versionCode).
class InstalledVersion {
  const InstalledVersion({required this.name, required this.build});

  final String name;
  final int build;

  String get label => '$name (build $build)';
}

/// A GitHub release carrying a Pawress APK.
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.title,
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.pageUrl,
    this.notes = '',
    this.size,
    this.prerelease = false,
  });

  final String tag;
  final String title;
  final String version;
  final int build;
  final String apkUrl;
  final String pageUrl;
  final String notes;
  final int? size;
  final bool prerelease;

  String get label => '$version (build $build)';

  /// CD writes a nightly's commit message into its notes and ends it with
  /// this marker; text after it is for the GitHub release page only.
  static const commitEnd = '<!-- end of commit message -->';

  /// The commit title and description from [notes]. Releases without the
  /// marker (versioned ones) use the release title and the whole notes.
  ({String title, String description}) get change {
    final text = notes.replaceAll('\r\n', '\n');
    final end = text.indexOf(commitEnd);
    if (end < 0) return (title: title, description: text.trim());
    final message = text.substring(0, end).trim();
    final lineEnd = message.indexOf('\n');
    final subject = (lineEnd < 0 ? message : message.substring(0, lineEnd))
        .trim();
    return (
      title: subject.isEmpty ? title : subject,
      description: lineEnd < 0 ? '' : message.substring(lineEnd + 1).trim(),
    );
  }

  /// CD attaches the release APK as `pawress-<version>-<build>.apk`. Debug
  /// APKs (`...-debug.apk`) don't match, so they're never installed.
  static final apkName = RegExp(
    r'^pawress-(.+)-(\d+)\.apk$',
    caseSensitive: false,
  );

  /// The release in a GitHub `releases` listing whose APK has the highest
  /// build number above [installedBuild], or null when none does.
  static AppRelease? newest(Object? listing, {required int installedBuild}) {
    if (listing is! List) return null;
    AppRelease? best;
    for (final release in listing) {
      if (release is! Map || release['draft'] == true) continue;
      final assets = release['assets'];
      if (assets is! List) continue;
      for (final asset in assets) {
        if (asset is! Map) continue;
        final match = apkName.firstMatch('${asset['name'] ?? ''}');
        final url = asset['browser_download_url'];
        final state = asset['state'];
        if (match == null || url is! String || !_fromGitHub(url)) continue;
        if (state != null && state != 'uploaded') continue;
        final build = int.tryParse(match.group(2)!) ?? 0;
        if (build <= installedBuild || build <= (best?.build ?? 0)) continue;
        final tag = '${release['tag_name'] ?? ''}';
        final page = release['html_url'];
        final size = asset['size'];
        final name = '${release['name'] ?? ''}'.trim();
        best = AppRelease(
          tag: tag,
          title: name.isEmpty ? tag : name,
          version: match.group(1)!,
          build: build,
          apkUrl: url,
          pageUrl: page is String && _fromGitHub(page) ? page : url,
          notes: '${release['body'] ?? ''}'.trim(),
          size: size is num && size > 0 ? size.toInt() : null,
          prerelease: release['prerelease'] == true,
        );
      }
    }
    return best;
  }

  static bool _fromGitHub(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host == 'github.com';
  }
}

/// Why an update was not installed.
enum UpdateFailure { signature, notNewer, invalid, network }

class UpdateException implements Exception {
  const UpdateException(this.failure);

  final UpdateFailure failure;

  /// Whether trying again may succeed.
  bool get retryable => failure == UpdateFailure.network;

  String get message => switch (failure) {
    UpdateFailure.signature =>
      'This update is not signed with the same key as the installed app, so '
          'it cannot be verified as a genuine Pawress release and was not '
          'installed. Keep this version, and do not uninstall Pawress to '
          'install it.',
    UpdateFailure.notNewer =>
      'This update is not newer than the installed app.',
    UpdateFailure.invalid => 'The downloaded file is not a Pawress update.',
    UpdateFailure.network =>
      'Could not download the update. Check your connection and try again.',
  };

  @override
  String toString() => message;
}

/// Finds newer releases on GitHub and hands their APK to Android's package
/// installer, through the `pawress/updater` channel in `MainActivity.kt`.
/// The native side checks that the APK is this app, newer, and signed with
/// the installed app's key before opening the installer.
class AppUpdater {
  AppUpdater({
    MethodChannel? channel,
    http.Client? client,
    this.repository = updateRepository,
  }) : channel = channel ?? const MethodChannel('pawress/updater'),
       _client = client ?? http.Client();

  final MethodChannel channel;
  final http.Client _client;
  final String repository;

  /// The installed version, or null without the Android host.
  Future<InstalledVersion?> installedVersion() async {
    try {
      final value = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'appVersion',
      );
      final build = value?['build'];
      if (value == null || build is! num) return null;
      return InstalledVersion(
        name: '${value['name'] ?? ''}',
        build: build.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// The newest release built after the installed app, or null when it is
  /// up to date. Throws when the releases cannot be read.
  Future<AppRelease?> check() async {
    final installed = await installedVersion();
    if (installed == null) return null;
    final response = await _client
        .get(
          Uri.https('api.github.com', '/repos/$repository/releases', {
            'per_page': '10',
          }),
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Pawress updater',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException('GitHub returned ${response.statusCode}');
    }
    return AppRelease.newest(
      jsonDecode(utf8.decode(response.bodyBytes)),
      installedBuild: installed.build,
    );
  }

  /// Downloads [release]'s APK and opens the package installer with it.
  /// [onProgress] gets the bytes received and the total, when known.
  /// Throws [UpdateException] when it cannot.
  Future<void> install(
    AppRelease release, {
    void Function(int received, int? total)? onProgress,
  }) async {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return;
      final args = call.arguments;
      if (args is! Map) return;
      final received = args['received'];
      final total = args['total'];
      if (received is num) {
        onProgress?.call(received.toInt(), total is num ? total.toInt() : null);
      }
    });
    try {
      await channel.invokeMethod<void>('installUpdate', {
        'url': release.apkUrl,
      });
    } on PlatformException catch (error) {
      throw UpdateException(switch (error.code) {
        'UPDATE_SIGNATURE' => UpdateFailure.signature,
        'UPDATE_NOT_NEWER' => UpdateFailure.notNewer,
        'UPDATE_INVALID' => UpdateFailure.invalid,
        _ => UpdateFailure.network,
      });
    } on MissingPluginException {
      throw const UpdateException(UpdateFailure.network);
    } finally {
      channel.setMethodCallHandler(null);
    }
  }
}
