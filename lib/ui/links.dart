import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'creator_page.dart';
import 'post_page.dart';
import 'tag_page.dart';
import 'widgets.dart';

/// Opens a provider's link (or shared text holding one) in the app: a post,
/// an artist, or posts with a tag. Anything else is offered to the browser.
void openPawchiveLink(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.of(context);
  final url = PawchiveLink.findUrl(text);
  if (url == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Pawress cannot open that link.')),
    );
    return;
  }
  final link = PawchiveLink.tryParse(url.path);
  final navigator = Navigator.of(context);
  void push(Widget page) =>
      navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  if (link?.post case final post?) {
    return push(
      PostPage(service: link!.service, creatorId: link.user, postId: post),
    );
  }
  if (link != null) {
    final known = AppScope.read(context).directory
        .known('${link.service}/${link.user}');
    return push(
      CreatorPage(
        creator:
            known ??
            Creator(id: link.user, service: link.service, name: link.user),
      ),
    );
  }
  final tag = url.queryParameters['tag'];
  if (url.path == '/posts' && tag != null && tag.isNotEmpty) {
    return push(TagPostsPage(tag: tag, provider: Provider.atHost(url.host)));
  }
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Pawress cannot open this page.'),
      action: SnackBarAction(
        label: 'Browser',
        onPressed: () => openExternal(url.toString()),
      ),
    ),
  );
}
