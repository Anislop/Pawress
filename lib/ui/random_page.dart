import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/store.dart';
import 'app_scope.dart';
import 'creator_page.dart';
import 'post_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// A random post or artist (as the site's random links pick them), with a
/// shuffle button to pick again and a gear to switch between the two. The
/// first visit asks which; the choice is kept in [AppSettings.randomKind].
class RandomPage extends StatefulWidget {
  const RandomPage({super.key});

  @override
  State<RandomPage> createState() => _RandomPageState();
}

class _RandomPageState extends State<RandomPage> {
  late RandomKind? _kind = AppScope.read(context).settings.randomKind;
  Widget? _shown;
  bool _loading = false;
  String? _error;

  /// Keys each pick so a new one starts fresh instead of reusing state.
  int _round = 0;

  @override
  void initState() {
    super.initState();
    if (_kind == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _choose(first: true));
    } else {
      _roll();
    }
  }

  Future<void> _roll() async {
    final kind = _kind;
    if (kind == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final state = AppScope.read(context);
    final api = state.api;
    try {
      final Widget page;
      switch (kind) {
        case RandomKind.post:
          final link = await api.randomPost();
          final post = link.post;
          if (post == null) {
            throw const ApiException('Pawchive did not pick a post.');
          }
          page = PostPage(
            key: ValueKey(++_round),
            service: link.service,
            creatorId: link.user,
            postId: post,
            embedded: true,
          );
        case RandomKind.artist:
          final creator = await api.randomCreator();
          final known = state.directory.known(creator.key);
          page = CreatorPage(
            key: ValueKey(++_round),
            creator: known ?? creator,
          );
      }
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _shown = page);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_shown == null) {
        setState(() => _error = e.message);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Asks posts or artists. Dismissing the first ask leaves the page.
  Future<void> _choose({bool first = false}) async {
    final state = AppScope.read(context);
    final kind = await showModalBottomSheet<RandomKind>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: canvas,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'What should Random pick?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          for (final (kind, icon, label, detail) in const [
            (
              RandomKind.post,
              Icons.article_outlined,
              'Posts',
              'A random post from any artist',
            ),
            (
              RandomKind.artist,
              Icons.person_outline_rounded,
              'Artists',
              'A random artist profile',
            ),
          ])
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(icon),
              title: Text(label),
              subtitle: Text(detail, style: TextStyle(color: ink(.5))),
              trailing: _kind == kind
                  ? const Icon(Icons.check_rounded, color: pawPink)
                  : null,
              onTap: () => Navigator.of(sheet).pop(kind),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (!mounted) return;
    if (kind == null) {
      if (first) Navigator.of(context).maybePop();
      return;
    }
    final changed = kind != _kind;
    _kind = kind;
    await state.updateSettings(state.settings.copyWith(randomKind: kind));
    if (changed || _shown == null) await _roll();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body:
        _shown ??
        Scaffold(
          appBar: AppBar(
            title: const Text(
              'Random',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: Center(
            child: _error != null
                ? StatusView(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not pick one',
                    body: _error,
                    action: 'Try again',
                    onAction: _roll,
                  )
                : const CircularProgressIndicator(),
          ),
        ),
    floatingActionButton: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'random-kind',
          tooltip: _kind == RandomKind.artist
              ? 'Picking artists'
              : 'Picking posts',
          backgroundColor: panel,
          foregroundColor: ink(.85),
          onPressed: _choose,
          child: const Icon(Icons.settings_rounded),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'random-roll',
          tooltip: _kind == RandomKind.artist
              ? 'Another artist'
              : 'Another post',
          backgroundColor: pawPink,
          foregroundColor: pawOutline,
          onPressed: _kind == null ? null : _roll,
          child: _loading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: pawOutline,
                  ),
                )
              : const Icon(Icons.shuffle_rounded),
        ),
      ],
    ),
  );
}
