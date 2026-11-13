import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import 'app_scope.dart';
import 'autoplay.dart';
import 'comments.dart';
import 'creator_page.dart';
import 'downloads.dart';
import 'media_viewer.dart';
import 'poll.dart';
import 'post_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// A post in a feed, laid out like a post on X: avatar column, name line,
/// text, then a media grid. Holding it opens [showPostMenu]. Posts already
/// opened have dimmer text unless [dimViewed] is off.
class PostCard extends StatelessWidget {
  const PostCard(this.post, {super.key, this.dimViewed = true});

  final Post post;
  final bool dimViewed;

  @override
  Widget build(BuildContext context) {
    final viewed = dimViewed && AppScope.of(context).wasViewed(post);
    final text = plainText(post.content);
    final media = post.media;
    final others = post.files.length - media.length;
    return InkWell(
      onTap: () => openPost(context, post),
      onLongPress: () => showPostMenu(context, post),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: ink(viewed ? .62 : .94),
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
                        color: ink(viewed ? .55 : .82),
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

/// Comments, thumbs up (a private like that tunes For You), favorite (with
/// the count when the popular page gave one) and the attachment count,
/// under a post.
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
    final liked = state.isLiked(post);
    final favorite = state.isFavorite(post);
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
          tooltip: liked ? 'Remove like' : 'Like',
          icon: liked
              ? Icons.thumb_up_alt_rounded
              : Icons.thumb_up_alt_outlined,
          color: liked ? pinkText : ink(.6),
          onTap: () {
            final first = state.likes.isEmpty && !liked;
            HapticFeedback.lightImpact();
            state.toggleLike(post);
            if (first) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Liked. For You will show more posts like this.',
                  ),
                ),
              );
            }
          },
        ),
        const SizedBox(width: 12),
        _ActionButton(
          tooltip: favorite ? 'Remove from favorites' : 'Favorite',
          icon: favorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: favorite ? pawPink : ink(.6),
          label: post.favorites == null ? null : compactCount(post.favorites!),
          onTap: () {
            HapticFeedback.lightImpact();
            state.toggleFavorite(post);
          },
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
                  color: Colors.white,
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

/// Quick actions for a post held in a feed: its artist, like, favorite,
/// download, copy and open.
Future<void> showPostMenu(BuildContext context, Post post) {
  HapticFeedback.mediumImpact();
  final state = AppScope.read(context);
  final creator =
      state.directory.known(post.creatorKey) ??
      Creator(id: post.user, service: post.service, name: post.user);
  final text = plainText(post.content);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: canvas,
    builder: (sheet) {
      final liked = state.isLiked(post);
      final favorite = state.isFavorite(post);
      Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: () {
          Navigator.of(sheet).pop();
          onTap();
        },
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(
              Icons.person_outline_rounded,
              'View ${creator.name}',
              () => openCreator(context, creator),
            ),
            item(
              liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
              liked ? 'Remove like' : 'Like',
              () => state.toggleLike(post),
            ),
            item(
              favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              favorite ? 'Remove from favorites' : 'Favorite',
              () => state.toggleFavorite(post),
            ),
            if (post.files.isNotEmpty)
              item(
                Icons.download_rounded,
                post.files.length == 1
                    ? 'Download file'
                    : 'Download all ${post.files.length} files',
                () => downloadFiles(context, post, post.files),
              ),
            item(
              Icons.link_rounded,
              'Copy link',
              () => copyLink(context, post.url),
            ),
            item(
              Icons.not_interested_rounded,
              'Not interested in this post',
              () => markNotInterested(context, post),
            ),
            if (post.tags.isNotEmpty)
              item(
                Icons.tag_rounded,
                'Block a tag…',
                () => showBlockTags(context, post),
              ),
            item(
              Icons.block_rounded,
              'Block ${creator.name}',
              () => blockCreator(context, creator),
            ),
            if (text.isNotEmpty)
              item(Icons.content_copy_rounded, 'Copy text', () {
                Clipboard.setData(
                  ClipboardData(
                    text: post.title.isEmpty ? text : '${post.title}\n\n$text',
                  ),
                );
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Text copied')));
              }),
            item(
              Icons.open_in_new_rounded,
              'Open on ${post.provider.name}',
              () => openExternal(post.url),
            ),
          ],
        ),
      );
    },
  );
}

/// Hides [post] and tells For You, with a way back.
void markNotInterested(BuildContext context, Post post) {
  final state = AppScope.read(context);
  HapticFeedback.lightImpact();
  state.notInterested(post);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text("Got it. You'll see fewer posts like this."),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => state.undoNotInterested(post),
        ),
      ),
    );
}

/// Asks, then blocks [creator]: their posts leave every feed and they're
/// unfollowed.
Future<void> blockCreator(BuildContext context, Creator creator) async {
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Block ${creator.name}?'),
      content: Text(
        state.isFollowing(creator.key)
            ? 'Their posts leave your feeds and you unfollow them. Their '
                  'profile still opens.'
            : 'Their posts leave your feeds. Their profile still opens.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  HapticFeedback.mediumImpact();
  await state.block(creator);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Blocked ${creator.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => state.unblock(creator.key),
        ),
      ),
    );
}

/// The post's tags, each with a switch to block it everywhere.
Future<void> showBlockTags(BuildContext context, Post post) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: canvas,
      builder: (sheet) {
        final state = AppScope.of(sheet);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Block tags',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: ink(.94),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Posts with a blocked tag leave every feed.',
                  style: TextStyle(color: ink(.55)),
                ),
              ),
              for (final tag in post.tags)
                SwitchListTile(
                  title: Text('#$tag'),
                  value: state.blocklist.blocksTag(tag),
                  onChanged: (block) {
                    HapticFeedback.selectionClick();
                    block ? state.blockTag(tag) : state.unblockTag(tag);
                  },
                ),
            ],
          ),
        );
      },
    );

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
