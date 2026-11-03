import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawress/core/api.dart';
import 'package:pawress/core/file_hash.dart';
import 'package:pawress/core/models.dart';
import 'package:pawress/core/store.dart';

// Trimmed from the live /posts/tags and /posts?tag= pages.
const _tagsPage = '''
<section id="tag-container">
    <article>
      <a href="/posts?tag=nsfw">
        <span>nsfw</span>
        <span>532728</span>
      </a>
    </article>
    <article>
      <a href="/posts?tag=Tom%20%26%20Jerry">
        <span>Tom &amp; Jerry</span>
        <span>12</span>
      </a>
    </article>
</section>
''';

const _taggedPage = '''
<div class="card-list__items">
  <article
    class="post-card post-card--preview"
    data-id="174253068"
    data-service="patreon"
    data-user="129539710"
  >
    <a href="/patreon/user/129539710/post/174253068">
      <header class="post-card__header">
            Red fox
      </header>
        <div class="post-card__image-container">
            <img
              class="post-card__image"
              src="https://img.pawchive.pw/thumbnail/data/1a/bd/1abd.jpg"
              alt="Red fox"
              loading="lazy"
            >
          </div>
      <footer class="post-card__footer">
              <time class="timestamp " datetime="2026-11-03 10:04:29">
  </time>
      </footer>
    </a>
  </article>
</div>
''';

void main() {
  test('parseTagPage reads tags and counts in order', () {
    final tags = parseTagPage(_tagsPage);
    expect(tags.map((t) => t.tag), ['nsfw', 'Tom & Jerry']);
    expect(tags.map((t) => t.postCount), [532728, 12]);
  });

  test('taggedPosts reads the tag page and pages with o', () async {
    final requested = <Uri>[];
    final api = PawchiveApi(
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response(_taggedPage, 200);
      }),
    );
    final posts = await api.taggedPosts('red fox', offset: 50);
    expect(requested.single.path, '/posts');
    expect(requested.single.queryParameters, {'tag': 'red fox', 'o': '50'});
    expect(posts.single.id, '174253068');
    expect(posts.single.title, 'Red fox');
    // Only the thumbnail is known, so the viewer fetches the post.
    expect(posts.single.file!.previewOnly, isTrue);
  });

  test('PawchiveLink reads post and artist links', () {
    final post = PawchiveLink.tryParse(
      'https://pawchive.pw/patreon/user/17722258/post/56165801',
    )!;
    expect(
      (post.service, post.user, post.post),
      ('patreon', '17722258', '56165801'),
    );
    final artist = PawchiveLink.tryParse('/fanbox/user/184422192')!;
    expect(
      (artist.service, artist.user, artist.post),
      ('fanbox', '184422192', null),
    );
    expect(PawchiveLink.tryParse('https://pawchive.pw/'), isNull);
  });

  test(
    'randomPost and randomCreator read the redirect without following',
    () async {
      final api = PawchiveApi(
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          final location = request.url.path == '/posts/random'
              ? 'https://pawchive.pw/patreon/user/1/post/2'
              : 'https://pawchive.pw/fanbox/user/3';
          return http.Response('', 302, headers: {'location': location});
        }),
      );
      final post = await api.randomPost();
      expect((post.service, post.user, post.post), ('patreon', '1', '2'));
      final creator = await api.randomCreator();
      expect(creator.key, 'fanbox/3');
    },
  );

  test('random without a location is an error', () async {
    final api = PawchiveApi(
      client: MockClient((_) async => http.Response('', 200)),
    );
    expect(api.randomPost(), throwsA(isA<ApiException>()));
  });

  test('searchHash reads posts and Discord matches, and 404 as none', () async {
    const hash =
        '925a6e2842e2cc617e4dde55ebd35b8acba95b2613acf0a541ccbc68ae58b594';
    final api = PawchiveApi(
      client: MockClient((request) async {
        if (!request.url.path.endsWith(hash)) return http.Response('{}', 404);
        return http.Response(
          jsonEncode({
            'hash': hash,
            'posts': [
              {
                'id': '174298665',
                'user': '397567',
                'service': 'patreon',
                'title': 'The Mom Next Door',
                'content': '<p>If you live',
                'published': '2026-11-03T19:26:15',
                'file': {
                  'name': 'a.png',
                  'node': 2,
                  'path': '/92/5a/$hash.png',
                },
                'attachments': [],
              },
            ],
            'discord_posts': [
              {'id': '1'},
            ],
          }),
          200,
        );
      }),
    );
    final found = (await api.searchHash(hash.toUpperCase()))!;
    expect(found.hash, hash);
    expect(found.posts.single.id, '174298665');
    expect(found.posts.single.files.single.fullUrl, isNotNull);
    expect(found.discordCount, 1);
    expect(await api.searchHash('0' * 64), isNull);
  });

  test('HashLookup reads null Discord posts as none', () {
    final lookup = HashLookup.fromJson({
      'hash': 'ab',
      'posts': [],
      'discord_posts': null,
    });
    expect(lookup.discordCount, 0);
    expect(lookup.posts, isEmpty);
  });

  test('sha256Hex hashes across chunks and reports progress', () async {
    final read = <int>[];
    final hash = await sha256Hex(
      Stream.fromIterable([utf8.encode('a'), utf8.encode('bc')]),
      onProgress: read.add,
    );
    expect(
      hash,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(read, [1, 3]);
    expect(isSha256(hash), isTrue);
    expect(isSha256(hash.toUpperCase()), isTrue);
    expect(isSha256('${hash}0'), isFalse);
    expect(isSha256('g' * 64), isFalse);
  });

  test('AppSettings keeps the Random choice', () {
    expect(const AppSettings().randomKind, isNull);
    final settings = AppSettings.fromJson(
      const AppSettings().copyWith(randomKind: RandomKind.artist).toJson(),
    );
    expect(settings.randomKind, RandomKind.artist);
    expect(
      settings.copyWith(checkUpdates: false).randomKind,
      RandomKind.artist,
    );
  });
}
