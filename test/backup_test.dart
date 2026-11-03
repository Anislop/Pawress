import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawress/core/api.dart';
import 'package:pawress/core/app_state.dart';
import 'package:pawress/core/backup.dart';
import 'package:pawress/core/models.dart';
import 'package:pawress/core/store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Follow _follow(String id, {List<String> seen = const []}) => Follow(
  creator: Creator(id: id, service: 'patreon', name: 'Artist $id'),
  followedAt: DateTime.utc(2026, 10, int.parse(id)),
  seenPostIds: seen,
  seenUpdated: seen.isEmpty ? null : '2026-10-01T00:00:00',
  unread: seen.length,
  synced: true,
);

Favorite _like(String id, {int day = 1, bool synced = true}) => Favorite(
  post: Post(id: id, user: '7', service: 'patreon', title: 'Post $id'),
  favoritedAt: DateTime.utc(2026, 10, day),
  synced: synced,
);

void main() {
  group('Backup', () {
    test('survives encoding with follows and likes', () {
      final backup = Backup(
        follows: [
          _follow('1', seen: ['a']),
        ],
        favorites: [_like('9')],
        exportedAt: DateTime.utc(2026, 11, 2),
      );
      final copy = Backup.decode(backup.encode());
      expect(copy.follows.single.key, 'patreon/1');
      expect(copy.favorites.single.key, 'patreon/7/9');
      expect(copy.credentials, isNull);
      expect(copy.exportedAt, DateTime.utc(2026, 11, 2));
    });

    test('rejects files that are not backups', () {
      expect(() => Backup.decode('not json'), throwsA(isA<BackupException>()));
      expect(
        () => Backup.decode(jsonEncode({'follows': []})),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => Backup.decode(
          jsonEncode({'format': Backup.format, 'version': Backup.version + 1}),
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('seals the sign-in so only the password opens it', () async {
      final sealed = await SealedCredentials.seal(
        session: 'secret-cookie',
        accountName: 'me',
        password: 'correct horse',
        iterations: 1000,
      );
      final text = Backup(
        follows: const [],
        favorites: const [],
        credentials: sealed,
      ).encode();
      expect(text, isNot(contains('secret-cookie')));

      final read = Backup.decode(text).credentials!;
      final account = await read.open('correct horse');
      expect(account.session, 'secret-cookie');
      expect(account.name, 'me');
      expect(
        () => read.open('wrong horse'),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            'Wrong password.',
          ),
        ),
      );
    });
  });

  test('mergeFollows adds new follows without their update state', () {
    final merged = mergeFollows(
      [_follow('1')],
      [
        _follow('1', seen: ['x']),
        _follow('2', seen: ['a', 'b']),
      ],
    );
    expect(merged.map((f) => f.key), ['patreon/1', 'patreon/2']);
    // The existing follow is kept as it was.
    expect(merged.first.seenPostIds, isEmpty);
    // The imported one starts fresh: the next check records a baseline
    // and the account sync adds it.
    final added = merged.last;
    expect(added.seenPostIds, isEmpty);
    expect(added.seenUpdated, isNull);
    expect(added.unread, 0);
    expect(added.synced, isFalse);
    expect(added.followedAt, DateTime.utc(2026, 10, 2));
  });

  test('mergeFavorites adds new likes unsynced, newest first', () {
    final merged = mergeFavorites(
      [_like('1', day: 5)],
      [_like('1', day: 1), _like('2', day: 9), _like('3', day: 2)],
    );
    expect(merged.map((f) => f.post.id), ['2', '1', '3']);
    expect(merged.firstWhere((f) => f.post.id == '1').favoritedAt.day, 5);
    expect(merged.firstWhere((f) => f.post.id == '2').synced, isFalse);
  });

  group('AppState likes', () {
    late List<String> calls;
    late List<Map<String, Object?>> remote;
    late AppState state;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      calls = [];
      remote = [];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        final path = request.url.path;
        if (path == '/api/v1/account/favorites') {
          final body = request.url.queryParameters['type'] == 'post'
              ? remote
              : const [];
          return http.Response(jsonEncode(body), 200);
        }
        return http.Response('', 200);
      });
      state = AppState(
        store: Store(),
        api: PawchiveApi(client: client),
      );
      await state.init();
    });

    test('like and unlike are kept on the device when signed out', () async {
      final post = _like('5').post;
      await state.toggleFavorite(post);
      expect(state.isFavorite(post), isTrue);
      expect((await state.store.favorites()).single.key, post.key);
      await state.toggleFavorite(post);
      expect(state.isFavorite(post), isFalse);
      expect(await state.store.favorites(), isEmpty);
      expect(calls, isEmpty);
    });

    test('sync adds, keeps and removes likes like follows', () async {
      state.api.session = 'cookie';
      await state.importBackup(
        Backup(follows: const [], favorites: [_like('local', synced: false)]),
      );
      // The unsynced local like was pushed to the account.
      expect(calls, contains('POST /api/v1/favorites/post/patreon/7/local'));
      expect(state.favorites.single.synced, isTrue);

      // The website removed it and liked another post.
      remote = [
        {'id': 'web', 'user': '8', 'service': 'fanbox', 'title': 'From web'},
      ];
      await state.syncFavorites();
      expect(state.favorites.map((f) => f.key), ['fanbox/8/web']);
      expect(state.favorites.single.post.title, 'From web');
    });
  });
}
