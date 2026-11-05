import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawress/core/api.dart';
import 'package:pawress/core/config.dart';
import 'package:pawress/core/for_you.dart';
import 'package:pawress/core/models.dart';

final _now = DateTime.utc(2026, 11, 3, 12);

Post _post(
  String id,
  String user, {
  String service = 'patreon',
  int hoursAgo = 1,
  List<String> tags = const [],
}) => Post(
  id: id,
  user: user,
  service: service,
  title: '',
  published: _now.subtract(Duration(hours: hoursAgo)),
  tags: tags,
);

Follow _follow(String user, {String service = 'patreon', DateTime? updated}) =>
    Follow(
      creator: Creator(
        id: user,
        service: service,
        name: user,
        updated: updated,
      ),
      followedAt: DateTime.utc(2026),
    );

Like _like(String user, {int daysAgo = 0, List<String> tags = const []}) =>
    Like(
      key: 'patreon/$user/x$daysAgo',
      service: 'patreon',
      user: user,
      tags: tags,
      likedAt: _now.subtract(Duration(days: daysAgo)),
    );

ForYouSignals _signals({
  List<Follow> follows = const [],
  List<Like> likes = const [],
  List<Favorite> favorites = const [],
  List<Like> dislikes = const [],
  Blocklist? blocklist,
  double share = .65,
}) => (
  follows: follows,
  likes: likes,
  favorites: favorites,
  dislikes: dislikes,
  blocklist: blocklist ?? Blocklist(),
  followingShare: share,
);

void main() {
  group('Taste', () {
    test('not interested pushes an artist and its tags down', () {
      final post = _post('1', 'meh', tags: ['Spiders']);
      final other = _post('2', 'fine', tags: ['cats']);
      final before = Taste.from(_signals(), now: _now);
      final after = Taste.from(
        _signals(dislikes: [Like.of(post, _now)]),
        now: _now,
      );
      expect(after.score(post, _now), lessThan(before.score(post, _now) - 2));
      expect(
        after.score(_post('3', 'fine', tags: ['SPIDERS']), _now),
        lessThan(after.score(other, _now)),
      );
      expect(after.disliked, contains(post.key));
      expect(after.aversion('patreon/meh'), greaterThan(0));
    });

    test('a fresh like counts more than an old one', () {
      final taste = Taste.from(
        _signals(likes: [_like('new'), _like('old', daysAgo: 90)]),
        now: _now,
      );
      expect(
        taste.affinity('patreon/new'),
        greaterThan(taste.affinity('patreon/old')),
      );
      expect(taste.affinity('patreon/old'), greaterThan(0));
      expect(taste.affinity('patreon/nobody'), 0);
    });

    test('tags are case-insensitive and scaled to the strongest', () {
      final taste = Taste.from(
        _signals(
          likes: [
            _like('a', tags: ['Cats']),
            _like('b', tags: ['cats', 'Dogs']),
          ],
        ),
        now: _now,
      );
      expect(taste.tags['cats'], 1);
      expect(taste.tags['dogs'], closeTo(.5, .01));
    });

    test('ranks followed, liked-tag and fresh posts higher', () {
      final taste = Taste.from(
        _signals(
          follows: [_follow('f')],
          likes: [
            _like('x', tags: ['cats']),
          ],
        ),
        now: _now,
      );
      final followed = taste.score(_post('1', 'f'), _now);
      final stranger = taste.score(_post('2', 's'), _now);
      final tagged = taste.score(_post('3', 's', tags: ['Cats']), _now);
      final stale = taste.score(_post('4', 's', hoursAgo: 24 * 14), _now);
      expect(followed, greaterThan(stranger));
      expect(tagged, greaterThan(stranger));
      expect(stranger, greaterThan(stale));
    });
  });

  group('pickSources', () {
    test('includes liked artists that are not followed', () {
      final taste = Taste.from(
        _signals(follows: [_follow('f')], likes: [_like('l')]),
        now: _now,
      );
      final sources = pickSources(taste, [_follow('f')], Random(1), now: _now);
      expect(
        sources.map((c) => c.key),
        unorderedEquals(['patreon/f', 'patreon/l']),
      );
    });

    test('favors artists with more affinity who posted recently', () {
      final follows = [
        _follow('loved', updated: _now),
        _follow('quiet', updated: _now.subtract(const Duration(days: 120))),
      ];
      final taste = Taste.from(
        _signals(
          follows: follows,
          likes: [for (var i = 0; i < 5; i++) _like('loved', daysAgo: i)],
        ),
        now: _now,
      );
      final random = Random(7);
      var lovedFirst = 0;
      for (var i = 0; i < 200; i++) {
        final first = pickSources(taste, follows, random, now: _now).first;
        if (first.id == 'loved') lovedFirst++;
      }
      // Weighted, not fixed: the quieter artist still leads sometimes.
      expect(lovedFirst, greaterThan(150));
      expect(lovedFirst, lessThan(200));
    });
  });

  test('blendForYou spreads the smaller list through the larger', () {
    final a = [for (var i = 0; i < 3; i++) _post('a$i', 'a')];
    final b = [_post('b0', 'b')];
    expect(blendForYou(a, b).map((p) => p.id), ['a0', 'a1', 'a2', 'b0']);
    expect(
      blendForYou(a.take(2).toList(), [
        _post('b0', 'b'),
        _post('b1', 'b'),
      ]).map((p) => p.id),
      ['a0', 'b0', 'a1', 'b1'],
    );
    expect(blendForYou([], b).single.id, 'b0');
  });

  test('spreadCreators breaks up runs from one creator', () {
    final spread = spreadCreators([
      _post('1', 'a'),
      _post('2', 'a'),
      _post('3', 'b'),
    ]);
    expect(spread.map((p) => p.id), ['1', '3', '2']);
  });

  test('takeBest caps each creator and removes what it takes', () {
    final posts = [
      for (var i = 0; i < 5; i++) _post('a$i', 'a'),
      _post('b0', 'b'),
    ];
    final best = takeBest(
      posts,
      4,
      (p) => p.user == 'a' ? 2 : 1,
      perCreator: 2,
    );
    expect(best.map((p) => p.id), ['a0', 'a1', 'b0']);
    expect(posts.map((p) => p.id), ['a2', 'a3', 'a4']);
  });

  group('ForYouFeed', () {
    late List<String> requests;

    Future<List<Post>> recent(int offset) async {
      requests.add('recent $offset');
      return [
        for (var i = 0; i < pageSize; i++)
          _post('r${offset + i}', 'stranger${(offset + i) % 25}', hoursAgo: i),
      ];
    }

    Future<List<Post>> creatorPosts(Creator creator) async {
      requests.add(creator.key);
      return [
        for (var i = 0; i < 10; i++)
          _post('${creator.id}-$i', creator.id, hoursAgo: 2 + i * 12),
      ];
    }

    setUp(() => requests = []);

    test('is the recent feed without follows or likes', () async {
      final feed = ForYouFeed.custom(
        recent: recent,
        creatorPosts: creatorPosts,
        signals: _signals,
        random: Random(1),
      );
      await feed.loadMore();
      expect(feed.posts, hasLength(30));
      expect(feed.posts.every((p) => p.id.startsWith('r')), isTrue);
      expect(requests, ['recent 0']);
    });

    test('leaves out blocked and dismissed posts', () async {
      final dismissed = _post('r0', 'stranger0', hoursAgo: 0);
      final feed = ForYouFeed.custom(
        recent: recent,
        creatorPosts: creatorPosts,
        signals: () => _signals(
          dislikes: [Like.of(dismissed, _now)],
          blocklist: Blocklist().withCreator(
            const Creator(id: 'stranger1', service: 'patreon', name: 's'),
          ),
        ),
        random: Random(1),
      );
      await feed.loadMore();
      expect(feed.posts, hasLength(30));
      expect(feed.posts.any((p) => p.key == dismissed.key), isFalse);
      expect(feed.posts.any((p) => p.user == 'stranger1'), isFalse);
    });

    test('draws mostly from followed artists, a few per page', () async {
      final follows = [for (var i = 0; i < 20; i++) _follow('f$i')];
      final feed = ForYouFeed.custom(
        recent: recent,
        creatorPosts: creatorPosts,
        signals: () => _signals(follows: follows),
        random: Random(2),
      );
      await feed.loadMore();
      final fromArtists = feed.posts.where((p) => p.user.startsWith('f'));
      expect(fromArtists.length, (30 * .65).round());
      expect(requests.where((r) => r.startsWith('patreon/')).length, 6);
      // No artist fills two rows in a row.
      for (var i = 1; i < feed.posts.length; i++) {
        expect(feed.posts[i].creatorKey, isNot(feed.posts[i - 1].creatorKey));
      }

      await feed.loadMore();
      expect(feed.posts, hasLength(60));
      expect(feed.posts.map((p) => p.key).toSet(), hasLength(60));
    });

    test('a thumbs up pulls in an artist you do not follow', () async {
      final likes = <Like>[];
      final feed = ForYouFeed.custom(
        recent: recent,
        creatorPosts: creatorPosts,
        signals: () => _signals(likes: likes),
        random: Random(3),
      );
      likes.add(_like('liked'));
      await feed.loadMore();
      expect(requests, contains('patreon/liked'));
      expect(feed.posts.any((p) => p.user == 'liked'), isTrue);
    });

    test('shows the error when nothing could load', () async {
      final feed = ForYouFeed.custom(
        recent: (_) async => throw const ApiException('Offline'),
        creatorPosts: creatorPosts,
        signals: _signals,
        random: Random(4),
      );
      await feed.loadMore();
      expect(feed.error, 'Offline');
      expect(feed.posts, isEmpty);
    });
  });
}
