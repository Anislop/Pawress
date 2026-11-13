/// Providers, their hosts and the request rules they share.
///
/// The file host refuses browser-looking user agents and asks clients to
/// identify themselves, keep to about one download a second and at most five
/// at once. Every request the app makes (API, thumbnails, full files, video)
/// sends [userAgent], and the media viewer only loads the page on screen.
library;

const appName = 'Pawress';
const appVersion = '1.0.0';

/// Identifies the app to Pawchive; a browser user agent gets a 403 from the
/// file host.
const userAgent = '$appName/$appVersion (Android; Pawchive client)';

const mediaHeaders = {'User-Agent': userAgent};

/// Posts per page on every paged Pawchive endpoint.
const pageSize = 50;

/// The cookie that authenticates API calls after signing in on the website.
const sessionCookie = 'session';

/// An archive Pawress reads. Both run Kemono-style software, but Coomer's
/// website is a single-page app over a fuller API, so nothing is scraped
/// there (see docs/coomer-api.md).
///
/// [host] can be pointed at a mirror; every URL is built from it, so
/// follows and favorites keep working across a move.
class Provider {
  Provider._({
    required this.id,
    required this.name,
    required this.defaultHost,
    required this.accept,
    this.services = const {},
    this.spa = false,
  }) : host = defaultHost;

  final String id;
  final String name;
  final String defaultHost;

  /// The `Accept` header for API calls. Coomer's DDoS guard refuses
  /// anything but `text/css` on its larger endpoints.
  final String accept;

  /// The creator sites this archive carries; a service belongs to one
  /// provider, so a post or creator needs no stored provider.
  final Set<String> services;

  /// The website is a single-page app: the API has what Pawchive's pages
  /// are scraped for, images come from the image host and files redirect
  /// from the site to a storage node.
  final bool spa;

  /// The host in use: [defaultHost] or a mirror from Settings.
  String host;

  String get siteUrl => 'https://$host';
  String get apiBase => '$siteUrl/api/v1';
  String get thumbnailBase => 'https://img.$host/thumbnail/data';

  /// Archived (not preview-only) files, by path.
  String get fileBase => spa ? '$siteUrl/data' : 'https://file.$host/data';

  /// Creator avatars (`/icons`) and banners (`/banners`).
  String get artBase => spa ? 'https://img.$host' : siteUrl;
  String get loginUrl => '$siteUrl/account/login';

  static final pawchive = Provider._(
    id: 'pawchive',
    name: 'Pawchive',
    defaultHost: 'pawchive.pw',
    accept: 'application/json',
  );

  static final coomer = Provider._(
    id: 'coomer',
    name: 'Coomer',
    defaultHost: 'coomer.st',
    accept: 'text/css',
    services: const {'onlyfans', 'fansly', 'candfans'},
    spa: true,
  );

  static final all = [pawchive, coomer];

  /// The provider carrying [service]; unknown services are Pawchive's.
  static Provider of(String service) =>
      coomer.services.contains(service) ? coomer : pawchive;

  static Provider? byId(String? id) => all.where((p) => p.id == id).firstOrNull;

  /// The provider at [host], by its current or default host.
  static Provider? atHost(String host) {
    final name = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    return all
        .where((p) => p.host == name || p.defaultHost == name)
        .firstOrNull;
  }

  static final _hostName = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$');

  /// The host in a typed mirror address ("https://coomer.su/", "coomer.su"),
  /// or null when it isn't one.
  static String? parseHost(String input) {
    var text = input.trim().toLowerCase();
    text = text.replaceFirst(RegExp(r'^[a-z]+://'), '');
    text = text.split(RegExp(r'[/?#:]')).first;
    text = text.replaceFirst(RegExp(r'^www\.'), '');
    return _hostName.hasMatch(text) ? text : null;
  }
}
