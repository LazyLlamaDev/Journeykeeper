# Journeykeeper settings reference

Open with `/jkp config` (or Esc > Options > AddOns > Journeykeeper). Generated from `Options.lua` by `tools/settings_doc.py`.

## Detail Preset

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Detail preset | cycle |  | essentials, storyteller, chronicler, custom | essentials = only the big moments, few popups. storyteller = the balanced default. chronicler = record nearly everything, more echoes. Changing any setting yourself switches to 'custom'. Choosing a preset never deletes memories. |
| Show the preset picker | button |  |  |  |

## Look

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Journal layout / theme | cycle | parchment | parchment, classic | parchment = the new aged-parchment pages, cards and popups (default). classic = the look before 0.7.1. Applies instantly; also /jkp layout. |

## General

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Echo intensity | cycle | present | silent, soft, present, storyteller | How often and how readily echoes appear. |
| Quiet Mode | toggle | false |  | Only the highest-weight memories are shown. |
| Quiet Mode minimum score | slider | 8 | 4 - 14 (step 1) |  |
| Toast style | cycle | parchment | parchment, dark |  |
| Popup position | cycle | top | top, center, bottom, custom | top = top-center (default), center = middle of the screen, bottom = bottom-center. 'custom' is set automatically when you Shift-drag a popup. |
| Reset popup position (Shift-drag a popup to move it) | button |  |  |  |
| Book size (%) | slider | 100 | 50 - 160 (step 5) | 100 = automatic size for your screen (1080p, 1440p and 4K). The book always stays fully on screen. |
| Reset book position | button |  |  |  |
| Hold echoes while in instances | toggle | true |  |  |
| World map pins for memorable spots | toggle | false |  | Off by default: pinning frames onto the world map can trigger Blizzard's addon blocker. Turn on only if you need the pins. |

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
| Minimap icon angle (degrees) | slider | 225 | 0 - 359 (step 1) | Position on the rim. 225 = southwest, away from the Issue Reporter. Shift-drag the icon to set this live. |

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
| Use the real in-game continent map behind the journey path | toggle | true |  | Reads Blizzard map tiles via C_Map onto the journal page. Falls back to the drawn parchment map. |
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

## Quick Notes

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Quick notes (master switch) | toggle | true |  | /jkp note <text>, the key binding, the journal's Note button and Shift-click on the minimap icon. Notes are journal entries with zone, time and character; right-click one in the journal to edit or archive it. |
| Also register /note (only if no other addon uses it) | toggle | true |  | Checked at login. If another addon already owns /note, only /jkp note is used. Takes effect after /reload. |
| Shift-click the minimap icon for a quick note | toggle | true |  |  |

## Fellowship

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Remember the people I group with (master switch) | toggle | true |  | Stores only name, realm and class, plus when and where you met, time together, shared dungeon runs and boss kills. Never sent anywhere. |
| Leave out members of my guild | toggle | false |  |  |
| Echo when I group again with someone I ran a dungeon or killed a boss with | toggle | true |  |  |
| Forget fellows not seen for (days, 0 = never) | slider | 0 | 0 - 730 (step 30) | 0 keeps everyone. A snapshot is taken before anyone is removed. |
| Never record these names (comma separated) | input |  |  | e.g. 'Bob, Alice-Realm'. A name without realm matches every realm. |

## Addon Compartment

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Use the Addon Compartment entry (left: journal, right: settings) | toggle | true |  | Blizzard always lists the entry; when this is off, clicking it only prints a hint. |

## Export

| Setting | Type | Default | Range / values | Notes |
|---|---|---|---|---|
| Memories in the HTML book | slider | 50 | 10 - 200 (step 10) |  |

## Events & channels

Each category is a collapsible group. Every event has an on/off toggle and a display channel: toast, chat, echoes (a chat window named 'Echoes'), tooltip, journal (logged, no popup) or off. See EVENT_CATALOG.md for the full list.
