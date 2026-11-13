import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/feeds.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'creator_page.dart';
import 'post_card.dart';
import 'tag_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Finds artists by name, posts by text, and tags (the site's popular tags
/// filtered on the device, or any tag typed in).
///
/// Artist search filters Pawchive's full creator list on the device; the
/// list (~16 MB) is downloaded the first time this page needs it per
/// session. Post search uses the API's `q` parameter.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _field = TextEditingController();
  Timer? _debounce;
  String _query = '';
  OffsetFeed? _posts;
  late final Future<List<Creator>> _creators = AppScope.read(context)
      .allCreators();

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _tabs.dispose();
    _posts?.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(value.trim()),
    );
  }

  void _clear() {
    _debounce?.cancel();
    _field.clear();
    _search('');
  }

  void _search(String query) {
    if (query == _query) return;
    final api = AppScope.read(context).api;
    setState(() {
      _query = query;
      _posts?.dispose();
      _posts = query.length < 3
          ? null
          : OffsetFeed(
              (offset) => api.recentPosts(offset: offset, query: query),
            );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: ListenableBuilder(
          listenable: _field,
          builder: (context, _) => TextField(
            controller: _field,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _field.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _clear,
                    ),
              isDense: true,
            ),
            onChanged: _changed,
            onSubmitted: (value) => _search(value.trim()),
          ),
        ),
      ),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Artists'),
          Tab(text: 'Posts'),
          Tab(text: 'Tags'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: [
        _ArtistResults(creators: _creators, query: _query),
        _posts == null
            ? const StatusView(
                icon: Icons.manage_search_rounded,
                title: 'Search posts',
                body: 'Type at least 3 characters to search post titles and text.',
              )
            : FeedView(
                key: ValueKey(_posts),
                feed: _posts!,
                itemBuilder: (context, post) => PostCard(post),
                empty: StatusView(
                  icon: Icons.search_off_rounded,
                  title: 'No posts match "$_query"',
                ),
              ),
        _TagResults(query: _query),
      ],
    ),
  );
}

class _ArtistResults extends StatelessWidget {
  const _ArtistResults({required this.creators, required this.query});

  final Future<List<Creator>> creators;
  final String query;

  static const _limit = 100;

  List<Creator> _match(List<Creator> all) {
    final q = query.toLowerCase();
    final matches = all
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              (c.publicId?.toLowerCase().contains(q) ?? false),
        )
        .toList();
    // Exact and prefix matches first, then by popularity.
    int rank(Creator c) {
      final name = c.name.toLowerCase();
      return name == q
          ? 0
          : name.startsWith(q)
          ? 1
          : 2;
    }

    matches.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : b.favorited.compareTo(a.favorited);
    });
    return matches.take(_limit).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (query.isEmpty) {
      final follows = state.follows;
      return ListView(
        children: [
          const StatusView(
            icon: Icons.person_search_rounded,
            title: 'Find artists',
            body: 'Search by name across Patreon, Pixiv Fanbox, Discord and more.',
          ),
          if (follows.isNotEmpty) ...[
            const SectionLabel('You follow'),
            for (final follow in follows.take(10)) ArtistTile(follow.creator),
          ],
        ],
      );
    }
    return FutureBuilder<List<Creator>>(
      future: creators,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StatusView(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load artists',
            body: '${snapshot.error}',
          );
        }
        final all = snapshot.data;
        if (all == null) {
          return const StatusView(
            icon: Icons.downloading_rounded,
            title: 'Loading the artist list…',
            body: 'This happens once per session.',
          );
        }
        final results = _match(all);
        if (results.isEmpty) {
          return StatusView(
            icon: Icons.search_off_rounded,
            title: 'No artists match "$query"',
          );
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) => ArtistTile(results[index]),
        );
      },
    );
  }
}

/// The site's popular tags (loaded when this tab first opens), filtered by
/// the query, under a shortcut to the posts with exactly the typed tag.
class _TagResults extends StatefulWidget {
  const _TagResults({required this.query});

  final String query;

  @override
  State<_TagResults> createState() => _TagResultsState();
}

class _TagResultsState extends State<_TagResults>
    with AutomaticKeepAliveClientMixin {
  late Future<List<CreatorTag>> _tags = AppScope.read(context).popularTags();
  late Provider _site = AppScope.read(context).browse;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (state.browse != _site) {
      _site = state.browse;
      _tags = state.popularTags();
    }
  }

  String get _tag {
    final query = widget.query.trim();
    return query.startsWith('#') ? query.substring(1).trim() : query;
  }

  List<CreatorTag> _match(List<CreatorTag> all) {
    final q = _tag.toLowerCase();
    if (q.isEmpty) return all;
    final starts = <CreatorTag>[];
    final contains = <CreatorTag>[];
    for (final tag in all) {
      final name = tag.tag.toLowerCase();
      if (name.startsWith(q)) {
        starts.add(tag);
      } else if (name.contains(q)) {
        contains.add(tag);
      }
    }
    // Popularity order within each group, as the site lists them.
    return [...starts, ...contains];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tag = _tag;
    return FutureBuilder<List<CreatorTag>>(
      future: _tags,
      builder: (context, snapshot) {
        final matches = snapshot.hasData
            ? _match(snapshot.data!)
            : const <CreatorTag>[];
        final header = <Widget>[
          const ProviderChips(),
          if (tag.isNotEmpty)
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              leading: const CircleAvatar(
                backgroundColor: pawPink,
                foregroundColor: pawOutline,
                child: Icon(Icons.tag_rounded),
              ),
              title: Text(
                'Posts tagged #$tag',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'From every artist',
                style: TextStyle(color: ink(.5)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => openTag(context, tag),
            ),
          if (snapshot.hasError)
            StatusView(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load popular tags',
              body: '${snapshot.error}',
              action: 'Try again',
              onAction: () =>
                  setState(() => _tags = AppScope.read(context).popularTags()),
            )
          else if (!snapshot.hasData)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (matches.isNotEmpty)
            SectionLabel(
              tag.isEmpty ? 'Popular tags' : 'Popular tags like this',
            )
          else if (tag.isEmpty)
            const StatusView(icon: Icons.tag_rounded, title: 'No tags'),
        ];
        return BackToTop(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: header.length + matches.length,
            itemBuilder: (context, index) {
              if (index < header.length) return header[index];
              final item = matches[index - header.length];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(Icons.tag_rounded, color: ink(.5)),
                title: Text(item.tag),
                trailing: Text(
                  '${compactCount(item.postCount)} posts',
                  style: TextStyle(color: ink(.5), fontSize: 13),
                ),
                onTap: () => openTag(context, item.tag),
              );
            },
          ),
        );
      },
    );
  }
}
