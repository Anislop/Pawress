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

Creator _creator(String id) =>
    Creator(id: id, service: 'patreon', name: 'Artist $id');

Post _post(String id, {String user = '7', List<String> tags = const []}) =>
    Post(
      id: id,
      user: user,
      service: 'patreon',
      title: 'Post $id',
      content: '<p>${'word ' * 200}</p>',
      tags: tags,
    );

void main() {
  group('Blocklist', () {
    test('hides blocked artists and tags without case or #', () {
      final blocklist = Blocklist().withCreator(_creator('7')).withTag('#Gore');
      expect(blocklist.hides(_post('1')), isTrue);
      expect(blocklist.hides(_post('2', user: '8', tags: ['GORE'])), isTrue);
      expect(blocklist.hides(_post('3', user: '8', tags: ['cute'])), isFalse);
      expect(blocklist.blocksTags(_post('4', tags: ['cute'])), isFalse);
      expect(blocklist.tags, ['gore']);
    });

    test('adds each artist and tag once and removes them', () {
      final blocklist = Blocklist()
          .withCreator(_creator('7'))
          .withCreator(_creator('7'))
          .withTag('a')
          .withTag(' A ')
          .withTag('#');
      expect(blocklist.creators, hasLength(1));
      expect(blocklist.tags, ['a']);
      final empty = blocklist.withoutCreator('patreon/7').withoutTag('#A');
      expect(empty.isEmpty, isTrue);
    });

    test('merges and survives JSON', () {
      final mine = Blocklist().withTag('a');
      final theirs = Blocklist().withCreator(_creator('9')).withTag('b');
      final merged = mine.merge(theirs);
      final copy = Blocklist.fromJson(
        jsonDecode(jsonEncode(merged.toJson())) as Map<String, dynamic>,
      );
      expect(copy.tags, ['a', 'b']);
      expect(copy.blocksCreator('patreon/9'), isTrue);
    });

    test('goes into backups', () {
      final backup = Backup(
        follows: const [],
        favorites: const [],
        blocklist: Blocklist().withTag('x').withCreator(_creator('3')),
      );
      final copy = Backup.decode(backup.encode());
      expect(copy.blocklist.blocksTag('X'), isTrue);
      expect(copy.blocklist.blocksCreator('patreon/3'), isTrue);
      expect(
        Backup.decode(Backup(follows: const [], favorites: const []).encode())
            .blocklist
            .isEmpty,
        isTrue,
      );
    });
  });

  test('Visit survives JSON for posts and artists', () {
    final at = DateTime.utc(2026, 11, 5);
    final post = Visit.tryParse(
      jsonDecode(jsonEncode(Visit.post(_post('1'), at).toJson()))
          as Map<String, dynamic>,
    )!;
    final artist = Visit.tryParse(
      jsonDecode(jsonEncode(Visit.creator(_creator('2'), at).toJson()))
          as Map<String, dynamic>,
    )!;
    expect(post.key, 'post:patreon/7/1');
    expect(post.at, at);
    expect(artist.key, 'creator:patreon/2');
    expect(Visit.tryParse(const {}), isNull);
  });

  test('settings keep the theme, data saver and history choices', () {
    const settings = AppSettings(
      theme: ThemeChoice.system,
      dataSaver: DataSaver.mobile,
      keepHistory: false,
    );
    final copy = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );
    expect(copy.theme, ThemeChoice.system);
    expect(copy.dataSaver, DataSaver.mobile);
    expect(copy.keepHistory, isFalse);
    expect(AppSettings.fromJson(const {}).dataSaver, DataSaver.off);
    expect(AppSettings.fromJson(const {}).keepHistory, isTrue);
  });

  group('PawchiveLink.findUrl', () {
    test('finds the address in shared text', () {
      final url = PawchiveLink.findUrl(
        'look at this https://pawchive.pw/fanbox/user/12/post/34?x=1 wow',
      )!;
      expect(url.path, '/fanbox/user/12/post/34');
      final link = PawchiveLink.tryParse(url.path)!;
      expect((link.service, link.user, link.post), ('fanbox', '12', '34'));
    });

    test('reads tag links and ignores other sites', () {
      final url = PawchiveLink.findUrl(
        'https://www.pawchive.pw/posts?tag=a%20b',
      )!;
      expect(url.queryParameters['tag'], 'a b');
      expect(
        PawchiveLink.findUrl('https://example.com/patreon/user/1'),
        isNull,
      );
      expect(PawchiveLink.findUrl('https://pawchive.pw.evil.com/x'), isNull);
    });
  });

  group('AppState filters and history', () {
    late AppState state;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/account/favorites') {
          return http.Response('[]', 200);
        }
        return http.Response('{}', 200);
      });
      state = AppState(
        store: Store(),
        api: ArchiveApi(client: client),
      );
      await state.init();
    });

    test(
      'not interested hides the post, drops its like and persists',
      () async {
        final post = _post('1');
        await state.toggleLike(post);
        await state.notInterested(post);
        expect(state.hides(post), isTrue);
        expect(state.isLiked(post), isFalse);
        expect((await state.store.dislikes()).single.key, post.key);
        await state.undoNotInterested(post);
        expect(state.hides(post), isFalse);
      },
    );

    test(
      'blocking unfollows and still shows the artist on their page',
      () async {
        final creator = _creator('7');
        await state.follow(creator);
        await state.block(creator);
        expect(state.isFollowing(creator.key), isFalse);
        expect(state.hides(_post('1')), isTrue);
        expect(state.hides(_post('1'), creatorKey: creator.key), isFalse);
        await state.blockTag('nsfw');
        expect(
          state.hides(_post('2', tags: ['NSFW']), creatorKey: creator.key),
          isTrue,
        );
        expect((await state.store.blocklist()).tags, ['nsfw']);
      },
    );

    test('history keeps one entry per item, newest first, cut short', () async {
      await state.recordPost(_post('1'));
      await state.recordCreator(_creator('2'));
      await state.recordPost(_post('1'));
      expect(state.history.map((v) => v.key), [
        'post:patreon/7/1',
        'creator:patreon/2',
      ]);
      expect(state.wasViewed(_post('1')), isTrue);
      expect(state.history.first.post!.content.length, lessThanOrEqualTo(400));
      final stored = await state.store.history();
      expect(stored, hasLength(2));
    });

    test('history records nothing when turned off', () async {
      await state.updateSettings(state.settings.copyWith(keepHistory: false));
      await state.recordPost(_post('1'));
      expect(state.history, isEmpty);
    });

    test('the Following marker only moves forward', () async {
      await state.markFollowingSeen(DateTime.utc(2026, 11, 5));
      await state.markFollowingSeen(DateTime.utc(2026, 11, 1));
      expect(state.followingSeenAt, DateTime.utc(2026, 11, 5));
      expect(await state.store.followingSeenAt(), DateTime.utc(2026, 11, 5));
    });
  });
}
