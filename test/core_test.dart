import 'package:flutter_test/flutter_test.dart';
import 'package:pawress/core/api.dart';
import 'package:pawress/core/feeds.dart';
import 'package:pawress/core/models.dart';

// Shapes copied from live Pawchive responses (trimmed).
const _creatorPost = {
  'id': '173978323',
  'user': '30500811',
  'service': 'patreon',
  'title': 'Exclusive',
  'content': '<p>Hello</p>',
  'added': '2026-11-01T10:00:00',
  'published': '2026-10-31T16:41:47',
  'file': {
    'name': 'a.jpg',
    'path': '/08/45/0845.jpg',
    'preview_only': true,
    'temp_url': 'https://t1.pawchive.pw/f/x/a.jpg?e=1&s=2',
  },
  'attachments': [
    {'name': 'a.jpg', 'path': '/08/45/0845.jpg'},
    {'name': 'clip.mp4', 'path': '/aa/bb/clip.mp4'},
    {'name': 'pack.zip', 'path': '/cc/dd/pack.zip'},
  ],
  'tags': ['NSFW', 'Pokemon'],
  'next': '173957487',
  'prev': null,
};

const _recentPost = {
  'id': '1',
  'user': '9',
  'service': 'fanbox',
  'title': 'Hi',
  'substring': '<p>short</p>',
  'published': '2026-11-02T07:49:29',
  'file': {},
  'attachments': [],
};

Post _post(String id, String user, {String service = 'patreon'}) =>
    Post(id: id, user: user, service: service, title: '');

Follow _follow(String user, {String service = 'patreon'}) => Follow(
  creator: Creator(id: user, service: service, name: user),
  followedAt: DateTime.utc(2026),
);

void main() {
  group('Post.fromJson', () {
    test('reads a creator post with files, tags and paging', () {
      final post = Post.fromJson(_creatorPost);
      expect(post.creatorKey, 'patreon/30500811');
      expect(post.published, DateTime.utc(2026, 10, 31, 16, 41, 47));
      expect(post.tags, ['NSFW', 'Pokemon']);
      expect(post.nextId, '173957487');
      expect(post.prevId, isNull);
      // The main file repeats as an attachment; it is listed once.
      expect(post.files.map((f) => f.name), ['a.jpg', 'clip.mp4', 'pack.zip']);
      expect(post.media.map((f) => f.kind), [MediaKind.image, MediaKind.video]);
      expect(post.file!.fullUrl, startsWith('https://t1.pawchive.pw/'));
      expect(
        post.file!.thumbnailUrl,
        'https://img.pawchive.pw/thumbnail/data/08/45/0845.jpg',
      );
    });

    test(
      'serves archived files from the file host; previews need a refetch',
      () {
        final archived = MediaFile.fromJson({
          'name': 'Giant (1).mp4',
          'path': '/7f/53/7f53.mp4',
          'node': 2,
        });
        final preview = MediaFile.fromJson({
          'name': 'a.png',
          'path': '/1e/66/1e66.png',
          'preview_only': true,
        });
        expect(
          archived.fullUrl,
          'https://file.pawchive.pw/data/7f/53/7f53.mp4?f=Giant%20(1).mp4',
        );
        expect(preview.fullUrl, isNull);
      },
    );

    test(
      'reads a recent-feed post, whose text is a substring and file empty',
      () {
        final post = Post.fromJson(_recentPost);
        expect(post.content, '<p>short</p>');
        expect(post.file, isNull);
        expect(post.files, isEmpty);
      },
    );
  });

  test('parseTags reads JSON lists and Postgres array literals', () {
    expect(parseTags(['A', 'B']), ['A', 'B']);
    expect(parseTags('{"GRANDE CUCULO","MY ROUTINE",PROCIONI}'), [
      'GRANDE CUCULO',
      'MY ROUTINE',
      'PROCIONI',
    ]);
    expect(parseTags(r'{"say \"hi\"",x}'), ['say "hi"', 'x']);
    expect(parseTags(null), isEmpty);
    expect(parseTags('{}'), isEmpty);
  });

  test('Creator.fromJson accepts epoch and ISO dates', () {
    final listed = Creator.fromJson({
      'id': '1',
      'name': 'A',
      'service': 'patreon',
      'updated': 1793527200,
      'favorited': 3233,
    });
    final profile = Creator.fromJson({
      'id': '1',
      'name': 'A',
      'service': 'patreon',
      'updated': '2026-11-01T10:00:00',
    });
    expect(listed.updated, isNotNull);
    expect(listed.favorited, 3233);
    expect(profile.updated, DateTime.utc(2026, 11, 1, 10));
    expect(listed.originalUrl, 'https://www.patreon.com/user?u=1');
  });

  test('Follow survives a JSON round trip', () {
    final follow = _follow('7')
        .copyWith(seenPostIds: ['1', '2'], unread: 3, synced: true);
    final copy = Follow.fromJson(follow.toJson());
    expect(copy.key, 'patreon/7');
    expect(copy.seenPostIds, ['1', '2']);
    expect(copy.unread, 3);
    expect(copy.synced, isTrue);
  });

  group('rankForYou', () {
    test(
      'keeps recency without follows but breaks up runs from one creator',
      () {
        final ranked = rankForYou([
          _post('1', 'a'),
          _post('2', 'a'),
          _post('3', 'b'),
        ], []);
        expect(ranked.map((p) => p.id), ['1', '3', '2']);
      },
    );

    test('lifts followed creators toward the top', () {
      final page = [for (var i = 0; i < 20; i++) _post('$i', 'u$i')];
      final ranked = rankForYou(page, [_follow('u15')]);
      expect(ranked.first.id, '15');
    });
  });

  test('parseDirectMessages reads DM cards from the DMs page', () {
    const html = '''
<div class="card-list__items">
  <article
    class="dm-card "
  >
    <header class="dm-card__header"><span class="dm-card__user">Meliodas</span></header>
    <section class="dm-card__body" tabindex="0">
      <div class="dm-card__content"><p>Thank you! <a href="https://example.com">link</a></p>
</div>
    </section>
    <footer class="dm-card__footer">
        <div class="dm-card__added">
          Added: 2026-11
        </div>
    </footer>
  </article>
</div>''';
    final dms = parseDirectMessages(html);
    expect(dms, hasLength(1));
    expect(dms.single.content, contains('Thank you!'));
    expect(dms.single.added, '2026-11');
  });

  test('parsePopularPage reads post cards and period links', () {
    const html = '''
<div id="daily">
  <span><a href="/posts/popular?date=2026-11-01&period=day">« prev</a></span>
  <span><a href="/posts/popular?date=2026-11-02&period=day">Day</a></span>
  <span><span>next »</span></span>
</div>
<div id="weekly">
  <span><a href="/posts/popular?date=2026-10-20&period=week">« prev</a></span>
  <span><a href="/posts/popular?date=2026-10-27&period=week">Week</a></span>
</div>
<article
    class="post-card post-card--preview"
    data-id="173960633"
    data-service="patreon"
    data-user="92168361"
  >
    <a href="/patreon/user/92168361/post/173960633">
      <header class="post-card__header">
            Trick or... Treat? &amp; more
      </header>
        <div class="post-card__image-container">
            <img
              class="post-card__image"
              src="https://img.pawchive.pw/thumbnail/data/fa/24/fa24.gif"
              alt="Trick or... Treat?"
            >
          </div>
      <footer class="post-card__footer">
              <time
    class="timestamp "
    datetime="2026-10-31 17:00:17"
  >2026-10-31 17:00</time>
        <div>
            1 attachment
          <br>
          285 favorites
        </div>
      </footer>
    </a>
  </article>''';
    final page = parsePopularPage(html);
    final post = page.posts.single;
    expect(post.creatorKey, 'patreon/92168361');
    expect(post.title, 'Trick or... Treat? & more');
    expect(post.favorites, 285);
    expect(post.published, DateTime.utc(2026, 10, 31, 17, 0, 17));
    expect(post.file!.path, '/fa/24/fa24.gif');
    expect(post.file!.fullUrl, isNull);
    expect(page.ranges[PopularPeriod.week]!.current, '2026-10-27');
    expect(page.ranges[PopularPeriod.week]!.previous, '2026-10-20');
    expect(page.ranges[PopularPeriod.day]!.current, '2026-11-02');
  });

  test('parseCreatorCards reads similar artists', () {
    const html = '''
  <a
    href="/patreon/user/176059643"
    class="user-card "
    data-id="176059643"
    data-service="patreon"
    data-style="background-image: url(/banners/patreon/176059643);"
  >
    <div class="user-card__info">
      <span class="user-card__service">Patreon</span>
      <div class="user-card__name">Daioo</div>
    </div>
  </a>''';
    final creator = parseCreatorCards(html).single;
    expect(creator.key, 'patreon/176059643');
    expect(creator.name, 'Daioo');
  });

  test('decodeEntities handles named and numeric entities once', () {
    expect(
      decodeEntities('I&#x27;m &amp; you&#39;re &lt;3'),
      "I'm & you're <3",
    );
    expect(decodeEntities('&amp;lt;'), '&lt;');
    expect(decodeEntities('&bogus; &#xZZ;'), '&bogus; &#xZZ;');
  });
}
