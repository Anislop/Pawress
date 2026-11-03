import 'package:flutter/material.dart';

import '../core/feeds.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'post_card.dart';
import 'theme.dart';
import 'widgets.dart';

enum _MediaFilter {
  all('All'),
  photos('Photos'),
  gifs('GIFs'),
  videos('Videos');

  const _MediaFilter(this.label);

  final String label;

  bool matches(MediaFile file) => switch (this) {
    _MediaFilter.all => true,
    _MediaFilter.photos => file.isImage && file.extension != 'gif',
    _MediaFilter.gifs => file.extension == 'gif',
    _MediaFilter.videos => file.isVideo,
  };
}

/// Every image, GIF and video from an artist's posts as a grid, filtered by
/// kind. It pages through the artist's posts like the Posts tab, but only
/// once the tab is opened.
class CreatorMediaTab extends StatefulWidget {
  const CreatorMediaTab({super.key, required this.creator});

  final Creator creator;

  @override
  State<CreatorMediaTab> createState() => _CreatorMediaTabState();
}

class _CreatorMediaTabState extends State<CreatorMediaTab>
    with AutomaticKeepAliveClientMixin {
  late final OffsetFeed _feed = _postFeed();
  _MediaFilter _filter = _MediaFilter.all;

  /// Pages loaded on their own because the filter left too little to
  /// scroll; capped so an artist without videos isn't read to the end.
  int _autoLoads = 0;
  static const _maxAutoLoads = 4;
  static const _fill = 24;

  @override
  bool get wantKeepAlive => true;

  OffsetFeed _postFeed() {
    final api = AppScope.read(context).api;
    final c = widget.creator;
    return OffsetFeed(
      (offset) => api.creatorPosts(c.service, c.id, offset: offset),
    );
  }

  @override
  void initState() {
    super.initState();
    _feed.refresh();
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 && notification.metrics.extentAfter < 1200) {
      _feed.loadMore();
    }
    return false;
  }

  void _setFilter(_MediaFilter filter) => setState(() {
    _filter = filter;
    _autoLoads = 0;
  });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final handle = NestedScrollView.sliverOverlapAbsorberHandleFor(context);
    return ListenableBuilder(
      listenable: _feed,
      builder: (context, _) {
        final items = [
          for (final post in _feed.posts)
            for (final file in post.media)
              if (_filter.matches(file)) (post: post, file: file),
        ];
        if (items.length < _fill &&
            _autoLoads < _maxAutoLoads &&
            !_feed.loading &&
            !_feed.done &&
            _feed.error == null &&
            _feed.posts.isNotEmpty) {
          _autoLoads++;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _feed.loadMore();
          });
        }
        return BackToTop(
          child: RefreshIndicator(
            onRefresh: () {
              _autoLoads = 0;
              return _feed.refresh();
            },
            edgeOffset: 100,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: CustomScrollView(
                key: const PageStorageKey('creator-media'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverOverlapInjector(handle: handle),
                  SliverToBoxAdapter(child: _filters()),
                  SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _MediaCell(
                      post: items[index].post,
                      file: items[index].file,
                    ),
                  ),
                  SliverToBoxAdapter(child: _footer(items.isEmpty)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    child: Row(
      children: [
        for (final filter in _MediaFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: _filter == filter,
              onSelected: (_) => _setFilter(filter),
            ),
          ),
      ],
    ),
  );

  Widget _footer(bool empty) {
    final feed = _feed;
    if (feed.error != null) {
      return StatusView(
        icon: Icons.cloud_off_rounded,
        title: empty ? 'Could not load media' : 'Could not load more',
        body: feed.error,
        action: 'Try again',
        onAction: feed.posts.isEmpty ? feed.refresh : feed.loadMore,
      );
    }
    if (feed.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!feed.done) {
      // Auto-loading stopped short; let the user keep looking.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: feed.loadMore,
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(
              empty
                  ? 'No ${_filter.label.toLowerCase()} yet. Look further'
                  : 'Load more',
            ),
          ),
        ),
      );
    }
    if (empty) {
      return StatusView(
        icon: Icons.perm_media_outlined,
        title: _filter == _MediaFilter.all
            ? 'No media'
            : 'No ${_filter.label.toLowerCase()}',
      );
    }
    return const SizedBox(height: 96);
  }
}

/// A square tile: the image's thumbnail, or for a video the post's first
/// image as a poster (videos have no thumbnails). Tapping opens the viewer
/// at this file; holding opens the post's quick actions.
class _MediaCell extends StatelessWidget {
  const _MediaCell({required this.post, required this.file});

  final Post post;
  final MediaFile file;

  @override
  Widget build(BuildContext context) {
    final poster =
        file.thumbnailUrl ??
        post.media.where((m) => m.isImage).firstOrNull?.thumbnailUrl;
    return GestureDetector(
      onTap: () => openViewer(context, post, file),
      onLongPress: () => showPostMenu(context, post),
      child: Stack(
        fit: StackFit.expand,
        children: [
          poster != null
              ? NetImage(poster)
              : ColoredBox(color: pawPlum.withValues(alpha: .6)),
          if (file.isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          if (file.extension == 'gif')
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'GIF',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
