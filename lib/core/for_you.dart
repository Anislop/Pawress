import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'config.dart';
import 'feeds.dart';
import 'models.dart';

/// What For You learns from, read again for every page so a thumbs up
/// changes what comes next.
typedef ForYouSignals = ({
  List<Follow> follows,
  List<Like> likes,
  List<Favorite> favorites,

  /// "Not interested" marks, which push artists and tags down.
  List<Like> dislikes,

  /// Never shown, so never picked.
  Blocklist blocklist,

  /// The share of a page drawn from followed and liked artists.
  double followingShare,
});

/// The user's taste as weights: per creator, per site and per tag. Follows
/// count fully; thumbs-up likes and favorites fade with age so the feed
/// follows what the user is into now. "Not interested" marks fade the same
/// way and count against an artist and tags.
class Taste {
  Taste._({
    required this.creators,
    required this.services,
    required this.tags,
    required this.followed,
    this.avoidCreators = const {},
    this.avoidTags = const {},
    this.disliked = const {},
  });

  factory Taste.from(ForYouSignals signals, {DateTime? now}) {
    final at = now ?? DateTime.now().toUtc();
    final creators = <String, double>{};
    final services = <String, double>{};
    final tags = <String, double>{};
    void add(Map<String, double> map, String key, double value) =>
        map[key] = (map[key] ?? 0) + value;
    double fade(DateTime when, int halfLifeDays) => pow(
      .5,
      max(0, at.difference(when).inHours) / (24 * halfLifeDays),
    ).toDouble();

    for (final follow in signals.follows) {
      add(creators, follow.key, _followWeight);
      add(services, follow.creator.service, 1);
    }
    for (final like in signals.likes) {
      final weight = fade(like.likedAt, _likeHalfLifeDays);
      add(creators, like.creatorKey, 2 * weight);
      add(services, like.service, weight);
      for (final tag in like.tags) {
        add(tags, _tagKey(tag), weight);
      }
    }
    for (final favorite in signals.favorites) {
      final weight = fade(favorite.favoritedAt, _favoriteHalfLifeDays);
      final post = favorite.post;
      add(creators, post.creatorKey, 1.5 * weight);
      add(services, post.service, .5 * weight);
      for (final tag in post.tags) {
        add(tags, _tagKey(tag), .75 * weight);
      }
    }
    final avoidCreators = <String, double>{};
    final avoidTags = <String, double>{};
    for (final dislike in signals.dislikes) {
      final weight = fade(dislike.likedAt, _likeHalfLifeDays);
      add(avoidCreators, dislike.creatorKey, 2 * weight);
      for (final tag in dislike.tags) {
        add(avoidTags, _tagKey(tag), weight);
      }
    }
    return Taste._(
      creators: creators,
      services: _normalized(services),
      tags: _normalized(tags),
      followed: {for (final follow in signals.follows) follow.key},
      avoidCreators: avoidCreators,
      avoidTags: avoidTags,
      disliked: {for (final dislike in signals.dislikes) dislike.key},
    );
  }

  /// A follow is worth this many fresh likes and a half.
  static const _followWeight = 3.0;
  static const _likeHalfLifeDays = 30;
  static const _favoriteHalfLifeDays = 60;

  /// A post this many hours old has half the freshness of a new one.
  static const _freshHalfLifeHours = 36.0;

  /// Raw affinity per creator key; grows with every follow, like and
  /// favorite.
  final Map<String, double> creators;

  /// Per site and per tag, scaled so the strongest is 1.
  final Map<String, double> services;
  final Map<String, double> tags;
  final Set<String> followed;

  /// Faded "not interested" weight per creator key and per tag.
  final Map<String, double> avoidCreators;
  final Map<String, double> avoidTags;

  /// Post keys marked "not interested".
  final Set<String> disliked;

  bool get isEmpty => creators.isEmpty;

  /// How much the user likes [creatorKey], with diminishing returns so one
  /// artist cannot take over the feed.
  double affinity(String creatorKey) => log(1 + (creators[creatorKey] ?? 0));

  /// How strongly the user turned away from [creatorKey], up to 2.5.
  double aversion(String creatorKey) =>
      min(2.5, avoidCreators[creatorKey] ?? 0);

  /// Higher is better: freshness (up to 2) plus taste for the creator, the
  /// post's tags and its site, minus what "not interested" counts against
  /// them.
  double score(Post post, DateTime now) {
    final date = post.date;
    final hours = date == null
        ? 24.0 * 30
        : max(0, now.difference(date).inMinutes) / 60;
    final fresh = pow(.5, hours / _freshHalfLifeHours);
    var tagMatch = 0.0;
    var tagAvoid = 0.0;
    for (final tag in post.tags) {
      tagMatch += tags[_tagKey(tag)] ?? 0;
      tagAvoid += avoidTags[_tagKey(tag)] ?? 0;
    }
    return 2 * fresh +
        affinity(post.creatorKey) +
        min(tagMatch, 1.5) +
        .4 * (services[post.service] ?? 0) -
        aversion(post.creatorKey) -
        min(tagAvoid, 1.5);
  }

  static String _tagKey(String tag) => tag.trim().toLowerCase();

  static Map<String, double> _normalized(Map<String, double> weights) {
    if (weights.isEmpty) return weights;
    final top = weights.values.reduce(max);
    if (top <= 0) return const {};
    return {for (final e in weights.entries) e.key: e.value / top};
  }
}

/// The creators For You pulls posts from, in the order to fetch them:
/// followed artists plus artists the user liked or favorited without
/// following. Each is weighted by [Taste.affinity] and how recently they
/// updated, then sampled (weighted random order) so every refresh starts
/// with different artists instead of always the same top few.
@visibleForTesting
List<Creator> pickSources(
  Taste taste,
  List<Follow> follows,
  Random random, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now().toUtc();
  final candidates = <String, Creator>{
    for (final follow in follows) follow.key: follow.creator,
  };
  final liked =
      taste.creators.entries
          .where(
            (e) =>
                !candidates.containsKey(e.key) &&
                e.value >= .5 &&
                taste.aversion(e.key) < e.value,
          )
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in liked.take(_likedSources)) {
    final [service, id] = entry.key.split('/');
    candidates[entry.key] = Creator(id: id, service: service, name: id);
  }
  double activity(Creator creator) {
    final updated = creator.updated;
    if (updated == null) return .5;
    final days = max(0, at.difference(updated).inHours) / 24;
    return max(.15, pow(.5, days / 14).toDouble());
  }

  // Efraimidis–Spirakis: sorting by u^(1/w) samples without replacement in
  // proportion to w.
  final keyed = [
    for (final creator in candidates.values)
      (
        creator,
        pow(
          random.nextDouble(),
          1 / max(1e-6, taste.affinity(creator.key) * activity(creator)),
        ),
      ),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final entry in keyed) entry.$1];
}

/// Most artists that are liked but not followed taken as sources.
const _likedSources = 30;

/// Lays [a] and [b] out in proportion to their lengths (a then b on ties),
/// keeping each list's order.
@visibleForTesting
List<Post> blendForYou(List<Post> a, List<Post> b) {
  final total = a.length + b.length;
  final result = <Post>[];
  var i = 0;
  var j = 0;
  for (var n = 0; n < total; n++) {
    if (i < a.length && (j >= b.length || i * total < (n + 1) * a.length)) {
      result.add(a[i++]);
    } else {
      result.add(b[j++]);
    }
  }
  return result;
}

/// Moves posts so one creator does not fill several rows in a row, keeping
/// the order otherwise.
@visibleForTesting
List<Post> spreadCreators(List<Post> posts) {
  final pending = [...posts];
  final result = <Post>[];
  while (pending.isNotEmpty) {
    final last = result.isEmpty ? null : result.last.creatorKey;
    final index = pending.indexWhere((post) => post.creatorKey != last);
    result.add(pending.removeAt(index < 0 ? 0 : index));
  }
  return result;
}

/// The best [count] of [posts] by [score], at most [perCreator] from one
/// creator. The chosen posts are removed from [posts].
@visibleForTesting
List<Post> takeBest(
  List<Post> posts,
  int count,
  double Function(Post) score, {
  int perCreator = 3,
}) {
  if (count <= 0 || posts.isEmpty) return const [];
  final scored = [for (final post in posts) (post, score(post))]
    ..sort((a, b) => b.$2.compareTo(a.$2));
  final perKey = <String, int>{};
  final chosen = <Post>[];
  for (final (post, _) in scored) {
    if (chosen.length >= count) break;
    final used = perKey[post.creatorKey] ?? 0;
    if (used >= perCreator) continue;
    perKey[post.creatorKey] = used + 1;
    chosen.add(post);
  }
  final picked = chosen.toSet();
  posts.removeWhere(picked.contains);
  return chosen;
}

/// The For You timeline. Pawchive has no recommendations, so it is built
/// here from two pools:
///
/// - **From your artists**: the first page of followed artists and of
///   artists you gave a thumbs up or favorited, a few creators per page,
///   picked by [pickSources].
/// - **Discovery**: site-wide recent posts.
///
/// Both are ranked by [Taste.score] with a little jitter, capped per
/// creator, blended by [ForYouSignals.followingShare] and spread so one
/// artist never fills consecutive rows. Without follows or likes it is the
/// recent feed.
class ForYouFeed extends Feed {
  ForYouFeed(
    PawchiveApi api,
    ForYouSignals Function() signals, {
    Random? random,
  }) : this.custom(
         recent: (offset) => api.recentPosts(offset: offset),
         creatorPosts: (creator) =>
             api.creatorPosts(creator.service, creator.id),
         signals: signals,
         random: random,
       );

  @visibleForTesting
  ForYouFeed.custom({
    required this._recent,
    required this._creatorPosts,
    required this._signals,
    Random? random,
  }) : _random = random ?? Random();

  final Future<List<Post>> Function(int offset) _recent;
  final Future<List<Post>> Function(Creator creator) _creatorPosts;
  final ForYouSignals Function() _signals;
  final Random _random;

  /// Posts per page.
  static const _batch = 30;

  /// Concurrent creator requests, and rounds of them per page, so a page
  /// costs at most six creator requests (see docs/pawchive-api.md).
  static const _parallel = 3;
  static const _rounds = 2;

  /// Random points added to scores so equal posts trade places.
  static const _jitter = .35;

  /// Candidates kept between pages; the weakest are dropped beyond this.
  static const _maxPool = 400;

  List<Creator>? _queue;
  final _pool = <Post>[];
  final _recentBuffer = <Post>[];
  final _taken = <String>{};
  int _offset = 0;
  bool _recentDone = false;

  @override
  void reset() {
    _queue = null;
    _pool.clear();
    _recentBuffer.clear();
    _taken.clear();
    _offset = 0;
    _recentDone = false;
  }

  @override
  Future<List<Post>> fetchNext() async {
    final signals = _signals();
    final now = DateTime.now().toUtc();
    final taste = Taste.from(signals, now: now);
    final queue = _queue ??= pickSources(
      taste,
      signals.follows,
      _random,
      now: now,
    );
    double score(Post post) =>
        taste.score(post, now) + _random.nextDouble() * _jitter;
    bool wanted(Post post) =>
        !_taken.contains(post.key) &&
        !taste.disliked.contains(post.key) &&
        !signals.blocklist.hides(post);

    final wantFollowing = queue.isEmpty && _pool.isEmpty
        ? 0
        : (_batch * signals.followingShare).round();
    for (var round = 0; round < _rounds; round++) {
      if (_pool.length >= wantFollowing * 2 || queue.isEmpty) break;
      final creators = queue.take(_parallel).toList();
      queue.removeRange(0, creators.length);
      final pages = await Future.wait(creators.map(_loadCreator));
      for (final page in pages) {
        _pool.addAll(page.where(wanted));
      }
    }
    // Three posts per artist keeps a page varied, but with only a few
    // artists to draw from they may fill more so the mix still holds.
    final artists = {for (final post in _pool) post.creatorKey}.length;
    final fromArtists = takeBest(
      _pool,
      wantFollowing,
      score,
      perCreator: max(3, (wantFollowing / max(1, artists)).ceil()),
    );

    final wantRecent = _batch - fromArtists.length;
    var requests = 0;
    while (_recentBuffer.length < wantRecent * 1.5 &&
        !_recentDone &&
        requests < 2) {
      requests++;
      final List<Post> page;
      try {
        page = await _recent(_offset);
      } on ApiException {
        if (fromArtists.isEmpty) rethrow;
        break;
      }
      _offset += pageSize;
      if (page.length < pageSize) _recentDone = true;
      _recentBuffer.addAll(page.where(wanted));
    }
    final discovery = takeBest(
      _recentBuffer..removeWhere((post) => !wanted(post)),
      wantRecent,
      score,
      perCreator: 2,
    );

    final page = spreadCreators(blendForYou(fromArtists, discovery));
    _taken.addAll(page.map((post) => post.key));
    _pool.removeWhere((post) => _taken.contains(post.key));
    _trim(_pool, score);
    _trim(_recentBuffer, score);
    return page;
  }

  /// One creator's newest posts; an unreachable creator just adds nothing.
  Future<List<Post>> _loadCreator(Creator creator) async {
    try {
      return await _creatorPosts(creator);
    } on ApiException {
      return const [];
    }
  }

  static void _trim(List<Post> posts, double Function(Post) score) {
    if (posts.length <= _maxPool) return;
    final kept = takeBest(posts, _maxPool, score, perCreator: _maxPool);
    posts
      ..clear()
      ..addAll(kept);
  }
}
