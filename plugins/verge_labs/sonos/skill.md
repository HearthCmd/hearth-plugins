---
name: sonos
description: >
  Use when playing, pausing, or changing music on Sonos speakers via a hearth
  resource connection — putting a favourite or playlist on in a room, changing
  volume, skipping tracks, checking what's playing, or grouping rooms together.
  Covers discovering rooms and speakers, transport, volume, favourites,
  playlists, grouping, and audio clips through the sonos plugin.
---

# Sonos plugin

Invoke via `hearth resource invoke <connection> <verb> '<args-json>'`.

`<connection>` is the name shown in your resource list — either the slug
(e.g. `sonos`) or the connection UUID. Both resolve. Examples below use
`sonos`; substitute the connection you were actually granted.

## Passing arguments

Args are **one JSON object**, quoted as a single shell argument. There is no
`--arg` flag:

```
hearth resource invoke sonos list_households
hearth resource invoke sonos pause '{"group_id":"RINCON_xxx:1"}'
```

`volume` and `volume_delta` are integers — pass bare JSON numbers. `muted`,
`shuffle`, `repeat` and `play_on_completion` are booleans — pass `true` /
`false`, not `"true"`.

## Two ids, and where they come from

Nearly every verb takes one of two opaque ids. **Never guess or construct
either.**

- **`group_id`** — a *room*, or several rooms playing together. This is the
  target of all playback and volume commands.
- **`player_id`** — one physical speaker. Only needed for `set_player_volume`
  and `play_audio_clip`.

Both come from `list_groups`:

```
hearth resource invoke sonos list_groups '{"household_id":"Sonos_xxx"}'
```

which returns `groups` (each with `id`, `name` like "Kitchen", `coordinatorId`,
`playerIds`, `playbackState`) and `players` (each with `id`, `name`,
`capabilities`).

`household_id` comes from `list_households`, which almost always returns
exactly one:

```
hearth resource invoke sonos list_households
```

If the connection has `household_id` configured you can omit it everywhere;
otherwise look it up once and reuse it for the whole conversation.

### Group ids are not stable — re-read them

A group id describes *the current grouping*, and Sonos mints a new one every
time rooms are grouped or split. An id from an hour ago, or from before you
called `create_group`, is very likely dead.

Call `list_groups` at the start of any music task, and again after any
grouping change. Use the id `create_group` / `set_group_members` returns rather
than a remembered one. A stale id gives you a 404, not silence — but it's an
avoidable round trip.

### Matching a room by name

The user says "the kitchen"; you need the group whose `name` is "Kitchen". Match
case-insensitively on `name`. Two wrinkles:

- When rooms are grouped, the group's name is usually the coordinator's, so
  "Kitchen" may be a group that also includes the dining room. Check
  `playerIds` before assuming a command hits one room.
- If nothing matches, say which rooms *do* exist rather than guessing at the
  closest one. Playing music in the wrong room at 7am is a real cost.

## Everything goes through Sonos' cloud

There is no supported local API. Every call in this plugin is an HTTPS request
to `api.ws.sonos.com`, which then reaches the speakers. Consequences worth
knowing:

- The speakers must be online and registered to the connected Sonos account.
- Commands are not instant; a small lag between call and sound is normal.
- If the household's internet is down, nothing here works even though the
  speakers and the phone are on the same Wi-Fi. Say that plainly rather than
  retrying.

## Checking what's playing

Two different verbs, and the distinction matters:

```
# Transport state: playing / paused / idle, and what actions are allowed
hearth resource invoke sonos get_playback_status '{"group_id":"..."}'

# The actual track: name, artist, album, and what it came from
hearth resource invoke sonos get_playback_metadata '{"group_id":"..."}'
```

"What's playing in the kitchen?" needs `get_playback_metadata`.
"Is anything playing?" needs `get_playback_status`.

`get_playback_status` also returns `availablePlaybackActions` — check
`canSkip` before skipping. Radio streams have no next track and the skip
fails with `ERROR_PLAYBACK_FAILED`.

## Transport

```
hearth resource invoke sonos play  '{"group_id":"..."}'
hearth resource invoke sonos pause '{"group_id":"..."}'
hearth resource invoke sonos skip_to_next_track '{"group_id":"..."}'
hearth resource invoke sonos skip_to_previous_track '{"group_id":"..."}'
```

`skip_to_previous_track` goes back in the queue. On most sources the first
press restarts the current track rather than moving to the previous one, so
"go back" may need two calls — check `get_playback_metadata` rather than
assuming.

`play` **resumes what is already loaded** — it does not choose anything. "Put
some music on" in an idle room needs `load_favorite` or `load_playlist`, not
`play`.

Prefer explicit `play` / `pause` over `toggle_play_pause`. Toggling acts on
the state at the speaker, not the state you last read, so a toggle sent on a
stale reading does exactly the opposite of what was asked.

## Shuffle and repeat

```
hearth resource invoke sonos set_play_modes '{"group_id":"...","shuffle":true}'
```

`set_play_modes` takes `shuffle`, `repeat`, `repeat_one` and `crossfade`, all
optional and all booleans. **Omitted modes are left unchanged**, so pass only
what the user asked to change — sending `{"shuffle":true}` won't quietly turn
off their repeat.

`get_playback_status` returns the current `playModes` if you need to report
them back.

## Volume — prefer relative

```
# "turn it up a bit"
hearth resource invoke sonos set_relative_group_volume '{"group_id":"...","volume_delta":10}'

# "set it to 30"
hearth resource invoke sonos set_group_volume '{"group_id":"...","volume":30}'
```

**`set_relative_group_volume` is the right default.** It needs no prior read,
Sonos clamps the result into 0–100, and it can't overshoot.

`set_group_volume` jumps to an absolute level. If you use it, read
`get_group_volume` first — going to 60 in a room that was at 12 is startling
and, at night, genuinely unpleasant. When the user gives a vague instruction
("louder"), a delta of 5–10 is a sensible step; don't interpret it as an
absolute.

`get_group_volume` also returns `fixed`. When true, the group's volume can't be
changed at all (a device wired to an amp) — report that rather than retrying.

To silence a room without losing its setting, use `set_group_mute` — unmuting
restores the level. Setting volume to 0 loses it.

`set_player_volume` adjusts one speaker inside a group, for rebalancing
("quieter in the kitchen but leave the rest"). For a whole room, use the group
verbs.

## Putting something on

Sonos can only start content the household has already saved — favourites and
Sonos playlists. There is no search, and no way to ask for an arbitrary artist
or album.

```
hearth resource invoke sonos list_favorites '{"household_id":"..."}'
hearth resource invoke sonos load_favorite '{"group_id":"...","favorite_id":"..."}'

hearth resource invoke sonos list_playlists '{"household_id":"..."}'
hearth resource invoke sonos load_playlist '{"group_id":"...","playlist_id":"..."}'
```

Favourites and playlists are separate lists. A favourite is anything saved in
the Sonos app — a radio station, an album, a playlist from a music service. A
Sonos playlist is one built in Sonos itself. When looking for something by
name, check both before concluding it isn't there.

`load_favorite` and `load_playlist` default to `action: "REPLACE"` and
`play_on_completion: true` — they swap the queue for the chosen thing and start
playing, which is what "put the radio on in the kitchen" means. Pass
`{"action":"APPEND"}` to add to the queue instead, and
`{"shuffle":true}` to shuffle.

When the user asks for something that isn't in favourites or playlists, say so
and list what *is* there. Don't substitute something that merely sounds
similar.

## Grouping rooms

Grouping is how "play this everywhere downstairs" works.

```
# New group from a set of speakers
hearth resource invoke sonos create_group '{
  "household_id": "...",
  "players_json": "[\"RINCON_aaa\",\"RINCON_bbb\"]"
}'

# Change who is in an existing group
hearth resource invoke sonos set_group_members '{
  "group_id": "...",
  "players_json": "[\"RINCON_aaa\",\"RINCON_bbb\",\"RINCON_ccc\"]"
}'
```

`players_json` is a **string containing JSON**, escaped inside the outer
object — not a nested array.

**`set_group_members` REPLACES the membership.** Include every player that
should remain, not just the ones you're adding. Passing only the new room
silently drops everyone else out of the group and stops their music. To
un-group a room, list the players that should stay.

Both verbs prompt for approval by default, because grouping changes what is
playing in rooms nobody asked you about. Expect the pause; explain it rather
than reporting a hang.

Grouping also mints new group ids. Use the returned one.

## Audio clips are not speech

```
hearth resource invoke sonos play_audio_clip '{"player_id":"...","name":"Doorbell"}'
```

`play_audio_clip` plays a short sound over whatever is playing and then returns
to the music — the built-in chime by default, or an MP3/WAV you pass as
`stream_url`.

**It cannot say words.** There is no text-to-speech in the Sonos API. To speak
to the household, use a Home Assistant voice satellite
(`verge_labs/home_assistant`, the `announce` verb) — that's what it's for.

Only speakers whose `capabilities` include `AUDIO_CLIP` support this; check
`list_groups` first. It asks for approval by default: it interrupts a room at a
volume the caller picks, and unlike a wrong volume setting it can't be undone
after the fact.

## Reading the room

Music is shared and audible, and the people affected usually didn't ask you for
anything. A few habits that avoid the obvious mistakes:

- **Check before changing what someone is listening to.** If
  `get_playback_status` says a room is `PLAYBACK_STATE_PLAYING` and the request
  is vague about which room, ask rather than replacing the queue.
- **Prefer the narrowest target.** One room over a group; a delta over an
  absolute; pause over stop-and-replace.
- **Late at night, be conservative with volume.** A relative nudge is almost
  always the right call.

## When a call fails

- **404** — the group or player id is stale or wrong. Re-run `list_groups`;
  don't retry the same id.
- **`ERROR_PLAYBACK_FAILED` on a skip** — the source has no next track (radio).
  Check `availablePlaybackActions.canSkip` first.
- **`ERROR_SKIP_LIMIT_REACHED`** — the music service caps skips. Nothing to be
  done; tell the user.
- **`ERROR_COMMAND_FAILED` on a volume set** — the player has fixed volume.
  Check `fixed` in `get_group_volume`.
- **401 / token errors** — the Sonos connection needs re-authorizing in the
  app. That's a person's job, not a retry.
