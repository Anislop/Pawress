import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/feeds.dart';
import 'app_scope.dart';
import 'post_card.dart';
import 'widgets.dart';

/// Posts with a tag from every artist, newest first.
class TagPostsPage extends StatefulWidget {
  const TagPostsPage({super.key, required this.tag});

  final String tag;

  @override
  State<TagPostsPage> createState() => _TagPostsPageState();
}

class _TagPostsPageState extends State<TagPostsPage> {
  late final OffsetFeed _posts = OffsetFeed(
    (offset) =>
        AppScope.read(context).api.taggedPosts(widget.tag, offset: offset),
  );

  @override
  void dispose() {
    _posts.dispose();
    super.dispose();
  }

  String get _url =>
      '$siteUrl/posts?tag=${Uri.encodeQueryComponent(widget.tag)}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '#${widget.tag}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        PopupMenuButton<VoidCallback>(
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: () => copyLink(context, _url),
              child: const Text('Copy link'),
            ),
            PopupMenuItem(
              value: () => openExternal(_url),
              child: const Text('Open on Pawchive'),
            ),
          ],
        ),
      ],
    ),
    body: FeedView(
      feed: _posts,
      itemBuilder: (context, post) => PostCard(post),
      empty: StatusView(
        icon: Icons.tag_rounded,
        title: 'No posts tagged #${widget.tag}',
        body: 'Tags match exactly; try another spelling.',
      ),
    ),
  );
}

void openTag(BuildContext context, String tag) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => TagPostsPage(tag: tag)));
