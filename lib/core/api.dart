import 'dart:convert';
import 'dart:math';

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

/// One provider's v1 API, as Pawchive serves it
/// (https://pawchive.pw/api/schema); [CoomerApi] overrides what Coomer does
/// differently. Creator post lists are paged [pageSize] at a time with the
/// `o` offset.
class SiteApi {
  SiteApi(this.provider, {http.Client? client, this.session})
    : _client = client ?? http.Client();

  final Provider provider;
  final http.Client _client;

  /// The `session` cookie from signing in, sent with every request.
  String? session;

  /// Called when an authenticated call is rejected, so the app can sign out.
  VoidCallback? onUnauthorized;

  Map<String, String> get _headers => {
    'User-Agent': userAgent,
    'Accept': provider.accept,
    if (session != null) 'Cookie': '$sessionCookie=$session',
  };

  Uri _uri(String path, [Map<String, String?>? query, String? base]) {
    final params = {
      for (final entry in (query ?? const <String, String?>{}).entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };
    return Uri.parse('${base ?? provider.apiBase}$path')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    bool followRedirects = true,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(headers ?? _headers)
      ..followRedirects = followRedirects;
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 30)),
      );
    } catch (_) {
      throw ApiException(
        'Could not reach ${provider.name}. Check your connection.',
      );
    }
    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException(
        'Your ${provider.name} session expired. Sign in again.',
        status: 401,
      );
    }
    if (response.statusCode == 429) {
      throw ApiException(
        '${provider.name} is rate limiting requests. Try again shortly.',
        status: 429,
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        '${provider.name} returned an error (${response.statusCode}).',
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

  /// Read from a Patreon creator's community web page; the API has no
  /// community endpoint. Without [channel] the site redirects to the first
  /// channel. A creator with no archived community is a 404, read as an
  /// empty page.
  Future<CommunityPage> community(
    String service,
    String id, {
    String? channel,
    int offset = 0,
  }) async {
    try {
      return parseCommunityPage(
        await _html(
          '/$service/user/$id/community${channel == null ? '' : '/$channel'}',
          {'o': offset == 0 ? null : '$offset'},
        ),
      );
    } on ApiException catch (e) {
      if (e.status == 404) return const CommunityPage();
      rethrow;
    }
  }

  /// The site's most used tags, most used first (about 2000), read from the
  /// `/posts/tags` web page; the API has no tag list.
  Future<List<CreatorTag>> popularTags() async =>
      parseTagPage(await _html('/posts/tags'));

  /// Posts with [tag] across the site, newest first, read from the
  /// `/posts?tag=` web page: the API's `/posts` ignores `tag`.
  Future<List<Post>> taggedPosts(String tag, {int offset = 0}) async =>
      parsePopularPage(
        await _html('/posts', {
          'tag': tag,
          'o': offset == 0 ? null : '$offset',
        }),
      ).posts;

  /// The posts holding the file with this SHA-256, or null when the archive
  /// has no such file (a 404).
  Future<HashLookup?> searchHash(String sha256) async {
    try {
      final json = await _get('/search_hash/${sha256.toLowerCase()}');
      return HashLookup.fromJson(
        json is Map<String, dynamic> ? json : const {},
        sha256,
      );
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// A random post, from where the site's `/posts/random` redirects.
  Future<PawchiveLink> randomPost() => _random('/posts/random');

  /// A random artist, from where the site's `/artists/random` redirects.
  /// Only the id is known; the name comes from the profile.
  Future<Creator> randomCreator() async {
    final link = await _random('/artists/random');
    return Creator(id: link.user, service: link.service, name: link.user);
  }

  Future<PawchiveLink> _random(String path) async {
    final response = await _send(
      'GET',
      _uri(path, null, provider.siteUrl),
      headers: {..._headers, 'Accept': 'text/html'},
      followRedirects: false,
    );
    final link = PawchiveLink.tryParse(response.headers['location'] ?? '');
    if (link == null) {
      throw ApiException('${provider.name} did not pick anything. Try again.');
    }
    return link;
  }

  /// Read from the creator's "similar artists" web page.
  Future<List<Creator>> recommendedCreators(String service, String id) async =>
      parseCreatorCards(await _html('/$service/user/$id/recommended'));

  Future<String> _html(String path, [Map<String, String?>? query]) async {
    final response = await _send(
      'GET',
      _uri(path, query, provider.siteUrl),
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

  Future<List<Post>> favoritePosts() async => [
    for (final json in _maps(
      await _get('/account/favorites', {'type': 'post'}),
    ))
      if (Post.fromJson(json) case final post
          when post.id.isNotEmpty && post.user.isNotEmpty)
        post,
  ];

  Future<void> addFavoritePost(Post post) => _send(
    'POST',
    _uri('/favorites/post/${post.service}/${post.user}/${post.id}'),
  );

  Future<void> removeFavoritePost(Post post) => _send(
    'DELETE',
    _uri('/favorites/post/${post.service}/${post.user}/${post.id}'),
  );
}

/// Coomer's API. Its website is a single-page app, so what [SiteApi] scrapes
/// from Pawchive's pages is JSON here; see docs/coomer-api.md.
class CoomerApi extends SiteApi {
  CoomerApi({super.client}) : super(Provider.coomer);

  /// Site-wide lists are wrapped as `{count, true_count, posts}`.
  List<Post> _posts(Object? json) =>
      _maps(json is Map<String, dynamic> ? json['posts'] : json)
          .map(Post.fromJson)
          .toList();

  @override
  Future<List<Post>> recentPosts({int offset = 0, String? query}) async =>
      _posts(
        await _get('/posts', {'o': offset == 0 ? null : '$offset', 'q': query}),
      );

  @override
  Future<List<Post>> creatorPosts(
    String service,
    String id, {
    int offset = 0,
    String? query,
    String? tag,
  }) async => _posts(
    await _get('/$service/user/$id/posts', {
      'o': offset == 0 ? null : '$offset',
      'q': query,
      'tag': tag,
    }),
  );

  @override
  Future<List<CreatorTag>> tags(String service, String id) async =>
      mergeTags(await super.tags(service, id));

  @override
  Future<List<DirectMessage>> directMessages(String service, String id) async =>
      [
        for (final json in _maps(await _get('/$service/user/$id/dms')))
          DirectMessage(
            content: '${json['content'] ?? ''}',
            added: (json['published'] ?? json['added'])?.toString(),
          ),
      ];

  @override
  Future<PopularPage> popularPosts({
    PopularPeriod? period,
    String? date,
    int offset = 0,
  }) async => parsePopularJson(
    await _get('/posts/popular', {
      'date': date,
      'period': date == null ? null : period?.name,
      'o': offset == 0 ? null : '$offset',
    }),
  );

  /// Coomer archives no communities.
  @override
  Future<CommunityPage> community(
    String service,
    String id, {
    String? channel,
    int offset = 0,
  }) async => const CommunityPage();

  @override
  Future<List<CreatorTag>> popularTags() async => mergeTags(
    _maps(await _get('/posts/tags')).map(CreatorTag.fromJson).toList(),
  );

  @override
  Future<List<Post>> taggedPosts(String tag, {int offset = 0}) async => _posts(
    await _get('/posts', {'tag': tag, 'o': offset == 0 ? null : '$offset'}),
  );

  /// An unknown hash is a 200 with no posts here, not a 404.
  @override
  Future<HashLookup?> searchHash(String sha256) async {
    final lookup = await super.searchHash(sha256);
    return lookup == null || lookup.posts.isEmpty ? null : lookup;
  }

  @override
  Future<PawchiveLink> _random(String path) async {
    final json = await _get(path);
    final service = json is Map ? '${json['service'] ?? ''}' : '';
    final user = json is Map ? '${json['artist_id'] ?? ''}' : '';
    if (service.isEmpty || user.isEmpty) {
      throw ApiException('${provider.name} did not pick anything. Try again.');
    }
    return PawchiveLink(
      service: service,
      user: user,
      post: (json as Map)['post_id']?.toString(),
    );
  }

  @override
  Future<List<Creator>> recommendedCreators(String service, String id) async =>
      _maps(await _get('/$service/user/$id/recommended'))
          .map(Creator.fromJson)
          .toList();
}

/// Every enabled provider behind one API. Calls about a creator or post go
/// to the provider carrying their service, whether or not it is enabled, so
/// saved posts still open. Site-wide lists that can be mixed (recent posts,
/// creators, hash lookup) ask every enabled provider; the ones ranked per
/// site (popular, tags, random) ask [browse].
class ArchiveApi {
  ArchiveApi({http.Client? client, String? session})
    : _sites = {
        Provider.pawchive: SiteApi(
          Provider.pawchive,
          client: client,
          session: session,
        ),
        Provider.coomer: CoomerApi(client: client),
      };

  final Map<Provider, SiteApi> _sites;
  Provider? _browse;

  /// The providers the sidebar has switched on, never empty.
  Set<Provider> enabled = {Provider.pawchive};

  bool isEnabled(Provider provider) => enabled.contains(provider);

  /// The enabled provider whose popular posts, tags and random picks are
  /// shown.
  Provider get browse => isEnabled(_browse ?? Provider.pawchive)
      ? _browse ?? Provider.pawchive
      : Provider.all.firstWhere(isEnabled, orElse: () => Provider.pawchive);

  set browse(Provider value) => _browse = value;

  SiteApi on(Provider provider) => _sites[provider]!;
  SiteApi _of(String service) => on(Provider.of(service));

  /// Only Pawchive has accounts in Pawress so far.
  String? get session => on(Provider.pawchive).session;
  set session(String? value) => on(Provider.pawchive).session = value;

  set onUnauthorized(VoidCallback? value) =>
      on(Provider.pawchive).onUnauthorized = value;

  /// [call] on every enabled provider. One that fails is left out unless
  /// they all do, so a provider that is down doesn't empty the others.
  Future<List<T>> _each<T>(Future<T> Function(SiteApi api) call) async {
    final results = <T>[];
    Object? failure;
    await Future.wait([
      for (final provider in Provider.all)
        if (isEnabled(provider))
          call(on(provider)).then<void>(
            results.add,
            onError: (Object e) {
              failure ??= e;
            },
          ),
    ]);
    if (results.isEmpty && failure != null) throw failure!;
    return results;
  }

  /// Recent posts from every enabled provider, taken in turns.
  Future<List<Post>> recentPosts({int offset = 0, String? query}) async =>
      interleave(
        await _each((api) => api.recentPosts(offset: offset, query: query)),
      );

  Future<Creator> creator(String service, String id) =>
      _of(service).creator(service, id);

  Future<List<Post>> creatorPosts(
    String service,
    String id, {
    int offset = 0,
    String? query,
    String? tag,
  }) =>
      _of(service)
          .creatorPosts(service, id, offset: offset, query: query, tag: tag);

  Future<Post> post(String service, String creatorId, String postId) =>
      _of(service).post(service, creatorId, postId);

  Future<List<Announcement>> announcements(String service, String id) =>
      _of(service).announcements(service, id);

  Future<List<CreatorTag>> tags(String service, String id) =>
      _of(service).tags(service, id);

  Future<List<Creator>> links(String service, String id) =>
      _of(service).links(service, id);

  Future<List<Fancard>> fancards(String service, String id) =>
      _of(service).fancards(service, id);

  Future<List<Comment>> comments(
    String service,
    String creatorId,
    String postId,
  ) => _of(service).comments(service, creatorId, postId);

  /// Every enabled provider's creators.
  Future<List<Creator>> allCreators() async => [
    for (final creators in await _each((api) => api.allCreators())) ...creators,
  ];

  Future<List<DirectMessage>> directMessages(String service, String id) =>
      _of(service).directMessages(service, id);

  Future<PopularPage> popularPosts({
    PopularPeriod? period,
    String? date,
    int offset = 0,
  }) => on(browse).popularPosts(period: period, date: date, offset: offset);

  Future<CommunityPage> community(
    String service,
    String id, {
    String? channel,
    int offset = 0,
  }) => _of(service).community(service, id, channel: channel, offset: offset);

  Future<List<CreatorTag>> popularTags([Provider? provider]) =>
      on(provider ?? browse).popularTags();

  Future<List<Post>> taggedPosts(
    String tag, {
    int offset = 0,
    Provider? provider,
  }) => on(provider ?? browse).taggedPosts(tag, offset: offset);

  /// The posts holding the file on any enabled provider, or null when none
  /// has it.
  Future<HashLookup?> searchHash(String sha256) async {
    final found = [...(await _each((api) => api.searchHash(sha256))).nonNulls];
    if (found.isEmpty) return null;
    return HashLookup(
      hash: found.first.hash,
      posts: [for (final lookup in found) ...lookup.posts],
      discordCount: found.fold(0, (sum, lookup) => sum + lookup.discordCount),
      mime: found.map((lookup) => lookup.mime).nonNulls.firstOrNull,
      size: found.map((lookup) => lookup.size).nonNulls.firstOrNull,
    );
  }

  Future<PawchiveLink> randomPost() => on(browse).randomPost();
  Future<Creator> randomCreator() => on(browse).randomCreator();

  Future<List<Creator>> recommendedCreators(String service, String id) =>
      _of(service).recommendedCreators(service, id);

  // Account (Pawchive only; requires [session]).

  Future<List<Creator>> favoriteCreators() =>
      on(Provider.pawchive).favoriteCreators();

  Future<void> addFavoriteCreator(String service, String id) =>
      on(Provider.pawchive).addFavoriteCreator(service, id);

  Future<void> removeFavoriteCreator(String service, String id) =>
      on(Provider.pawchive).removeFavoriteCreator(service, id);

  Future<List<Post>> favoritePosts() => on(Provider.pawchive).favoritePosts();

  Future<void> addFavoritePost(Post post) =>
      on(Provider.pawchive).addFavoritePost(post);

  Future<void> removeFavoritePost(Post post) =>
      on(Provider.pawchive).removeFavoritePost(post);
}

/// [lists] taken in turns, one item from each until all run out.
List<T> interleave<T>(List<List<T>> lists) {
  if (lists.length == 1) return lists.first;
  final longest = lists.fold(0, (most, list) => max(most, list.length));
  return [
    for (var i = 0; i < longest; i++)
      for (final list in lists)
        if (i < list.length) list[i],
  ];
}

/// Tags by their [cleanTag] name, most used first. Coomer lists a tag once
/// per markup variant ("ads", "ads</p>"); the most used variant is kept,
/// since searching by the clean name only finds that one.
@visibleForTesting
List<CreatorTag> mergeTags(List<CreatorTag> tags) {
  final best = <String, CreatorTag>{};
  for (final tag in tags) {
    final name = cleanTag(tag.tag);
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    if ((best[key]?.postCount ?? -1) < tag.postCount) {
      best[key] = CreatorTag(name, tag.postCount);
    }
  }
  return best.values.toList()
    ..sort((a, b) => b.postCount.compareTo(a.postCount));
}

/// Coomer's `/posts/popular`: the posts, the range in words and, per
/// period, `[previous, next, current]` start dates. Its `next` runs into the
/// future, so one after `props.today` is dropped like Pawchive's.
@visibleForTesting
PopularPage parsePopularJson(Object? json) {
  final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
  final info = map['info'] is Map ? map['info'] as Map : const {};
  final props = map['props'] is Map ? map['props'] as Map : const {};
  final dates = info['navigation_dates'];
  final today = props['today']?.toString();
  final ranges = <PopularPeriod, PopularRange>{};
  for (final period in PopularPeriod.values) {
    final range = dates is Map ? dates[period.name] : null;
    if (range is! List || range.length < 3) continue;
    final next = '${range[1]}';
    ranges[period] = (
      current: '${range[2]}',
      previous: '${range[0]}',
      next: today != null && next.compareTo(today) > 0 ? null : next,
    );
  }
  return PopularPage(
    [
      for (final item in map['posts'] as List? ?? const [])
        if (item is Map<String, dynamic>) Post.fromJson(item),
    ],
    ranges,
    label: info['range_desc']?.toString(),
  );
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

/// The start dates a popular page links for one period: the range shown
/// (null when it is the page's own period, which isn't linked) and the
/// ranges before and after it (null at the newest).
typedef PopularRange = ({String? current, String? previous, String? next});

/// A page of popular posts, the range it covers in words ("October 20,
/// 2026 - October 27, 2026", "the past 24 hours") and, per period, the
/// dates it links.
class PopularPage {
  const PopularPage(this.posts, this.ranges, {this.label});

  final List<Post> posts;
  final Map<PopularPeriod, PopularRange> ranges;
  final String? label;
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
final _popularLabel = RegExp(
  r'site-section__heading">[^<]*<span[^>]*>([^<]*)</span>',
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
  final ranges = <PopularPeriod, PopularRange>{};
  for (final block in _periodBlock.allMatches(html)) {
    String? current;
    String? previous;
    String? next;
    for (final link in _periodLink.allMatches(block.group(2)!)) {
      final text = link.group(2)!;
      if (text.contains('prev')) {
        previous = link.group(1);
      } else if (text.contains('next')) {
        next = link.group(1);
      } else {
        current = link.group(1);
      }
    }
    ranges[periods[block.group(1)]!] = (
      current: current,
      previous: previous,
      next: next,
    );
  }
  final label = _popularLabel.firstMatch(html)?.group(1);
  return PopularPage(posts, ranges, label: label == null ? null : _text(label));
}

final _tagCard = RegExp(
  r'<article>\s*<a href="/posts\?tag=[^"]*">\s*<span>(.*?)</span>\s*'
  r'<span>(\d+)</span>',
  dotAll: true,
);

@visibleForTesting
List<CreatorTag> parseTagPage(String html) => [
  for (final card in _tagCard.allMatches(html))
    CreatorTag(_text(card.group(1)!), int.parse(card.group(2)!)),
];

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

final _channelLink = RegExp(
  r'<a\s+class="chat-page__channel([^"]*)"\s+href="[^"]*/community/([^"/?]+)"'
  r'[^>]*>(.*?)</a>',
  dotAll: true,
);
final _channelName = RegExp(
  r'<span class="chat-page__channel-name">\s*(.*?)\s*</span>',
  dotAll: true,
);
final _channelCount = RegExp(r'chat-page__channel-count">\s*(\d+)');
final _messageStart = RegExp(r'<div class="cmsg[\s"]');
final _messageAuthor = RegExp(r'<span class="cmsg__author"[^>]*>(.*?)</span>');
final _messageAvatar = RegExp(r'<img class="cmsg__avatar" src="([^"]+)"');
final _messageLetter = RegExp(
  r'cmsg__avatar--letter"\s+style="background:\s*hsl\((\d+)[^"]*">([^<]*)<',
);
final _messageTime = RegExp(r'class="cmsg__time"\s+datetime="([^"]+)"');
final _messageReplyAuthor = RegExp(
  r'<span class="cmsg__reply-author"[^>]*>(.*?)</span>',
  dotAll: true,
);
final _messageReplyText = RegExp(
  r'<span class="cmsg__reply-text">(.*?)</span>',
  dotAll: true,
);
final _messageText = RegExp(
  r'<div class="cmsg__text">(.*?)</div>',
  dotAll: true,
);
final _messageImage = RegExp(
  r'<a class="cmsg__image" href="([^"]+)"[^>]*>\s*<img src="([^"]+)"',
);
final _messageEmbed = RegExp(
  r'<a class="cmsg__embed" href="([^"]+)"[^>]*>(.*?)</a>',
  dotAll: true,
);
final _messageRange = RegExp(r'Showing\s+\d+\s*-\s*(\d+)\s+of\s+(\d+)');

String _absolute(String url) =>
    url.startsWith('/') ? '${Provider.pawchive.siteUrl}$url' : url;

/// The text of an element, without its tags.
String _text(String html) =>
    decodeEntities(html.replaceAll(RegExp(r'<[^>]*>'), '')).trim();

@visibleForTesting
CommunityPage parseCommunityPage(String html) {
  final channels = [
    for (final link in _channelLink.allMatches(html))
      CommunityChannel(
        id: link.group(2)!,
        name: _text(
          _channelName.firstMatch(link.group(3)!)?.group(1) ?? link.group(2)!,
        ),
        count:
            int.tryParse(
              _channelCount.firstMatch(link.group(3)!)?.group(1) ?? '',
            ) ??
            0,
        active: link.group(1)!.contains('is-active'),
      ),
  ];
  final starts = [for (final m in _messageStart.allMatches(html)) m.start];
  final messages = <CommunityMessage>[];
  for (final (index, start) in starts.indexed) {
    final block = html.substring(
      start,
      index + 1 < starts.length ? starts[index + 1] : html.length,
    );
    final opening = block.substring(0, block.indexOf('>') + 1);
    final author = _messageAuthor.firstMatch(block)?.group(1);
    final previous = messages.lastOrNull;
    // A message without a head continues the previous author's run.
    final continued =
        !opening.contains('cmsg--head') && author == null && previous != null;
    final avatar = _messageAvatar.firstMatch(block)?.group(1);
    final letter = _messageLetter.firstMatch(block);
    final replyAuthor = _messageReplyAuthor.firstMatch(block)?.group(1);
    final replyText = _messageReplyText.firstMatch(block)?.group(1);
    messages.add(
      CommunityMessage(
        author: author != null
            ? _text(author)
            : continued
            ? previous.author
            : '',
        content: _messageText.firstMatch(block)?.group(1)?.trim() ?? '',
        time: parseDate(_messageTime.firstMatch(block)?.group(1)),
        fromCreator: continued
            ? previous.fromCreator
            : opening.contains('cmsg--creator'),
        avatarUrl: avatar == null ? null : _absolute(avatar),
        avatarLetter: letter == null ? null : _text(letter.group(2)!),
        avatarHue: letter == null ? null : int.tryParse(letter.group(1)!),
        replyAuthor: replyAuthor == null ? null : _text(replyAuthor),
        replyText: replyText == null ? null : _text(replyText),
        images: [
          for (final image in _messageImage.allMatches(block))
            (
              url: _absolute(decodeEntities(image.group(1)!)),
              thumbnail: _absolute(decodeEntities(image.group(2)!)),
            ),
        ],
        embeds: [
          for (final embed in _messageEmbed.allMatches(block))
            (
              url: decodeEntities(embed.group(1)!),
              title: _text(embed.group(2)!),
            ),
        ],
        continued: continued,
      ),
    );
  }
  final range = _messageRange.firstMatch(html);
  return CommunityPage(
    channels: channels,
    messages: messages,
    end: int.tryParse(range?.group(1) ?? '') ?? messages.length,
    total: int.tryParse(range?.group(2) ?? '') ?? messages.length,
  );
}
