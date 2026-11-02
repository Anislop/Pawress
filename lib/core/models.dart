import 'config.dart';

/// Pawchive returns ids as strings but some fields as numbers or booleans in
/// other places; these readers accept either.
String _str(Object? value) => value == null ? '' : value.toString();

String? _optStr(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_str(value)) ?? 0;

bool _bool(Object? value) => value == true || value == 'true' || value == 1;

/// Parses ISO dates ("2026-10-31T16:41:47") and epoch seconds. Pawchive's
/// dates carry no zone and are UTC.
DateTime? parseDate(Object? value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
      isUtc: true,
    );
  }
  final text = value.toString();
  if (text.isEmpty) return null;
  final hasZone =
      text.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(text);
  return DateTime.tryParse(hasZone ? text : '${text}Z');
}

final _arrayItem = RegExp(r'"((?:[^"\\]|\\.)*)"|([^,{}]+)');

/// Post tags arrive as a JSON list from single posts but as a Postgres array
/// literal from post lists: `{"GRANDE CUCULO",PROCIONI}`.
List<String> parseTags(Object? value) {
  if (value is List) return [for (final tag in value) _str(tag)];
  if (value is! String || value.isEmpty) return const [];
  return [
    for (final match in _arrayItem.allMatches(value))
      if (match.group(1) case final quoted?)
        quoted.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!)
      else
        match.group(2)!.trim(),
  ].where((tag) => tag.isNotEmpty && tag != 'NULL').toList();
}

/// The site an archived creator comes from.
class Service {
  const Service(this.id, this.label, this.color, this.profileUrl);

  final String id;
  final String label;
  final int color;

  /// The creator's page on the original site, from their id and public id.
  final String Function(String id, String? publicId) profileUrl;

  static final _known = <String, Service>{
    'patreon': Service(
      'patreon',
      'Patreon',
      0xFFF96854,
      (id, _) => 'https://www.patreon.com/user?u=$id',
    ),
    'fanbox': Service(
      'fanbox',
      'Pixiv Fanbox',
      0xFF0096FA,
      (id, _) => 'https://www.pixiv.net/fanbox/creator/$id',
    ),
    'discord': Service(
      'discord',
      'Discord',
      0xFF5865F2,
      (id, _) => 'https://discord.com/channels/$id',
    ),
    'fantia': Service(
      'fantia',
      'Fantia',
      0xFFE1306C,
      (id, _) => 'https://fantia.jp/fanclubs/$id',
    ),
    'gumroad': Service(
      'gumroad',
      'Gumroad',
      0xFFFF90E8,
      (id, publicId) => 'https://gumroad.com/${publicId ?? id}',
    ),
    'subscribestar': Service(
      'subscribestar',
      'SubscribeStar',
      0xFF009688,
      (id, publicId) => 'https://subscribestar.adult/${publicId ?? id}',
    ),
    'boosty': Service(
      'boosty',
      'Boosty',
      0xFFF15F2C,
      (id, publicId) => 'https://boosty.to/${publicId ?? id}',
    ),
    'dlsite': Service(
      'dlsite',
      'DLsite',
      0xFF052A83,
      (id, _) => 'https://www.dlsite.com/eng/circle/profile/=/maker_id/$id',
    ),
    'afdian': Service(
      'afdian',
      'Afdian',
      0xFF946CE6,
      (id, publicId) => 'https://afdian.com/a/${publicId ?? id}',
    ),
  };

  static Service of(String id) =>
      _known[id] ??
      Service(id, id.isEmpty ? 'Unknown' : id, 0xFF8F6B7E, (_, _) => siteUrl);

  /// Pawchive's own small site icon.
  String get iconUrl => '$siteUrl/static/small_icons/$id.png';
}

/// An archived creator ("artist").
class Creator {
  const Creator({
    required this.id,
    required this.service,
    required this.name,
    this.publicId,
    this.indexed,
    this.updated,
    this.favorited = 0,
  });

  final String id;
  final String service;
  final String name;
  final String? publicId;
  final DateTime? indexed;
  final DateTime? updated;
  final int favorited;

  /// Unique across services, used as the follow and notification key.
  String get key => '$service/$id';

  Service get site => Service.of(service);
  String get iconUrl => '$siteUrl/icons/$service/$id';
  String get bannerUrl => '$siteUrl/banners/$service/$id';
  String get pawchiveUrl => '$siteUrl/$service/user/$id';
  String get originalUrl => site.profileUrl(id, publicId);

  factory Creator.fromJson(Map<String, dynamic> json) => Creator(
    id: _str(json['id']),
    service: _str(json['service']),
    name: _str(json['name']).isEmpty ? _str(json['id']) : _str(json['name']),
    publicId: _optStr(json['public_id']),
    indexed: parseDate(json['indexed']),
    updated: parseDate(json['updated']),
    favorited: _int(json['favorited']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'service': service,
    'name': name,
    'public_id': publicId,
    'indexed': indexed?.toIso8601String(),
    'updated': updated?.toIso8601String(),
    'favorited': favorited,
  };
}

final _entity = RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);');

/// Decodes the HTML entities Pawchive's text uses, in one pass so `&amp;lt;`
/// stays `&lt;`.
String decodeEntities(String text) => text.replaceAllMapped(_entity, (match) {
  final name = match.group(1)!;
  if (name.startsWith('#')) {
    final hex = name.length > 1 && (name[1] == 'x' || name[1] == 'X');
    final code = int.tryParse(
      hex ? name.substring(2) : name.substring(1),
      radix: hex ? 16 : 10,
    );
    return code == null || code > 0x10FFFF
        ? match.group(0)!
        : String.fromCharCode(code);
  }
  return const {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
  }[name]!;
});

enum MediaKind { image, video, audio, other }

/// A file attached to a post. Pawchive has two kinds:
///
/// * Archived files (`preview_only` false, usually with a `node`) are served
///   from the file host at [fileBase] + path.
/// * Preview-only files are only reachable through [tempUrl], a signed URL
///   that expires after about two weeks and only comes with creator post
///   lists and single posts, not the site-wide recent feed.
class MediaFile {
  const MediaFile({
    required this.name,
    required this.path,
    this.tempUrl,
    this.previewOnly = false,
  });

  final String name;
  final String path;
  final String? tempUrl;
  final bool previewOnly;

  static const _images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'};
  static const _videos = {'mp4', 'webm', 'mov', 'm4v', 'mkv'};
  static const _audio = {'mp3', 'wav', 'ogg', 'flac', 'm4a'};

  String get extension {
    final source = path.isNotEmpty ? path : name;
    final dot = source.lastIndexOf('.');
    return dot < 0 ? '' : source.substring(dot + 1).toLowerCase();
  }

  MediaKind get kind => _images.contains(extension)
      ? MediaKind.image
      : _videos.contains(extension)
      ? MediaKind.video
      : _audio.contains(extension)
      ? MediaKind.audio
      : MediaKind.other;

  bool get isImage => kind == MediaKind.image;
  bool get isVideo => kind == MediaKind.video;

  /// Viewable in the media viewer.
  bool get isViewable => isImage || isVideo;

  /// A resized still; only images have one.
  String? get thumbnailUrl => isImage ? '$thumbnailBase$path' : null;

  /// The original file, or null for a preview-only file whose post must be
  /// fetched again to get a signed [tempUrl].
  String? get fullUrl =>
      tempUrl ??
      (previewOnly ? null : '$fileBase$path?f=${Uri.encodeComponent(name)}');

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
    name: _str(json['name']),
    path: _str(json['path']),
    tempUrl: _optStr(json['temp_url']),
    previewOnly: _bool(json['preview_only']),
  );

  static MediaFile? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final file = MediaFile.fromJson(json);
    return file.path.isEmpty ? null : file;
  }
}

class Post {
  const Post({
    required this.id,
    required this.user,
    required this.service,
    required this.title,
    this.content = '',
    this.published,
    this.added,
    this.file,
    this.attachments = const [],
    this.tags = const [],
    this.nextId,
    this.prevId,
    this.favorites,
  });

  final String id;

  /// The creator's id.
  final String user;
  final String service;
  final String title;

  /// HTML; the recent feed only sends a short `substring`.
  final String content;
  final DateTime? published;
  final DateTime? added;
  final MediaFile? file;
  final List<MediaFile> attachments;
  final List<String> tags;
  final String? nextId;
  final String? prevId;

  /// Only known for posts from the popular page.
  final int? favorites;

  String get creatorKey => '$service/$user';
  String get url => '$siteUrl/$service/user/$user/post/$id';

  /// The main file followed by attachments, without repeats.
  List<MediaFile> get files {
    final seen = <String>{};
    return [?file, ...attachments].where((f) => seen.add(f.path)).toList();
  }

  List<MediaFile> get media => files.where((f) => f.isViewable).toList();

  DateTime? get date => published ?? added;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: _str(json['id']),
    user: _str(json['user']),
    service: _str(json['service']),
    title: _str(json['title']),
    content: _str(json['content'] ?? json['substring']),
    published: parseDate(json['published']),
    added: parseDate(json['added']),
    file: MediaFile.tryParse(json['file']),
    attachments: [
      for (final item in (json['attachments'] as List? ?? const []))
        ?MediaFile.tryParse(item),
    ],
    tags: parseTags(json['tags']),
    nextId: _optStr(json['next']),
    prevId: _optStr(json['prev']),
  );
}

class Announcement {
  const Announcement({required this.hash, required this.content, this.added});

  final String hash;
  final String content;
  final DateTime? added;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    hash: _str(json['hash']),
    content: _str(json['content']),
    added: parseDate(json['added']),
  );
}

class CreatorTag {
  const CreatorTag(this.tag, this.postCount);

  final String tag;
  final int postCount;

  factory CreatorTag.fromJson(Map<String, dynamic> json) =>
      CreatorTag(_str(json['tag']), _int(json['post_count']));
}

class Fancard {
  const Fancard({required this.file, this.added});

  final MediaFile file;
  final DateTime? added;

  static Fancard? tryParse(Map<String, dynamic> json) {
    final file = MediaFile.tryParse(json['file'] ?? json);
    return file == null
        ? null
        : Fancard(file: file, added: parseDate(json['added']));
  }
}

/// A direct message a creator sent to supporters, read from the creator's
/// DMs web page (the API has no DM endpoint).
class DirectMessage {
  const DirectMessage({required this.content, this.added});

  final String content;

  /// As the site prints it, e.g. "2026-11".
  final String? added;
}

class Comment {
  const Comment({
    required this.id,
    required this.commenter,
    required this.content,
    this.parentId,
    this.published,
  });

  final String id;
  final String commenter;
  final String content;
  final String? parentId;
  final DateTime? published;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: _str(json['id']),
    commenter: _str(json['commenter_name']).isEmpty
        ? _str(json['commenter'])
        : _str(json['commenter_name']),
    content: _str(json['content']),
    parentId: _optStr(json['parent_id']),
    published: parseDate(json['published']),
  );
}

/// A followed creator and what the update checker last saw of them.
class Follow {
  const Follow({
    required this.creator,
    required this.followedAt,
    this.seenPostIds = const [],
    this.seenUpdated,
    this.unread = 0,
    this.synced = false,
  });

  final Creator creator;
  final DateTime followedAt;

  /// Newest post ids at the last check; anything else on the first page is
  /// new.
  final List<String> seenPostIds;

  /// The profile's `updated` stamp at the last check; when unchanged the
  /// posts are not fetched.
  final String? seenUpdated;

  /// New posts since the user last opened this creator.
  final int unread;

  /// Whether this follow has been seen in the account's Pawchive favorites,
  /// so its absence there means it was removed on the website.
  final bool synced;

  String get key => creator.key;

  Follow copyWith({
    Creator? creator,
    List<String>? seenPostIds,
    String? seenUpdated,
    int? unread,
    bool? synced,
  }) => Follow(
    creator: creator ?? this.creator,
    followedAt: followedAt,
    seenPostIds: seenPostIds ?? this.seenPostIds,
    seenUpdated: seenUpdated ?? this.seenUpdated,
    unread: unread ?? this.unread,
    synced: synced ?? this.synced,
  );

  factory Follow.fromJson(Map<String, dynamic> json) => Follow(
    creator: Creator.fromJson(json['creator'] as Map<String, dynamic>),
    followedAt: parseDate(json['followedAt']) ?? DateTime.now().toUtc(),
    seenPostIds: [for (final id in json['seen'] as List? ?? const []) _str(id)],
    seenUpdated: _optStr(json['seenUpdated']),
    unread: _int(json['unread']),
    synced: _bool(json['synced']),
  );

  Map<String, dynamic> toJson() => {
    'creator': creator.toJson(),
    'followedAt': followedAt.toIso8601String(),
    'seen': seenPostIds,
    'seenUpdated': seenUpdated,
    'unread': unread,
    'synced': synced,
  };
}

/// "New post from X" in the notifications list.
class UpdateNotice {
  const UpdateNotice({
    required this.id,
    required this.creator,
    required this.postId,
    required this.postTitle,
    required this.at,
    this.thumbnailPath,
    this.read = false,
  });

  final String id;
  final Creator creator;
  final String postId;
  final String postTitle;
  final DateTime at;
  final String? thumbnailPath;
  final bool read;

  String? get thumbnailUrl =>
      thumbnailPath == null ? null : '$thumbnailBase$thumbnailPath';

  UpdateNotice markRead() => UpdateNotice(
    id: id,
    creator: creator,
    postId: postId,
    postTitle: postTitle,
    at: at,
    thumbnailPath: thumbnailPath,
    read: true,
  );

  factory UpdateNotice.fromJson(Map<String, dynamic> json) => UpdateNotice(
    id: _str(json['id']),
    creator: Creator.fromJson(json['creator'] as Map<String, dynamic>),
    postId: _str(json['postId']),
    postTitle: _str(json['postTitle']),
    at: parseDate(json['at']) ?? DateTime.now().toUtc(),
    thumbnailPath: _optStr(json['thumb']),
    read: _bool(json['read']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'creator': creator.toJson(),
    'postId': postId,
    'postTitle': postTitle,
    'at': at.toIso8601String(),
    'thumb': thumbnailPath,
    'read': read,
  };
}
