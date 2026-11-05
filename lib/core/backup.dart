import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

import 'models.dart';

/// Thrown when a backup can't be read or its password is wrong.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A Pawress backup file: follows, liked posts and, when exported with a
/// password, the Pawchive sign-in sealed with it. Follows and likes stay
/// readable so the file is useful without the password.
class Backup {
  Backup({
    required this.follows,
    required this.favorites,
    this.likes = const [],
    Blocklist? blocklist,
    this.credentials,
    this.exportedAt,
  }) : blocklist = blocklist ?? Blocklist();

  final List<Follow> follows;
  final List<Favorite> favorites;

  /// Thumbs-up likes, which teach For You.
  final List<Like> likes;

  /// Blocked artists and tags.
  final Blocklist blocklist;
  final SealedCredentials? credentials;
  final DateTime? exportedAt;

  static const format = 'pawress-backup';
  static const version = 1;

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': format,
    'version': version,
    'exportedAt': (exportedAt ?? DateTime.now().toUtc()).toIso8601String(),
    'follows': [for (final follow in follows) follow.toJson()],
    'favorites': [for (final favorite in favorites) favorite.toJson()],
    'likes': [for (final like in likes) like.toJson()],
    if (!blocklist.isEmpty) 'blocklist': blocklist.toJson(),
    if (credentials != null) 'credentials': credentials!.toJson(),
  });

  factory Backup.decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const BackupException('This file is not a Pawress backup.');
    }
    if (json is! Map<String, dynamic> || json['format'] != format) {
      throw const BackupException('This file is not a Pawress backup.');
    }
    final Map<String, dynamic> map = json;
    if ((map['version'] as num? ?? 0) > version) {
      throw const BackupException(
        'This backup is from a newer Pawress. Update the app first.',
      );
    }
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) => [
      for (final item in map[key] as List? ?? const [])
        if (item is Map<String, dynamic>) parse(item),
    ];
    try {
      final credentials = map['credentials'];
      final blocklist = map['blocklist'];
      return Backup(
        follows: list('follows', Follow.fromJson),
        favorites: list('favorites', Favorite.fromJson),
        likes: list('likes', Like.fromJson),
        blocklist: blocklist is Map<String, dynamic>
            ? Blocklist.fromJson(blocklist)
            : null,
        credentials: credentials is Map<String, dynamic>
            ? SealedCredentials.fromJson(credentials)
            : null,
        exportedAt: parseDate(map['exportedAt']),
      );
    } catch (_) {
      throw const BackupException('This backup is damaged.');
    }
  }
}

/// The session cookie and account name, encrypted with AES-256-GCM under a
/// key derived from a password with PBKDF2-HMAC-SHA256.
class SealedCredentials {
  const SealedCredentials({
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  /// About half a second on a desktop; the derivation runs off the UI
  /// thread.
  static const defaultIterations = 100000;

  final int iterations;
  final List<int> salt;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  static final _cipher = AesGcm.with256bits();

  static Future<SealedCredentials> seal({
    required String session,
    String? accountName,
    required String password,
    int iterations = defaultIterations,
  }) async {
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await _derive(password, salt, iterations);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode({'session': session, 'name': accountName})),
      secretKey: SecretKey(key),
    );
    return SealedCredentials(
      iterations: iterations,
      salt: salt,
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  /// Throws [BackupException] for a wrong password.
  Future<({String session, String? name})> open(String password) async {
    final key = await _derive(password, salt, iterations);
    final List<int> clear;
    try {
      clear = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupException('Wrong password.');
    }
    final json = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    final session = json['session'];
    if (session is! String || session.isEmpty) {
      throw const BackupException('This backup is damaged.');
    }
    return (session: session, name: json['name'] as String?);
  }

  static Future<List<int>> _derive(
    String password,
    List<int> salt,
    int iterations,
  ) => Isolate.run(() async {
    final key = await Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    return key.extractBytes();
  });

  factory SealedCredentials.fromJson(Map<String, dynamic> json) =>
      SealedCredentials(
        iterations: (json['iterations'] as num).toInt(),
        salt: base64.decode(json['salt'] as String),
        nonce: base64.decode(json['nonce'] as String),
        cipherText: base64.decode(json['data'] as String),
        mac: base64.decode(json['mac'] as String),
      );

  Map<String, dynamic> toJson() => {
    'kdf': 'pbkdf2-hmac-sha256',
    'cipher': 'aes-256-gcm',
    'iterations': iterations,
    'salt': base64.encode(salt),
    'nonce': base64.encode(nonce),
    'data': base64.encode(cipherText),
    'mac': base64.encode(mac),
  };
}

/// [current] plus the follows in [imported] it doesn't have. Imported
/// follows start without update state, so their first check only records a
/// baseline instead of reporting old posts, and unsynced, so the account
/// sync adds them.
List<Follow> mergeFollows(List<Follow> current, List<Follow> imported) {
  final have = {for (final follow in current) follow.key};
  return [
    ...current,
    for (final follow in imported)
      if (have.add(follow.key))
        Follow(
          creator: follow.creator,
          followedAt: follow.followedAt,
          notify: follow.notify,
        ),
  ];
}

/// [current] plus the likes in [imported] it doesn't have, newest first.
List<Favorite> mergeFavorites(List<Favorite> current, List<Favorite> imported) {
  final have = {for (final favorite in current) favorite.key};
  return [
    ...current,
    for (final favorite in imported)
      if (have.add(favorite.key)) favorite.copyWith(synced: false),
  ]..sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
}

/// [current] plus the thumbs-up likes in [imported] it doesn't have, newest
/// first.
List<Like> mergeLikes(List<Like> current, List<Like> imported) {
  final have = {for (final like in current) like.key};
  return [
    ...current,
    for (final like in imported)
      if (have.add(like.key)) like,
  ]..sort((a, b) => b.likedAt.compareTo(a.likedAt));
}
