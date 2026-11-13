import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawress/core/api.dart';
import 'package:pawress/core/config.dart';
import 'package:pawress/core/models.dart';
import 'package:pawress/core/store.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'text/css; charset=utf-8'},
);

Map<String, dynamic> _post(String id, {String service = 'onlyfans'}) => {
  'id': id,
  'user': 'someone',
  'service': service,
  'title': 'Post $id',
  'substring': 'text',
  'published': '2025-10-20T01:10:29',
  'file': <String, dynamic>{},
  'attachments': [
    {'name': 'a.jpg', 'path': '/56/0b/560b.jpg'},
  ],
};

void main() {
  tearDown(() => const AppSettings().applyMirrors());

  group('Provider', () {
    test('a service belongs to one provider', () {
      expect(Provider.of('onlyfans'), Provider.coomer);
      expect(Provider.of('fansly'), Provider.coomer);
      expect(Provider.of('patreon'), Provider.pawchive);
      expect(Provider.of('something-new'), Provider.pawchive);
    });

    test('parseHost reads typed mirror addresses', () {
      expect(Provider.parseHost(' https://Coomer.su/ '), 'coomer.su');
      expect(Provider.parseHost('www.coomer.su/posts?o=50'), 'coomer.su');
      expect(Provider.parseHost('coomer.su:443'), 'coomer.su');
      expect(Provider.parseHost('coomer'), isNull);
      expect(Provider.parseHost('not a host'), isNull);
      expect(Provider.parseHost(''), isNull);
    });

    test('Coomer URLs use its image host and site-relative files', () {
      final post = Post.fromJson(_post('1'));
      final file = post.files.single;
      expect(
        file.thumbnailUrl,
        'https://img.coomer.st/thumbnail/data/56/0b/560b.jpg',
      );
      expect(file.fullUrl, 'https://coomer.st/data/56/0b/560b.jpg?f=a.jpg');
      expect(post.url, 'https://coomer.st/onlyfans/user/someone/post/1');
      const creator = Creator(id: 'someone', service: 'onlyfans', name: 'x');
      expect(creator.iconUrl, 'https://img.coomer.st/icons/onlyfans/someone');
      expect(
        creator.bannerUrl,
        'https://img.coomer.st/banners/onlyfans/someone',
      );
      expect(creator.originalUrl, 'https://onlyfans.com/someone');
    });

    test('Pawchive URLs are unchanged', () {
      final post = Post.fromJson(_post('1', service: 'patreon'));
      final file = post.files.single;
      expect(
        file.thumbnailUrl,
        'https://img.pawchive.pw/thumbnail/data/56/0b/560b.jpg',
      );
      expect(
        file.fullUrl,
        'https://file.pawchive.pw/data/56/0b/560b.jpg?f=a.jpg',
      );
      const creator = Creator(id: '1', service: 'patreon', name: 'x');
      expect(creator.iconUrl, 'https://pawchive.pw/icons/patreon/1');
    });

    test('a mirror moves every URL and still matches links', () {
      final settings = AppSettings.fromJson({
        'providers': ['coomer', 'nonsense'],
        'mirrors': {'coomer': 'https://Coomer.su/', 'nonsense': 'x.y'},
      });
      expect(settings.providers, {'coomer'});
      expect(settings.mirrors, {'coomer': 'coomer.su'});
      expect(AppSettings.fromJson(settings.toJson()).mirrors, settings.mirrors);
      settings.applyMirrors();
      final post = Post.fromJson(_post('1'));
      expect(post.url, startsWith('https://coomer.su/'));
      expect(
        post.files.single.thumbnailUrl,
        startsWith('https://img.coomer.su/'),
      );
      expect(Provider.atHost('www.coomer.su'), Provider.coomer);
      expect(Provider.atHost('coomer.st'), Provider.coomer);
      expect(
        PawchiveLink.findUrl(
          'look https://example.com/a https://coomer.su/fansly/user/1',
        )?.host,
        'coomer.su',
      );
      const AppSettings().applyMirrors();
      expect(Provider.coomer.host, 'coomer.st');
    });

    test('settings default to Pawchive only', () {
      expect(AppSettings.fromJson(const {}).providers, {'pawchive'});
      expect(AppSettings.fromJson(const {'providers': []}).providers, {
        'pawchive',
      });
    });
  });

  group('Coomer tags', () {
    test('cleanTags strips markup and hashes', () {
      expect(
        cleanTags([
          'ads</p>',
          'ads',
          '#',
          '##',
          'ai</p><p>#advertising</p>',
          '#🔥',
          'Ads',
        ]),
        ['ads', 'ai', '🔥'],
      );
      final post = Post.fromJson({
        ..._post('1'),
        'tags': ['ads</p>', 'fyp'],
      });
      expect(post.tags, ['ads', 'fyp']);
    });

    test('Pawchive tags are left alone', () {
      final post = Post.fromJson({
        ..._post('1', service: 'patreon'),
        'tags': ['#sketch', 'a<b'],
      });
      expect(post.tags, ['#sketch', 'a<b']);
    });

    test('mergeTags keeps the most used variant, most used first', () {
      final tags = mergeTags(const [
        CreatorTag('advertising</p>', 80),
        CreatorTag('advertising', 70),
        CreatorTag('#', 60),
        CreatorTag('fyp', 90),
      ]);
      expect(
        [for (final tag in tags) (tag.tag, tag.postCount)],
        [('fyp', 90), ('advertising', 80)],
      );
    });
  });

  test('parsePopularJson reads ranges and drops a future next', () {
    final page = parsePopularJson({
      'info': {
        'navigation_dates': {
          'day': ['2026-11-12', '2026-11-14', '2026-11-13'],
          'week': ['2026-10-27', '2026-11-10', '2026-11-03'],
          'month': ['2026-10-01', '2026-12-01', '2026-11-01'],
        },
        'range_desc': 'November 03, 2026 - November 10, 2026',
      },
      'props': {'today': '2026-11-13'},
      'posts': [
        {..._post('9'), 'fav_count': 28},
      ],
    });
    expect(page.label, 'November 03, 2026 - November 10, 2026');
    expect(page.ranges[PopularPeriod.week], (
      current: '2026-11-03',
      previous: '2026-10-27',
      next: '2026-11-10',
    ));
    expect(page.ranges[PopularPeriod.day]!.next, isNull);
    expect(page.ranges[PopularPeriod.month]!.next, isNull);
    expect(page.posts.single.favorites, 28);
    expect(page.posts.single.files.single.previewOnly, isFalse);
    expect(parsePopularJson(null).posts, isEmpty);
  });

  group('CoomerApi', () {
    test('reads wrapped lists, the posts path and JSON random picks', () async {
      final seen = <http.Request>[];
      final api = CoomerApi(
        client: MockClient((request) async {
          seen.add(request);
          return switch (request.url.path) {
            '/api/v1/posts' => _json({
              'count': 1,
              'posts': [_post('1')],
            }),
            '/api/v1/onlyfans/user/someone/posts' => _json([_post('2')]),
            '/api/v1/posts/random' => _json({
              'service': 'onlyfans',
              'artist_id': 'someone',
              'post_id': '3',
            }),
            '/api/v1/artists/random' => _json({
              'service': 'fansly',
              'artist_id': '42',
            }),
            '/api/v1/onlyfans/user/someone/recommended' => _json([
              {'id': 'other', 'name': 'other', 'service': 'onlyfans'},
            ]),
            '/api/v1/search_hash/00' => _json({'posts': <Object>[]}),
            '/api/v1/posts/tags' => _json([
              {'tag': 'ads</p>', 'post_count': 5},
              {'tag': 'ads', 'post_count': 3},
            ]),
            _ => http.Response('{}', 404),
          };
        }),
      );
      expect((await api.recentPosts(offset: 50)).single.id, '1');
      expect(seen.last.url.queryParameters, {'o': '50'});
      expect(seen.last.headers['Accept'], 'text/css');
      expect(seen.last.headers['User-Agent'], userAgent);
      expect((await api.creatorPosts('onlyfans', 'someone')).single.id, '2');
      expect((await api.taggedPosts('fyp')).single.id, '1');
      expect(seen.last.url.queryParameters, {'tag': 'fyp'});
      final link = await api.randomPost();
      expect(
        (link.service, link.user, link.post),
        ('onlyfans', 'someone', '3'),
      );
      expect((await api.randomCreator()).key, 'fansly/42');
      expect(
        (await api.recommendedCreators('onlyfans', 'someone')).single.id,
        'other',
      );
      expect((await api.popularTags()).single.postCount, 5);
      expect(await api.searchHash('00'), isNull);
      final before = seen.length;
      expect((await api.community('onlyfans', 'someone')).messages, isEmpty);
      expect(seen.length, before);
    });
  });

  group('ArchiveApi', () {
    ArchiveApi build(
      List<String> hosts, {
      Set<String> down = const {},
    }) => ArchiveApi(
      client: MockClient((request) async {
        hosts.add(request.url.host);
        if (down.contains(request.url.host)) return http.Response('', 503);
        final coomer = request.url.host == 'coomer.st';
        final posts = [
          _post(coomer ? 'c1' : 'p1', service: coomer ? 'fansly' : 'patreon'),
          _post(coomer ? 'c2' : 'p2', service: coomer ? 'fansly' : 'patreon'),
        ];
        return switch (request.url.path) {
          '/api/v1/posts' => _json(coomer ? {'posts': posts} : posts),
          _ => _json(posts),
        };
      }),
    );

    test('sends creator calls to the service\'s provider', () async {
      final hosts = <String>[];
      final api = build(hosts);
      await api.creatorPosts('fansly', '1');
      await api.creatorPosts('patreon', '1');
      expect(hosts, ['coomer.st', 'pawchive.pw']);
    });

    test('asks only enabled providers for site-wide lists', () async {
      final hosts = <String>[];
      final api = build(hosts);
      expect([for (final p in await api.recentPosts()) p.id], ['p1', 'p2']);
      expect(hosts, ['pawchive.pw']);
      api.enabled = {Provider.pawchive, Provider.coomer};
      expect(
        [for (final p in await api.recentPosts()) p.id],
        ['p1', 'c1', 'p2', 'c2'],
      );
      api.enabled = {Provider.coomer};
      expect(api.browse, Provider.coomer);
      expect([for (final p in await api.recentPosts()) p.id], ['c1', 'c2']);
    });

    test('a provider that is down does not empty the others', () async {
      final api = build([], down: {'coomer.st'})
        ..enabled = {Provider.pawchive, Provider.coomer};
      expect([for (final p in await api.recentPosts()) p.id], ['p1', 'p2']);
      api.enabled = {Provider.coomer};
      expect(api.recentPosts(), throwsA(isA<ApiException>()));
    });

    test('browse falls back to an enabled provider', () {
      final api = build([])..enabled = {Provider.pawchive, Provider.coomer};
      expect(api.browse, Provider.pawchive);
      api.browse = Provider.coomer;
      expect(api.browse, Provider.coomer);
      api.enabled = {Provider.pawchive};
      expect(api.browse, Provider.pawchive);
    });
  });

  test('interleave takes turns and keeps leftovers', () {
    expect(
      interleave([
        [1, 2, 3],
        [10],
      ]),
      [1, 10, 2, 3],
    );
    expect(interleave(<List<int>>[]), isEmpty);
  });
}
