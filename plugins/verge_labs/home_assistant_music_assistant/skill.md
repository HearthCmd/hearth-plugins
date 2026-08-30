---
name: home-assistant-music-assistant
description: >
  Use when playing or controlling music through Music Assistant on Home
  Assistant via a hearth resource connection — putting an artist, album or
  playlist on in a room, pausing, skipping, changing volume, grouping
  speakers, moving music between rooms, or checking what's playing. Covers
  search, the library, transport, volume, multi-room and announcements.
---

# Music Assistant (Home Assistant) plugin

Invoke via `hearth resource invoke <connection> <verb> '<args-json>'`.

`<connection>` is the name shown in your resource list — either the slug
(e.g. `music_assistant`) or the connection UUID. Both resolve. Examples below
use `music_assistant`; substitute the connection you were actually granted.

## Passing arguments

Args are **one JSON object**, quoted as a single shell argument:

```
hearth resource invoke music_assistant get_player '{"entity_id":"media_player.kitchen"}'
```

`limit`, `offset` and `position_seconds` are integers; `volume_level` is a
decimal; `shuffle`, `muted`, `radio_mode`, `library_only`, `auto_play` and
`use_pre_announce` are booleans (`true` / `false`, not `"true"`).

`members_json` is a JSON array carried as a **string**, escaped inside the
outer object.

## The one that will bite you: volume is 0.0 to 1.0

```
hearth resource invoke music_assistant set_volume '{"entity_id":"media_player.kitchen","volume_level":0.35}'
```

`volume_level` is a **fraction**, not a percentage. `0.35` is a normal
listening level. `35` is not "35%" — it is out of range and the call fails.
Every other music system you have seen uses 0–100; this one does not.

There is **no relative-volume service**. "Turn it up a bit" means reading
`volume_level` from `get_player` and adding roughly `0.1`. Never jump to a
level you chose yourself — going to 0.7 in a room sitting at 0.15 is
startling, and at night genuinely unpleasant. If you cannot read the current
level, ask.

To silence a room without losing its setting use `set_mute`; setting volume
to 0 loses it.

## Finding the speakers

```
hearth resource invoke music_assistant list_players
```

This returns **every entity Home Assistant knows about**, which on a real
installation is a lot. The speakers are the `media_player.*` ones. Each
carries `entity_id`, `friendly_name`, `state` (`playing` / `paused` / `idle`
/ `off`), `volume_level`, `group_members`, and when something is on,
`media_title` and `media_artist`.

Once you know which speaker you want, use `get_player` — it is one entity
instead of hundreds:

```
hearth resource invoke music_assistant get_player '{"entity_id":"media_player.kitchen"}'
```

Match a room by `friendly_name`, case-insensitively. If nothing matches, say
which speakers *do* exist rather than guessing at the closest one — starting
music in the wrong room at 7am is a real cost.

### What's playing, and what's next

`get_player` answers "what's playing in the kitchen?" — `media_title`,
`media_artist`, `media_album_name`. For what comes *after* it:

```
hearth resource invoke music_assistant get_queue '{"entity_id":"media_player.kitchen"}'
```

`get_queue` returns `current_item` and `next_item`. Use it for "what's coming
up?" and to confirm an enqueue actually landed — worth doing after an `add`,
since a queue that silently didn't take looks identical to one that did until
the track changes.

## Putting music on

**`play_media` takes a plain name.** Music Assistant resolves it against
everything it is connected to, so the common request needs no lookup first:

```
hearth resource invoke music_assistant play_media '{
  "entity_id": "media_player.kitchen",
  "media_id": "Big Thief"
}'
```

`media_id` also accepts a `uri` from `search` (e.g. `spotify://album/123`),
which is how you remove all ambiguity about *which* thing was meant.

### enqueue: what happens to what's already playing

| value | effect |
|---|---|
| `play` | start it now, keeping the rest of the queue *(default)* |
| `replace` | clear the queue and play this instead |
| `next` | play it after the current track |
| `replace_next` | replace whatever was queued next |
| `add` | append to the end of the queue |

**If something is already playing, "play X" usually means `next` or `add`,
not `replace`.** Somebody's evening of music is gone the moment you replace
the queue, and nothing brings it back. Reach for `replace` when the room is
quiet or the user clearly wants a change ("put something else on").

`radio_mode: true` turns the selection into an endless similar-music station
rather than playing just that one thing — the right answer to "put on
something like Big Thief".

### There is no media_type argument

Deliberately. To force a *kind* of thing — the album rather than the song of
the same name — `search` first and pass the returned `uri`. Guessing a type
is worse than letting Music Assistant work it out.

## Search and the library

Both need `config_entry_id` set on the connection. If it isn't, the call
fails naming that field — that is a person's job to fix in the connection
settings, not something to retry.

```
hearth resource invoke music_assistant search '{"name":"hounds of love"}'
```

Results are **grouped by type**: `artists`, `albums`, `tracks`, `playlists`,
`radio`, `audiobooks`, `podcasts`. Each item has a `name` and a `uri`. `limit`
is per group and defaults to 5. `library_only: true` restricts to music
already in the library instead of reaching the streaming providers.

Use search when a name is ambiguous, when the user should choose, or when you
need to know something exists before promising it. For "play some Radiohead",
skip it.

```
hearth resource invoke music_assistant browse_library '{"media_type":"album","limit":50}'
```

`browse_library` lists what is **in the library** — `media_type` is required
and is one of artist, album, track, playlist, radio, audiobook, podcast.
`search` narrows within it, `order_by` takes name / year / random, `offset`
pages.

Search reaches the streaming providers; browse_library is the collection.
"What albums do we have?" is browse_library.

## Transport

```
hearth resource invoke music_assistant play     '{"entity_id":"media_player.kitchen"}'
hearth resource invoke music_assistant pause    '{"entity_id":"media_player.kitchen"}'
hearth resource invoke music_assistant next_track '{"entity_id":"media_player.kitchen"}'
hearth resource invoke music_assistant previous_track '{"entity_id":"media_player.kitchen"}'
hearth resource invoke music_assistant seek '{"entity_id":"media_player.kitchen","position_seconds":45}'
```

`play` only resumes what is loaded — an idle speaker with an empty queue has
nothing to resume, so "put some music on" is `play_media`.

`previous_track` behaves like every music player: the first call usually
restarts the current track rather than going back one. "Go back a song" may
take two.

`seek` counts from the **start of the track**, so relative requests ("back 30
seconds") need `media_position` from `get_player` first.

`turn_off` shuts the speaker down; `pause` is what "stop the music" means.

## Shuffle and repeat are different types

```
hearth resource invoke music_assistant set_shuffle '{"entity_id":"...","shuffle":true}'
hearth resource invoke music_assistant set_repeat  '{"entity_id":"...","repeat":"all"}'
```

`shuffle` is a **boolean**. `repeat` is a **string**: `off`, `one` (this
track) or `all` (the queue). Mixing them up fails the call.

## Multi-room

Two different things, and picking the wrong one is disruptive.

**`transfer_queue` moves the music.** "I'm going upstairs, bring the music
with me." The source room goes quiet, the destination picks up where it left
off:

```
hearth resource invoke music_assistant transfer_queue '{
  "entity_id": "media_player.study",
  "source_player": "media_player.kitchen"
}'
```

`entity_id` is where the music is going **to**. `source_player` is required —
Music Assistant would otherwise pick "whichever player is playing", which in a
house with several rooms going at once is a coin flip that silences someone
who asked for nothing.

**`join_players` makes speakers play together.** "Put this on everywhere
downstairs." `entity_id` is the leader; the members follow it and stop
whatever they were playing:

```
hearth resource invoke music_assistant join_players '{
  "entity_id": "media_player.kitchen",
  "members_json": "[\"media_player.dining_room\",\"media_player.hall\"]"
}'
```

`unjoin_player` removes one speaker from its group; that speaker stops. Read
`group_members` from `get_player` first so you know what the group is.

Both grouping verbs ask for approval by default, because they change what is
playing in rooms nobody asked you about. Expect the pause and explain it
rather than reporting a hang.

## Announcements are not speech

```
hearth resource invoke music_assistant play_announcement '{
  "entity_id": "media_player.kitchen",
  "url": "http://homeassistant.local:8123/local/doorbell.mp3"
}'
```

Plays a sound over the music and then returns to it. `url` must point at
audio Home Assistant can reach. `use_pre_announce: true` plays a chime first.

**It cannot say words.** To speak to the household, use a Home Assistant
voice satellite — `verge_labs/home_assistant`, the `announce` verb. That is
what it is for.

Asks for approval by default: it interrupts a room, and unlike a wrong volume
it cannot be un-heard.

## Reading the room

Music is shared and audible, and the people it reaches usually didn't ask you
for anything:

- **Enqueue rather than replace** when something is already playing.
- **Check before changing a room in use.** If `get_player` shows `playing` and
  the request is vague about what to do with it, ask.
- **Prefer the narrowest target** — one room over a group, a nudge over a jump,
  pause over turn_off.
- **Be conservative with volume at night.** Read, then nudge.

## When a call fails

- **`Service not found` / 400 naming `music_assistant`** — the Music Assistant
  integration isn't set up on this Home Assistant, or its add-on is stopped.
  Nothing here works until a person fixes that; the plain `media_player`
  verbs may still work, but playing by name will not.
- **404 on `get_player`** — no such entity. Re-run `list_players`; don't retry
  the same id.
- **400 on `set_volume`** — almost always a percentage. It is 0.0–1.0.
- **400 on `set_repeat`** — `repeat` must be `off`, `one` or `all`.
- **A missing `config_entry_id`** — only `search` and `browse_library` need it.
  Everything else works without; say so rather than declaring the connection
  broken.
- **401** — the Home Assistant token is invalid or revoked. A person has to
  issue a new one; there is no retry that helps.
