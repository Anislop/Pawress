import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/feeds.dart';
import '../core/models.dart';
import 'app_scope.dart';
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
/// links point at [base], or Pawchive.
class HtmlContent extends StatelessWidget {
  const HtmlContent(this.html, {super.key, this.fontSize = 15, this.base});

  /// Where the text's relative links point.
  final String? base;

  final String html;
  final double fontSize;

  @override
  Widget build(BuildContext context) => HtmlWidget(
    html,
    textStyle: TextStyle(fontSize: fontSize, height: 1.4, color: ink(.9)),
    customStylesBuilder: (element) => element.localName == 'a'
        ? {'color': isLight ? '#9E4A76' : '#E8B6D1'}
        : null,
    onTapUrl: (url) => openExternal(url, base: base),
  );
}

/// Picks the site whose popular posts, tags or random picks are shown.
/// Empty while only one provider is on.
class ProviderChips extends StatelessWidget {
  const ProviderChips({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.manyProviders) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Wrap(
        spacing: 8,
        children: [
          for (final provider in Provider.all)
            if (state.providerEnabled(provider))
              ChoiceChip(
                label: Text(provider.name),
                selected: provider == state.browse,
                onSelected: (_) => state.setBrowse(provider),
              ),
        ],
      ),
    );
  }
}

/// Opens [url] in the browser. A relative one is on [base], or Pawchive.
Future<bool> openExternal(String url, {String? base}) {
  final uri = Uri.tryParse(
    url.startsWith('/') ? '${base ?? Provider.pawchive.siteUrl}$url' : url,
  );
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
    _jumpNearTop(
      inner.positions.reduce((a, b) => a.pixels >= b.pixels ? a : b),
    );
  }
  final outer = nested.outerController;
  if (!outer.hasClients) return;
  outer.animateTo(0, duration: _toTop, curve: Curves.easeOutCubic);
}

/// [scrollNestedToTop] for a plain scroll view.
void scrollToTop(ScrollPosition position) {
  if (!position.hasPixels) return;
  _jumpNearTop(position);
  position.animateTo(0, duration: _toTop, curve: Curves.easeOutCubic);
}

const _toTop = Duration(milliseconds: 380);

void _jumpNearTop(ScrollPosition position) {
  final near = position.viewportDimension * 1.5;
  if (position.pixels > near) position.jumpTo(near);
}

/// An arrow over a vertical scroll view that shows once it's a couple of
/// screens down and takes it back to the top (header included inside a
/// [NestedScrollView]).
class BackToTop extends StatefulWidget {
  const BackToTop({super.key, required this.child});

  final Widget child;

  @override
  State<BackToTop> createState() => _BackToTopState();
}

class _BackToTopState extends State<BackToTop> {
  final _shown = ValueNotifier(false);
  ScrollPosition? _position;

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 || metrics.axis != Axis.vertical) {
      return false;
    }
    _position = notification.context
        ?.findAncestorStateOfType<ScrollableState>()
        ?.position;
    _shown.value = metrics.pixels > metrics.viewportDimension * 2;
    return false;
  }

  void _up() {
    _shown.value = false;
    final nested = context.findAncestorStateOfType<NestedScrollViewState>();
    if (nested != null) return scrollNestedToTop(nested);
    final position = _position;
    if (position != null) scrollToTop(position);
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
        child: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: _shown,
            builder: (context, shown, child) => IgnorePointer(
              ignoring: !shown,
              child: AnimatedScale(
                scale: shown ? 1 : .4,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: shown ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: child,
                ),
              ),
            ),
            child: Material(
              color: pawPink,
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _up,
                child: const Tooltip(
                  message: 'Back to top',
                  child: Padding(
                    padding: EdgeInsets.all(11),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      color: pawOutline,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
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

/// 512 B, 40 KB, 3.4 MB, 1.25 GB.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
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
/// Blocked and "not interested" posts are left out as they're marked, with
/// no reload.
class FeedView extends StatefulWidget {
  const FeedView({
    super.key,
    required this.feed,
    required this.itemBuilder,
    this.overlapHandle,
    this.empty,
    this.header,
    this.creatorKey,
    this.newSince,
  });

  final Feed feed;
  final Widget Function(BuildContext context, Post post) itemBuilder;
  final SliverOverlapAbsorberHandle? overlapHandle;

  /// Shown when the feed loaded and has no posts.
  final Widget? empty;

  /// A sliver above the posts, such as an active tag filter.
  final Widget? header;

  /// On this artist's profile, their posts show even when blocked.
  final String? creatorKey;

  /// Posts after this are new since the last visit; a line marks where
  /// they end.
  final DateTime? newSince;

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

  bool _isNew(Post post) {
    final since = widget.newSince;
    final date = post.date;
    return since != null && date != null && date.isAfter(since);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.feed,
    builder: (context, _) {
      final feed = widget.feed;
      final state = AppScope.of(context);
      final posts = [
        for (final post in feed.posts)
          if (!state.hides(post, creatorKey: widget.creatorKey)) post,
      ];
      // Hiding can leave too little to scroll, and loading more is
      // triggered by scrolling.
      if (posts.length < 6 &&
          posts.length < feed.posts.length &&
          !feed.done &&
          !feed.loading &&
          feed.error == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => feed.loadMore());
      }
      return BackToTop(
        child: RefreshIndicator(
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
                  itemCount: posts.length,
                  itemBuilder: (context, index) =>
                      widget.itemBuilder(context, posts[index]),
                  separatorBuilder: (_, index) =>
                      _isNew(posts[index]) && !_isNew(posts[index + 1])
                      ? const _CaughtUp()
                      : const Divider(),
                ),
                SliverToBoxAdapter(child: _footer(feed, posts.isEmpty)),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _footer(Feed feed, bool empty) {
    if (feed.error != null) {
      return StatusView(
        icon: Icons.cloud_off_rounded,
        title: empty ? 'Could not load posts' : 'Could not load more',
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
    if (feed.done && empty) {
      return widget.empty ??
          const StatusView(icon: Icons.inbox_outlined, title: 'No posts yet');
    }
    return const SizedBox(height: 96);
  }
}

/// Where the posts that are new since the last visit end.
class _CaughtUp extends StatelessWidget {
  const _CaughtUp();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Divider(color: pawPink.withValues(alpha: .5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: pawPink,
              ),
              const SizedBox(width: 6),
              Text(
                "You're caught up",
                style: TextStyle(
                  color: ink(.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: Divider(color: pawPink.withValues(alpha: .5))),
      ],
    ),
  );
}
