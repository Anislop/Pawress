import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/feeds.dart';
import '../core/for_you.dart';
import '../core/intents.dart';
import '../core/models.dart';
import '../core/updates.dart';
import 'app_scope.dart';
import 'creator_page.dart';
import 'update_dialog.dart';
import 'downloads.dart';
import 'favorites_page.dart';
import 'following_page.dart';
import 'hash_lookup_page.dart';
import 'history_page.dart';
import 'links.dart';
import 'login_page.dart';
import 'notifications_page.dart';
import 'popular.dart';
import 'post_card.dart';
import 'random_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// The main screen, laid out like X on Android: a top bar that hides while
/// scrolling down, the For You / Following / Popular tabs, and a sidebar
/// opened from the account avatar or by swiping right on the first tab. A
/// bottom bar appears only on Popular, to switch between artists and posts.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _followingTab = 1;
  static const _popularTab = 2;

  final _scaffold = GlobalKey<ScaffoldState>();
  final _nested = GlobalKey<NestedScrollViewState>();
  bool _drawerOpen = false;
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTab);
  int _tab = 0;
  PopularSection _section = PopularSection.artists;
  late final ForYouFeed _forYou;
  late final FollowingFeed _following;
  StreamSubscription<String>? _taps;
  StreamSubscription<String>? _links;
  String _followSignature = '';

  /// Looks for notices the background check wrote while the app is open.
  Timer? _poll;
  static const _pollInterval = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    _forYou = ForYouFeed(state.api, state.forYouSignals);
    _following = FollowingFeed(state.api, () => state.follows);
    _followSignature = _signature();
    state.addListener(_onState);
    WidgetsBinding.instance.addObserver(this);
    _taps = Notifier.taps.stream.listen(_openFromNotification);
    Notifier.launchPayload().then((key) {
      if (key != null) _openFromNotification(key);
    });
    _links = AndroidIntents.links.stream.listen(_openLink);
    AndroidIntents.initialLink().then((text) {
      if (text != null) _openLink(text);
    });
    unawaited(_checkForUpdate());
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(
      _pollInterval,
      (_) => AppScope.read(context).pollNotices(),
    );
  }

  /// Looks for a newer release once per launch, unless turned off in
  /// Settings. Failures (offline, rate limited) wait for the next launch.
  Future<void> _checkForUpdate() async {
    final state = AppScope.read(context);
    if (!state.settings.checkUpdates) return;
    try {
      final release = await state.updater.check();
      // The setting may have been turned off while the check ran.
      if (release == null || !mounted || !state.settings.checkUpdates) return;
      await showUpdateDialog(context, updater: state.updater, release: release);
    } catch (_) {}
  }

  @override
  void dispose() {
    AppScope.read(context).removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    _taps?.cancel();
    _links?.cancel();
    _poll?.cancel();
    _tabs.dispose();
    _forYou.dispose();
    _following.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The background check may have found posts while the app was away.
    if (state == AppLifecycleState.resumed) {
      AppScope.read(context).reload(alert: true);
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      if (_tab == _followingTab) _markFollowingSeen();
    }
  }

  void _onTab() {
    if (_tabs.index == _tab) return;
    if (_tab == _followingTab) _markFollowingSeen();
    setState(() => _tab = _tabs.index);
  }

  /// Leaving Following moves its "caught up" line to the newest post there.
  void _markFollowingSeen() {
    final newest = _following.posts.firstOrNull?.date;
    if (newest != null) AppScope.read(context).markFollowingSeen(newest);
  }

  void _openLink(String text) {
    if (mounted) openPawchiveLink(context, text);
  }

  void _scrollToTop() {
    HapticFeedback.selectionClick();
    scrollNestedToTop(_nested.currentState);
  }

  /// Tapping the tab that's already open scrolls it back to the top.
  void _onTabTap(int index) {
    if (index == _tabs.index && !_tabs.indexIsChanging) _scrollToTop();
  }

  void _onSection(int index) {
    final section = PopularSection.values[index];
    if (section == _section) return _scrollToTop();
    HapticFeedback.selectionClick();
    setState(() => _section = section);
  }

  /// Swiping right past the first tab opens the sidebar, as in X.
  bool _onOverscroll(OverscrollNotification notification) {
    if (notification.metrics.axis == Axis.horizontal &&
        notification.overscroll < 0 &&
        notification.dragDetails != null &&
        _tabs.index == 0 &&
        !(_scaffold.currentState?.isDrawerOpen ?? true)) {
      _scaffold.currentState!.openDrawer();
    }
    return false;
  }

  String _signature() =>
      AppScope.read(context).follows.map((f) => f.key).join(',');

  void _onState() {
    final state = AppScope.read(context);
    final message = state.takeMessage();
    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    final alert = state.takeAlert();
    if (alert != null && mounted) _showAlert(alert);
    final signature = _signature();
    if (signature != _followSignature) {
      _followSignature = signature;
      if (_following.posts.isNotEmpty || _following.done) _following.refresh();
    }
  }

  /// An in-app banner for new posts, X style: the artist, what they posted
  /// and a way to see it.
  void _showAlert(List<UpdateNotice> notices) {
    final first = notices.first;
    final creators = {for (final notice in notices) notice.creator.key};
    final title = creators.length > 1
        ? '${notices.length} new posts from artists you follow'
        : notices.length == 1
        ? 'New post from ${first.creator.name}'
        : '${notices.length} new posts from ${first.creator.name}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            CreatorAvatar(first.creator, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (notices.length == 1 && first.postTitle.isNotEmpty)
                    Text(
                      first.postTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => creators.length == 1
              ? _openFromNotification(first.creator.key)
              : _push((_) => const NotificationsPage()),
        ),
      ),
    );
  }

  void _openFromNotification(String key) {
    if (!mounted) return;
    if (key == Notifier.downloadsPayload) {
      _push((_) => const DownloadsPage());
      return;
    }
    final follow = AppScope.read(context).followOf(key);
    if (follow == null) {
      _push((_) => const NotificationsPage());
      return;
    }
    _push((_) => CreatorPage(creator: follow.creator));
  }

  void _push(WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

  /// Back on Following or Popular returns to For You before leaving the
  /// app, as in X.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _tab == 0 || _drawerOpen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _tabs.animateTo(0);
    },
    child: _scaffoldView(context),
  );

  Widget _scaffoldView(BuildContext context) => Scaffold(
    key: _scaffold,
    drawer: Sidebar(onOpen: _push),
    onDrawerChanged: (open) => setState(() => _drawerOpen = open),
    bottomNavigationBar: AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _tab == _popularTab
          ? NavigationBar(
              height: 64,
              selectedIndex: _section.index,
              onDestinationSelected: _onSection,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.people_outline_rounded),
                  selectedIcon: Icon(Icons.people_rounded),
                  label: 'Artists',
                ),
                NavigationDestination(
                  icon: Icon(Icons.local_fire_department_outlined),
                  selectedIcon: Icon(Icons.local_fire_department_rounded),
                  label: 'Posts',
                ),
              ],
            )
          : const SizedBox(width: double.infinity),
    ),
    body: NestedScrollView(
      key: _nested,
      floatHeaderSlivers: true,
      headerSliverBuilder: (context, scrolled) => [
        SliverOverlapAbsorber(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          sliver: SliverAppBar(
            floating: true,
            snap: true,
            forceElevated: scrolled,
            centerTitle: true,
            leading: Builder(
              builder: (context) => IconButton(
                tooltip: 'Open menu',
                onPressed: () => _scaffold.currentState!.openDrawer(),
                icon: const _AccountAvatar(size: 32),
              ),
            ),
            title: GestureDetector(
              onTap: _scrollToTop,
              child: Image.asset(logoAsset, height: 26),
            ),
            actions: [
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => _push((_) => const SearchPage()),
              ),
              const _BellButton(),
            ],
            bottom: TabBar(
              controller: _tabs,
              onTap: _onTabTap,
              tabs: const [
                Tab(text: 'For You'),
                Tab(text: 'Following'),
                Tab(text: 'Popular'),
              ],
            ),
          ),
        ),
      ],
      body: NotificationListener<OverscrollNotification>(
        onNotification: _onOverscroll,
        child: TabBarView(
          controller: _tabs,
          children: [
            _Tab(
              feed: _forYou,
              empty: const StatusView(
                icon: Icons.auto_awesome_rounded,
                title: 'Nothing here yet',
                body: 'Pull down to refresh.',
              ),
            ),
            _Tab(
              feed: _following,
              marksNew: true,
              empty: StatusView(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Follow artists to fill this tab',
                body: 'Open an artist from For You or search, then tap Follow.',
                action: 'Find artists',
                onAction: () => _push((_) => const SearchPage()),
              ),
            ),
            PopularTab(section: _section),
          ],
        ),
      ),
    ),
  );
}

class _Tab extends StatefulWidget {
  const _Tab({required this.feed, required this.empty, this.marksNew = false});

  final Feed feed;
  final Widget empty;

  /// Draws the "caught up" line at [AppState.followingSeenAt].
  final bool marksNew;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = AppScope.of(context);
    if (widget.feed is FollowingFeed && state.follows.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverToBoxAdapter(child: widget.empty),
        ],
      );
    }
    return FeedView(
      feed: widget.feed,
      overlapHandle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      itemBuilder: (context, post) => PostCard(post),
      empty: widget.empty,
      newSince: widget.marksNew ? state.followingSeenAt : null,
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton();

  @override
  Widget build(BuildContext context) {
    final unread = AppScope.of(context).unreadNotices;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
      ),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: pawPink,
        textColor: pawOutline,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

/// The account's initial when signed in, otherwise the paw icon.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final name = AppScope.of(context).accountName;
    if (name == null || name.isEmpty) return BrandMark(size: size);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: pawPink,
      child: Text(
        name.characters.first.toUpperCase(),
        style: TextStyle(
          color: pawOutline,
          fontWeight: FontWeight.w800,
          fontSize: size * .45,
        ),
      ),
    );
  }
}

/// X-style navigation drawer: account header with counts, then Following,
/// Notifications and Settings.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.onOpen});

  final void Function(WidgetBuilder builder) onOpen;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    void open(WidgetBuilder builder) {
      Navigator.of(context).pop();
      onOpen(builder);
    }

    // Scrolls on short screens; the logo stays at the bottom otherwise.
    return Drawer(
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _AccountAvatar(size: 44),
                        const SizedBox(height: 12),
                        Text(
                          state.signedIn
                              ? (state.accountName ?? 'Pawchive account')
                              : 'Guest',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          state.signedIn
                              ? 'Signed in to Pawchive'
                              : 'Follows are saved on this device',
                          style: TextStyle(color: ink(.5)),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => open((_) => const FollowingPage()),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${state.follows.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                TextSpan(
                                  text: ' Following',
                                  style: TextStyle(color: ink(.55)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  _SidebarItem(
                    icon: Icons.person_outline_rounded,
                    label: state.signedIn ? 'Account' : 'Sign in',
                    onTap: () => state.signedIn
                        ? open((_) => const SettingsPage())
                        : open((_) => const LoginPage()),
                  ),
                  _SidebarItem(
                    icon: Icons.people_outline_rounded,
                    label: 'Following',
                    onTap: () => open((_) => const FollowingPage()),
                  ),
                  _SidebarItem(
                    icon: Icons.favorite_border_rounded,
                    label: 'Favorites',
                    onTap: () => open((_) => const FavoritesPage()),
                  ),
                  _SidebarItem(
                    icon: Icons.history_rounded,
                    label: 'History',
                    onTap: () => open((_) => const HistoryPage()),
                  ),
                  _SidebarItem(
                    icon: Icons.notifications_none_rounded,
                    label: 'Notifications',
                    badge: state.unreadNotices,
                    onTap: () => open((_) => const NotificationsPage()),
                  ),
                  _SidebarItem(
                    icon: Icons.search_rounded,
                    label: 'Explore',
                    onTap: () => open((_) => const SearchPage()),
                  ),
                  _SidebarItem(
                    icon: Icons.shuffle_rounded,
                    label: 'Random',
                    onTap: () => open((_) => const RandomPage()),
                  ),
                  _SidebarItem(
                    icon: Icons.fingerprint_rounded,
                    label: 'Hash lookup',
                    onTap: () => open((_) => const HashLookupPage()),
                  ),
                  ListenableBuilder(
                    listenable: state.downloads,
                    builder: (context, _) => _SidebarItem(
                      icon: Icons.download_rounded,
                      label: 'Downloads',
                      badge: state.downloads.active,
                      onTap: () => open((_) => const DownloadsPage()),
                    ),
                  ),
                  const Divider(),
                  _SidebarItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => open((_) => const SettingsPage()),
                  ),
                ],
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Image.asset(logoAsset, height: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    leading: Icon(icon, size: 26),
    title: Text(
      label,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
    ),
    trailing: badge > 0
        ? Badge(
            backgroundColor: pawPink,
            textColor: pawOutline,
            label: Text('$badge'),
          )
        : null,
    onTap: onTap,
  );
}
