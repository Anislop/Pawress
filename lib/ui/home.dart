import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
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

/// Where the home's bottom bar goes.
enum _Destination { home, popular, search, notifications }

/// The main screen, laid out like X on Android: a bottom bar of icons (Home,
/// Popular, Search, Notifications) that hides while scrolling down, a top
/// bar that does the same, Home's For You / Following tabs, and a sidebar
/// opened from the account avatar or by swiping right on the first tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _followingTab = 1;

  /// How far past For You's edge, and how far right overall, a drag goes
  /// before the sidebar opens.
  static const _swipeOpenPull = 40.0;
  static const _swipeOpenDistance = 72.0;

  final _scaffold = GlobalKey<ScaffoldState>();
  final _nested = GlobalKey<NestedScrollViewState>();
  final _popularNested = GlobalKey<NestedScrollViewState>();
  bool _drawerOpen = false;
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTab);
  int _tab = 0;
  late final TabController _sections = TabController(
    length: PopularSection.values.length,
    vsync: this,
  )..addListener(_onSection);
  PopularSection _section = PopularSection.artists;
  _Destination _destination = _Destination.home;

  /// Destinations are built the first time they're opened (Search loads the
  /// whole artist list), then kept.
  final _opened = {_Destination.home};
  bool _barShown = true;
  late final ForYouFeed _forYou;
  late final FollowingFeed _following;
  StreamSubscription<String>? _taps;
  StreamSubscription<String>? _links;
  String _followSignature = '';

  /// The enabled providers and their hosts the feeds were loaded from.
  String _sources = '';

  /// Looks for notices the background check wrote while the app is open.
  Timer? _poll;
  static const _pollInterval = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    _forYou = ForYouFeed(state.api, state.forYouSignals);
    _following = FollowingFeed(state.api, () => state.activeFollows);
    _sources = state.sourceKey;
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
    _sections.dispose();
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
      if (_onFollowing) _markFollowingSeen();
    }
  }

  bool get _onFollowing =>
      _destination == _Destination.home && _tab == _followingTab;

  void _onTab() {
    if (_tabs.index == _tab) return;
    if (_tab == _followingTab) _markFollowingSeen();
    setState(() => _tab = _tabs.index);
  }

  /// Opens a bottom bar destination; the open one goes back to the top.
  void _select(_Destination destination) {
    if (destination == _destination) {
      switch (destination) {
        case _Destination.home:
          _scrollToTop();
        case _Destination.popular:
          HapticFeedback.selectionClick();
          scrollNestedToTop(_popularNested.currentState);
        case _Destination.search || _Destination.notifications:
          break;
      }
      return;
    }
    HapticFeedback.selectionClick();
    if (_onFollowing) _markFollowingSeen();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _destination = destination;
      _opened.add(destination);
      _barShown = true;
    });
  }

  /// Scrolling down puts the bottom bar away; scrolling up brings it back.
  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final shown = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _barShown,
    };
    if (shown != _barShown) setState(() => _barShown = shown);
    return false;
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

  void _onSection() {
    final section = PopularSection.values[_sections.index];
    if (section == _section) return;
    HapticFeedback.selectionClick();
    setState(() => _section = section);
  }

  /// Tapping the open Popular section scrolls it back to the top.
  void _onSectionTap(int index) {
    if (index == _section.index && !_sections.indexIsChanging) {
      HapticFeedback.selectionClick();
      scrollNestedToTop(_popularNested.currentState);
    }
  }

  /// Where the pager's current drag started, and how far it has pulled
  /// past For You's left edge.
  Offset? _swipeStart;
  double _swipePull = 0;

  /// Swiping right past the first tab opens the sidebar, as in X. Only a
  /// deliberate, mostly sideways drag of the pager itself counts: nested
  /// horizontal lists, a few pixels of jitter while scrolling a feed, or a
  /// diagonal drag don't.
  bool _onPagerScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _swipeStart = notification.dragDetails?.globalPosition;
      _swipePull = 0;
    } else if (notification is ScrollEndNotification) {
      _swipeStart = null;
    } else if (notification is OverscrollNotification) {
      final start = _swipeStart;
      final drag = notification.dragDetails;
      if (start == null ||
          drag == null ||
          notification.overscroll >= 0 ||
          _tabs.index != 0 ||
          _tabs.indexIsChanging) {
        return false;
      }
      _swipePull -= notification.overscroll;
      final moved = drag.globalPosition - start;
      if (_swipePull >= _swipeOpenPull &&
          moved.dx >= _swipeOpenDistance &&
          moved.dx >= moved.dy.abs() * 2 &&
          !(_scaffold.currentState?.isDrawerOpen ?? true)) {
        _swipeStart = null;
        _scaffold.currentState!.openDrawer();
      }
    }
    return false;
  }

  String _signature() =>
      AppScope.read(context).activeFollows.map((f) => f.key).join(',');

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
    final moved = state.sourceKey != _sources;
    _sources = state.sourceKey;
    if (signature != _followSignature || moved) {
      _followSignature = signature;
      if (_following.posts.isNotEmpty || _following.done) _following.refresh();
    }
    // A provider was switched or moved to a mirror in the sidebar.
    if (moved && (_forYou.posts.isNotEmpty || _forYou.done)) _forYou.refresh();
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
              : _select(_Destination.notifications),
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
      _select(_Destination.notifications);
      return;
    }
    _push((_) => CreatorPage(creator: follow.creator));
  }

  void _push(WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

  /// Back on another destination returns to Home, and on Following to For
  /// You, before leaving the app, as in X.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: (_destination == _Destination.home && _tab == 0) || _drawerOpen,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_destination != _Destination.home) {
        _select(_Destination.home);
      } else {
        _tabs.animateTo(0);
      }
    },
    child: _scaffoldView(context),
  );

  Widget _scaffoldView(BuildContext context) => Scaffold(
    key: _scaffold,
    drawer: Sidebar(onOpen: _push),
    onDrawerChanged: (open) => setState(() => _drawerOpen = open),
    bottomNavigationBar: ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: _barShown ? 1 : 0,
        child: NavigationBar(
          height: 56,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          selectedIndex: _destination.index,
          onDestinationSelected: (index) => _select(_Destination.values[index]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
              tooltip: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_fire_department_outlined),
              selectedIcon: Icon(Icons.local_fire_department_rounded),
              label: 'Popular',
              tooltip: 'Popular',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.manage_search_rounded),
              label: 'Search',
              tooltip: 'Search',
            ),
            NavigationDestination(
              icon: _NoticesIcon(selected: false),
              selectedIcon: _NoticesIcon(selected: true),
              label: 'Notifications',
              tooltip: 'Notifications',
            ),
          ],
        ),
      ),
    ),
    body: NotificationListener<UserScrollNotification>(
      onNotification: _onUserScroll,
      child: IndexedStack(
        index: _destination.index,
        children: [
          for (final destination in _Destination.values)
            if (!_opened.contains(destination))
              const SizedBox.shrink()
            else
              switch (destination) {
                _Destination.home => _home(),
                _Destination.popular => _popular(),
                _Destination.search => const SearchPage(),
                _Destination.notifications => const NotificationsPage(),
              },
        ],
      ),
    ),
  );

  Widget _menuButton() => IconButton(
    tooltip: 'Open menu',
    onPressed: () => _scaffold.currentState!.openDrawer(),
    icon: const _AccountAvatar(size: 32),
  );

  Widget _home() => NestedScrollView(
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
          leading: _menuButton(),
          title: GestureDetector(
            onTap: _scrollToTop,
            child: Image.asset(logoAsset, height: 26),
          ),
          bottom: TabBar(
            controller: _tabs,
            onTap: _onTabTap,
            tabs: const [
              Tab(text: 'For You'),
              Tab(text: 'Following'),
            ],
          ),
        ),
      ),
    ],
    body: NotificationListener<ScrollNotification>(
      onNotification: _onPagerScroll,
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
              onAction: () => _select(_Destination.search),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _popular() => NestedScrollView(
    key: _popularNested,
    floatHeaderSlivers: true,
    headerSliverBuilder: (context, scrolled) => [
      SliverOverlapAbsorber(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        sliver: SliverAppBar(
          floating: true,
          snap: true,
          forceElevated: scrolled,
          centerTitle: true,
          leading: _menuButton(),
          title: GestureDetector(
            onTap: () => _onSectionTap(_section.index),
            child: const Text(
              'Popular',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          bottom: TabBar(
            controller: _sections,
            onTap: _onSectionTap,
            tabs: const [
              Tab(text: 'Artists'),
              Tab(text: 'Posts'),
            ],
          ),
        ),
      ),
    ],
    body: PopularTab(section: _section),
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
    if (widget.feed is FollowingFeed && state.activeFollows.isEmpty) {
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

/// The bottom bar's bell, with the unread count.
class _NoticesIcon extends StatelessWidget {
  const _NoticesIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final unread = AppScope.of(context).unreadNotices;
    return Badge(
      isLabelVisible: unread > 0,
      backgroundColor: pawPink,
      textColor: pawOutline,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: Icon(
        selected
            ? Icons.notifications_rounded
            : Icons.notifications_none_rounded,
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
/// Favorites, History, the tools and Settings. Search and Notifications are
/// in the bottom bar.
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
                  for (final provider in Provider.all) _ProviderItem(provider),
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

/// A website in the sidebar: a switch to browse it and a gear for its
/// mirror. The last one on can't be switched off.
class _ProviderItem extends StatelessWidget {
  const _ProviderItem(this.provider);

  final Provider provider;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final enabled = state.providerEnabled(provider);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 20, right: 8),
      leading: Icon(
        Icons.public_rounded,
        size: 26,
        color: ink(enabled ? 1 : .4),
      ),
      title: Text(
        provider.name,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        provider.host,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: ink(.5)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Mirror',
            icon: Icon(Icons.settings_outlined, color: ink(.7)),
            onPressed: () => showMirrorDialog(context, provider),
          ),
          Switch(
            value: enabled,
            onChanged: enabled && !state.manyProviders
                ? null
                : (value) => state.setProviderEnabled(provider, value),
          ),
        ],
      ),
    );
  }
}

/// Asks for the address [provider] is read from, for when the site moves
/// or a mirror works better.
Future<void> showMirrorDialog(BuildContext context, Provider provider) async {
  final state = AppScope.read(context);
  final controller = TextEditingController(text: provider.host);
  String? error;
  final host = await showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) {
        void save() {
          final host = Provider.parseHost(controller.text);
          if (host == null) {
            setState(
              () => error = 'Enter an address like ${provider.defaultHost}',
            );
          } else {
            Navigator.of(dialog).pop(host);
          }
        }

        return AlertDialog(
          backgroundColor: panel,
          title: Text('${provider.name} mirror'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The address Pawress reads ${provider.name} from. Its image '
                'and file hosts are taken from it.',
                style: TextStyle(color: ink(.7)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => save(),
                decoration: InputDecoration(
                  hintText: provider.defaultHost,
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(provider.defaultHost),
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: save, child: const Text('Save')),
          ],
        );
      },
    ),
  );
  controller.dispose();
  if (host != null && host != provider.host) {
    await state.setMirror(provider, host);
  }
}
