# Journeykeeper settings reference

Open with `/jkp config` (or Esc > Options > AddOns > Journeykeeper). Generated from `Options.lua`.

## General

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Echo intensity | cycle | present | silent, soft, present, storyteller | How often and how readily echoes appear. |
| Quiet Mode | toggle | false |  | Only the highest-weight memories are shown. |
| Quiet Mode minimum score | slider | 8 | 4 - 14 (step 1) |  |
| Toast style | cycle | parchment | parchment, dark |  |
| Hold echoes while in instances | toggle | true |  |  |
| World map pins for memorable spots | toggle | true |  |  |

## Emotional Weighting

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Rarity weight | slider | 1 | 0 - 3 (step 0.5) | Bonus for memories that are rare across the whole account. |
| Context weight | slider | 2 | 0 - 4 (step 0.5) | e.g. returning at high level to where you died at low level. |
| Pinned moment boost | slider | 6 | 0 - 10 (step 1) |  |
| Ordinary memories fade over (days) | slider | 90 | 7 - 365 (step 7) |  |
| Reinforcement per revisit/echo | slider | 0.5 | 0 - 1 (step 0.25) |  |
| Reset 'remind me more' boosts | button |  |  |  |

## Warband Resonance

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Echoes that name your other characters | toggle | true |  |  |
| Warband 'family firsts' | toggle | true |  |  |
| Ghost trail of other characters on the world map | toggle | false |  |  |
| Ghost trail density | cycle | low | low, medium, high | Sampling: 120 s / 60 s / 30 s, max 400 dots per map. |
| Include the current character's trail | toggle | false |  |  |

## Soft Social

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Known-player lines in unit tooltips | toggle | true |  |  |
| Ask for a private rating after a group ends | toggle | true |  |  |
| Only ask after grouping for (minutes) | slider | 10 | 5 - 60 (step 5) |  |
| How much ratings affect ally echoes | slider | 3 | 0 - 5 (step 1) |  |

## Atmosphere

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Toast sound | toggle | true |  |  |
| Ambient sound for strong echoes | cycle | chime | off, chime, parchment, horn |  |
| Subtle screen vignette for strong echoes | toggle | false |  |  |
| Vignette minimum score | slider | 9 | 4 - 14 (step 1) |  |
| Minimap icon (glows on new echoes) | toggle | true |  |  |

## Threads & Arcs

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Detect chains (returning to where you first fell, ...) | toggle | true |  |  |
| 'Since you were last here' digest at login | toggle | true |  |  |
| Digest after an absence of (hours) | slider | 8 | 1 - 72 (step 1) |  |

## Agency

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Adapt intensity: lower in long sessions, instances and raids, higher while resting | toggle | true |  |  |
| Unmute all memories | button |  |  |  |

## Combat Metrics

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Track fight records via the built-in damage meter | toggle | true |  | Reads C_DamageMeter only after combat ends and only non-secret values. No single biggest hit: the API exposes per-spell totals per fight. |
| Ignore fights shorter than (seconds) | slider | 15 | 5 - 120 (step 5) |  |
| Echo toasts for new personal records | toggle | true |  |  |
| Use the combat log (killer names, rare kills) | toggle | false |  | Off by default: the combat log is WoW's busiest event and Midnight-era clients restrict it for addons. Without it, killer names come from your last hostile target. |

## Flavor & Seasons

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Seasonal / atmospheric wording in echoes | toggle | true |  |  |
| How often to add a flavor line (%) | slider | 40 | 0 - 100 (step 10) |  |
| Holiday flavor (from the in-game calendar) | toggle | true |  |  |
| Real-world season flavor | toggle | true |  |  |
| Game time of day flavor | toggle | true |  |  |
| Zone mood flavor | toggle | true |  |  |
| Era / phase label (journal title) | input |  |  | e.g. 'Forever Phase 1'. Shown on the journal title page and in exports. |

## Photo Mode

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Photo mode (master switch) | toggle | true |  | /jkp photo, keybind, or the camera button on toasts and the journal. Out of combat only. |
| Hide the interface while shooting | toggle | true |  |  |
| Vignette | toggle | true |  |  |
| Ornate frame | toggle | true |  |  |
| Caption (memory, zone, character, date) | toggle | true |  |  |
| Camera preset | cycle | none | none, close, medium, wide |  |

## Journey Map

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Journey chapter (master switch) | toggle | true |  |  |
| Continent sketch pages | toggle | true |  |  |
| Draw my path on the world map | toggle | true |  | Uses the ghost-trail samples you already record. |

## Death Reports

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Last-moments report per death (master switch) | toggle | true |  |  |
| Announce my deaths (one line) | cycle | off | off, party, guild | Off by default. At most once per 5 minutes, never in combat or during a boss encounter. |

## Person Profiles

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Private profiles for people you meet (master switch) | toggle | true |  | Never sent to anyone. /jkp who <name>, /jkp tag, /jkp rate. |
| Show rating and tags in unit tooltips | toggle | true |  |  |

## Warband Overview

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Warband table of contents (master switch) | toggle | true |  | Time played is only requested when you click it or type /jkp played. |

## Book-style Dialogue

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Book-style dialogue (master switch) | toggle | false |  | Adds a 'Read in Journeykeeper' button beside the quest window. Blizzard's quest window is never changed. |
| Save story quest texts to the journal | toggle | true |  |  |
| Save all quest texts, not only story quests | toggle | false |  |  |
| Open the parchment automatically | toggle | false |  |  |

## Sharing

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Enable friend sharing (master switch, opt-in) | toggle | false |  | Sends small addon messages only to trusted friends. Never in combat. Nothing is sent while this is off. |

## What to share

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Milestones (levels, achievements, mounts, guild) | toggle | true |  |  |
| Firsts (boss kills, rares, dungeons, epics) | toggle | true |  |  |
| Detect shared memories with friends | toggle | true |  |  |
| Include zone name | toggle | false |  | Off: messages never contain a location. |

## Channels

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Also send to GUILD channel | toggle | false |  |  |
| Also send to PARTY channel | toggle | false |  |  |

## Accept from

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Players on my friends list | toggle | false |  |  |
| Members of my guild | toggle | false |  |  |

## Incoming

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Show toasts for incoming friend milestones | toggle | true |  | Off: they are only logged in the journal. |
| Show toasts for shared memories | toggle | true |  |  |

## Export

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Memories in the HTML book | slider | 50 | 10 - 200 (step 10) |  |

## Events & channels

Each category is a collapsible group. Every event has an on/off toggle and a display channel: toast, chat, echoes (a chat window named 'Echoes'), tooltip, journal (logged, no popup) or off. See EVENT_CATALOG.md for the full list.
