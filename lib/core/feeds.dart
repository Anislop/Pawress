import 'package:flutter/foundation.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';

/// A list of posts loaded a page at a time.
abstract class Feed extends ChangeNotifier {
  final List<Post> posts = [];
  bool loading = false;

  /// No more pages.
  bool done = false;
  String? error;

  final _keys = <String>{};
  int _generation = 0;

  /// Fetches the next batch, or nothing when there is none.
  @protected
  Future<List<Post>> fetchNext();

  /// Clears paging state before a refresh.
  @protected
  void reset() {}

  Future<void> refresh() async {
    _generation++;
    posts.clear();
    _keys.clear();
    done = false;
    error = null;
    loading = false;
    reset();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading || done) return;
    final generation = _generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final batch = await fetchNext();
      if (generation != _generation) return;
      if (batch.isEmpty) done = true;
      for (final post in batch) {
        if (_keys.add('${post.creatorKey}/${post.id}')) posts.add(post);
      }
    } on ApiException catch (e) {
      if (generation == _generation) error = e.message;
    } catch (e) {
      // A response the models could not read; show it rather than hang.
      debugPrint('Feed failed: $e');
      if (generation == _generation) {
        error = 'Pawchive sent something Pawress could not read.';
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }
}

/// An endpoint paged by offset, such as a creator's posts or a search.
class OffsetFeed extends Feed {
  OffsetFeed(this._fetch);

  final Future<List<Post>> Function(int offset) _fetch;
  int _offset = 0;

  @override
  void reset() => _offset = 0;

  @override
  Future<List<Post>> fetchNext() async {
    final page = await _fetch(_offset);
    _offset += pageSize;
    if (page.length < pageSize) done = true;
    return transform(page);
  }

  @protected
  List<Post> transform(List<Post> page) => page;
}

/// The site's most favorited posts over a [period]. The last 24 hours need
/// no date; a week or month needs the range start the site links to, which
/// is read from the first page once.
class PopularFeed extends Feed {
  PopularFeed(this._api, {this.period = PopularPeriod.day});

  final PawchiveApi _api;
  PopularPeriod period;
  Map<PopularPeriod, ({String? current, String? previous})>? _ranges;
  int _offset = 0;

  @override
  void reset() => _offset = 0;

  @override
  Future<List<Post>> fetchNext() async {
    String? date;
    if (period != PopularPeriod.day) {
      _ranges ??= (await _api.popularPosts()).ranges;
      date = _ranges![period]?.current;
      if (date == null) return const [];
    }
    final page = await _api.popularPosts(
      period: period,
      date: date,
      offset: _offset,
    );
    _offset += pageSize;
    if (page.posts.length < pageSize) done = true;
    return page.posts;
  }
}

/// Every followed creator's posts merged newest first. Each creator is
/// paged on its own and only fetched again once its loaded posts have all
/// been placed.
class FollowingFeed extends Feed {
  FollowingFeed(this._api, this._follows);

  final PawchiveApi _api;
  final List<Follow> Function() _follows;

  /// Posts placed per [loadMore].
  static const _batch = 30;

  /// Concurrent creator requests.
  static const _parallel = 3;

  final _sources = <String, _Source>{};

  @override
  void reset() => _sources.clear();

  @override
  Future<List<Post>> fetchNext() async {
    for (final follow in _follows()) {
      _sources.putIfAbsent(follow.key, () => _Source(follow.creator));
    }
    final batch = <Post>[];
    while (batch.length < _batch) {
      await _fill();
      final live = _sources.values.where((s) => s.buffer.isNotEmpty).toList();
      if (live.isEmpty) break;
      live.sort(
        (a, b) => _time(b.buffer.first).compareTo(_time(a.buffer.first)),
      );
      batch.add(live.first.buffer.removeAt(0));
    }
    return batch;
  }

  static DateTime _time(Post post) =>
      post.date ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Loads the next page for every source that has run out.
  Future<void> _fill() async {
    final empty = _sources.values
        .where((s) => s.buffer.isEmpty && !s.done)
        .toList();
    for (var i = 0; i < empty.length; i += _parallel) {
      await Future.wait(empty.skip(i).take(_parallel).map(_load));
    }
  }

  Future<void> _load(_Source source) async {
    final creator = source.creator;
    final List<Post> page;
    try {
      page = await _api.creatorPosts(
        creator.service,
        creator.id,
        offset: source.offset,
      );
    } on ApiException {
      // One unreachable creator should not block the rest of the feed.
      if (_sources.values.every((s) => s == source || s.done)) rethrow;
      source.done = true;
      return;
    }
    source.offset += pageSize;
    source.buffer.addAll(page);
    if (page.length < pageSize) source.done = true;
  }
}

class _Source {
  _Source(this.creator);

  final Creator creator;
  final buffer = <Post>[];
  int offset = 0;
  bool done = false;
}
