# Journeykeeper data safety

Goal: a new Journeykeeper version never breaks or loses your data, and a WoW patch or crash can never silently wipe it or leave it half-corrupted.

## Where data lives

| SavedVariables | File (WTF\Account\<acct>\SavedVariables\) | Content |
|---|---|---|
| `JourneykeeperDB` | `Journeykeeper.lua` | The journal itself: entries, diary, arcs, settings, sharing, records |
| `JourneykeeperBackupDB` | `Journeykeeper.lua` | Backup ring 1 (3 snapshots), the pinned pre-migration snapshot, and the migration log |
| `JourneykeeperVaultDB` | `Journeykeeper_Vault.lua` (companion addon **Journeykeeper_Vault**) | Backup ring 2 (3 snapshots), the newest snapshot, the pinned pre-migration snapshot, and the log |
| `JourneykeeperCharDB` | `<realm>\<char>\SavedVariables\Journeykeeper.lua` | Per-character caches; also captured inside snapshots |

WoW writes one file per addon, so all of Journeykeeper's account variables share `Journeykeeper.lua`. The tiny Journeykeeper_Vault addon exists so that at least one backup sits in a **different file**. If `Journeykeeper.lua` is truncated, everything in it is lost, but the vault keeps the newest snapshot.

If Journeykeeper_Vault is not installed, Journeykeeper keeps 6 snapshots in the main file. The Data & Backups page warns about this.

WoW also keeps its own `Journeykeeper.lua.bak` next to each file.

## Load sequence (Data.lua `D.Load`)

1. **Malformed** (`JourneykeeperDB` is not a table):
   - Journeykeeper runs **read-only** on an empty working copy.
   - The original value is never written over.
   - A warning appears; restore from Data & Backups.
2. **Missing, but backups exist** (truncated or deleted file):
   - State becomes `empty_with_backup`.
   - Nothing is attached to `JourneykeeperDB`, so nothing is saved over it.
   - A popup offers to restore the newest backup or start fresh.
   - Logout snapshots are refused, so empty data can never rotate out real backups.
3. **Newer schema** than this code (downgrade):
   - **Read-only** on a deep copy.
   - The saved data stays byte-identical.
4. **Older schema:**
   1. A snapshot is taken first and pinned in both backup files.
   2. Migrations run **on a deep copy**, each one in `pcall`.
   3. On success, the copy replaces the live table.
   4. On any error, the original is untouched, the failure is logged, and the addon goes read-only.
5. **Validate / repair:**
   - Structural damage goes to `JourneykeeperDB.quarantine` with where/why/value; it is never deleted.
   - Bad entries are replaced *in place* by a readable tombstone (`id = "_quarantined"`), so arc, diary and pin indices never shift.
   - Repairable fields (numeric strings, a missing char, an unknown category) are fixed in place. The original category is kept as `_cat`.
6. `C.InitDB` adds missing defaults only (additive). Unknown fields from other versions are preserved.

## Schema and migrations

`JourneykeeperDB.schema` is an integer; `D.SCHEMA` is the version this code writes. For data saved before schema numbers existed, the version is inferred from which tables are present.

| Schema | Release | Migration |
|---|---|---|
| 1 | v0.1 | (base) |
| 2 | v0.2 | `echoSeen`, `muted`, `tplRecent` |
| 3 | v0.3 | intensity rename quiet→soft / normal→present (old value kept in `settings._legacy`); `diary`, `arcs`, `family`, `trail`, `chars` |
| 4 | v0.4 | `records`, `share{trusted,blocked,peers,inbox}` |
| 5 | v0.4.1 | `peers[].shared = 0` |
| 6 | v0.5 | stable `uid` on every entry; `quarantine`, `health`, `migrations` tables |
| 7 | v0.6 | new lists `photos`, `deathReports`, `quests` (each record has a `uid`); entries may carry `photo` / `report` uid links. Additive only. |
| 8 | v0.7.1 | `fellowship{people,archive}`; settings get `preset = "custom"` for existing journals (no other setting is touched). Additive only. |
| 9 | v0.7.2 | new list `shots` (automatic screenshot records: time, expected file name, event, linked memory `uid`); entries may carry `shot = {t, file}`; fellows may carry `myLevel` / `myChar` (your own level and character at the last meeting, for reunion echoes). Additive only; a pre-migration snapshot is taken as for every schema step. |

Every migration is:
- **ordered:** it runs from `schema + 1` up to `D.SCHEMA`
- **idempotent:** re-running it is a no-op
- **additive:** `ensure()` creates tables. A value of the wrong type is moved to `_legacy`, never dropped.

Every step is logged to `JourneykeeperDB.migrations` and to both backup logs.

## Snapshots

A snapshot contains:
- the serialized `JourneykeeperDB`, plus the current character's `JourneykeeperCharDB`
- an Adler-32 checksum
- counts (entries, diary, deaths, arcs, players, places)
- addon version, schema, interface and reason

Snapshots are serialized but **not compressed**.

When snapshots are taken:
- `PLAYER_LOGOUT`, which also covers `/reload`. An unchanged DB only refreshes the timestamp.
- before a migration (pinned)
- before a restore
- before an import
- manually ("Back up now", `/jkp backup`)

**Verify** recomputes the checksum, parses the data with the strict parser and compares the entry count.

**Restore** verifies first, snapshots the current data, replaces the tables, then asks you to reload.

## Patch resilience

- Every event handler runs in its own `pcall`. Errors are logged to `JourneykeeperDB.health.errors` (capped at 50).
- A handler that fails 5 times is paused for the session. Only that module/event stops; everything else keeps working.
- An interface version change (from `GetBuildInfo`) is logged at load.
- `C.API("C_X.Func", ...)` checks the function exists and calls it in `pcall`. Failures are listed on the Data page.
- `C.Emit` builds the complete record, assigns its uid, and only then inserts it, so a half-built entry is never stored.

## Stable IDs

`uid = "C" .. adler32(key) .. "-" .. hex(t) .. "-" .. hex(djb(key))`, where `key = char|t|id|text`.

Because the id is derived from the content, the same memory gets the same id on every client and in every export, which makes deduplication reliable.

## Export / import

**Export format:** `!JOURNEYKEEPER1!<adler32>!<base64(serialize({format, v, schema, addon, t, char, db}))>`

**Import steps:**
1. Check the header and checksum.
2. Parse with the strict parser.
3. Reject exports from a newer schema.
4. Migrate the payload on a copy, then validate it.
5. Take a pre-import snapshot.
6. Merge:
   - entries are deduplicated by uid and appended, so existing indices never change
   - keyed tables only gain keys they don't have
   - the death, diary and arc lists are deduplicated, with entry references remapped
7. Nothing is ever overwritten. Import is disabled in read-only mode.

The parser (`Serialize.lua`) accepts only the serializer's data grammar. It **never** uses `loadstring`, so a pasted string cannot run code.

## Extra copies on disk (optional)

The in-game snapshots and the vault cover most accidents. For an extra safety net, close WoW and copy every `Journeykeeper*.lua` (plus WoW's `.bak` files) from `...\WTF\Account\<acct>\SavedVariables\` (and the per-character `SavedVariables` folders) to a folder of your own. To roll back, close WoW and copy them back.

## Integrity checks in-game

- **Data & Backups page:** shows the load state, schema, counts, every snapshot with its checksum status, the migration log, quarantined items and API failures.
- **Verify** any snapshot before restoring; a damaged or tampered snapshot fails verify and cannot be restored.
- **Read-only mode** is shown clearly whenever the data is malformed, from a newer version, or a migration failed. Nothing is written in that mode.
- `/jkp backup` takes a manual snapshot at any time.

## Developer checklist (every release)

- [ ] Data shape changed? Bump `D.SCHEMA` and add `D.MIGRATIONS[n]`: additive, idempotent, `ensure()` only, never `nil` a user field.
- [ ] Renaming a field? Copy it to the new name, keep the old one (or `_legacy`), and remove the old one only in a later release after a verify step.
- [ ] Test the migration against saved data from the *previous* release.
- [ ] Never reorder or remove items in `entries` (indices are referenced). Append only; quarantine with tombstones.
- [ ] New `JourneykeeperDB` tables go into `Validate` (`MAPS`/`LISTS`) and into the import merge if they hold user data.
- [ ] New Blizzard API calls go through `C.API` or a guarded `pcall` with feature detection. No secret values.
- [ ] New event handlers build the full record before writing.
- [ ] Run the offline tests (all must pass) and the syntax check.
- [ ] Bump the TOC `## Version`. Keep `## Interface` current.
- [ ] Ship Journeykeeper_Vault alongside Journeykeeper.
