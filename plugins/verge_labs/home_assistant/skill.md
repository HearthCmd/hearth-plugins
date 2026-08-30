---
name: home_assistant
description: >
  Use when controlling or checking the smart home through a hearth resource
  connection — lights, switches, fans, scenes, locks — or when speaking a
  message out loud on a voice satellite. Covers reading entity state, finding
  the right entity by room and name, turning things on and off, activating
  scenes, locking and unlocking doors, and announcing through the
  home_assistant plugin.
---

# Home Assistant plugin

Invoke via `hearth resource invoke <connection> <verb> '<args-json>'`.

`<connection>` is the name shown in your resource list — either the slug
(e.g. `home`) or the connection UUID. Both resolve. Examples below use
`home`; substitute the connection you were actually granted.

## Passing arguments

Args are **one JSON object**, quoted as a single shell argument. There is no
`--arg` flag:

```
hearth resource invoke home list_entities
hearth resource invoke home get_state '{"entity_id":"light.kitchen_ceiling"}'
```

Every verb here takes `entity_id`, and `announce` / `start_conversation` also
take `message`.

## Find the entity before you act on it

`entity_id` is an opaque Home Assistant identifier — `light.kitchen_ceiling`,
`switch.porch`, `lock.front_door`. **Never guess or construct one.** The user
says "the kitchen light"; the system wants `light.kitchen_ceiling`, and the
mapping is unique to their house.

```
hearth resource invoke home list_entities
```

That returns every entity with its state and attributes. Match on:

- `attributes.friendly_name` — the label the user actually says out loud
  ("Kitchen Ceiling", "Porch", "Front Door")
- `attributes.area_id` — the room, when the user names one ("the bedroom lamp")
- the domain prefix before the dot — `light.`, `switch.`, `fan.`, `scene.`,
  `lock.`, `climate.`, `media_player.`, `assist_satellite.`

A house has hundreds of entities, so `list_entities` is a big response. Fetch
it once and reuse it for the rest of the conversation rather than calling it
before every action.

### When the match is ambiguous, ask

"Turn off the light" in a house with fourteen lights is not a request you can
safely resolve by picking one. If several entities match, name the candidates
by their friendly names and ask which. Guessing wrong here is visible and
annoying — someone is sitting in a room that just went dark.

Exception: when exactly one entity in the named area matches, act. "The
bedroom lamp" with a single `light.*` in `area_id: bedroom` is unambiguous.

## Reading state

```
hearth resource invoke home get_state '{"entity_id":"light.kitchen_ceiling"}'
```

Returns `state` (`"on"` / `"off"` / `"unavailable"` / a number for sensors)
plus `attributes` — brightness, temperature, battery level, whatever that
device reports.

Two things worth checking before you report an answer:

- **`unavailable` is not `off`.** It means the device isn't reachable — a dead
  battery, a hub that dropped off. Say that, rather than reporting it as off.
- **Check state before toggling.** If the user asks you to turn off a light
  that's already off, say so instead of firing a no-op and reporting success.

## Turning things on and off

```
hearth resource invoke home turn_on  '{"entity_id":"light.kitchen_ceiling"}'
hearth resource invoke home turn_off '{"entity_id":"switch.porch"}'
```

The domain is inferred from the `entity_id` prefix, so the same two verbs
cover lights, switches, fans, input booleans, and media players. There is no
separate `fan_on`.

**Only lights are pre-approved.** The plugin's default rules allow `turn_on`
and `turn_off` without asking *when the entity is a light*. Anything else — a
switch, a fan, a media player — goes to the household for approval on every
call. That is a deliberate setting, not a bug: a "switch" might be a space
heater or a well pump.

So when you turn on a non-light, expect a pause while someone approves it on
their phone, and tell the user that's what's happening rather than reporting a
hang. If they want it to stop asking, they can widen the rule themselves.

### Brightness, colour, temperature

This plugin's `turn_on` sends only `entity_id` — it cannot set brightness,
colour, or a thermostat's target. "Dim the lights to 40%" is not something
these verbs can do. Say so plainly and offer what you can: on, off, or a scene
the user has already built for that purpose.

## Scenes

```
hearth resource invoke home list_entities        # find scene.* entities
hearth resource invoke home set_scene '{"entity_id":"scene.movie_night"}'
```

A scene is a saved set of device states the user curated themselves — "Movie
Night", "Good Morning", "Away". Activating one applies all of it at once.

Scenes are allowed by default and are usually the *better* answer than driving
devices individually: the user already decided what "movie night" means, so
prefer their scene over your own guess at six separate light calls. When a
request sounds like a mood rather than a device ("make it cosy", "we're going
to bed"), look for a matching scene first.

## Locks — expect to be asked

```
hearth resource invoke home lock   '{"entity_id":"lock.front_door"}'
hearth resource invoke home unlock '{"entity_id":"lock.front_door"}'
```

Both are `ask` by default: **every** call prompts a human, every time. This is
the one place in the plugin where that is true regardless of which entity you
name.

Don't try to route around it, and don't treat the prompt as an error. Say what
you're about to do and that it needs their approval. If the request is vague
("lock up"), resolve exactly which doors you mean *before* firing calls — each
one costs the user a separate approval.

Never unlock on a schedule, a guess, or an inference. Unlock because a person
in this conversation asked you to, now.

## Speaking out loud

`announce` speaks a message on a voice satellite (`assist_satellite.kitchen`).
`start_conversation` speaks **and then opens the microphone** for a reply with
no wake word.

```
hearth resource invoke home announce '{
  "entity_id": "assist_satellite.kitchen",
  "message": "The dishwasher has finished."
}'
```

### Do NOT use these to answer someone who just spoke to you

When a voice message reaches you, the reply path is the `<hearth-voice>`
marker described in that message — you wrap the words you want spoken, and
Hearth speaks them on the right satellite. It has already worked out which
satellite that is.

Calling `announce` yourself to answer a voice message makes the house say it
**twice**. Wrap your reply in the marker instead, and don't invoke these verbs
at all on a voice turn.

### What they *are* for

Speaking **unprompted** — when nobody asked you anything and there's no
conversation in flight:

- a timer or a long job finishing ("the laundry's done")
- something the household asked to be told about ("the garage door has been
  open for an hour")
- a reminder they set

For that, pick the satellite nearest whoever needs to hear it (`list_entities`,
`assist_satellite.*`, matched on `area_id`), and use `announce`. Reach for
`start_conversation` only when you're genuinely asking a question and expect an
answer back — an open microphone in an empty room records a conversation nobody
meant to have.

Announcing out loud interrupts a room. A house that talks unprompted all day
gets muted. Use it when it earns the interruption.

## When a call fails

- **404** — the `entity_id` doesn't exist. You guessed or the entity was
  renamed. Re-run `list_entities` and match again; don't retry the same id.
- **`unavailable` state** — the device is offline. Report it as such; retrying
  won't help.
- **A permission prompt** — expected for locks, and for `turn_on`/`turn_off`
  on anything that isn't a light. Wait for the human; explain the wait.

Home Assistant is the user's own house. When something doesn't work, prefer
telling them plainly over retrying in a loop — a light that won't respond is
often a real-world problem (a flat battery, a hub reboot) that only they can
fix.
