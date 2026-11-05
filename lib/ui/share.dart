import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config.dart';
import '../core/downloads.dart';
import '../core/intents.dart';
import '../core/models.dart';

/// Where [shareImage] and [setImageAs] put the file they hand to another
/// app. MainActivity's FileProvider only exposes this folder.
const _sharedFolder = 'shared';

/// Sends a post's image to Android's share sheet.
Future<void> shareImage(BuildContext context, Post post, MediaFile file) =>
    _handOver(context, post, file, AndroidIntents.shareFile);

/// Offers a post's image to "Set as": the wallpaper picker, a contact
/// photo and so on, which crop it themselves.
Future<void> setImageAs(BuildContext context, Post post, MediaFile file) =>
    _handOver(context, post, file, AndroidIntents.setAs);

/// Copies the image out of the image cache (the viewer usually loaded it
/// already, so nothing is downloaded again) into the shared folder, which
/// holds only the latest file, and passes it to [send].
Future<void> _handOver(
  BuildContext context,
  Post post,
  MediaFile file,
  Future<bool> Function(String path, String mime) send,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  final url = file.fullUrl ?? file.thumbnailUrl;
  if (url == null) return say('This image is not available yet.');
  try {
    final cached = await DefaultCacheManager().getSingleFile(
      url,
      headers: mediaHeaders,
    );
    final folder = Directory(
      '${(await getTemporaryDirectory()).path}/$_sharedFolder',
    );
    if (await folder.exists()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    final copy = await cached.copy(
      '${folder.path}/${downloadName(post, file)}',
    );
    if (!await send(copy.path, mimeOf(file.extension))) {
      say('No app can take this image.');
    }
  } catch (_) {
    say('Could not get the image. Try again in a moment.');
  }
}

/// The bytes the image cache and shared files take on the device.
Future<int> imageCacheBytes() async {
  final temp = await getTemporaryDirectory();
  var total = 0;
  for (final name in [DefaultCacheManager.key, _sharedFolder]) {
    final folder = Directory('${temp.path}/$name');
    if (!await folder.exists()) continue;
    await for (final entry in folder.list(recursive: true)) {
      if (entry is File) total += await entry.length();
    }
  }
  return total;
}

/// Empties the image cache: thumbnails, avatars and full images load again
/// as they're shown.
Future<void> clearImageCache() async {
  await DefaultCacheManager().emptyCache();
  final temp = await getTemporaryDirectory();
  final shared = Directory('${temp.path}/$_sharedFolder');
  if (await shared.exists()) await shared.delete(recursive: true);
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
}
