import 'package:flutter/material.dart';

import '../core/models.dart';
import 'app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens [post]'s comments in a draggable sheet over the current page.
Future<void> showComments(BuildContext context, Post post) {
  final comments = AppScope.read(context).api
      .comments(post.service, post.user, post.id);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: canvas,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      minChildSize: .4,
      maxChildSize: 1,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              post.title.isEmpty ? 'Comments' : 'Comments on ${post.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          CommentList(comments),
        ],
      ),
    ),
  );
}

/// A post's comments as threads, every row aligned to the left edge with
/// replies indented under their parent.
class CommentList extends StatelessWidget {
  const CommentList(this.comments, {super.key});

  final Future<List<Comment>> comments;

  /// Deeper replies stay at this indent so long threads keep their width.
  static const _maxDepth = 4;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Comment>>(
    future: comments,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${snapshot.error}', style: TextStyle(color: ink(.6))),
        );
      }
      final list = snapshot.data;
      if (list == null) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (list.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No comments.', style: TextStyle(color: ink(.5))),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (:comment, :depth) in threadComments(list))
            _CommentRow(comment: comment, depth: depth.clamp(0, _maxDepth)),
        ],
      );
    },
  );
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.depth});

  final Comment comment;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: comment.commenter,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: '  ·  ${shortTime(comment.published)}',
                style: TextStyle(color: ink(.5)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        HtmlContent(comment.content, fontSize: 14),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(depth < 2 ? 16 : 16.0 * depth, 6, 16, 6),
      child: depth == 0
          ? body
          : Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: hairline, width: 2)),
              ),
              child: body,
            ),
    );
  }
}
