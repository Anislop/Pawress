# Coomer API notes

What Pawress relies on for the Coomer provider, verified against
<https://coomer.st> on 2026-11-13. Coomer runs newer Kemono software than
Pawchive: the website is a single-page app (every path returns the same
small HTML shell), so nothing can be scraped, but the API has what
Pawchive's pages are scraped for. Read [pawchive-api.md](pawchive-api.md)
first; this file only lists the differences. The code is `CoomerApi` in
`lib/core/api.dart`, and the hosts are `Provider.coomer` in
`lib/core/config.dart`.

## Hosts

The host can be changed in the sidebar (the gear beside the site), so a
mirror must follow the same layout.

| Host | Use |
| --- | --- |
| `https://{host}/api/v1` | JSON API |
| `https://img.{host}/icons/{service}/{id}`, `/banners/...` | Creator avatar and banner (`https://{host}/icons/...` is a 302 to it) |
| `https://{host}/static/small_icons/{service}.png` | Site (service) icon |
| `https://img.{host}/thumbnail/data{path}` | Image thumbnails |
| `https://{host}/data{path}?f={name}` | Full files: a **302** to a storage node (`https://n3.{host}/data{path}`) |

Services are `onlyfans`, `fansly` and `candfans`. They don't overlap
Pawchive's, so `Provider.of(service)` decides the provider and nothing
stored needs to name it.

## Request rules

- **Send `Accept: text/css`.** The site is behind DDoS-Guard, which answers
  the larger endpoints (`/creators`) with a 403 for any other `Accept`.
  Responses are still JSON (gzip), labelled `text/css`.
- The Pawress user agent is accepted by the API and the image host. Full
  files could not be checked from the development container (its proxy
  resets connections to the storage nodes); check on a device.
- 50 items per page, paged with `o`, as on Pawchive.

## Endpoints that differ

| Endpoint | Notes |
| --- | --- |
| `GET /posts?o=&q=&tag=` | Wrapped: `{count, true_count, posts}`. `tag` works here (Pawchive ignores it); with `tag`, items carry the full `content`. Not strictly newest first. |
| `GET /{service}/user/{id}/posts?o=&q=&tag=` | A creator's posts. `/{service}/user/{id}` is a **404**. Without `q` the items are short: `substring`, no `tags`, no `added`. With `q` they are full. |
| `GET /{service}/user/{id}/post/{post}` | `{post, attachments, previews, videos, props}`; `next` (older) and `prev` are inside `post`. `props.revisions` holds the revisions. |
| `GET /posts/popular?period=&date=&o=` | `{info, props, posts}`. `info.navigation_dates.{day,week,month}` is `[previous, next, current]`; `next` runs into the future, so `parsePopularJson` drops one after `props.today`. `info.range_desc` is the range in words. Posts have `fav_count` and real file paths. `props.count` is capped at 500. |
| `GET /posts/tags` | `[{tag, post_count}]`, most used first. |
| `GET /posts/random`, `/artists/random` | JSON `{service, artist_id[, post_id]}`, not a redirect. |
| `GET /{service}/user/{id}/recommended` | Creator objects with a `score`. |
| `GET /{service}/user/{id}/dms` | A JSON list (empty for every creator checked, so the item shape is assumed to be Kemono's `{content, published, added}`). |
| `GET /search_hash/{sha256}` | The file's fields (`mime`, `size`, `ext`, ...) and `posts`. An unknown hash is a **200** with no posts. |
| `GET /creators` | About 220,000 creators, 6 MB gzipped. Needs `Accept: text/css`. |
| `POST /authentication/login` | JSON `{username, password}`; a wrong pair is a 400 `{"error": ...}`. Not used yet. |
| `/{service}/user/{id}/community`, `/post/{post}/revisions` | 404. `CoomerApi.community` returns an empty page without asking. |

Profiles, announcements, links, comments, fancards and the favorites
endpoints have Pawchive's shapes (fancards, polls and announcements are
normally empty).

## Quirks

- **Tags are made from hashtags and keep markup**: `advertising</p>`,
  `ai</p><p>#advertising</p>`, `#`. `cleanTag` keeps the word before the
  first `<` and drops leading `#`s, on posts (`Post.fromJson`) and in tag
  lists (`mergeTags`, which keeps the most used variant of each name).
  Searching by the clean name only finds posts tagged with exactly that
  variant.
- **Feed posts carry no tags**, so blocked tags only hide Coomer posts once
  their full post has been read; blocked artists hide everywhere.
- **Post text keeps the original site's relative links** (`/someone` on an
  OnlyFans post), so `PostPage` resolves them against the original site.
- **There are no preview-only files or `temp_url`s.** Every file has a
  `path`.
- **No accounts in Pawress yet.** Follows and favorites of Coomer creators
  stay on the device; `AppState._syncs` keeps them out of the Pawchive
  account sync.
