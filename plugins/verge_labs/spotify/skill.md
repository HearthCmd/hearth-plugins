---
name: spotify
description: >
  Use when playing or controlling music on Spotify via a hearth resource
  connection — putting on a song, album or playlist, pausing, skipping,
  changing volume, queueing something up, moving playback to another speaker,
  checking what's playing, or saving a track. Covers search, transport,
  devices, queue, playlists and library through the spotify plugin.
---

# Spotify plugin

Invoke via `hearth resource invoke <connection> <verb> '<args-json>'`.

`<connection>` is the name shown in your resource list — either the slug
(e.g. `spotify`) or the connection UUID. Both resolve. Examples below use
`spotify`; substitute the connection you were actually granted.

## Passing arguments

Args are **one JSON object**, quoted as a single shell argument. There is no
`--arg` flag:

```
hearth resource invoke spotify get_playback_state
hearth resource invoke spotify search '{"q":"bon iver holocene"}'
```

`limit`, `offset`, `position_ms` and `volume_percent` are integers — pass bare
JSON numbers. `state` (for `set_shuffle`) and `play` are booleans — `true` /
`false`, not `"true"`.

Arguments ending in `_json` are **a JSON array carried as a string**, escaped
inside the outer object:

```
hearth resource invoke spotify play_tracks '{"track_uris_json":"[\"spotify:track:0VjIjW4GlUZAMYd2vXMi3b\"]"}'
```

## Two things that will bite you first

### 1. Two different 403s, and neither is retryable

**`PREMIUM_REQUIRED`** — every verb that *changes* anything fails on a free
account. Reading works fine, which makes this confusing: the connection looks
healthy, `get_playback_state` answers correctly, and then `pause` fails. Tell
the user their account isn't Premium.

**A 403 on everything, including reads** — this connection runs on a Spotify
app the household registered themselves, and Spotify only serves users who have
been added to that app. Someone whose Spotify account isn't on the list gets
rejected wholesale. The fix is a person's, not yours: whoever set the
connection up adds them in the Spotify Developer Dashboard under
Settings → User Management, using their Spotify account email.

Neither is fixed by retrying or by trying a different verb.

### 2. There is always exactly one active device

Spotify has no concept of rooms. The account has **one playback session**, and
it lives on one device — a phone, a laptop, a Sonos speaker, a TV. Every
command goes to whichever device is active.

When nothing is active, playback verbs fail with **404 `NO_ACTIVE_DEVICE`**.
That's not an error to retry; it's a device that needs choosing:

```
hearth resource invoke spotify list_devices
hearth resource invoke spotify transfer_playback '{"device_id":"...","play":false}'
```

A device only appears in `list_devices` while its Spotify app is actually
running. A speaker that's powered off, or a laptop whose Spotify is closed,
simply isn't in the list — say which devices *are* available rather than
guessing.

**None of the playback verbs take a device_id.** Targeting is always a separate
`transfer_playback` first, then the playback command. To start music on a
specific speaker, pass `"play": false` on the transfer so it moves the session
without noise, then call `play_context` or `play_tracks`.

## Finding something to play

`search` is the way in. Pass `q` **exactly as the person said it** — it is
percent-encoded for you. Do not pre-escape it, or you'll double-encode and get
nothing.

```
hearth resource invoke spotify search '{"q":"simon and garfunkel the boxer"}'
hearth resource invoke spotify search '{"q":"in rainbows","type":"album"}'
hearth resource invoke spotify search '{"q":"track:Hallelujah artist:Jeff Buckley"}'
```

`type` defaults to `track` and takes a comma-separated list of `album`,
`artist`, `playlist`, `track`, `show`, `episode`, `audiobook`. `limit` defaults
to 10, which is also Spotify's current maximum.

Ask for the type that matches the request. "Play the new Big Thief album" is a
`type: "album"` search; searching tracks for it returns one song from it and
you'll play only that.

Spotify's field filters (`artist:`, `album:`, `track:`, `year:`, `genre:`) go
inside `q` and are how you pin down a covered song or a common title.

### Every uri comes from a response

Results carry a `uri` like `spotify:track:…`, `spotify:album:…`,
`spotify:playlist:…`. **Never construct or guess one.** Ids are opaque; a
hand-built uri is either a 404 or, worse, someone else's track.

Which verb takes which:

| uri kind | verb |
|---|---|
| `spotify:track:…` | `play_tracks` (as a one-element array) or `add_to_queue` |
| `spotify:album:…`, `spotify:playlist:…`, `spotify:artist:…` | `play_context` |

Passing a track uri to `play_context` fails — a track is not a context.

## Starting music

```
# A playlist, album, or artist
hearth resource invoke spotify play_context '{"context_uri":"spotify:album:..."}'

# Specific songs
hearth resource invoke spotify play_tracks '{"track_uris_json":"[\"spotify:track:...\"]"}'
```

Both **replace** what is playing and clear the queue.

### Prefer the queue when music is already on

If `get_playback_state` says something is playing, "play X" almost always means
"play X next", not "stop this and play X":

```
hearth resource invoke spotify add_to_queue '{"uri":"spotify:track:..."}'
```

`add_to_queue` doesn't interrupt anyone. Reach for `play_context` /
`play_tracks` when the room is quiet, or when the user clearly wants a change
("put something else on", "skip this album").

You can't un-replace a queue. Somebody's carefully built evening of music is
gone the moment you call `play_tracks`, and nothing will bring it back.

## Checking what's playing

```
hearth resource invoke spotify get_playback_state
```

One call answers everything: `is_playing`, the active `device` (with
`volume_percent`), `item` (name, artists, album, `uri`, `duration_ms`),
`progress_ms`, `shuffle_state`, `repeat_state`, and `actions`.

**An empty response is a valid answer.** The endpoint returns 204 with no body
when nothing is playing and no device is active. Read that as "Spotify is
idle" — not as a failure, and not as "I don't know". It usually means the next
playback command needs a `transfer_playback` first.

`item.uri` is what `save_to_library` takes for "save this song".

For what's coming up:

```
hearth resource invoke spotify get_queue
```

## Transport

```
hearth resource invoke spotify resume
hearth resource invoke spotify pause
hearth resource invoke spotify next_track
hearth resource invoke spotify previous_track
hearth resource invoke spotify seek '{"position_ms":45000}'
```

`resume` only resumes what is already loaded — it starts nothing. An idle
account with an empty queue has nothing to resume, so "put some music on" needs
`play_context` or `play_tracks`.

`previous_track` behaves like every music player: the first call usually
restarts the current track rather than going back one. "Go back a song" may
need two calls — check `get_playback_state` between them rather than assuming.

`seek` takes milliseconds from the **start of the track**, so relative requests
("back 30 seconds") need `progress_ms` from `get_playback_state` first. Seeking
past the end skips to the next track.

Before skipping, check `actions.disallows` in `get_playback_state` — some
contexts disallow it.

## Shuffle and repeat

```
hearth resource invoke spotify set_shuffle '{"state":true}'
hearth resource invoke spotify set_repeat '{"state":"context"}'
```

`set_shuffle` takes a **boolean**. `set_repeat` takes a **string**: `off`,
`context` (repeat the album or playlist), or `track` (repeat this one song).
They're different types on purpose — mixing them up is a 400.

## Volume

```
hearth resource invoke spotify set_volume '{"volume_percent":35}'
```

**Spotify has no relative-volume endpoint.** "Turn it up a bit" means reading
`device.volume_percent` from `get_playback_state` and adding to it — a step of
about 10 is a sensible reading of "a bit".

Never jump to an absolute level you picked yourself. Going to 70 in a room that
was at 15 is startling, and at night it's genuinely unpleasant. If you can't
read the current volume, ask rather than guess.

Devices whose `supports_volume` is false (many TVs and Connect speakers) reject
this entirely. Check `list_devices`, and report it rather than retrying.

## Playlists

```
hearth resource invoke spotify list_playlists
hearth resource invoke spotify get_playlist_items '{"playlist_id":"..."}'
```

`list_playlists` covers playlists this account owns *and* follows, 50 at a time
(`offset` pages). Each carries a `uri` for `play_context` and an `id` for
`get_playlist_items`.

Match a requested playlist name case-insensitively. If nothing matches, list
what does exist rather than picking the nearest-sounding one — "dinner" and
"dinner party" are different evenings.

`get_playlist_items` returns 50 tracks at a time, trimmed to name, artists, uri
and duration. Use it for "is X on my running playlist?" or "how long is this?".

**This plugin cannot add to or edit a playlist.** That's deliberate, not an
oversight. If someone asks, say so and offer `save_to_library` instead — it's
the closest thing to "keep this".

## Saving

```
hearth resource invoke spotify save_to_library '{"uris_json":"[\"spotify:track:...\"]"}'
hearth resource invoke spotify remove_from_library '{"uris_json":"[\"spotify:track:...\"]"}'
```

Works for track, album and artist uris — saving an artist uri follows them.
Get the uri of the current song from `get_playback_state` (`item.uri`).

`remove_from_library` asks for approval by default. It deletes something the
person deliberately kept, and unlike a wrong volume nothing in the room signals
that it happened. Expect the pause and explain it rather than reporting a hang.

## Reading the room

Music is shared and audible, and the people it reaches usually didn't ask you
for anything:

- **Queue rather than replace** whenever something is already playing.
- **Confirm before changing a room that's in use.** If `get_playback_state`
  shows music playing and the request is vague about what to do with it, ask.
- **Be conservative with volume at night.** A read-then-nudge, never a jump.
- **One device means one audience.** Transferring playback to the kitchen takes
  the music off whatever was playing it. If someone might be listening there,
  say what you're about to do.

## When a call fails

- **403 `PREMIUM_REQUIRED`** — the account is not Premium. No playback verb
  will ever work. Tell the user; don't retry.
- **404 `NO_ACTIVE_DEVICE`** — nothing is active. `list_devices`, then
  `transfer_playback`. Don't retry the same call.
- **404 on a device id** — the device's app closed since you listed it.
  Re-run `list_devices`.
- **403 `RESTRICTION_VIOLATED`** — the action isn't allowed on this source
  (skipping where skips are disallowed, or a context that can't be shuffled).
  Check `actions.disallows` and report it.
- **400 on `play_context`** — you passed a track uri. Use `play_tracks`.
- **429** — rate limited; a `Retry-After` header says for how long. Back off
  rather than looping.
- **401, or `invalid_grant` on a refresh** — the connection needs
  re-authorizing in the app. Spotify refresh tokens now expire six months
  after the original sign-in and refreshing does not extend that, so a
  connection that worked for months can stop for no reason visible in the
  house. A person has to reconnect it; there is no retry that helps.
