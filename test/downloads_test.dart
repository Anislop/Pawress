import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawress/core/api.dart';
import 'package:pawress/core/downloads.dart';
import 'package:pawress/core/models.dart';

class _MemoryTarget implements DownloadTarget {
  final files = <String, BytesBuilder>{};
  final names = <String, String>{};

  @override
  Future<({String handle, String? name})> open(
    String folderUri,
    String name,
    String mime,
  ) async {
    final handle = 'h${files.length}';
    files[handle] = BytesBuilder();
    names[handle] = name;
    return (handle: handle, name: name);
  }

  @override
  Future<void> write(String handle, Uint8List bytes) async =>
      files[handle]!.add(bytes);

  @override
  Future<void> close(String handle) async {}
}

void main() {
  test(
    'resolves preview-only files through the post, then saves them',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.toString());
        expect(request.headers['User-Agent'], startsWith('Pawress/'));
        if (request.url.path == '/api/v1/patreon/user/7/post/1') {
          return http.Response(
            jsonEncode({
              'id': '1',
              'user': '7',
              'service': 'patreon',
              'title': 'Post',
              'file': {
                'name': 'Cover art.png',
                'path': '/aa/bb/cover.png',
                'preview_only': true,
                'temp_url': 'https://t1.pawchive.pw/f/cover.png',
              },
            }),
            200,
          );
        }
        if (request.url.host == 't1.pawchive.pw') {
          return http.Response.bytes([1, 2, 3], 200);
        }
        return http.Response('', 404);
      });
      final target = _MemoryTarget();
      final idle = Completer<(int, int)>();
      final manager = DownloadManager(
        PawchiveApi(client: client),
        client: client,
        target: target,
        spacing: Duration.zero,
      )..onIdle = (saved, failed) => idle.complete((saved, failed));

      // A popular post knows only the thumbnail path.
      const post = Post(
        id: '1',
        user: '7',
        service: 'patreon',
        title: 'Post',
        file: MediaFile(name: '', path: '/aa/bb/cover.png', previewOnly: true),
      );
      manager.enqueue(
        post,
        [post.file!],
        folderUri: 'tree',
        folderName: 'Pics',
      );

      expect(await idle.future, (1, 0));
      final task = manager.tasks.single;
      expect(task.status, DownloadStatus.done);
      expect(task.savedName, '1_Cover art.png');
      expect(target.files.values.single.toBytes(), [1, 2, 3]);
    },
  );

  test('a failed download is reported and can be retried', () async {
    var fail = true;
    final client = MockClient(
      (request) async =>
          fail ? http.Response('', 403) : http.Response.bytes([9], 200),
    );
    final results = <(int, int)>[];
    final manager = DownloadManager(
      PawchiveApi(client: client),
      client: client,
      target: _MemoryTarget(),
      spacing: Duration.zero,
    )..onIdle = (saved, failed) => results.add((saved, failed));
    const post = Post(id: '2', user: '7', service: 'patreon', title: '');
    const file = MediaFile(name: 'a.jpg', path: '/a/b/a.jpg');

    manager.enqueue(post, [file], folderUri: 'tree', folderName: 'Pics');
    await pumpEventQueue();
    expect(manager.tasks.single.status, DownloadStatus.failed);
    expect(results, [(0, 1)]);

    fail = false;
    manager.retry(manager.tasks.single);
    await pumpEventQueue();
    expect(manager.tasks.single.status, DownloadStatus.done);
    expect(results, [(0, 1), (1, 0)]);
  });
}
