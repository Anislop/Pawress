import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/api.dart';
import '../core/feeds.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'creator_page.dart';
import 'post_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// The two halves of the Popular tab, switched by the home's bottom bar.
enum PopularSection { artists, posts }

enum _ArtistSort {
  favorites('Most favorited'),
  updated('Recently updated'),
  indexed('Recently added'),
  name('Name');

  const _ArtistSort(this.label);

  final String label;
}

/// Popular artists (the sites' `/creators`, ranked by favorites) and popular
/// posts (`/posts/popular`). The home screen owns the bottom bar that picks
/// the [section]; this state keeps both alive while switching.
class PopularTab extends StatefulWidget {
  const PopularTab({super.key, required this.section});

  final PopularSection section;

  @override
  State<PopularTab> createState() => _PopularTabState();
}

class _PopularTabState extends State<PopularTab>
    with AutomaticKeepAliveClientMixin {
  late final PopularFeed _posts = PopularFeed(AppScope.read(context).api);
  Future<List<Creator>>? _creators;
  String? _service;
  _ArtistSort _sort = _ArtistSort.favorites;

  // Sorting the full creator list takes a moment, so it's kept until the
  // filter or sort changes.
  List<Creator>? _sorted;
  List<Creator>? _sortedFrom;
  List<(String, int)> _services = const [];

  String? _sources;
  Provider? _site;

  @override
  bool get wantKeepAlive => true;

  /// Switching site (the chips) or the enabled providers and mirrors (the
  /// sidebar) starts both lists again.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final sources = state.sourceKey;
    final site = state.browse;
    if (_sources != null && sources != _sources) {
      _creators = null;
      _service = null;
      _sorted = null;
    }
    if (_site != null && (site != _site || sources != _sources)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _posts.showRange(null);
      });
    }
    _sources = sources;
    _site = site;
  }

  @override
  void dispose() {
    _posts.dispose();
    super.dispose();
  }

  List<Creator> _arrange(List<Creator> all) {
    if (_sorted != null && identical(_sortedFrom, all)) return _sorted!;
    if (!identical(_sortedFrom, all)) {
      final counts = <String, int>{};
      for (final creator in all) {
        counts[creator.service] = (counts[creator.service] ?? 0) + 1;
      }
      _services = [for (final entry in counts.entries) (entry.key, entry.value)]
        ..sort((a, b) => b.$2.compareTo(a.$2));
    }
    final list = [
      for (final creator in all)
        if (_service == null || creator.service == _service) creator,
    ];
    final epoch = DateTime.utc(1970);
    switch (_sort) {
      case _ArtistSort.favorites:
        list.sort((a, b) => b.favorited.compareTo(a.favorited));
      case _ArtistSort.updated:
        list.sort((a, b) => (b.updated ?? epoch).compareTo(a.updated ?? epoch));
      case _ArtistSort.indexed:
        list.sort((a, b) => (b.indexed ?? epoch).compareTo(a.indexed ?? epoch));
      case _ArtistSort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }
    _sortedFrom = all;
    return _sorted = list;
  }

  void _arrangeBy({
    String? service,
    _ArtistSort? sort,
    bool allServices = false,
  }) => setState(() {
    if (allServices || service != null) _service = service;
    _sort = sort ?? _sort;
    _sorted = null;
  });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final handle = NestedScrollView.sliverOverlapAbsorberHandleFor(context);
    return switch (widget.section) {
      PopularSection.posts => FeedView(
        key: const PageStorageKey('popular-posts'),
        feed: _posts,
        overlapHandle: handle,
        header: SliverToBoxAdapter(child: _periods()),
        itemBuilder: (context, post) => PostCard(post),
        empty: const StatusView(
          icon: Icons.local_fire_department_outlined,
          title: 'No popular posts in this range',
        ),
      ),
      PopularSection.artists => _artists(handle),
    };
  }

  Widget _periods() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const ProviderChips(),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Row(
          children: [
            for (final (period, label) in const [
              (PopularPeriod.day, 'Day'),
              (PopularPeriod.week, 'Week'),
              (PopularPeriod.month, 'Month'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _posts.period == period,
                  onSelected: (_) {
                    if (_posts.period == period && _posts.date == null) {
                      return;
                    }
                    setState(() => _posts.period = period);
                    _posts.refresh();
                  },
                ),
              ),
          ],
        ),
      ),
      ListenableBuilder(listenable: _posts, builder: (context, _) => _range()),
    ],
  );

  /// The range shown, with arrows to the one before and after it.
  Widget _range() {
    void go(String? date) {
      HapticFeedback.selectionClick();
      _posts.showRange(date);
    }

    final label = _posts.label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Earlier',
            onPressed: _posts.previousDate == null
                ? null
                : () => go(_posts.previousDate),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              label == null || label.isEmpty
                  ? ''
                  : label[0].toUpperCase() + label.substring(1),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink(.7), fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Later',
            onPressed: _posts.nextDate == null
                ? null
                : () => go(_posts.nextDate),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          if (_posts.date != null && _posts.nextDate != null)
            IconButton(
              tooltip: 'Newest',
              onPressed: () => go(null),
              icon: const Icon(Icons.last_page_rounded),
            ),
        ],
      ),
    );
  }

  Widget _artists(SliverOverlapAbsorberHandle handle) {
    final creators = _creators ??= AppScope.read(context).allCreators();
    return FutureBuilder<List<Creator>>(
      future: creators,
      builder: (context, snapshot) {
        final Widget body;
        if (snapshot.hasError) {
          body = SliverToBoxAdapter(
            child: StatusView(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load artists',
              body: snapshot.error.toString(),
              action: 'Try again',
              onAction: () => setState(() => _creators = null),
            ),
          );
        } else if (!snapshot.hasData) {
          body = const SliverToBoxAdapter(
            child: StatusView(
              icon: Icons.downloading_rounded,
              title: 'Loading artists',
              body:
                  'The artist list is large; this takes a moment the first '
                  'time.',
            ),
          );
        } else {
          final list = _arrange(snapshot.data!);
          final ranked = _sort == _ArtistSort.favorites;
          body = SliverList.separated(
            itemCount: list.length,
            itemBuilder: (context, index) =>
                ArtistTile(list[index], rank: ranked ? index + 1 : null),
            separatorBuilder: (_, _) => const Divider(),
          );
        }
        return BackToTop(
          child: CustomScrollView(
            key: const PageStorageKey('popular-artists'),
            slivers: [
              SliverOverlapInjector(handle: handle),
              if (snapshot.hasData) SliverToBoxAdapter(child: _artistFilters()),
              body,
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      },
    );
  }

  Widget _artistFilters() => Row(
    children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _service == null,
                  onSelected: (_) => _arrangeBy(allServices: true),
                ),
              ),
              for (final (service, _) in _services)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: ServiceBadge(service, compact: true),
                    label: Text(Service.of(service).label),
                    selected: _service == service,
                    onSelected: (_) => _arrangeBy(service: service),
                  ),
                ),
            ],
          ),
        ),
      ),
      PopupMenuButton<_ArtistSort>(
        tooltip: 'Sort',
        initialValue: _sort,
        onSelected: (sort) => _arrangeBy(sort: sort),
        itemBuilder: (_) => [
          for (final sort in _ArtistSort.values)
            PopupMenuItem(value: sort, child: Text(sort.label)),
        ],
        icon: Icon(Icons.sort_rounded, color: ink(.7)),
      ),
      const SizedBox(width: 4),
    ],
  );
}
