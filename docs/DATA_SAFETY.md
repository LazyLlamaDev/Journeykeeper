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

WoW also keeps its own `Journeykeeper.lua.bak`. The Windows script copies that file as well.

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
   - The saved data stays byte-identical. This is tested.
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

## Disk backups (Windows)

`tools/windows/backup_savedvars.ps1` copies every `Journeykeeper*.lua` (plus WoW's `.bak` files) from `...\_classic_beta_\WTF\Account\**\SavedVariables\` to `Documents\Journeykeeper-backups\<yyyy-MM-dd_HHmmss>\` (change with `-Dest`). It keeps the folder layout, writes a SHA256 manifest, and keeps the newest 60 backups.

- **Run once:** `powershell -ExecutionPolicy Bypass -File tools\windows\backup_savedvars.ps1`
- **Optional schedule** (daily 04:00 and at logon): add `-InstallTask`. Remove it with `-RemoveTask`. Nothing is scheduled unless you run that yourself.

`tools/svcheck.py <file>` parses a SavedVariables file outside WoW and prints the schema, the counts, and every embedded snapshot with its checksum status.

## Tests (`tools/smoke6.py`, 72 checks)

- Fixtures v0.1, v0.2, v0.3, v0.4 and v0.4.1 (`tests/fixtures/`, generated by `tools/make_fixtures.py`) migrate to schema 6 with:
  - no entries lost and every text byte-intact
  - uids on all entries
  - a pinned pre-migration snapshot and a correct log
  - the legacy value kept on rename
  - arcs, trail and unknown future fields preserved
- Migrations are idempotent, and data survives a reload byte-identical.
- **Corruption:** tombstones keep indices stable, bad items are quarantined, repairable fields are repaired, and the journal still renders.
- **Malformed SavedVariables** are left untouched at logout.
- **Truncated `Journeykeeper.lua`** with only the vault file left: "missing, backups exist" is detected, nothing is written, backups are not rotated, restore works, and the next reload is normal.
- **Future schema 99:** read-only, and the data is byte-identical after a session.
- **Failing migration:** the original is untouched (the migration ran on a copy), the addon goes read-only, and both the snapshot and the log exist.
- **Rotation:** 3 snapshots per file, the vault holds the newest, and without the vault there are 6 in one file. Every snapshot verifies; a tampered one fails verify and restore; an empty DB never rotates.
- **Export/import:** the uid merge deduplicates 20 shared memories, re-importing adds 0, a damaged string is rejected, a fresh import contains everything, and there is no import in read-only mode.
- **Codec:** any bytes and numbers round-trip, the parser rejects code, and base64 handles every padding case.
- **Handlers:** the healthy handler keeps running, the failing one pauses after 5 errors, errors are logged, and the interface change is detected.

## Developer checklist (every release)

- [ ] Data shape changed? Bump `D.SCHEMA` and add `D.MIGRATIONS[n]`: additive, idempotent, `ensure()` only, never `nil` a user field.
- [ ] Renaming a field? Copy it to the new name, keep the old one (or `_legacy`), and remove the old one only in a later release after a verify step.
- [ ] Add a fixture for the *previous* release to `tools/make_fixtures.py` and extend the smoke6 loop.
- [ ] Never reorder or remove items in `entries` (indices are referenced). Append only; quarantine with tombstones.
- [ ] New `JourneykeeperDB` tables go into `Validate` (`MAPS`/`LISTS`) and into the import merge if they hold user data.
- [ ] New Blizzard API calls go through `C.API` or a guarded `pcall` with feature detection. No secret values.
- [ ] New event handlers build the full record before writing.
- [ ] Run `tools/smoke*.py` (all must pass) and the syntax check.
- [ ] Bump the TOC `## Version`. Keep `## Interface` current.
- [ ] Ship Journeykeeper_Vault alongside Journeykeeper.
