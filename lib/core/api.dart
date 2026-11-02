import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;
  final int? status;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// Pawchive's v1 API (https://pawchive.pw/api/schema). Creator post lists are
/// paged [pageSize] at a time with the `o` offset.
class PawchiveApi {
  PawchiveApi({http.Client? client, this.session})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// The `session` cookie from signing in, sent with every request.
  String? session;

  /// Called when an authenticated call is rejected, so the app can sign out.
  VoidCallback? onUnauthorized;

  Map<String, String> get _headers => {
    'User-Agent': userAgent,
    'Accept': 'application/json',
    if (session != null) 'Cookie': '$sessionCookie=$session',
  };

  Uri _uri(String path, [Map<String, String?>? query, String base = apiBase]) {
    final params = {
      for (final entry in (query ?? const <String, String?>{}).entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };
    return Uri.parse('$base$path')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(headers ?? _headers);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 30)),
      );
    } catch (_) {
      throw ApiException('Could not reach Pawchive. Check your connection.');
    }
    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const ApiException(
        'Your Pawchive session expired. Sign in again.',
        status: 401,
      );
    }
    if (response.statusCode == 429) {
      throw const ApiException(
        'Pawchive is rate limiting requests. Try again shortly.',
        status: 429,
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        'Pawchive returned an error (${response.statusCode}).',
        status: response.statusCode,
      );
    }
    return response;
  }

  Future<Object?> _get(String path, [Map<String, String?>? query]) async {
    final response = await _send('GET', _uri(path, query));
    final body = utf8.decode(response.bodyBytes);
    // Creator post pages run to a megabyte or more; decode off the UI thread.
    if (body.length > 64 * 1024) return await compute(_decodeJson, body);
    return jsonDecode(body);
  }

  List<Map<String, dynamic>> _maps(Object? json) => [
    for (final item in (json is List ? json : const []))
      if (item is Map<String, dynamic>) item,
  ];

  /// Site-wide recent posts, optionally searched with [query].
  Future<List<Post>> recentPosts({int offset = 0, String? query}) async =>
      _maps(
        await _get('/posts', {'o': offset == 0 ? null : '$offset', 'q': query}),
      ).map(Post.fromJson).toList();

  Future<Creator> creator(String service, String id) async {
    final json = await _get('/$service/user/$id/profile');
    if (json is! Map<String, dynamic>) {
      throw const ApiException('This creator could not be found.');
    }
    return Creator.fromJson(json);
  }

  Future<List<Post>> creatorPosts(
    String service,
    String id, {
    int offset = 0,
    String? query,
    String? tag,
  }) async => _maps(
    await _get('/$service/user/$id', {
      'o': offset == 0 ? null : '$offset',
      'q': query,
      'tag': tag,
    }),
  ).map(Post.fromJson).toList();

  Future<Post> post(String service, String creatorId, String postId) async {
    final json = await _get('/$service/user/$creatorId/post/$postId');
    // Older Kemono-style servers wrap the post as {"post": {...}}.
    final map = json is Map<String, dynamic> && json['post'] is Map
        ? json['post'] as Map<String, dynamic>
        : json;
    if (map is! Map<String, dynamic>) {
      throw const ApiException('This post could not be found.');
    }
    return Post.fromJson(map);
  }

  Future<List<Announcement>> announcements(String service, String id) async =>
      _maps(await _get('/$service/user/$id/announcements'))
          .map(Announcement.fromJson)
          .toList();

  Future<List<CreatorTag>> tags(String service, String id) async =>
      _maps(await _get('/$service/user/$id/tags'))
          .map(CreatorTag.fromJson)
          .toList();

  Future<List<Creator>> links(String service, String id) async =>
      _maps(await _get('/$service/user/$id/links'))
          .map(Creator.fromJson)
          .toList();

  Future<List<Fancard>> fancards(String service, String id) async => [
    for (final json in _maps(await _get('/$service/user/$id/fancards')))
      ?Fancard.tryParse(json),
  ];

  Future<List<Comment>> comments(
    String service,
    String creatorId,
    String postId,
  ) async =>
      _maps(await _get('/$service/user/$creatorId/post/$postId/comments'))
          .map(Comment.fromJson)
          .toList();

  /// Every archived creator, about 16 MB of JSON. Only the creator search
  /// uses it, and it caches the result for the session.
  Future<List<Creator>> allCreators() async {
    final response = await _send('GET', _uri('/creators'));
    return compute(_decodeCreators, response.bodyBytes);
  }

  /// Read from the creator's DMs web page; the API has no DM endpoint.
  Future<List<DirectMessage>> directMessages(String service, String id) async =>
      parseDirectMessages(await _html('/$service/user/$id/dms'));

  /// Read from the popular posts web page; the API has no popular endpoint.
  /// Without [date] it's the last 24 hours. Week and month need the range
  /// start the site itself links to, which [PopularPage.ranges] gives.
  Future<PopularPage> popularPosts({
    PopularPeriod? period,
    String? date,
    int offset = 0,
  }) async => parsePopularPage(
    await _html('/posts/popular', {
      'date': date,
      'period': date == null ? null : period?.name,
      'o': offset == 0 ? null : '$offset',
    }),
  );

  /// Read from the creator's "similar artists" web page.
  Future<List<Creator>> recommendedCreators(String service, String id) async =>
      parseCreatorCards(await _html('/$service/user/$id/recommended'));

  Future<String> _html(String path, [Map<String, String?>? query]) async {
    final response = await _send(
      'GET',
      _uri(path, query, siteUrl),
      headers: {..._headers, 'Accept': 'text/html'},
    );
    return utf8.decode(response.bodyBytes);
  }

  // Account (requires [session]).

  Future<List<Creator>> favoriteCreators() async =>
      _maps(await _get('/account/favorites', {'type': 'artist'}))
          .map(Creator.fromJson)
          .toList();

  Future<void> addFavoriteCreator(String service, String id) =>
      _send('POST', _uri('/favorites/creator/$service/$id'));

  Future<void> removeFavoriteCreator(String service, String id) =>
      _send('DELETE', _uri('/favorites/creator/$service/$id'));
}

Object? _decodeJson(String body) => jsonDecode(body);

List<Creator> _decodeCreators(List<int> bytes) => [
  for (final item in jsonDecode(utf8.decode(bytes)) as List)
    if (item is Map<String, dynamic>) Creator.fromJson(item),
];

final _dmCard = RegExp(
  r'<article\s+class="dm-card[^"]*"[^>]*>(.*?)</article>',
  dotAll: true,
);
final _dmContent = RegExp(
  r'<div class="dm-card__content">(.*?)</div>\s*</section>',
  dotAll: true,
);
final _dmAdded = RegExp(
  r'<div class="dm-card__added">\s*Added:\s*([^<]*?)\s*</div>',
  dotAll: true,
);

@visibleForTesting
List<DirectMessage> parseDirectMessages(String html) => [
  for (final card in _dmCard.allMatches(html))
    if (_dmContent.firstMatch(card.group(1)!) case final content?)
      DirectMessage(
        content: content.group(1)!.trim(),
        added: _dmAdded.firstMatch(card.group(1)!)?.group(1),
      ),
];

enum PopularPeriod { day, week, month }

/// A page of popular posts and the date each period's current and previous
/// ranges start on, as the page links them.
class PopularPage {
  const PopularPage(this.posts, this.ranges);

  final List<Post> posts;
  final Map<PopularPeriod, ({String? current, String? previous})> ranges;
}

final _postCard = RegExp(
  r'<article\s+class="post-card[^"]*"\s+data-id="([^"]*)"\s+'
  r'data-service="([^"]*)"\s+data-user="([^"]*)"[^>]*>(.*?)</article>',
  dotAll: true,
);
final _postCardTitle = RegExp(
  r'<header class="post-card__header">\s*(.*?)\s*</header>',
  dotAll: true,
);
final _postCardImage = RegExp(
  r'class="post-card__image"\s+src="[^"]*/thumbnail/data(/[^"]+)"',
);
final _postCardTime = RegExp(r'datetime="([^"]+)"');
final _postCardFavorites = RegExp(r'(\d+)\s+favorites?');
final _periodBlock = RegExp(
  r'<div id="(daily|weekly|monthly)">(.*?)</div>',
  dotAll: true,
);
final _periodLink = RegExp(
  r'href="/posts/popular\?date=([\d-]+)&(?:amp;)?period=\w+">([^<]*)</a>',
);

@visibleForTesting
PopularPage parsePopularPage(String html) {
  final posts = <Post>[];
  for (final card in _postCard.allMatches(html)) {
    final body = card.group(4)!;
    final image = _postCardImage.firstMatch(body)?.group(1);
    posts.add(
      Post(
        id: card.group(1)!,
        service: card.group(2)!,
        user: card.group(3)!,
        title: decodeEntities(_postCardTitle.firstMatch(body)?.group(1) ?? ''),
        published: parseDate(
          _postCardTime.firstMatch(body)?.group(1)?.replaceFirst(' ', 'T'),
        ),
        // Only the thumbnail is on the page, so the file is marked preview
        // only and the viewer fetches the post for the real URL.
        file: image == null
            ? null
            : MediaFile(name: '', path: image, previewOnly: true),
        favorites: int.tryParse(
          _postCardFavorites.firstMatch(body)?.group(1) ?? '',
        ),
      ),
    );
  }
  const periods = {
    'daily': PopularPeriod.day,
    'weekly': PopularPeriod.week,
    'monthly': PopularPeriod.month,
  };
  final ranges = <PopularPeriod, ({String? current, String? previous})>{};
  for (final block in _periodBlock.allMatches(html)) {
    String? current;
    String? previous;
    for (final link in _periodLink.allMatches(block.group(2)!)) {
      if (link.group(2)!.contains('prev')) {
        previous = link.group(1);
      } else if (!link.group(2)!.contains('next')) {
        current = link.group(1);
      }
    }
    ranges[periods[block.group(1)]!] = (current: current, previous: previous);
  }
  return PopularPage(posts, ranges);
}

final _creatorCard = RegExp(
  r'<a\s+href="[^"]*"\s+class="user-card[^"]*"\s+data-id="([^"]*)"\s+'
  r'data-service="([^"]*)"(.*?)</a>',
  dotAll: true,
);
final _creatorCardName = RegExp(
  r'<div class="user-card__name">\s*(.*?)\s*</div>',
  dotAll: true,
);

@visibleForTesting
List<Creator> parseCreatorCards(String html) => [
  for (final card in _creatorCard.allMatches(html))
    Creator(
      id: card.group(1)!,
      service: card.group(2)!,
      name: decodeEntities(
        _creatorCardName.firstMatch(card.group(3)!)?.group(1) ?? card.group(1)!,
      ),
    ),
];
