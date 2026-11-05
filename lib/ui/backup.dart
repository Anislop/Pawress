import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../core/backup.dart';
import 'app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Asks what to include, then saves a backup into a folder the user picks.
Future<void> exportBackup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final saved = await showDialog<String>(
    context: context,
    builder: (_) => const _ExportDialog(),
  );
  if (saved != null) messenger.showSnackBar(SnackBar(content: Text(saved)));
}

/// Reads a backup the user picks, then asks how to import it.
Future<void> importBackup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));
  final file = await SafUtil().pickFile(
    // File managers label .json files inconsistently.
    mimeTypes: const ['application/json', 'application/octet-stream', 'text/*'],
  );
  if (file == null) return;
  final Backup backup;
  try {
    final bytes = await SafStream().readFileBytes(file.uri);
    backup = Backup.decode(utf8.decode(bytes, allowMalformed: true));
  } on BackupException catch (e) {
    say(e.message);
    return;
  } catch (_) {
    say('Could not read ${file.name}.');
    return;
  }
  if (!context.mounted) return;
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _ImportDialog(backup: backup),
  );
  if (result != null) say(result);
}

String _count(int count, String noun) =>
    count == 1 ? '1 $noun' : '$count ${noun}s';

class _ExportDialog extends StatefulWidget {
  const _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _credentials = AppScope.read(context).signedIn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_credentials) {
      if (_password.text.length < 8) {
        setState(() => _error = 'Use a password of at least 8 characters.');
        return;
      }
      if (_password.text != _confirm.text) {
        setState(() => _error = 'The passwords don\'t match.');
        return;
      }
    }
    final navigator = Navigator.of(context);
    final state = AppScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final folder = await SafUtil().pickDirectory(writePermission: true);
      if (folder == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final backup = await state.exportBackup(
        password: _credentials ? _password.text : null,
      );
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final written = await SafStream().writeFileBytes(
        folder.uri,
        'pawress-backup-$date.json',
        'application/json',
        utf8.encode(backup.encode()),
      );
      navigator.pop(
        'Saved ${written.fileName ?? 'the backup'} to ${folder.name}.',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save the backup: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AlertDialog(
      backgroundColor: panel,
      title: const Text('Export backup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_count(state.follows.length, 'follow')}, '
              '${_count(state.favorites.length, 'favorite')} and '
              '${_count(state.likes.length, 'like')} go into a JSON file in '
              'a folder you choose.',
              style: TextStyle(color: ink(.75)),
            ),
            if (state.signedIn) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include sign-in'),
                subtitle: const Text(
                  'Encrypted with a password. Anyone with the file and the '
                  'password can use your Pawchive account.',
                ),
                value: _credentials,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _credentials = value),
              ),
              if (_credentials) ...[
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'Password'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Repeat password',
                  ),
                  onSubmitted: (_) => _export(),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: pinkText)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _export,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Export'),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.backup});

  final Backup backup;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _password = TextEditingController();
  late bool _signIn =
      widget.backup.credentials != null && !AppScope.read(context).signedIn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final navigator = Navigator.of(context);
    final state = AppScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credentials = widget.backup.credentials;
      final account = _signIn && credentials != null
          ? await credentials.open(_password.text)
          : null;
      final added = await state.importBackup(widget.backup, account: account);
      navigator.pop(
        'Added ${_count(added.follows, 'follow')} and '
        '${_count(added.favorites, 'favorite')}'
        '${account == null ? '' : ', and signed in'}.',
      );
    } on BackupException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backup = widget.backup;
    final signedIn = AppScope.of(context).signedIn;
    return AlertDialog(
      backgroundColor: panel,
      title: const Text('Import backup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_count(backup.follows.length, 'follow')}, '
              '${_count(backup.favorites.length, 'favorite')} and '
              '${_count(backup.likes.length, 'like')}'
              '${backup.exportedAt == null ? '' : ' from ${longDate(backup.exportedAt)}'}. '
              'Ones you already have are kept as they are.',
              style: TextStyle(color: ink(.75)),
            ),
            if (backup.credentials != null) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sign in from this backup'),
                subtitle: Text(
                  signedIn
                      ? 'Replaces the account you\'re signed in to.'
                      : 'Needs the password it was exported with.',
                ),
                value: _signIn,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _signIn = value),
              ),
              if (_signIn)
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'Password'),
                  onSubmitted: (_) => _import(),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: pinkText)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _import,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import'),
        ),
      ],
    );
  }
}
