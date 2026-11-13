import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../core/api.dart';
import '../core/file_hash.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'post_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Finds the posts that hold a file, like the site's hash search: paste a
/// SHA-256, or pick a file and Pawress hashes it on the device (the file is
/// never uploaded).
class HashLookupPage extends StatefulWidget {
  const HashLookupPage({super.key});

  @override
  State<HashLookupPage> createState() => _HashLookupPageState();
}

class _HashLookupPageState extends State<HashLookupPage> {
  final _field = TextEditingController();

  /// While hashing a picked file: its name and how far along.
  ({String name, double? progress})? _hashing;
  bool _searching = false;
  String? _error;

  /// The last lookup; `result` is null when Pawchive has no such file.
  ({String hash, HashLookup? result})? _lookup;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _field.text = text;
    if (isSha256(text)) await _search(text);
  }

  Future<void> _pickFile() async {
    final file = await SafUtil().pickFile();
    if (file == null || !mounted) return;
    setState(() {
      _hashing = (name: file.name, progress: file.length > 0 ? 0 : null);
      _error = null;
    });
    try {
      var shown = 0.0;
      final hash = await sha256Hex(
        await SafStream().readFileStream(file.uri),
        onProgress: (read) {
          if (file.length <= 0 || !mounted) return;
          final progress = (read / file.length).clamp(0.0, 1.0);
          // Repaint every percent, not every chunk.
          if (progress - shown < .01 && progress < 1) return;
          shown = progress;
          setState(() => _hashing = (name: file.name, progress: progress));
        },
      );
      if (!mounted) return;
      setState(() => _hashing = null);
      _field.text = hash;
      await _search(hash);
    } catch (_) {
      if (mounted) {
        setState(() {
          _hashing = null;
          _error = 'Could not read ${file.name}.';
        });
      }
    }
  }

  Future<void> _search([String? text]) async {
    final hash = (text ?? _field.text).trim().toLowerCase();
    FocusScope.of(context).unfocus();
    if (!isSha256(hash)) {
      setState(() => _error = 'A SHA-256 hash is 64 characters, 0-9 and a-f.');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await AppScope.read(context).api.searchHash(hash);
      if (mounted) setState(() => _lookup = (hash: hash, result: result));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _searching || _hashing != null;
    final hashing = _hashing;
    final lookup = _lookup;
    final result = lookup?.result;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hash lookup',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: BackToTop(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Find the posts a file came from. Paste its SHA-256 hash, or '
                'choose the file and Pawress works the hash out on this '
                'phone; the file itself is never uploaded.',
                style: TextStyle(color: ink(.6), height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _field,
                enabled: !busy,
                maxLines: 2,
                minLines: 1,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'SHA-256 hash',
                  prefixIcon: const Icon(Icons.tag_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: busy ? null : _paste,
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : _search,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Look up'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _pickFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Choose file'),
                    ),
                  ),
                ],
              ),
            ),
            if (hashing != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hashing ${hashing.name}…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink(.7)),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: hashing.progress),
                  ],
                ),
              ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (lookup != null && !_searching) ...[
              if (result == null || result.posts.isEmpty)
                StatusView(
                  icon: Icons.search_off_rounded,
                  title: 'No posts have this file',
                  body: result != null && result.discordCount > 0
                      ? 'It is only in ${_messages(result.discordCount)} on '
                            'Discord.'
                      : 'No enabled site has a file with this hash.',
                )
              else ...[
                SectionLabel(
                  result.posts.length == 1
                      ? 'Found in 1 post'
                      : 'Found in ${result.posts.length} posts',
                ),
                if (result.discordCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Also in ${_messages(result.discordCount)} on Discord.',
                      style: TextStyle(color: ink(.5)),
                    ),
                  ),
                for (final post in result.posts) ...[
                  PostCard(post),
                  const Divider(),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _messages(int count) =>
      count == 1 ? '1 message' : '$count messages';
}
