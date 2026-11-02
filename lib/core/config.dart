/// Hosts and request rules for Pawchive.
///
/// The file host refuses browser-looking user agents and asks clients to
/// identify themselves, keep to about one download a second and at most five
/// at once. Every request the app makes (API, thumbnails, full files, video)
/// sends [userAgent], and the media viewer only loads the page on screen.
library;

const appName = 'Pawress';
const appVersion = '1.0.0';

const siteHost = 'pawchive.pw';
const siteUrl = 'https://$siteHost';
const apiBase = '$siteUrl/api/v1';
const thumbnailBase = 'https://img.$siteHost/thumbnail/data';

/// Archived (not preview-only) files, by path.
const fileBase = 'https://file.$siteHost/data';

/// Identifies the app to Pawchive; a browser user agent gets a 403 from the
/// file host.
const userAgent = '$appName/$appVersion (Android; Pawchive client)';

const mediaHeaders = {'User-Agent': userAgent};

/// Posts per page on every paged Pawchive endpoint.
const pageSize = 50;

/// The cookie that authenticates API calls after signing in on the website.
const sessionCookie = 'session';

const loginUrl = '$siteUrl/account/login';
