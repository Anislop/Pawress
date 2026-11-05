import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saf_util/saf_util.dart';

import '../core/downloads.dart';
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

/// The download queue: progress, failures with retry, and finished files.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.read(context).downloads;
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final tasks = downloads.tasks.reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads'),
            actions: [
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
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
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
        DownloadStatus.done => const Icon(
          Icons.check_circle_rounded,
          color: pawPink,
        ),
        _ => null,
      },
    );
  }
}
