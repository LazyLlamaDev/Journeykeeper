# Journeykeeper performance

These are approximations. They come from an offline benchmark that runs the real addon code in a mock WoW API:
- under **Lua 5.1** (lupa), which is the closest to WoW's interpreter
- under **LuaJIT 2.1**, for comparison

Limits of the mock:
- Mock widgets are free no-ops, so UI timings are lower bounds.
- WoW's allocator and garbage collector differ from the mock's.
- WoW measures addon memory with `GetAddOnMemoryUsage`, not `collectgarbage`.

Raw data is in `docs/bench/*.json`.

## Growth model

The model assumes, per hour of play:
- 10 journal entries
- 3 echoes (diary, capped at 500)
- 30 ghost-trail points per character (cap 3000 per character, so the cap is reached at about 100 h per character)
- 4 new players met
- 1 death spot
- 3 echo-cooldown keys
- 3 characters

These rates are assumptions, not measurements of real play. Leveling produces more entries than endgame.

## Measured (Lua 5.1 mock; v0.5.0 → v0.5.1, LuaJIT in brackets)

| | 10 h | 100 h | 1000 h |
|---|---|---|---|
| Entries | 100 | 1 000 | 10 000 |
| Lua memory: code + data (no UI open) | 0.86 MB | 2.6 MB | 15.5 MB |
| Lua memory after a session with backups loaded + journal opened | 1.7 → **1.7 MB** | 9.4 → **7.9 MB** | 62 → **43 MB** (34) |
| Serialized DB (one snapshot) | 74 → 65 KB | 686 → 598 KB | 4.6 → 4.2 MB |
| `Journeykeeper.lua` on disk (DB + backup ring 1) | 342 → **242 KB** | 3.1 → **2.2 MB** | 21 → **10 MB** |
| `Journeykeeper_Vault.lua` on disk | 332 → **148 KB** | 3.0 → **1.3 MB** | 21 → **4.7 MB** |
| Parse time of `Journeykeeper.lua` at load (loadstring) | 1.8 → 1.5 ms | 17 → 14 ms | 130 → 87 ms |
| Logout/reload snapshot, data changed | 14 → 11 ms (5) | 109 → 107 ms (41) | 890 → **860 ms** (390) |
| Logout/reload, nothing changed | – → **0.8 ms** | – → **1.4 ms** | – → **6.6 ms** |
| Zone/subzone change | 34 → 27 µs | 107 → **48 µs** | 1 095 → **203 µs** |
| `C.Emit` (log + echo pipeline) | 7 µs | 8 µs | 8 µs |
| Unit tooltip post-call | 1.6 µs | 1.8 µs | 1.5 µs |
| Combat-log handler per event (now opt-in) | 1.5 µs | 1.5 µs | 1.3 µs |
| World map refresh (pins + 400 trail dots), only on map/zoom change | 0.1 ms | 0.8 ms | 7.8 ms (2.8) |
| Journal page build (open / refresh while open) | 1.0 ms | 4.7 ms | 48 ms (13) |
| ADDON_LOADED (migrate check + validate + defaults) | 0.2 ms | 0.5 ms | 3.9 ms |

**Idle CPU:** no per-frame work except the world-map watcher, which only checks whether the map is shown (every 0.3 s). The other timers are:
- Fall detection: 0.25 s ticker, one `IsFalling` call.
- Ghost-trail sampler: a 10 s ticker that records a point every 30, 60 or 120 s.
- Death-spot proximity: 5 s ticker.
- Session clock: 60 s ticker.
- Sharing queue: runs only while messages are queued.

## Hot-path review

| Path | Before | Now |
|---|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` | Always registered; the busiest event in WoW (hundreds per second in groups). Midnight-era clients restrict it for addons, and registering can raise ADDON_ACTION_FORBIDDEN ([DragonShout #28](https://github.com/Xerrion/DragonShout/issues/28), [Blizzard](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)) | **Opt-in** setting, off by default, on its own frame. The player GUID is cached. Killer names fall back to the last hostile target. |
| Zone/subzone revisit | Full scan of every entry for old deaths on each zone change, O(n) | Incremental index of death entries |
| Sharing queue | Per-frame `OnUpdate`, even with sharing off | 0.2 s ticker that exists only while the queue is non-empty |
| Settings pages (main, Friends & Sharing, Data & Backups) | About 200 widgets created at login | Built on first open |
| Journal, toasts, export windows | Already lazy (created on first use) | Unchanged |
| Tooltip post-call | Rebuilt a constant table on every unit tooltip | Constant hoisted |
| Map pins | Redraw only on map/zoom change; 400-dot cap with even thinning | Unchanged; 7.8 ms at 1000 h per map change is fine |
| Combat-meter read | Once, 1.5 s after combat ends | Unchanged |
| Snapshots | Full DB copied up to 6 + 1 + 2 times, floats written as 17 digits, caches included, a new copy at every logout | See below |

## Snapshot cost and mitigation

The concern is real. Every snapshot is a full copy of the DB, and saved variables are loaded into Lua memory every session. In v0.5.0, 1000 h meant about 42 MB across the two files and about 0.9 s of extra logout time.

What v0.5.1 does:
1. **Compact snapshots.** Volatile caches are left out (echo cooldowns, template rotation, health log) and rebuilt after a restore. Floats are written in their shortest form that round-trips: `50.3`, not `50.299999999999997`. That saved about 12% per snapshot.
2. **Fewer copies:**
   - 2 ring snapshots per file instead of 3.
   - A new ring snapshot only every **6 h**. Logouts in between overwrite one "latest" slot in the vault.
   - Above **1.5 MB** per snapshot, 1 ring snapshot per file.
   - The main file drops its pre-migration copy after 14 days; the vault keeps its own.
3. **Skip when unchanged.** A cheap signature (counts, last entry, trail size, players, settings, arcs, records) means a reload with no changes costs about 1–7 ms instead of a full serialize.

**Result:** disk at 1000 h went from 42 to 15 MB, and memory from 62 to 43 MB.

The remaining cost is about 0.1 s (100 h) to 0.9 s (1000 h) at a logout where data changed, on top of WoW's own save.

**Proposed next steps** (not implemented, because they add complexity to the safety layer):
- **Delta snapshots.** Entries are append-only, so a ring snapshot could store only entries since its base plus the mutable tables. That is roughly 10× smaller and faster, but restore would then depend on two snapshots.
- **Frozen archive blocks.** Entries older than 30 days would be serialized once into immutable chunks (with a checksum per chunk) that every snapshot reuses by reference.
- **A user cap:** a "backup depth" setting from 1 to 3.

## Other addons: what is actually sourced

Memory figures depend on the version, settings and content. Where no credible source exists, the table says *unknown*. Comparing memory across addons is weak evidence: addon authors and community testers consistently say CPU matters more than memory.

| Addon | Memory (source) | CPU (source) |
|---|---|---|
| All The Things | **~180–190 MB** at login, grows slightly with item cache. Author reply on [GitHub #174](https://github.com/DFortun81/AllTheThings/issues/174) | unknown |
| Questie (Classic) | ~20 MB after v6.0.0, down from ~150 MB ([r/classicwow, v6.0.0 thread](https://www.reddit.com/r/classicwow/comments/hjn1qr/questie_v600_is_out/)). 80 MB+ in a 2019 user report ([WoWInterface](https://www.wowinterface.com/downloads/info24994-Questie.html)) | unknown |
| WeakAuras | 2.6–3.5 MB idle, **50 MB+ after opening options** until /reload ([MMO-Champion, old](https://www.mmo-champion.com/threads/1258252-Problem-with-memory-usage)). One user went from 40 MB to under 15 MB by deleting auras ([Blizzard forums 2024](https://us.forums.blizzard.com/en/wow/t/reducing-memory-usage-of-details-addon/1763164)) | Users report it as a top CPU user in raids ([r/WowUI](https://www.reddit.com/r/WowUI/comments/lee82m/help_is_elvui_as_resource_heavy_as_it_was_in_the/)); anecdotal |
| ElvUI | 7.1 MB in an old report ([MMO-Champion](https://www.mmo-champion.com/threads/1258252-Problem-with-memory-usage)) | Noticeable in raids per users ([r/WowUI benchmark thread](https://www.reddit.com/r/WowUI/comments/1llus3d/i_was_curious_what_the_performance_cost_of_elvui/)); no reproducible number |
| Details! | Grows with stored segments; one user reported "2 GB" (doubtful, likely a misread; [r/wownoob](https://www.reddit.com/r/wownoob/comments/vd6kgz/is_there_a_details_lite_version/)) | The update interval is the main lever (same thread) |
| DBM vs BigWigs | Similar in combat (2013 test) | 2013 MoP LFR test: DBM 21.2 vs BigWigs 3.7 CPU ms/s on Council of Elders ([MMO-Champion](https://www.mmo-champion.com/threads/1277630-What-is-the-difference-between-BigWigs-and-DBM)); old, single run |
| Plater, Altoholic, TomTom, RestedXP | unknown (no credible measurement found) | unknown |

**Expectation for Journeykeeper:**
- **Memory:** about 1–2 MB for a 10 h journal, about 8 MB at 100 h, and about 35–45 MB only after around 1000 h, almost all of it the player's own saved history plus backups.
- **CPU:** effectively zero per frame while idle. On the order of microseconds per handled event and per tooltip. Spikes only when opening the journal or map, and at logout when backing up.

## How to measure in game

- **`/jkp perf`** shows:
  - Journeykeeper and Vault memory (`UpdateAddOnMemoryUsage` + `GetAddOnMemoryUsage`)
  - CPU from the built-in profiler (`C_AddOnProfiler.GetAddOnMetric`): recent and session average, peak, frames over 1, 5 and 50 ms, and share of all addon CPU
  - data counts, backup sizes, and how long the last backup took

  The profiler is always on and needs no CVar ([warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_C_AddOnProfiler.GetAddOnMetric)); it lists the Forever 1.60.1 client.
- To compare with other addons, use a tool such as AddonUsage ([Wago](https://addons.wago.io/addons/addonusage)) or the game's built-in addon list. Memory includes saved data, so compare after a `/reload`.
- To test the worst case, play a session, then `/reload` twice. The second reload should report "skipped: nothing changed".
