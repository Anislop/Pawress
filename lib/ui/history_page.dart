import 'package:flutter/material.dart';

import '../core/models.dart';
import 'app_scope.dart';
import 'creator_page.dart';
import 'post_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Posts and artists opened lately, newest first, kept on the device.
/// Swipe one away to forget it; Settings can turn recording off.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  Future<void> _confirmClear(BuildContext context) async {
    final state = AppScope.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('Every opened post and artist is forgotten.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final posts = [
      for (final visit in state.history)
        if (visit.post != null) visit,
    ];
    final artists = [
      for (final visit in state.history)
        if (visit.creator != null) visit,
    ];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'History',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (state.history.isNotEmpty)
              TextButton(
                onPressed: () => _confirmClear(context),
                child: const Text('Clear'),
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Posts (${posts.length})'),
              Tab(text: 'Artists (${artists.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _VisitList(
              visits: posts,
              empty: state.settings.keepHistory
                  ? 'Posts you open show up here.'
                  : 'History is off in Settings.',
              builder: (visit) => PostCard(visit.post!, dimViewed: false),
            ),
            _VisitList(
              visits: artists,
              empty: state.settings.keepHistory
                  ? 'Artists you open show up here.'
                  : 'History is off in Settings.',
              builder: (visit) => ArtistTile(visit.creator!),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitList extends StatelessWidget {
  const _VisitList({
    required this.visits,
    required this.empty,
    required this.builder,
  });

  final List<Visit> visits;
  final String empty;
  final Widget Function(Visit visit) builder;

  @override
  Widget build(BuildContext context) {
    if (visits.isEmpty) {
      return StatusView(
        icon: Icons.history_rounded,
        title: 'Nothing here yet',
        body: empty,
      );
    }
    final state = AppScope.read(context);
    return BackToTop(
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 48),
        itemCount: visits.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final visit = visits[index];
          return Dismissible(
            key: ValueKey(visit.key),
            background: ColoredBox(
              color: panel,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Icon(Icons.delete_outline_rounded, color: ink(.6)),
                ),
              ),
            ),
            secondaryBackground: ColoredBox(
              color: panel,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Icon(Icons.delete_outline_rounded, color: ink(.6)),
                ),
              ),
            ),
            onDismissed: (_) => state.removeVisit(visit),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _viewed(visit.at),
                    style: TextStyle(color: ink(.45), fontSize: 12),
                  ),
                ),
                builder(visit),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "Viewed just now", "Viewed 5m ago", "Viewed Oct 3".
String _viewed(DateTime at) {
  final time = shortTime(at);
  if (time == 'now') return 'Viewed just now';
  return RegExp(r'^\d+[mhd]$').hasMatch(time)
      ? 'Viewed $time ago'
      : 'Viewed $time';
}
