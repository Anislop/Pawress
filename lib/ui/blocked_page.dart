import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import 'app_scope.dart';
import 'post_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Blocked artists and tags, and the "not interested" marks For You keeps.
/// Everything here stays on the device and goes into backups (except the
/// marks).
class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key});

  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  final _tag = TextEditingController();

  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = Blocklist.tagKey(_tag.text);
    if (tag.isEmpty) return;
    HapticFeedback.lightImpact();
    AppScope.read(context).blockTag(tag);
    _tag.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final blocklist = state.blocklist;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Blocked',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          const SectionLabel('Tags'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _tag,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addTag(),
              decoration: InputDecoration(
                hintText: 'Block a tag',
                prefixIcon: const Icon(Icons.tag_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Block tag',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _addTag,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: blocklist.tags.isEmpty
                ? Text(
                    'Posts with a blocked tag are left out of every feed. '
                    'Popular and tag pages list posts without their tags, so '
                    'only blocked artists hide there.',
                    style: TextStyle(color: ink(.55), height: 1.4),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in blocklist.tags)
                        InputChip(
                          label: Text('#$tag'),
                          onDeleted: () => state.unblockTag(tag),
                          deleteButtonTooltipMessage: 'Unblock',
                        ),
                    ],
                  ),
          ),
          const SectionLabel('Artists'),
          if (blocklist.creators.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Block an artist from their profile menu or by holding one '
                'of their posts. Their profile still opens, but their posts '
                'leave your feeds.',
                style: TextStyle(color: ink(.55), height: 1.4),
              ),
            )
          else
            for (final creator in blocklist.creators)
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                leading: CreatorAvatar(creator, size: 40),
                title: Text(
                  creator.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  creator.site.label,
                  style: TextStyle(color: ink(.5)),
                ),
                trailing: TextButton(
                  onPressed: () => state.unblock(creator.key),
                  child: const Text('Unblock'),
                ),
                onTap: () => openCreator(context, creator),
              ),
          const SectionLabel('Not interested'),
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            leading: const Icon(Icons.not_interested_rounded),
            title: Text(
              state.dislikes.length == 1
                  ? '1 post marked'
                  : '${state.dislikes.length} posts marked',
            ),
            subtitle: Text(
              'Hidden, and their artists and tags show up less in For You. '
              'The effect fades over a month.',
              style: TextStyle(color: ink(.5)),
            ),
            trailing: TextButton(
              onPressed: state.dislikes.isEmpty ? null : state.clearDislikes,
              child: const Text('Reset'),
            ),
          ),
        ],
      ),
    );
  }
}
