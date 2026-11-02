# Pawchive API notes

What Pawress relies on, verified against the live site on 2026-11-02. The
official schema is at <https://pawchive.pw/api/schema> (Swagger UI; the raw
OpenAPI document is embedded in <https://pawchive.pw/api/swagger_schema>).
Pawchive is a Kemono-style archive, so Kemono client knowledge mostly
applies.

## Hosts

| Host | Use |
| --- | --- |
| `https://pawchive.pw/api/v1` | JSON API |
| `https://pawchive.pw/icons/{service}/{id}` | Creator avatar |
| `https://pawchive.pw/banners/{service}/{id}` | Creator banner |
| `https://pawchive.pw/static/small_icons/{service}.png` | Site (service) icon |
| `https://img.pawchive.pw/thumbnail/data{path}` | Image thumbnails (images only) |
| `https://file.pawchive.pw/data{path}?f={name}` | Archived (not preview-only) files, including video; supports range requests |
| `temp_url` on a file object (e.g. `https://t1.pawchive.pw/f/...`) | Signed URL for preview-only files; expires in about two weeks |

## Request rules

- **Send an identifiable `User-Agent`.** The file host returns 403 ("Are you
  a bot or using download tools?") to browser user agents. Pawress sends
  `Pawress/<version> (Android; Pawchive client)` everywhere (`lib/core/config.dart`).
- The file host asks for at most about **1 download per second and 5 at
  once**. The media viewer only loads the full file for the page on screen,
  and creator lookups and update checks are throttled.
- Paged endpoints return **50 items** per page; page with `o` (offset).

## Endpoints used

| Endpoint | Notes |
| --- | --- |
| `GET /posts?o=&q=` | Site-wide recent posts. Items have `substring` (truncated HTML, may end mid-tag) instead of `content`, no creator name, and no `temp_url`. |
| `GET /{service}/user/{id}?o=&q=&tag=` | A creator's posts (full `content`, `temp_url`s). |
| `GET /{service}/user/{id}/profile` | Creator profile. `updated` is cheap to poll for changes. |
| `GET /{service}/user/{id}/post/{post}` | Single post, unwrapped (not `{"post": ...}`), with `next`/`prev` ids. |
| `GET /{service}/user/{id}/announcements` | `[{hash, content (HTML), added}]` |
| `GET /{service}/user/{id}/tags` | `[{tag, post_count}]` |
| `GET /{service}/user/{id}/links` | Linked creator accounts on other services |
| `GET /{service}/user/{id}/fancards` | Fanbox only. `[{id, user_id, file_id, price, hash, ext, mime, size, added, ...}]` with no `path`; see Quirks. |
| `GET /{service}/user/{id}/post/{post}/comments` | `[{id, parent_id, commenter_name, content, published}]` |
| `GET /creators` | Every creator, about 16 MB. Only used by artist search, once per session. |
| `GET /account/favorites?type=artist` | Needs the session cookie (401 otherwise). |
| `GET /account/favorites?type=post` | The account's favorite posts, read as posts (`id`, `user`, `service`, ...). Needs the session cookie. Not checked against a live account; the schema only lists creator fields. |
| `POST`/`DELETE /favorites/post/{service}/{creator}/{post}` | Like / unlike a post. Needs the session cookie. |

Web pages Pawress scrapes (`https://pawchive.pw`, not the API):

| Page | Notes |
| --- | --- |
| `/{service}/user/{id}/dms` | DM cards; see Quirks. |
| `/posts/popular?date=&period=&o=` | 50 `article.post-card` per page with `data-id`, `data-service`, `data-user`, a `post-card__header` title, a `/thumbnail/data{path}` image, `<time datetime="YYYY-MM-DD HH:MM:SS">` and "N favorites". No params means the last 24 hours. `period=day` takes any date; `week` and `month` only work with the start date the page itself links to in `#daily`, `#weekly` and `#monthly` (a week started 2026-10-27 for 2026-11-02, a month starts on the 1st). Other dates return no posts. |
| `/{service}/user/{id}/community[/{channel}]?o=` | Patreon community chats; see Quirks. |
| `/{service}/user/{id}/recommended` | "Similar artists": up to 50 `a.user-card` with `data-id`, `data-service` and `div.user-card__name`. No favorites or dates. |
| `POST`/`DELETE /favorites/creator/{service}/{id}` | Needs the session cookie. |

## Quirks

- **Tags** are a JSON list on single posts but a **Postgres array literal**
  string on post lists: `{"GRANDE CUCULO","MY ROUTINE",PROCIONI}`, or
  `null`. See `parseTags` in `lib/core/models.dart`.
- **Dates** are ISO strings without a zone (UTC) on posts and profiles, but
  epoch seconds in `/creators`. `parseDate` handles both.
- **File objects** come in two kinds: archived files (`preview_only` false,
  usually a `node` number) served from `file.pawchive.pw`, and preview-only
  files reachable only through `temp_url`. A preview-only file from the recent
  feed has neither, so the app fetches the single post to get its
  `temp_url` (`MediaViewer._resolve`). `https://pawchive.pw/data{path}` is a
  404.
- **There's no login endpoint.** Auth is the `session` cookie set by the
  website's login form, so Pawress signs in through a WebView
  (`lib/ui/login_page.dart`) and confirms the cookie with
  `/account/favorites` before keeping it.
- **There's no DM endpoint.** `/api/v1/{service}/user/{id}/dms` is a 404. DMs are
  scraped from the web page `/{service}/user/{id}/dms` (`article.dm-card`,
  `div.dm-card__content`, `div.dm-card__added`); see `parseDirectMessages`
  in `lib/core/api.dart`.
- **There's no popular or recommendation endpoint.** `/api/v1/posts/popular`
  and `/api/v1/{service}/user/{id}/recommended` are 404s, so the web pages
  above are scraped (`parsePopularPage`, `parseCreatorCards` in
  `lib/core/api.dart`). For You is built client-side (`rankForYou` in
  `lib/core/feeds.dart`).
- Scraped text can contain numeric HTML entities (`&#x27;`), and so can the
  recent feed's `substring`. `decodeEntities` in `lib/core/models.dart`
  handles both.
- **Fancards** have no `path` or file object. The file lives at
  `/{hash[0:2]}/{hash[2:4]}/{hash}{ext}` (ext includes the dot), so the
  thumbnail is `https://img.pawchive.pw/thumbnail/data/b8/04/b804....webp`.
  `price` is the plan's yen price as a string. See `Fancard.tryParse`.
- **Polls.** Creator post lists and single posts have `poll` (`null` without
  one): `{title, description, choices: [{text, votes}], created_at,
  closes_at, allow_multiple}`, dates with a `+00:00` zone. The site-wide
  `/posts` list has no `poll` key. Only results are archived.
- **Post favorite counts** exist only on the popular page ("N favorites");
  post JSON and the post web page have none.
- **There's no community endpoint.** `/api/v1/.../community` is a 404, so
  Pawress scrapes the web page (`parseCommunityPage`). `/community` redirects
  (302) to the first channel, `/community/{channel}`; a creator without a
  community is a 404. Channels are `a.chat-page__channel` (`is-active` on
  the shown one) with `chat-page__channel-name` and `-count`. Pages hold 25
  `div.cmsg` messages, oldest first, but `o=0` is the **newest** page, so
  older messages are at higher offsets; "Showing 1 - 25 of 114" gives the
  range. A message with `cmsg--head` has `cmsg__author`, `cmsg__time`
  (`datetime`, UTC), an avatar (`img.cmsg__avatar` for the creator, a letter
  on `hsl(...)` for members), an optional `cmsg__reply` quote, and
  `cmsg--creator` for the creator. One without a head continues the previous
  author. `cmsg__text` holds the HTML, followed by `a.cmsg__image` (full
  file `href`, thumbnail `img src`, sometimes Patreon's CDN) and
  `a.cmsg__embed` link previews.
- **Popular artists** have no endpoint either; `/artists` on the site sorts
  the same `/creators` data that Pawress sorts on the device.
