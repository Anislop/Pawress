import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'comments.dart';
import 'downloads.dart';
import 'creator_page.dart';
import 'poll.dart';
import 'post_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// A single post: creator, full text, every image and video, other
/// attachments, tags and comments. Opened with a feed [post] (shown at once
/// while the full post loads) or with just its ids.
class PostPage extends StatefulWidget {
  PostPage({
    super.key,
    Post? post,
    String? service,
    String? creatorId,
    String? postId,
  }) : initial = post,
       service = post?.service ?? service!,
       creatorId = post?.user ?? creatorId!,
       postId = post?.id ?? postId!;

  final Post? initial;
  final String service;
  final String creatorId;
  final String postId;

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  Post? _post;
  String? _error;
  Future<List<Comment>>? _comments;
  final _commentsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final post = await api.post(
        widget.service,
        widget.creatorId,
        widget.postId,
      );
      if (mounted) {
        setState(() {
          _post = post;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _loadComments(Post post) => setState(() {
    _comments ??= AppScope.read(context).api
        .comments(post.service, post.user, post.id);
  });

  /// Loads the comments and scrolls down to them.
  void _showComments(Post post) {
    _loadComments(post);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _commentsKey.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Post',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (post != null && post.files.isNotEmpty)
            IconButton(
              tooltip: post.files.length == 1
                  ? 'Download file'
                  : 'Download all ${post.files.length} files',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => downloadFiles(context, post, post.files),
            ),
          if (post != null)
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.link_rounded),
              onPressed: () => copyLink(context, post.url),
            ),
          if (post != null)
            IconButton(
              tooltip: 'Open on Pawchive',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => openExternal(post.url),
            ),
        ],
      ),
      body: post == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : StatusView(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load this post',
                      body: _error,
                      action: 'Try again',
                      onAction: _load,
                    ),
            )
          : RefreshIndicator(onRefresh: _load, child: _body(post)),
    );
  }

  Widget _body(Post post) {
    final state = AppScope.of(context);
    final creator =
        state.directory.known(post.creatorKey) ??
        Creator(id: post.user, service: post.service, name: post.user);
    final media = post.media;
    final others = post.files.where((f) => !f.isViewable).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          leading: CreatorAvatar(creator, size: 44),
          title: Text(
            creator.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Row(
            children: [
              ServiceBadge(post.service, compact: true),
              const SizedBox(width: 6),
              Text(
                Service.of(post.service).label,
                style: TextStyle(color: ink(.55)),
              ),
            ],
          ),
          trailing: FollowButton(creator: creator, compact: true),
          onTap: () => openCreator(context, creator),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Holding the title or text selects it for copying.
              SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.title.isNotEmpty)
                      Text(
                        post.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (post.published != null)
                          'Published ${longDate(post.published)}',
                        if (post.added != null)
                          'archived ${longDate(post.added)}',
                      ].join(' · '),
                      style: TextStyle(color: ink(.5), fontSize: 13),
                    ),
                    if (plainText(post.content).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      HtmlContent(post.content),
                    ],
                  ],
                ),
              ),
              if (post.poll != null) ...[
                const SizedBox(height: 12),
                PollView(post.poll!),
              ],
              const SizedBox(height: 4),
              PostActions(post: post, onComments: () => _showComments(post)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final file in media) _MediaBlock(post: post, file: file),
        if (others.isNotEmpty) ...[
          const SectionLabel('Attachments'),
          for (final file in others)
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                file.extension.toUpperCase(),
                style: TextStyle(color: ink(.5)),
              ),
              trailing: IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download_rounded),
                onPressed: () => downloadFiles(context, post, [file]),
              ),
              onTap: file.fullUrl == null
                  ? null
                  : () => openExternal(file.fullUrl!),
            ),
        ],
        if (post.tags.isNotEmpty) ...[
          const SectionLabel('Tags'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in post.tags)
                  ActionChip(
                    label: Text('#$tag'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CreatorPage(creator: creator, initialTag: tag),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        SectionLabel('Comments', key: _commentsKey),
        _comments == null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _loadComments(post),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Load comments'),
                  ),
                ),
              )
            : CommentList(_comments!),
      ],
    );
  }
}

/// A full-width image or video tile; tapping opens the viewer.
class _MediaBlock extends StatelessWidget {
  const _MediaBlock({required this.post, required this.file});

  final Post post;
  final MediaFile file;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: GestureDetector(
      onTap: () => openViewer(context, post, file),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: file.thumbnailUrl != null
            ? Image(
                image: netImageProvider(file.thumbnailUrl!),
                fit: BoxFit.fitWidth,
                width: double.infinity,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : AspectRatio(
                        aspectRatio: 1,
                        child: ColoredBox(color: panel),
                      ),
                errorBuilder: (_, _, _) => AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(
                    color: panel,
                    child: Icon(Icons.broken_image_outlined, color: ink(.3)),
                  ),
                ),
              )
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: pawPlum,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 56,
                        color: pawPinkLight,
                      ),
                      const SizedBox(height: 8),
                      Text(file.name, style: TextStyle(color: ink(.7))),
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
}
