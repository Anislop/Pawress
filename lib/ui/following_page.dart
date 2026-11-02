import 'package:flutter/material.dart';

import '../core/models.dart';
import 'app_scope.dart';
import 'creator_page.dart';
import 'post_card.dart';
import 'search_page.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Order { recent, name, unread }

/// Every followed artist, with unread counts and a filter box.
class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  String _query = '';
  _Order _order = _Order.recent;

  List<Follow> _sorted(List<Follow> follows) {
    final query = _query.toLowerCase();
    final list = follows
        .where(
          (f) => query.isEmpty || f.creator.name.toLowerCase().contains(query),
        )
        .toList();
    switch (_order) {
      case _Order.recent:
        list.sort((a, b) => b.followedAt.compareTo(a.followedAt));
      case _Order.name:
        list.sort(
          (a, b) => a.creator.name.toLowerCase().compareTo(
            b.creator.name.toLowerCase(),
          ),
        );
      case _Order.unread:
        list.sort((a, b) => b.unread.compareTo(a.unread));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final follows = _sorted(state.follows);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Following',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              state.follows.length == 1
                  ? '1 artist'
                  : '${state.follows.length} artists',
              style: TextStyle(fontSize: 12, color: ink(.5)),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_Order>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _order,
            onSelected: (order) => setState(() => _order = order),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _Order.recent,
                child: Text('Recently followed'),
              ),
              PopupMenuItem(value: _Order.name, child: Text('Name')),
              PopupMenuItem(value: _Order.unread, child: Text('New posts')),
            ],
          ),
          IconButton(
            tooltip: 'Find artists',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const SearchPage())),
          ),
        ],
      ),
      body: state.follows.isEmpty
          ? Center(
              child: StatusView(
                icon: Icons.people_outline_rounded,
                title: 'You are not following anyone',
                body: 'Follow artists to see their posts in Following and get notified when they post.',
                action: 'Find artists',
                onAction: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchPage()),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await state.syncFavorites();
                await state.checkForUpdates();
              },
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 48),
                itemCount: follows.length + 1,
                separatorBuilder: (_, index) =>
                    index == 0 ? const SizedBox.shrink() : const Divider(),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Filter followed artists',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) =>
                            setState(() => _query = value.trim()),
                      ),
                    );
                  }
                  return _FollowTile(follow: follows[index - 1]);
                },
              ),
            ),
    );
  }
}

class _FollowTile extends StatelessWidget {
  const _FollowTile({required this.follow});

  final Follow follow;

  @override
  Widget build(BuildContext context) {
    final c = follow.creator;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
      leading: CreatorAvatar(c, size: 46),
      title: Text(
        c.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Row(
        children: [
          ServiceBadge(c.service, compact: true),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              c.updated == null
                  ? c.site.label
                  : '${c.site.label} · updated ${shortTime(c.updated)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink(.5)),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (follow.unread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Badge(
                backgroundColor: pawPink,
                textColor: pawOutline,
                label: Text('${follow.unread} new'),
              ),
            ),
          FollowButton(creator: c, compact: true),
        ],
      ),
      onTap: () => openCreator(context, c),
    );
  }
}
