import 'package:flutter_test/flutter_test.dart';
import 'package:pawress/core/api.dart';
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
    expect(copy.notify, NotifyLevel.push);
  });

  test('Follow keeps its bell, and older saves default to push', () {
    final follow = _follow('7').copyWith(notify: NotifyLevel.inApp);
    expect(Follow.fromJson(follow.toJson()).notify, NotifyLevel.inApp);
    final old = follow.toJson()..remove('notify');
    expect(Follow.fromJson(old).notify, NotifyLevel.push);
  });

  test('Like keeps what For You reads', () {
    final post = Post(
      id: '5',
      user: '9',
      service: 'fanbox',
      title: 'Hi',
      tags: const ['Cats'],
    );
    final like = Like.fromJson(Like.of(post, DateTime.utc(2026, 11)).toJson());
    expect(like.key, post.key);
    expect(like.creatorKey, 'fanbox/9');
    expect(like.tags, ['Cats']);
    expect(like.likedAt, DateTime.utc(2026, 11));
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

  test('parsePopularPage reads the range label and its neighbours', () {
    const html = '''
    <h1 class="site-section__heading">Popular Posts for <span title="2026-10-20 00:00:00 to 2026-10-27 00:00:00">October 20, 2026 - October 27, 2026</span></h1>
    <div class="paginator" id="paginator-dates">
      <div id="daily">
        <span><a href="/posts/popular?date=2026-10-19&period=day">« prev</a></span>
        <span><a href="/posts/popular?date=2026-10-20&period=day">Day</a></span>
        <span><a href="/posts/popular?date=2026-10-21&period=day">next »</a></span>
      </div>
      <div id="weekly">
        <span><a href="/posts/popular?date=2026-10-13&period=week">« prev</a></span>
        <span><strong>Week</strong></span>
        <span><a href="/posts/popular?date=2026-10-27&period=week">next »</a></span>
      </div>
      <div id="monthly">
        <span><a href="/posts/popular?date=2026-09-01&period=month">« prev</a></span>
        <span><a href="/posts/popular?date=2026-10-01&period=month">Month</a></span>
        <span><span>next »</span></span>
      </div>''';
    final page = parsePopularPage(html);
    expect(page.label, 'October 20, 2026 - October 27, 2026');
    final week = page.ranges[PopularPeriod.week]!;
    expect(week.current, isNull);
    expect(week.previous, '2026-10-13');
    expect(week.next, '2026-10-27');
    expect(page.ranges[PopularPeriod.month]!.next, isNull);
    expect(page.ranges[PopularPeriod.day]!.next, '2026-10-21');
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

  group('Poll', () {
    const poll = {
      'title': 'Character Poll 51',
      'choices': [
        {'text': 'Qifrey', 'votes': 4},
        {'text': 'Tighnari', 'votes': 31},
        {'text': 'Baizhu', 'votes': '6'},
      ],
      'closes_at': '2026-11-08T21:02:00.000+00:00',
      'created_at': '2026-11-02T20:55:05.000+00:00',
      'description': null,
      'allow_multiple': false,
    };

    test('reads a Patreon poll from a post', () {
      final post = Post.fromJson({..._creatorPost, 'poll': poll});
      final read = post.poll!;
      expect(read.title, 'Character Poll 51');
      expect(read.choices.map((c) => c.votes), [4, 31, 6]);
      expect(read.totalVotes, 41);
      expect(read.mostVotes, 31);
      expect(read.description, isNull);
      expect(read.closesAt, DateTime.utc(2026, 11, 8, 21, 2));
      expect(read.closedAt(DateTime.utc(2026, 11, 9)), isTrue);
      expect(read.closedAt(DateTime.utc(2026, 11, 3)), isFalse);
    });

    test('is absent for null or empty polls', () {
      expect(Post.fromJson({..._creatorPost, 'poll': null}).poll, isNull);
      expect(
        Post.fromJson({
          ..._creatorPost,
          'poll': {'title': 'x', 'choices': []},
        }).poll,
        isNull,
      );
    });
  });

  test('Post survives a JSON round trip without its expiring temp_url', () {
    final post = Post.fromJson({
      ..._creatorPost,
      'poll': {
        'title': 'Vote',
        'choices': [
          {'text': 'A', 'votes': 1},
        ],
      },
    });
    final copy = Post.fromJson(post.toJson());
    expect(copy.key, 'patreon/30500811/173978323');
    expect(copy.title, post.title);
    expect(copy.content, post.content);
    expect(copy.published, post.published);
    expect(copy.tags, post.tags);
    expect(copy.files.map((f) => f.path), post.files.map((f) => f.path));
    expect(copy.poll!.choices.single.text, 'A');
    // The signed URL expires, so a stored preview-only file is fetched
    // again instead.
    expect(copy.file!.tempUrl, isNull);
    expect(copy.file!.previewOnly, isTrue);
    expect(copy.file!.fullUrl, isNull);
  });

  test('Favorite survives a JSON round trip', () {
    final favorite = Favorite(
      post: Post.fromJson(_recentPost),
      favoritedAt: DateTime.utc(2026, 11, 2),
      synced: true,
    );
    final copy = Favorite.fromJson(favorite.toJson());
    expect(copy.key, 'fanbox/9/1');
    expect(copy.favoritedAt, favorite.favoritedAt);
    expect(copy.synced, isTrue);
  });

  test('Fancard builds its path from the hash Pawchive sends', () {
    // The live shape: no path or file object, only hash and ext.
    final card = Fancard.tryParse({
      'id': 8649,
      'user_id': '37736420',
      'file_id': 8649,
      'price': '1000',
      'hash':
          'b804011ce50cbf64750c71b20c0e59ae2baf7a6994f4684a301ea97a0ba06d96',
      'mime': 'image/webp',
      'ext': '.webp',
      'added': '2026-09-16T21:00:00',
      'size': 33406,
    })!;
    expect(
      card.file.thumbnailUrl,
      'https://img.pawchive.pw/thumbnail/data/b8/04/'
      'b804011ce50cbf64750c71b20c0e59ae2baf7a6994f4684a301ea97a0ba06d96.webp',
    );
    expect(card.price, '1000');
    expect(card.added, DateTime.utc(2026, 9, 16, 21));
    expect(Fancard.tryParse({'id': 1}), isNull);
  });

  group('threadComments', () {
    Comment c(String id, [String? parent]) =>
        Comment(id: id, commenter: id, content: '', parentId: parent);

    test('puts replies under their parent, depth first', () {
      final threaded = threadComments([
        c('1'),
        c('2'),
        c('3', '1'),
        c('4', '3'),
        c('5', '2'),
        c('6', '1'),
      ]);
      expect(
        [for (final t in threaded) '${t.comment.id}:${t.depth}'],
        ['1:0', '3:1', '4:2', '6:1', '2:0', '5:1'],
      );
    });

    test('keeps orphans and loops at the top level, each once', () {
      final threaded = threadComments([
        c('1', 'gone'),
        c('2', '3'),
        c('3', '2'),
        c('4', '4'),
      ]);
      expect([for (final t in threaded) t.comment.id], ['1', '4', '2', '3']);
      expect(threaded.every((t) => t.comment.id != '1' || t.depth == 0), true);
    });
  });

  test('parseCommunityPage reads channels, messages and paging', () {
    const html = '''
<div class="chat-page">
  <div class="paginator chat-page__pager">
    <small>
      Showing 1 - 25 of 114
    </small>
  </div>
  <details class="chat-page__picker" open>
    <ul class="chat-page__channels">
      <li>
        <a class="chat-page__channel is-active"
           href="/patreon/user/109106017/community/28ae6a71342144349849e41ec3c82e17" title="Chat">
          <span class="chat-page__channel-name">Chat</span>
          <span class="chat-page__channel-count">114</span>
        </a>
      </li>
      <li>
        <a class="chat-page__channel"
           href="/patreon/user/109106017/community/ff00" title="Art &amp; WIPs">
          <span class="chat-page__channel-name">Art &amp; WIPs</span>
          <span class="chat-page__channel-count">7</span>
        </a>
      </li>
    </ul>
  </details>
  <div class="chat-page__log">
    <div class="community__chat">
      <div class="cmsg cmsg--head cmsg--creator ">
        <div class="cmsg__gutter">
          <img class="cmsg__avatar" src="/icons/patreon/109106017" alt="Okitatsuki AI Art" loading="lazy">
        </div>
        <div class="cmsg__body">
          <div class="cmsg__reply">
            <span class="cmsg__reply-author" title="Sumith Laxan">Sumith Laxan</span>
            <span class="cmsg__reply-text">I can&#39;t seem to understand the collections</span>
          </div>
          <div class="cmsg__head">
            <span class="cmsg__author" title="Okitatsuki AI Art">Okitatsuki AI Art</span>
            <span class="cmsg__badge">Creator</span>
            <time class="cmsg__time" datetime="2026-10-27T03:34:23.809111" title="Oct 27, 2026 03:34 UTC">6 days ago</time>
          </div>
          <div class="cmsg__text"><p>The longer videos are from this year.</p></div>
        </div>
      </div>
      <div class="cmsg cmsg--head ">
        <div class="cmsg__gutter">
          <span class="cmsg__avatar cmsg__avatar--letter" style="background:hsl(279 42% 48%)">D</span>
        </div>
        <div class="cmsg__body">
          <div class="cmsg__head">
            <span class="cmsg__author" title="dapjpjnm">dapjpjnm</span>
            <time class="cmsg__time" datetime="2026-10-30T00:40:47.867754" title="Oct 30, 2026 00:40 UTC">3 days ago</time>
          </div>
          <div class="cmsg__text"><p>Here&#x27;s a small suggestion!</p></div>
        </div>
      </div>
      <div class="cmsg ">
        <div class="cmsg__gutter">
        </div>
        <div class="cmsg__body">
          <div class="cmsg__text"><p>Second line</p></div>
          <a class="cmsg__image" href="https://file.pawchive.pw/data/51/b5/51b5.png" target="_blank" rel="noopener noreferrer">
            <img src="https://img.pawchive.pw/thumbnail/data/51/b5/51b5.png" alt="a.png" loading="lazy" referrerpolicy="no-referrer">
          </a>
          <a class="cmsg__embed" href="https://mega.nz/file/SM513JIa" target="_blank" rel="noopener">
            <span class="cmsg__embed-title">21.51 MB file on MEGA</span>
          </a>
        </div>
      </div>
    </div>
  </div>
</div>''';
    final page = parseCommunityPage(html);
    expect(page.channels.map((c) => c.id), [
      '28ae6a71342144349849e41ec3c82e17',
      'ff00',
    ]);
    expect(page.channels.first.count, 114);
    expect(page.channels.last.name, 'Art & WIPs');
    expect(page.channel!.name, 'Chat');
    expect(page.total, 114);
    expect(page.end, 25);
    expect(page.hasOlder, isTrue);

    final [creator, member, continued] = page.messages;
    expect(creator.author, 'Okitatsuki AI Art');
    expect(creator.fromCreator, isTrue);
    expect(creator.avatarUrl, 'https://pawchive.pw/icons/patreon/109106017');
    expect(creator.replyAuthor, 'Sumith Laxan');
    expect(creator.replyText, "I can't seem to understand the collections");
    expect(creator.time, DateTime.utc(2026, 10, 27, 3, 34, 23, 809, 111));
    expect(creator.content, '<p>The longer videos are from this year.</p>');
    expect(member.fromCreator, isFalse);
    expect(member.avatarLetter, 'D');
    expect(member.avatarHue, 279);
    expect(member.avatarUrl, isNull);
    expect(member.continued, isFalse);
    expect(continued.continued, isTrue);
    expect(continued.author, 'dapjpjnm');
    expect(continued.content, '<p>Second line</p>');
    expect(
      continued.images.single.url,
      'https://file.pawchive.pw/data/51/b5/51b5.png',
    );
    expect(
      continued.images.single.thumbnail,
      'https://img.pawchive.pw/thumbnail/data/51/b5/51b5.png',
    );
    expect(continued.embeds.single.title, '21.51 MB file on MEGA');
    expect(creator.images, isEmpty);
  });

  test('parseCommunityPage reads the last page as having nothing older', () {
    final page = parseCommunityPage('<small>Showing 101 - 114 of 114</small>');
    expect(page.hasOlder, isFalse);
    expect(page.messages, isEmpty);
  });
}
