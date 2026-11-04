import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawress/core/api.dart';
import 'package:pawress/core/models.dart';
import 'package:pawress/core/store.dart';
import 'package:pawress/core/updates.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A fake Pawchive with one creator whose posts and `updated` stamp the test
/// changes between checks.
class _FakePawchive {
  String updated = '2026-11-01T10:00:00';
  List<String> postIds = ['2', '1'];
  int postRequests = 0;

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/v1/patreon/user/7/profile') {
      return _json({
        'id': '7',
        'name': 'Artist',
        'service': 'patreon',
        'updated': updated,
      });
    }
    if (path == '/api/v1/patreon/user/7') {
      postRequests++;
      return _json([
        for (final id in postIds)
          {
            'id': id,
            'user': '7',
            'service': 'patreon',
            'title': 'Post $id',
            'content': '<p>Text of <b>post</b> $id</p>',
            'file': {'name': '$id.png', 'path': '/aa/bb/$id.png'},
            'added': '2026-11-0${id}T00:00:00',
          },
      ]);
    }
    return http.Response('{"error":"not found"}', 404);
  });

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  late _FakePawchive server;
  late Store store;
  late UpdateChecker checker;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = _FakePawchive();
    store = Store();
    checker = UpdateChecker(PawchiveApi(client: server.client), store);
    await store.saveFollows([
      Follow(
        creator: const Creator(id: '7', service: 'patreon', name: 'Artist'),
        followedAt: DateTime.utc(2026),
      ),
    ]);
  });

  test('the first check records existing posts without notifying', () async {
    expect(await checker.check(), isEmpty);
    final follow = (await store.follows()).single;
    expect(follow.seenPostIds, ['2', '1']);
    expect(follow.unread, 0);
    expect(await store.notices(), isEmpty);
  });

  test('a later post becomes a notice and an unread count', () async {
    await checker.check();
    server
      ..updated = '2026-11-03T10:00:00'
      ..postIds = ['3', '2', '1'];

    final found = await checker.check();

    expect(found.map((n) => n.postId), ['3']);
    expect(found.single.creator.name, 'Artist');
    final follow = (await store.follows()).single;
    expect(follow.unread, 1);
    expect(follow.seenPostIds, ['3', '2', '1']);
    final stored = (await store.notices()).single;
    expect(stored.postTitle, 'Post 3');
    expect(stored.excerpt, 'Text of post 3');
    expect(stored.thumbnailPath, '/aa/bb/3.png');
  });

  test('an unchanged profile stamp skips fetching posts', () async {
    await checker.check();
    final before = server.postRequests;
    expect(await checker.check(), isEmpty);
    expect(server.postRequests, before);
  });

  test('a follow removed during the check is not brought back', () async {
    await checker.check();
    server
      ..updated = '2026-11-03T10:00:00'
      ..postIds = ['3', '2', '1'];
    final pending = checker.check();
    await store.saveFollows([]);
    await pending;
    expect(await store.follows(), isEmpty);
  });

  test('a follow with its bell off is not checked at all', () async {
    final follow = (await store.follows()).single;
    await store.saveFollows([follow.copyWith(notify: NotifyLevel.off)]);
    expect(await checker.check(), isEmpty);
    expect(server.postRequests, 0);
    expect((await store.follows()).single.seenPostIds, isEmpty);
  });

  test('only push follows become Android notifications', () {
    UpdateNotice notice(String id) => UpdateNotice(
      id: 'patreon/$id/1',
      creator: Creator(id: id, service: 'patreon', name: id),
      postId: '1',
      postTitle: '',
      at: DateTime.utc(2026),
    );
    Follow follow(String id, NotifyLevel level) => Follow(
      creator: Creator(id: id, service: 'patreon', name: id),
      followedAt: DateTime.utc(2026),
      notify: level,
    );
    final shown = pushable(
      [notice('1'), notice('2'), notice('3')],
      [follow('1', NotifyLevel.push), follow('2', NotifyLevel.inApp)],
    );
    expect(shown.map((n) => n.creator.id), ['1']);
  });

  group('push notification text', () {
    const creator = Creator(id: '7', service: 'patreon', name: 'Artist');
    UpdateNotice notice(String id, {String title = '', String excerpt = ''}) =>
        UpdateNotice(
          id: 'patreon/7/$id',
          creator: creator,
          postId: id,
          postTitle: title,
          excerpt: excerpt,
          at: DateTime.utc(2026),
        );

    test('is artist - title over the start of the text', () {
      final text = notificationText([
        notice('2', title: 'Sketch dump', excerpt: 'Some sketches'),
      ]);
      expect(text.title, 'Artist - Sketch dump');
      expect(text.body, 'Some sketches');
      expect(text.count, isNull);
    });

    test('uses the newest post and counts the rest', () {
      final text = notificationText([
        notice('3', title: 'Newest', excerpt: 'New'),
        notice('2', title: 'Older'),
      ]);
      expect(text.title, 'Artist - Newest');
      expect(text.count, '2 new posts');
    });

    test('falls back to the artist name and site', () {
      final text = notificationText([notice('1')]);
      expect(text.title, 'Artist');
      expect(text.body, 'New post on ${creator.site.label}');
    });

    test('keeps the excerpt through JSON', () {
      final stored = UpdateNotice.fromJson(
        jsonDecode(jsonEncode(notice('1', excerpt: 'Hi').toJson()))
            as Map<String, dynamic>,
      );
      expect(stored.excerpt, 'Hi');
      expect(stored.markRead().excerpt, 'Hi');
    });
  });

  group('htmlExcerpt', () {
    test('strips tags, decodes entities and joins lines', () {
      expect(
        htmlExcerpt('<p>One &amp; two</p><p>three<br>four</p>'),
        'One & two three four',
      );
    });

    test('drops a tag cut off at the end', () {
      expect(htmlExcerpt('Hello <a href="https://exa'), 'Hello');
    });

    test('cuts long text at a word with an ellipsis', () {
      final text = htmlExcerpt('word ' * 100, max: 30);
      expect(text.length, lessThanOrEqualTo(30));
      expect(text, endsWith('word…'));
    });
  });
}
