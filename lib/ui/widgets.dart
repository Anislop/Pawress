import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/feeds.dart';
import '../core/models.dart';
import 'theme.dart';

/// A network image sent with the app's user agent, which Pawchive requires.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallback,
    this.placeholder,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallback;

  /// Shown while loading instead of a plain panel.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: url,
    httpHeaders: mediaHeaders,
    fit: fit,
    width: width,
    height: height,
    fadeInDuration: const Duration(milliseconds: 150),
    placeholder: (_, _) => placeholder ?? ColoredBox(color: panel),
    errorWidget: (_, _, _) =>
        fallback ??
        ColoredBox(
          color: panel,
          child: Icon(Icons.broken_image_outlined, color: ink(.3)),
        ),
  );
}

ImageProvider netImageProvider(String url) =>
    CachedNetworkImageProvider(url, headers: mediaHeaders);

class CreatorAvatar extends StatelessWidget {
  const CreatorAvatar(this.creator, {super.key, this.size = 40});

  final Creator creator;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: size,
      child: NetImage(
        creator.iconUrl,
        fallback: ColoredBox(
          color: pawPlum,
          child: Center(
            child: Text(
              creator.name.isEmpty ? '?' : creator.name.characters.first,
              style: TextStyle(
                color: pawPinkLight,
                fontWeight: FontWeight.w700,
                fontSize: size * .42,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The original site's icon and, unless [compact], its name.
class ServiceBadge extends StatelessWidget {
  const ServiceBadge(this.service, {super.key, this.compact = false});

  final String service;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final site = Service.of(service);
    final icon = ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.network(
        site.iconUrl,
        headers: mediaHeaders,
        width: 14,
        height: 14,
        errorBuilder: (_, _, _) =>
            Icon(Icons.public, size: 14, color: Color(site.color)),
      ),
    );
    if (compact) return icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Color(site.color).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(site.color).withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(
            site.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ink(.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// Post, announcement and DM bodies. Links open outside the app; relative
/// links point at Pawchive.
class HtmlContent extends StatelessWidget {
  const HtmlContent(this.html, {super.key, this.fontSize = 15});

  final String html;
  final double fontSize;

  @override
  Widget build(BuildContext context) => HtmlWidget(
    html,
    textStyle: TextStyle(fontSize: fontSize, height: 1.4, color: ink(.9)),
    customStylesBuilder: (element) =>
        element.localName == 'a' ? {'color': '#E8B6D1'} : null,
    onTapUrl: (url) => openExternal(url),
  );
}

Future<bool> openExternal(String url) {
  final uri = Uri.tryParse(url.startsWith('/') ? '$siteUrl$url' : url);
  if (uri == null) return Future.value(false);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Copies [url] to the clipboard and says so.
Future<void> copyLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: url));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Link copied')));
}

/// Scrolls a [NestedScrollView] back to the top with its header showing,
/// as tapping X's current tab does. NestedScrollView moves its inner lists
/// together, so every tab returns to the top. From far down it jumps close
/// first, so the animation doesn't build (and load images for) every row in
/// between.
void scrollNestedToTop(NestedScrollViewState? nested) {
  if (nested == null) return;
  final inner = nested.innerController;
  if (inner.hasClients) {
    final position = inner.positions.reduce(
      (a, b) => a.pixels >= b.pixels ? a : b,
    );
    final near = position.viewportDimension * 1.5;
    if (position.pixels > near) position.jumpTo(near);
  }
  final outer = nested.outerController;
  if (!outer.hasClients) return;
  outer.animateTo(
    0,
    duration: const Duration(milliseconds: 380),
    curve: Curves.easeOutCubic,
  );
}

/// 950, 1.2K, 34K, 1.5M.
String compactCount(int count) {
  if (count < 1000) return '$count';
  if (count < 1000000) {
    final k = count / 1000;
    return '${k < 10 ? k.toStringAsFixed(1).replaceFirst('.0', '') : k.round()}K';
  }
  final m = count / 1000000;
  return '${m < 10 ? m.toStringAsFixed(1).replaceFirst('.0', '') : m.round()}M';
}

String shortTime(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final age = DateTime.now().difference(local);
  if (age.inMinutes < 1) return 'now';
  if (age.inHours < 1) return '${age.inMinutes}m';
  if (age.inDays < 1) return '${age.inHours}h';
  if (age.inDays < 7) return '${age.inDays}d';
  return longDate(local);
}

String longDate(DateTime? time) {
  if (time == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = time.toLocal();
  final year = local.year == DateTime.now().year ? '' : ', ${local.year}';
  return '${months[local.month - 1]} ${local.day}$year';
}

/// HTML reduced to plain text for previews.
String plainText(String html) => decodeEntities(
  html
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      // The recent feed's `substring` can end partway through a tag.
      .replaceAll(RegExp(r'<[^>]*$'), ''),
).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

/// Centered message for empty, loading and failed states.
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: pawPink),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: TextStyle(color: ink(.6), height: 1.4),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

/// A [Feed] as an endless, pull-to-refresh list. Inside a [NestedScrollView]
/// pass its [overlapHandle] so the list starts below the collapsing header.
class FeedView extends StatefulWidget {
  const FeedView({
    super.key,
    required this.feed,
    required this.itemBuilder,
    this.overlapHandle,
    this.empty,
    this.header,
  });

  final Feed feed;
  final Widget Function(BuildContext context, Post post) itemBuilder;
  final SliverOverlapAbsorberHandle? overlapHandle;

  /// Shown when the feed loaded and has no posts.
  final Widget? empty;

  /// A sliver above the posts, such as an active tag filter.
  final Widget? header;

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  @override
  void initState() {
    super.initState();
    final feed = widget.feed;
    if (feed.posts.isEmpty && !feed.loading && !feed.done) feed.refresh();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 1200) widget.feed.loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.feed,
    builder: (context, _) {
      final feed = widget.feed;
      return RefreshIndicator(
        onRefresh: feed.refresh,
        edgeOffset: widget.overlapHandle == null ? 0 : 100,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            key: PageStorageKey(feed),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (widget.overlapHandle != null)
                SliverOverlapInjector(handle: widget.overlapHandle!),
              ?widget.header,
              SliverList.separated(
                itemCount: feed.posts.length,
                itemBuilder: (context, index) =>
                    widget.itemBuilder(context, feed.posts[index]),
                separatorBuilder: (_, _) => const Divider(),
              ),
              SliverToBoxAdapter(child: _footer(feed)),
            ],
          ),
        ),
      );
    },
  );

  Widget _footer(Feed feed) {
    if (feed.error != null) {
      return StatusView(
        icon: Icons.cloud_off_rounded,
        title: feed.posts.isEmpty
            ? 'Could not load posts'
            : 'Could not load more',
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
    if (feed.done && feed.posts.isEmpty) {
      return widget.empty ??
          const StatusView(icon: Icons.inbox_outlined, title: 'No posts yet');
    }
    return const SizedBox(height: 96);
  }
}
