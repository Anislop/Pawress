import 'dart:async';

import 'package:flutter/material.dart';

import '../core/feeds.dart';
import '../core/updates.dart';
import 'app_scope.dart';
import 'creator_page.dart';
import 'update_dialog.dart';
import 'downloads.dart';
import 'favorites_page.dart';
import 'following_page.dart';
import 'login_page.dart';
import 'notifications_page.dart';
import 'popular.dart';
import 'post_card.dart';
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
  static const _popularTab = 2;

  final _scaffold = GlobalKey<ScaffoldState>();
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTab);
  int _tab = 0;
  PopularSection _section = PopularSection.artists;
  late final ForYouFeed _forYou;
  late final FollowingFeed _following;
  StreamSubscription<String>? _taps;
  String _followSignature = '';

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    _forYou = ForYouFeed(state.api, () => state.follows);
    _following = FollowingFeed(state.api, () => state.follows);
    _followSignature = _signature();
    state.addListener(_onState);
    WidgetsBinding.instance.addObserver(this);
    _taps = Notifier.taps.stream.listen(_openFromNotification);
    Notifier.launchPayload().then((key) {
      if (key != null) _openFromNotification(key);
    });
    unawaited(_checkForUpdate());
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
    _tabs.dispose();
    _forYou.dispose();
    _following.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The background check may have found posts while the app was away.
    if (state == AppLifecycleState.resumed) AppScope.read(context).reload();
  }

  void _onTab() {
    if (_tabs.index != _tab) setState(() => _tab = _tabs.index);
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
    final signature = _signature();
    if (signature != _followSignature) {
      _followSignature = signature;
      if (_following.posts.isNotEmpty || _following.done) _following.refresh();
    }
  }

  void _openFromNotification(String key) {
    if (!mounted) return;
    final follow = AppScope.read(context).followOf(key);
    if (follow == null) {
      _push((_) => const NotificationsPage());
      return;
    }
    _push((_) => CreatorPage(creator: follow.creator));
  }

  void _push(WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _scaffold,
    drawer: Sidebar(onOpen: _push),
    bottomNavigationBar: AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _tab == _popularTab
          ? NavigationBar(
              height: 64,
              selectedIndex: _section.index,
              onDestinationSelected: (index) =>
                  setState(() => _section = PopularSection.values[index]),
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
            title: Image.asset(logoAsset, height: 26),
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
  const _Tab({required this.feed, required this.empty});

  final Feed feed;
  final Widget empty;

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

    return Drawer(
      child: SafeArea(
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
                            style: const TextStyle(fontWeight: FontWeight.w800),
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
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Image.asset(logoAsset, height: 22),
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
