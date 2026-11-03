import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/feeds.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'community_page.dart';
import 'notify_bell.dart';
import 'post_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// An artist's profile: banner, original site, linked accounts and a Follow
/// button, then tabs for posts, announcements, tags, DMs, (Patreon only)
/// community chats and (Fanbox only) fancards.
class CreatorPage extends StatefulWidget {
  const CreatorPage({super.key, required this.creator, this.initialTag});

  final Creator creator;

  /// Opens with the posts filtered to this tag.
  final String? initialTag;

  @override
  State<CreatorPage> createState() => _CreatorPageState();
}

class _CreatorPageState extends State<CreatorPage>
    with SingleTickerProviderStateMixin {
  late Creator _creator = widget.creator;
  late String? _tag = widget.initialTag;
  late OffsetFeed _posts = _postFeed();
  late final TabController _tabs = TabController(
    length: _tabLabels.length,
    vsync: this,
  );
  Future<List<Creator>>? _links;

  /// The community's newest page, read with its channel list.
  CommunityPage? _community;

  List<String> get _tabLabels => [
    'Posts',
    'Announcements',
    'Tags',
    'DMs',
    if (widget.creator.service == 'patreon') 'Community',
    if (widget.creator.service == 'fanbox') 'Fancards',
  ];

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    final c = widget.creator;
    _links = state.api.links(c.service, c.id);
    _refreshProfile();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => state.markCreatorSeen(c.key),
    );
  }

  Future<void> _refreshProfile() async {
    final state = AppScope.read(context);
    try {
      final profile = await state.api.creator(_creator.service, _creator.id);
      state.directory.remember([profile]);
      if (mounted) setState(() => _creator = profile);
    } on ApiException {
      // Keep what we were given.
    }
  }

  OffsetFeed _postFeed() {
    final api = AppScope.read(context).api;
    final c = widget.creator;
    final tag = _tag;
    return OffsetFeed(
      (offset) => api.creatorPosts(c.service, c.id, offset: offset, tag: tag),
    );
  }

  void _filter(String? tag) {
    setState(() {
      _tag = tag;
      _posts.dispose();
      _posts = _postFeed();
    });
    _tabs.animateTo(0);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _posts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _creator;
    final tabBar = TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [for (final label in _tabLabels) Tab(text: label)],
    );
    // Banner, profile and tabs are one pinned app bar so the tab bodies can
    // inject its overlap; the profile has a fixed height for that reason.
    final expanded =
        _bannerHeight + _ProfileHeader.height + tabBar.preferredSize.height;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, scrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              pinned: true,
              forceElevated: scrolled,
              expandedHeight: expanded,
              backgroundColor: canvas,
              title: scrolled
                  ? Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )
                  : null,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Stack(
                  children: [
                    Column(
                      children: [
                        SizedBox(
                          // The app bar's area also covers the status bar.
                          height:
                              _bannerHeight + MediaQuery.paddingOf(context).top,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              NetImage(
                                c.bannerUrl,
                                fallback: const ColoredBox(color: pawPlum),
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black54,
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _ProfileHeader(creator: c, links: _links),
                      ],
                    ),
                    // The avatar overlaps the banner's bottom edge, like X.
                    Positioned(
                      left: 16,
                      top:
                          MediaQuery.paddingOf(context).top +
                          _bannerHeight -
                          40,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: canvas, width: 4),
                        ),
                        child: CreatorAvatar(c, size: 80),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (value) => openExternal(value),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: c.originalUrl,
                      child: Text('Open on ${c.site.label}'),
                    ),
                    PopupMenuItem(
                      value: c.pawchiveUrl,
                      child: const Text('Open on Pawchive'),
                    ),
                  ],
                ),
              ],
              bottom: PreferredSize(
                preferredSize: tabBar.preferredSize,
                child: ColoredBox(color: canvas, child: tabBar),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            Builder(
              builder: (context) => FeedView(
                key: ValueKey(_posts),
                feed: _posts,
                overlapHandle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
                itemBuilder: (context, post) => PostCard(post),
                header: _tag == null
                    ? null
                    : SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: InputChip(
                              label: Text('#$_tag'),
                              onDeleted: () => _filter(null),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            _FutureList<Announcement>(
              load: () =>
                  AppScope.read(context).api.announcements(c.service, c.id),
              empty: 'No announcements',
              itemBuilder: (item) =>
                  _TextCard(html: item.content, footer: longDate(item.added)),
            ),
            _FutureList<CreatorTag>(
              load: () => AppScope.read(context).api.tags(c.service, c.id),
              empty: 'No tags',
              wrap: true,
              itemBuilder: (item) => ActionChip(
                label: Text('#${item.tag}  ${item.postCount}'),
                onPressed: () => _filter(item.tag),
              ),
            ),
            _FutureList<DirectMessage>(
              load: () =>
                  AppScope.read(context).api.directMessages(c.service, c.id),
              empty: 'No DMs archived',
              itemBuilder: (item) => _TextCard(
                html: item.content,
                footer: item.added == null ? '' : 'Added ${item.added}',
              ),
            ),
            if (c.service == 'patreon')
              _FutureList<CommunityChannel>(
                load: () async {
                  final page = await AppScope.read(context).api
                      .community(c.service, c.id);
                  _community = page;
                  return page.channels;
                },
                empty: 'No community archived',
                itemBuilder: (channel) => ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                  leading: const Icon(Icons.tag_rounded, color: pawPink),
                  title: Text(
                    channel.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    channel.count == 1
                        ? '1 message'
                        : '${compactCount(channel.count)} messages',
                    style: TextStyle(color: ink(.5)),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CommunityChatPage(
                        creator: c,
                        channel: channel,
                        initial: channel.active ? _community : null,
                      ),
                    ),
                  ),
                ),
              ),
            if (c.service == 'fanbox')
              _FutureList<Fancard>(
                load: () =>
                    AppScope.read(context).api.fancards(c.service, c.id),
                empty: 'No fancards',
                itemBuilder: (item) => _FancardTile(item),
              ),
          ],
        ),
      ),
    );
  }
}

/// A supporter card: the plan's card art with its price and date.
class _FancardTile extends StatelessWidget {
  const _FancardTile(this.fancard);

  final Fancard fancard;

  @override
  Widget build(BuildContext context) {
    final f = fancard;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: NetImage(
              f.file.thumbnailUrl ?? '',
              fit: BoxFit.fitWidth,
              width: double.infinity,
              placeholder: AspectRatio(
                aspectRatio: 1.6,
                child: ColoredBox(color: panel),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (f.price != null) '¥${f.price} plan',
              if (f.added != null) 'added ${longDate(f.added)}',
            ].join(' · '),
            style: TextStyle(color: ink(.55), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

const _bannerHeight = 120.0;

/// Avatar, name, site and linked accounts in a fixed [height]; rows that
/// could grow scroll sideways instead.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.creator, required this.links});

  final Creator creator;
  final Future<List<Creator>>? links;

  static const height = 192.0;

  @override
  Widget build(BuildContext context) {
    final c = creator;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room for the avatar, which the page draws over the banner.
            SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton.outlined(
                    tooltip: 'Similar artists',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showSimilarCreators(context, c),
                    icon: const Icon(Icons.group_add_outlined, size: 20),
                  ),
                  const SizedBox(width: 8),
                  if (AppScope.of(context).isFollowing(c.key)) ...[
                    NotifyBell(creator: c),
                    const SizedBox(width: 8),
                  ],
                  FollowButton(creator: c),
                ],
              ),
            ),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Text(
              c.publicId != null && c.publicId != c.name
                  ? '@${c.publicId}'
                  : 'on ${c.site.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink(.55)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 26,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => openExternal(c.originalUrl),
                    child: ServiceBadge(c.service),
                  ),
                  if (c.favorited > 0)
                    _Stat(Icons.favorite_rounded, '${c.favorited} favorites'),
                  if (c.updated != null)
                    _Stat(
                      Icons.update_rounded,
                      'Updated ${longDate(c.updated)}',
                    ),
                  if (c.indexed != null)
                    _Stat(
                      Icons.inventory_2_outlined,
                      'Since ${longDate(c.indexed)}',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: FutureBuilder<List<Creator>>(
                future: links,
                builder: (context, snapshot) {
                  final list = snapshot.data ?? const [];
                  if (list.isEmpty) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No linked accounts',
                        style: TextStyle(color: ink(.35), fontSize: 13),
                      ),
                    );
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: ServiceBadge(list[index].service, compact: true),
                      label: Text(list[index].name),
                      onPressed: () => openCreator(context, list[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(width: 12),
      Icon(icon, size: 15, color: ink(.5)),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(color: ink(.6), fontSize: 13)),
    ],
  );
}

/// Pawchive's "similar artists" for [creator], in a bottom sheet.
Future<void> showSimilarCreators(BuildContext context, Creator creator) {
  final similar = AppScope.read(context).api
      .recommendedCreators(creator.service, creator.id);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      minChildSize: .3,
      maxChildSize: 1,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Similar to ${creator.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Creator>>(
              future: similar,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return StatusView(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load similar artists',
                    body: snapshot.error.toString(),
                  );
                }
                final list = snapshot.data;
                if (list == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (list.isEmpty) {
                  return const StatusView(
                    icon: Icons.group_outlined,
                    title: 'No similar artists yet',
                  );
                }
                return ListView.separated(
                  controller: scroll,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) => ArtistTile(list[index]),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// Follow / Following, like X's profile button.
class FollowButton extends StatelessWidget {
  const FollowButton({super.key, required this.creator, this.compact = false});

  final Creator creator;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final following = state.isFollowing(creator.key);
    final padding = EdgeInsets.symmetric(horizontal: compact ? 14 : 20);
    if (!following) {
      return FilledButton(
        style: FilledButton.styleFrom(
          padding: padding,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => state.follow(creator),
        child: const Text('Follow'),
      );
    }
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: padding,
        visualDensity: VisualDensity.compact,
        foregroundColor: ink(.94),
        side: BorderSide(color: ink(.35)),
      ),
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Unfollow ${creator.name}?'),
            content: const Text(
              'Their posts will no longer show in Following and you will stop getting notifications.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Unfollow'),
              ),
            ],
          ),
        );
        if (confirmed == true) await state.unfollow(creator);
      },
      child: const Text('Following'),
    );
  }
}

/// A tab loaded once from the API.
class _FutureList<T> extends StatefulWidget {
  const _FutureList({
    required this.load,
    required this.itemBuilder,
    required this.empty,
    this.wrap = false,
  });

  final Future<List<T>> Function() load;
  final Widget Function(T item) itemBuilder;
  final String empty;

  /// Lays items out as wrapping chips instead of rows.
  final bool wrap;

  @override
  State<_FutureList<T>> createState() => _FutureListState<T>();
}

class _FutureListState<T> extends State<_FutureList<T>>
    with AutomaticKeepAliveClientMixin {
  late Future<List<T>> _future = widget.load();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.hasError) {
          child = StatusView(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load',
            body: '${snapshot.error}',
            action: 'Try again',
            onAction: () => setState(() => _future = widget.load()),
          );
        } else if (snapshot.data == null) {
          child = const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.data!.isEmpty) {
          child = StatusView(icon: Icons.inbox_outlined, title: widget.empty);
        } else if (widget.wrap) {
          child = Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in snapshot.data!) widget.itemBuilder(item),
              ],
            ),
          );
        } else {
          child = Column(
            children: [
              for (final item in snapshot.data!) widget.itemBuilder(item),
            ],
          );
        }
        return CustomScrollView(
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverToBoxAdapter(child: child),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        );
      },
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({required this.html, required this.footer});

  final String html;
  final String footer;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HtmlContent(html),
        if (footer.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(footer, style: TextStyle(color: ink(.5), fontSize: 12)),
        ],
      ],
    ),
  );
}

/// A creator row with site, favorites and a compact Follow button.
class ArtistTile extends StatelessWidget {
  const ArtistTile(this.creator, {super.key, this.rank});

  final Creator creator;

  /// A position shown before the avatar, as in a ranking.
  final int? rank;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
    leading: rank == null
        ? CreatorAvatar(creator, size: 44)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: rank! <= 3 ? pawPink : ink(.5),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              CreatorAvatar(creator, size: 44),
            ],
          ),
    title: Text(
      creator.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    subtitle: Row(
      children: [
        ServiceBadge(creator.service, compact: true),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            creator.favorited > 0
                ? '${creator.site.label} · ${compactCount(creator.favorited)} favorites'
                : creator.site.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ink(.5)),
          ),
        ),
      ],
    ),
    trailing: FollowButton(creator: creator, compact: true),
    onTap: () => openCreator(context, creator),
  );
}
