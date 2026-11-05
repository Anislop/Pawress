import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saf_util/saf_util.dart';

import '../core/downloads.dart';
import '../core/intents.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Asks Android for a folder Pawress may keep writing to.
Future<({String uri, String name})?> pickDownloadFolder() async {
  final folder = await SafUtil().pickDirectory(
    writePermission: true,
    persistablePermission: true,
  );
  if (folder == null) return null;
  return (uri: folder.uri, name: folder.name);
}

/// Queues [files] from [post], picking a folder first when none is saved,
/// the saved one lost its permission, or Settings asks every time.
Future<void> downloadFiles(
  BuildContext context,
  Post post,
  List<MediaFile> files,
) async {
  if (files.isEmpty) return;
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  var settings = state.settings;
  ({String uri, String name})? folder;
  final saved = settings.downloadFolderUri;
  if (!settings.askDownloadFolder &&
      saved != null &&
      await SafUtil().hasPersistedPermission(saved, checkWrite: true)) {
    folder = (uri: saved, name: settings.downloadFolderName ?? 'Downloads');
  } else {
    folder = await pickDownloadFolder();
    if (folder == null) return;
    if (saved == null || !settings.askDownloadFolder) {
      settings = settings.copyWith(downloadFolder: folder);
      await state.updateSettings(settings);
    }
  }
  HapticFeedback.lightImpact();
  state.downloads.enqueue(
    post,
    files,
    folderUri: folder.uri,
    folderName: folder.name,
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          files.length == 1
              ? 'Downloading to ${folder.name}'
              : 'Downloading ${files.length} files to ${folder.name}',
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => navigator.push(
            MaterialPageRoute<void>(builder: (_) => const DownloadsPage()),
          ),
        ),
      ),
    );
}

/// Opens a finished download in an app that can show it.
Future<void> viewDownload(BuildContext context, DownloadTask task) async {
  final uri = task.savedUri;
  final messenger = ScaffoldMessenger.of(context);
  final opened = uri != null && await AndroidIntents.viewFile(uri, task.mime);
  if (!opened) _cantOpen(messenger, 'No app can open this file.');
}

/// Opens a download folder in the phone's file browser.
Future<void> viewDownloadFolder(BuildContext context, String folderUri) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await AndroidIntents.viewFolder(folderUri)) {
    _cantOpen(messenger, 'No file browser can open this folder.');
  }
}

void _cantOpen(ScaffoldMessengerState messenger, String message) => messenger
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// The download queue: progress, failures with retry, and finished files.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final downloads = state.downloads;
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final tasks = downloads.tasks.reversed.toList();
        final folder =
            tasks.firstOrNull?.folderUri ?? state.settings.downloadFolderUri;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads'),
            actions: [
              if (folder != null)
                IconButton(
                  tooltip: 'View folder',
                  icon: const Icon(Icons.folder_open_rounded),
                  onPressed: () => viewDownloadFolder(context, folder),
                ),
              if (tasks.any((task) => task.finished))
                TextButton(
                  onPressed: downloads.clearFinished,
                  child: const Text('Clear finished'),
                ),
            ],
          ),
          body: tasks.isEmpty
              ? const StatusView(
                  icon: Icons.download_rounded,
                  title: 'No downloads',
                  body:
                      'Download from the media viewer or a post. Choose the '
                      'folder in Settings.',
                )
              : ListView.separated(
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) => _DownloadTile(tasks[index]),
                ),
        );
      },
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile(this.task);

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final thumbnail = task.file.thumbnailUrl;
    final status = switch (task.status) {
      DownloadStatus.queued => 'Waiting',
      DownloadStatus.running =>
        task.total == null
            ? formatBytes(task.received)
            : '${formatBytes(task.received)} of ${formatBytes(task.total!)}',
      DownloadStatus.done => 'Saved to ${task.folderName}',
      DownloadStatus.failed => task.error ?? 'Failed',
    };
    final saved = task.status == DownloadStatus.done;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      onTap: saved && task.savedUri != null
          ? () => viewDownload(context, task)
          : null,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 48,
          child: thumbnail != null
              ? NetImage(thumbnail)
              : ColoredBox(
                  color: panel,
                  child: Icon(
                    task.file.isVideo
                        ? Icons.movie_outlined
                        : Icons.insert_drive_file_outlined,
                    color: ink(.5),
                  ),
                ),
        ),
      ),
      title: Text(
        task.savedName ?? task.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: task.status == DownloadStatus.failed
                  ? Theme.of(context).colorScheme.error
                  : ink(.55),
            ),
          ),
          if (task.status == DownloadStatus.running) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: task.progress),
          ],
        ],
      ),
      trailing: switch (task.status) {
        DownloadStatus.failed => IconButton(
          tooltip: 'Retry',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => AppScope.read(context).downloads.retry(task),
        ),
        DownloadStatus.done => PopupMenuButton<bool>(
          tooltip: 'Open',
          icon: const Icon(Icons.check_circle_rounded, color: pawPink),
          onSelected: (file) => file
              ? viewDownload(context, task)
              : viewDownloadFolder(context, task.folderUri),
          itemBuilder: (_) => [
            if (task.savedUri != null)
              const PopupMenuItem(
                value: true,
                child: ListTile(
                  leading: Icon(Icons.open_in_new_rounded),
                  title: Text('View'),
                ),
              ),
            const PopupMenuItem(
              value: false,
              child: ListTile(
                leading: Icon(Icons.folder_open_rounded),
                title: Text('View folder'),
              ),
            ),
          ],
        ),
        _ => null,
      },
    );
  }
}
