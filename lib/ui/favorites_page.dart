import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'post_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Every liked post, newest like first. Likes are kept on the device and,
/// when signed in, synced with the account's favorite posts.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final favorites = state.favorites;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Favorites',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              favorites.length == 1 ? '1 post' : '${favorites.length} posts',
              style: TextStyle(fontSize: 12, color: ink(.5)),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: state.syncFavorites,
        child: favorites.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 80),
                  StatusView(
                    icon: Icons.favorite_border_rounded,
                    title: 'No favorites yet',
                    body: 'Tap the heart on a post to keep it here.',
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 48),
                itemCount: favorites.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) => PostCard(
                  favorites[index].post,
                  key: ValueKey(favorites[index].key),
                ),
              ),
      ),
    );
  }
}
