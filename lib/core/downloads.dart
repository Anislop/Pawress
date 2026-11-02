import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:saf_stream/saf_stream.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';

enum DownloadStatus { queued, running, done, failed }

class DownloadTask {
  DownloadTask({
    required this.post,
    required this.file,
    required this.folderUri,
    required this.folderName,
  });

  final Post post;
  final MediaFile file;
  final String folderUri;
  final String folderName;

  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int? total;
  String? error;

  /// The saved file's name, which Android may have numbered to avoid a
  /// clash.
  String? savedName;

  /// The file as the full post lists it, when it had to be fetched; popular
  /// posts only know a thumbnail path, not the original name.
  MediaFile? _resolved;

  String get name => downloadName(post, _resolved ?? file);

  double? get progress =>
      total == null || total == 0 ? null : (received / total!).clamp(0, 1);

  bool get finished =>
      status == DownloadStatus.done || status == DownloadStatus.failed;
}

/// `<post id>_<original name>`, so files from different posts don't clash.
String downloadName(Post post, MediaFile file) {
  final original = file.name.isNotEmpty
      ? file.name
      : file.path.substring(file.path.lastIndexOf('/') + 1);
  return '${post.id}_${original.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
}

/// Writes a download into a folder the user picked.
abstract class DownloadTarget {
  /// Returns a handle for [write] and [close], and the name actually used.
  Future<({String handle, String? name})> open(
    String folderUri,
    String name,
    String mime,
  );
  Future<void> write(String handle, Uint8List bytes);
  Future<void> close(String handle);
}

/// Storage access framework folders, through saf_stream.
class SafTarget implements DownloadTarget {
  final _saf = SafStream();

  @override
  Future<({String handle, String? name})> open(
    String folderUri,
    String name,
    String mime,
  ) async {
    final info = await _saf.startWriteStream(folderUri, name, mime);
    return (handle: info.session, name: info.fileResult.fileName);
  }

  @override
  Future<void> write(String handle, Uint8List bytes) =>
      _saf.writeChunk(handle, bytes);

  @override
  Future<void> close(String handle) => _saf.endWriteStream(handle);
}

/// A queue of media downloads. It keeps to the file host's limits: at most
/// [parallel] at once and [spacing] between starts.
class DownloadManager extends ChangeNotifier {
  DownloadManager(
    this._api, {
    http.Client? client,
    DownloadTarget? target,
    this.parallel = 2,
    this.spacing = const Duration(seconds: 1),
  }) : _client = client ?? http.Client(),
       _target = target ?? SafTarget();

  final PawchiveApi _api;
  final http.Client _client;
  final DownloadTarget _target;
  final int parallel;
  final Duration spacing;

  final List<DownloadTask> tasks = [];

  /// Called when the queue empties, with how many files saved and failed
  /// since it was last empty.
  void Function(int saved, int failed)? onIdle;

  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pumping = false;
  int _running = 0;
  int _saved = 0;
  int _failed = 0;

  int get active => tasks.where((task) => !task.finished).length;

  void enqueue(
    Post post,
    Iterable<MediaFile> files, {
    required String folderUri,
    required String folderName,
  }) {
    for (final file in files) {
      tasks.add(
        DownloadTask(
          post: post,
          file: file,
          folderUri: folderUri,
          folderName: folderName,
        ),
      );
    }
    notifyListeners();
    unawaited(_pump());
  }

  void retry(DownloadTask task) {
    if (task.status != DownloadStatus.failed) return;
    task
      ..status = DownloadStatus.queued
      ..error = null
      ..received = 0;
    notifyListeners();
    unawaited(_pump());
  }

  void clearFinished() {
    tasks.removeWhere((task) => task.finished);
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final next = tasks
            .where((task) => task.status == DownloadStatus.queued)
            .firstOrNull;
        if (next == null || _running >= parallel) break;
        final wait = spacing - DateTime.now().difference(_lastStart);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        if (next.status != DownloadStatus.queued) continue;
        _lastStart = DateTime.now();
        _running++;
        next.status = DownloadStatus.running;
        notifyListeners();
        unawaited(
          _run(next).whenComplete(() {
            _running--;
            unawaited(_pump());
          }),
        );
      }
    } finally {
      _pumping = false;
    }
    if (_running == 0 && active == 0 && _saved + _failed > 0) {
      onIdle?.call(_saved, _failed);
      _saved = 0;
      _failed = 0;
    }
  }

  Future<void> _run(DownloadTask task) async {
    String? handle;
    try {
      final url = await _resolve(task);
      final response = await _client
          .send(
            http.Request('GET', Uri.parse(url))..headers.addAll(mediaHeaders),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 400) {
        throw ApiException('The file host returned ${response.statusCode}.');
      }
      task.total = response.contentLength;
      final opened = await _target.open(
        task.folderUri,
        task.name,
        _mimeOf((task._resolved ?? task.file).extension),
      );
      handle = opened.handle;
      task.savedName = opened.name ?? task.name;

      // Platform channel calls are slow, so bytes go over in larger blocks.
      final buffer = BytesBuilder(copy: false);
      var lastNotify = DateTime.now();
      await for (final chunk in response.stream) {
        buffer.add(chunk);
        task.received += chunk.length;
        if (buffer.length >= 512 * 1024) {
          await _target.write(handle, buffer.takeBytes());
        }
        if (DateTime.now().difference(lastNotify).inMilliseconds > 250) {
          lastNotify = DateTime.now();
          notifyListeners();
        }
      }
      if (buffer.isNotEmpty) await _target.write(handle, buffer.takeBytes());
      await _target.close(handle);
      handle = null;
      task.status = DownloadStatus.done;
      _saved++;
    } catch (e) {
      if (handle != null) {
        try {
          await _target.close(handle);
        } catch (_) {}
      }
      task
        ..status = DownloadStatus.failed
        ..error = e is ApiException ? e.message : 'Download failed: $e';
      _failed++;
    }
    notifyListeners();
  }

  /// Preview-only files (and popular posts, which only list a thumbnail)
  /// need the post fetched again for a signed URL.
  Future<String> _resolve(DownloadTask task) async {
    final direct = task.file.fullUrl;
    if (direct != null) return direct;
    final post = await _api.post(
      task.post.service,
      task.post.user,
      task.post.id,
    );
    for (final file in post.files) {
      if (file.path == task.file.path && file.fullUrl != null) {
        task._resolved = file;
        return file.fullUrl!;
      }
    }
    throw const ApiException('This file is not available to download.');
  }
}

String _mimeOf(String extension) => switch (extension) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  'bmp' => 'image/bmp',
  'avif' => 'image/avif',
  'mp4' || 'm4v' => 'video/mp4',
  'webm' => 'video/webm',
  'mov' => 'video/quicktime',
  'mkv' => 'video/x-matroska',
  'mp3' => 'audio/mpeg',
  'wav' => 'audio/wav',
  'ogg' => 'audio/ogg',
  'flac' => 'audio/flac',
  'm4a' => 'audio/mp4',
  'zip' => 'application/zip',
  'rar' => 'application/vnd.rar',
  '7z' => 'application/x-7z-compressed',
  'pdf' => 'application/pdf',
  'psd' => 'image/vnd.adobe.photoshop',
  'txt' => 'text/plain',
  _ => 'application/octet-stream',
};
