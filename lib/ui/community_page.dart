import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// A Patreon community chat as a log, newest at the bottom like Discord.
/// The site pages it 25 messages at a time from the newest, so scrolling up
/// loads older pages.
class CommunityChatPage extends StatefulWidget {
  const CommunityChatPage({
    super.key,
    required this.creator,
    required this.channel,
    this.initial,
  });

  final Creator creator;
  final CommunityChannel channel;

  /// The newest page when the caller already loaded it.
  final CommunityPage? initial;

  @override
  State<CommunityChatPage> createState() => _CommunityChatPageState();
}

class _CommunityChatPageState extends State<CommunityChatPage> {
  /// Oldest first, as the site lists them.
  final _messages = <CommunityMessage>[];
  int _offset = 0;
  bool _hasOlder = true;
  bool _loading = false;
  String? _error;

  static const _pageSize = 25;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _add(initial);
    } else {
      _loadOlder();
    }
  }

  void _add(CommunityPage page) {
    _messages.insertAll(0, page.messages);
    _offset += _pageSize;
    _hasOlder = page.hasOlder && page.messages.isNotEmpty;
  }

  Future<void> _loadOlder() async {
    if (_loading || !_hasOlder) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = widget.creator;
      final page = await AppScope.read(context).api.community(
        c.service,
        c.id,
        channel: widget.channel.id,
        offset: _offset,
      );
      if (mounted) setState(() => _add(page));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    // The list is reversed, so the older end is "after".
    if (notification.metrics.extentAfter < 800) _loadOlder();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final count = _messages.length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '# ${widget.channel.name}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              widget.creator.name,
              style: TextStyle(fontSize: 12, color: ink(.5)),
            ),
          ],
        ),
      ),
      body: count == 0 && !_hasOlder
          ? const Center(
              child: StatusView(
                icon: Icons.forum_outlined,
                title: 'No messages archived',
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                itemCount: count + 1,
                itemBuilder: (context, index) {
                  if (index == count) return _top();
                  // Index 0 is the newest message, at the bottom.
                  final message = _messages[count - 1 - index];
                  return _MessageRow(message);
                },
              ),
            ),
    );
  }

  Widget _top() {
    if (_error != null) {
      return StatusView(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load messages',
        body: _error,
        action: 'Try again',
        onAction: _loadOlder,
      );
    }
    if (_hasOlder) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        'The start of #${widget.channel.name}',
        style: TextStyle(color: ink(.45), fontSize: 13),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow(this.message);

  final CommunityMessage message;

  static const _avatar = 38.0;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (m.content.isNotEmpty) HtmlContent(m.content, fontSize: 14.5),
        for (final image in m.images)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ImageScreen(image.url),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 280,
                    maxHeight: 320,
                  ),
                  child: NetImage(image.thumbnail, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        for (final embed in m.embeds)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              onTap: () => openExternal(embed.url),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: pawPink, width: 3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_rounded, size: 18, color: ink(.6)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        embed.title.isEmpty ? embed.url : embed.title,
                        style: const TextStyle(color: pawPinkLight),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    if (m.continued) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16 + _avatar + 12, 1, 16, 1),
        child: text,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.replyAuthor != null)
            Padding(
              padding: const EdgeInsets.only(left: 18, bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 15,
                    color: ink(.4),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    m.replyAuthor!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ink(.6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m.replyText ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: ink(.5)),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(message: m, size: _avatar),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          m.author.isEmpty ? 'Unknown' : m.author,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: m.fromCreator ? pawPinkLight : ink(.94),
                          ),
                        ),
                        if (m.fromCreator)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: pawPink,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'CREATOR',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: pawOutline,
                              ),
                            ),
                          ),
                        Text(
                          longDate(m.time),
                          style: TextStyle(fontSize: 12, color: ink(.45)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    text,
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.message, required this.size});

  final CommunityMessage message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HSLColor.fromAHSL(
          1,
          (message.avatarHue ?? 320).toDouble() % 360,
          .42,
          .48,
        ).toColor(),
      ),
      child: Text(
        message.avatarLetter ??
            (message.author.isEmpty ? '?' : message.author[0].toUpperCase()),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
    final url = message.avatarUrl;
    if (url == null) return letter;
    return ClipOval(
      child: NetImage(url, width: size, height: size, fallback: letter),
    );
  }
}

/// A chat image at full size, with pinch to zoom.
class _ImageScreen extends StatelessWidget {
  const _ImageScreen(this.url);

  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black),
    body: InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: Image(
          image: netImageProvider(url),
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 40,
          ),
        ),
      ),
    ),
  );
}
