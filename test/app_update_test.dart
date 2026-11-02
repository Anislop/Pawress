import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawress/core/app_update.dart';

Map<String, Object?> _release(
  String tag,
  List<String> assets, {
  String body = '',
  bool draft = false,
  bool prerelease = false,
}) => {
  'tag_name': tag,
  'name': tag == 'nightly' ? 'Nightly (abc1234)' : 'Pawress $tag',
  'html_url': 'https://github.com/Anislop/Pawress/releases/tag/$tag',
  'draft': draft,
  'prerelease': prerelease,
  'body': body,
  'assets': [
    for (final name in assets)
      {
        'name': name,
        'state': 'uploaded',
        'size': 1234,
        'browser_download_url':
            'https://github.com/Anislop/Pawress/releases/download/$tag/$name',
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppRelease.newest', () {
    test('picks the highest build above the installed one', () {
      final release = AppRelease.newest([
        _release('v1.0.0', ['pawress-1.0.0-12.apk']),
        _release('nightly', [
          'pawress-1.0.0-15.apk',
          'pawress-1.0.0-15-debug.apk',
        ], prerelease: true),
      ], installedBuild: 12);
      expect(release!.build, 15);
      expect(release.tag, 'nightly');
      expect(release.version, '1.0.0');
      expect(release.prerelease, isTrue);
      expect(release.apkUrl, endsWith('/pawress-1.0.0-15.apk'));
      expect(release.size, 1234);
    });

    test('returns null when nothing is newer', () {
      expect(
        AppRelease.newest([
          _release('v1.0.0', ['pawress-1.0.0-12.apk']),
        ], installedBuild: 12),
        isNull,
      );
    });

    test('ignores drafts, debug APKs and files off GitHub', () {
      final listing = [
        _release('draft', ['pawress-1.0.0-99.apk'], draft: true),
        _release('v2', ['pawress-1.0.0-50-debug.apk']),
        {
          ..._release('v3', []),
          'assets': [
            {
              'name': 'pawress-1.0.0-60.apk',
              'browser_download_url': 'https://example.com/pawress.apk',
            },
          ],
        },
      ];
      expect(AppRelease.newest(listing, installedBuild: 1), isNull);
      expect(AppRelease.newest('not a list', installedBuild: 1), isNull);
    });
  });

  test('a nightly shows its commit message as the change', () {
    final release = AppRelease.newest([
      _release(
        'nightly',
        ['pawress-1.0.0-3.apk'],
        body:
            'Add downloads\n\nPick a folder once.\n\n'
            '${AppRelease.commitEnd}\nBuilt from abc1234.',
      ),
    ], installedBuild: 1)!;
    expect(release.change.title, 'Add downloads');
    expect(release.change.description, 'Pick a folder once.');

    final versioned = AppRelease.newest([
      _release('v1.1.0', ['pawress-1.1.0-4.apk'], body: 'Notes'),
    ], installedBuild: 1)!;
    expect(versioned.change.title, 'Pawress v1.1.0');
    expect(versioned.change.description, 'Notes');
  });

  group('AppUpdater', () {
    const channel = MethodChannel('pawress/updater');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('checks GitHub releases against the installed build', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'appVersion');
        return {'name': '1.0.0', 'build': 7};
      });
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        expect(request.headers['User-Agent'], 'Pawress updater');
        return http.Response(
          jsonEncode([
            _release('nightly', ['pawress-1.0.0-8.apk']),
          ]),
          200,
        );
      });
      final updater = AppUpdater(
        channel: channel,
        client: client,
        repository: 'Anislop/Pawress',
      );

      expect((await updater.installedVersion())!.label, '1.0.0 (build 7)');
      final release = await updater.check();
      expect(release!.build, 8);
      expect(requested!.path, '/repos/Anislop/Pawress/releases');
    });

    test('a failed GitHub request throws', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'name': '1.0.0', 'build': 7},
      );
      final updater = AppUpdater(
        channel: channel,
        client: MockClient((_) async => http.Response('rate limited', 403)),
      );
      expect(updater.check(), throwsA(isA<http.ClientException>()));
    });

    test('without the Android host there is nothing to update', () async {
      final updater = AppUpdater(
        channel: channel,
        client: MockClient((_) async => fail('should not request')),
      );
      expect(await updater.check(), isNull);
    });

    test('maps native refusals to update failures', () async {
      final release = AppRelease.newest([
        _release('nightly', ['pawress-1.0.0-8.apk']),
      ], installedBuild: 1)!;
      final updater = AppUpdater(channel: channel);
      for (final (code, failure) in [
        ('UPDATE_SIGNATURE', UpdateFailure.signature),
        ('UPDATE_NOT_NEWER', UpdateFailure.notNewer),
        ('UPDATE_INVALID', UpdateFailure.invalid),
        ('IO', UpdateFailure.network),
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'installUpdate');
          expect((call.arguments as Map)['url'], release.apkUrl);
          throw PlatformException(code: code);
        });
        await expectLater(
          updater.install(release),
          throwsA(
            isA<UpdateException>().having((e) => e.failure, 'failure', failure),
          ),
        );
      }
    });
  });
}
