import 'package:flutter/material.dart';

import '../core/models.dart';
import 'app_scope.dart';
import 'autoplay.dart';
import 'comments.dart';
import 'creator_page.dart';
import 'media_viewer.dart';
import 'poll.dart';
import 'post_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// A post in a feed, laid out like a post on X: avatar column, name line,
/// text, then a media grid.
class PostCard extends StatelessWidget {
  const PostCard(this.post, {super.key});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final text = plainText(post.content);
    final media = post.media;
    final others = post.files.length - media.length;
    return InkWell(
      onTap: () => openPost(context, post),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CreatorLookup(
              post: post,
              builder: (creator) => GestureDetector(
                onTap: () => openCreator(context, creator),
                child: CreatorAvatar(creator, size: 42),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NameLine(post: post),
                  if (post.title.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: ink(.82),
                      ),
                    ),
                  ],
                  if (media.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    MediaGrid(post: post, media: media),
                  ],
                  if (post.poll != null) ...[
                    const SizedBox(height: 10),
                    PollView(post.poll!, compact: true),
                  ],
                  const SizedBox(height: 2),
                  PostActions(post: post, attachments: others),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Comments, like (with the count when the popular page gave one) and the
/// attachment count, under a post.
class PostActions extends StatelessWidget {
  const PostActions({
    super.key,
    required this.post,
    this.attachments = 0,
    this.onComments,
  });

  final Post post;
  final int attachments;

  /// Defaults to the comments sheet.
  final VoidCallback? onComments;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final liked = state.isFavorite(post);
    return Row(
      children: [
        _ActionButton(
          tooltip: 'Comments',
          icon: Icons.chat_bubble_outline_rounded,
          color: ink(.6),
          onTap: onComments ?? () => showComments(context, post),
        ),
        const SizedBox(width: 12),
        _ActionButton(
          tooltip: liked ? 'Unlike' : 'Like',
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: liked ? pawPink : ink(.6),
          label: post.favorites == null ? null : compactCount(post.favorites!),
          onTap: () => state.toggleFavorite(post),
        ),
        const Spacer(),
        if (attachments > 0) ...[
          Icon(Icons.attach_file_rounded, size: 16, color: ink(.5)),
          const SizedBox(width: 4),
          Text(
            attachments == 1 ? '1 attachment' : '$attachments attachments',
            style: TextStyle(color: ink(.5), fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.label,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(icon, key: ValueKey(icon), size: 18, color: color),
            ),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label!, style: TextStyle(color: color, fontSize: 13)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _NameLine extends StatelessWidget {
  const _NameLine({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) => _CreatorLookup(
    post: post,
    builder: (creator) => Row(
      children: [
        Flexible(
          child: Text(
            creator.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(width: 5),
        ServiceBadge(post.service, compact: true),
        Text(
          '  ·  ${shortTime(post.date)}',
          style: TextStyle(color: ink(.5), fontSize: 14),
        ),
      ],
    ),
  );
}

/// Builds with the post's creator, using a placeholder named after the id
/// until the profile loads.
class _CreatorLookup extends StatelessWidget {
  const _CreatorLookup({required this.post, required this.builder});

  final Post post;
  final Widget Function(Creator creator) builder;

  @override
  Widget build(BuildContext context) {
    final directory = AppScope.read(context).directory;
    final placeholder = Creator(
      id: post.user,
      service: post.service,
      name: post.user,
    );
    final known = directory.known(post.creatorKey);
    if (known != null) return builder(known);
    return FutureBuilder<Creator?>(
      future: directory.lookup(post.service, post.user),
      builder: (context, snapshot) => builder(snapshot.data ?? placeholder),
    );
  }
}

/// Up to four media tiles in X's arrangements; a fifth and later show as
/// "+N" on the last tile.
class MediaGrid extends StatelessWidget {
  const MediaGrid({super.key, required this.post, required this.media});

  final Post post;
  final List<MediaFile> media;

  @override
  Widget build(BuildContext context) {
    final count = media.length.clamp(1, 4);
    Widget tile(int index) => _MediaTile(
      post: post,
      file: media[index],
      extra: index == 3 && media.length > 4 ? media.length - 4 : 0,
      onTap: () => openViewer(context, post, media[index]),
    );
    const gap = SizedBox.square(dimension: 2);
    final Widget grid = switch (count) {
      1 => tile(0),
      2 => Row(
        children: [
          Expanded(child: tile(0)),
          gap,
          Expanded(child: tile(1)),
        ],
      ),
      3 => Row(
        children: [
          Expanded(child: tile(0)),
          gap,
          Expanded(
            child: Column(
              children: [
                Expanded(child: tile(1)),
                gap,
                Expanded(child: tile(2)),
              ],
            ),
          ),
        ],
      ),
      _ => Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: tile(0)),
                gap,
                Expanded(child: tile(1)),
              ],
            ),
          ),
          gap,
          Expanded(
            child: Row(
              children: [
                Expanded(child: tile(2)),
                gap,
                Expanded(child: tile(3)),
              ],
            ),
          ),
        ],
      ),
    };
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: count == 1 ? 4 / 3.6 : 16 / 10,
        child: grid,
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.post,
    required this.file,
    required this.extra,
    required this.onTap,
  });

  final Post post;
  final MediaFile file;
  final int extra;
  final VoidCallback onTap;

  bool get _animated => file.isVideo || file.extension == 'gif';

  @override
  Widget build(BuildContext context) {
    final still = file.thumbnailUrl != null
        ? NetImage(file.thumbnailUrl!)
        : ColoredBox(color: pawPlum.withValues(alpha: .6));
    Widget overlay(bool playing) => Stack(
      fit: StackFit.expand,
      children: [
        if (file.isVideo && !playing)
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 1.5),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        if (file.isVideo && playing)
          const Positioned(
            right: 8,
            bottom: 8,
            child: Icon(
              Icons.volume_off_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        if (file.extension == 'gif')
          const Positioned(left: 8, bottom: 8, child: _Label('GIF')),
        if (extra > 0)
          ColoredBox(
            color: Colors.black54,
            child: Center(
              child: Text(
                '+$extra',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
    return GestureDetector(
      onTap: onTap,
      child: _animated && extra == 0
          ? AutoplayMedia(
              post: post,
              file: file,
              still: still,
              overlay: overlay,
            )
          : Stack(fit: StackFit.expand, children: [still, overlay(false)]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .7),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );
}

void openPost(BuildContext context, Post post) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => PostPage(post: post)));

void openCreator(BuildContext context, Creator creator) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => CreatorPage(creator: creator)));

void openViewer(BuildContext context, Post post, MediaFile file) {
  final media = post.media;
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (_, _, _) => MediaViewer(
        post: post,
        initialIndex: media.indexOf(file).clamp(0, media.length - 1),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
