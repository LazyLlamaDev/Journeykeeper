-- Data safety layer: schema versioning + migrations, load guards, validation/quarantine, redundant backups,
-- export/import, module health. Rules: never delete user data, never overwrite on doubt, read-only when unsure.
local _, C = ...
local D = {}; C.Data = D
local Codec = C.Codec
D.SCHEMA = 8                 -- bump with every data-shape change, add a migration below
D.RING = 2                   -- ring snapshots per backup file (+ one "latest" slot + pinned pre-migration)
D.state, D.writable, D.warnings = "init", false, {}

local function now() return time() end
local function addonVersion()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or function() end, "Journeykeeper", "Version")
  return ok and v or "?"
end
local function interface() local ok, _, _, _, toc = pcall(GetBuildInfo); return ok and toc or 0 end
local function warn(msg) tinsert(D.warnings, msg); C.Print("|cffff6040" .. msg .. "|r") end

---------------------------------------------------------------- safe API wrappers
D.apiFail = {}
-- C.API("C_Calendar.GetNumDayEvents", 0, 15): feature detection + pcall; nil on any failure
function C.API(path, ...)
  local f = _G
  for part in path:gmatch("[^%.]+") do f = type(f) == "table" and f[part] or nil end
  if type(f) ~= "function" then D.apiFail[path] = "missing"; return nil end
  local res = { pcall(f, ...) }
  if not res[1] then D.apiFail[path] = tostring(res[2]); return nil end
  return select(2, unpack(res))
end
function C.Has(path)
  local f = _G
  for part in path:gmatch("[^%.]+") do f = type(f) == "table" and f[part] or nil end
  return f ~= nil
end

---------------------------------------------------------------- stable ids
local function djb(s) local h = 5381; for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967291 end; return h end
-- Content-derived, so the same memory gets the same id on every client/import (dedupe), e.g. C1a2b3c4d-66f0a1b2-9f3e21
function D.UID(e)
  local key = tostring(e.char) .. "|" .. tostring(e.t) .. "|" .. tostring(e.id) .. "|" .. tostring(e.text)
  return format("C%s-%08x-%06x", Codec.Checksum(key), (tonumber(e.t) or 0) % 4294967296, djb(key) % 16777216)
end

---------------------------------------------------------------- migrations (ordered, idempotent, additive)
local function ensure(t, k, v) if type(t[k]) ~= "table" then if t[k] ~= nil then t._legacy = t._legacy or {}; t._legacy[k] = t[k] end; t[k] = v or {} end end
D.MIGRATIONS = {
  [2] = { name = "v0.2 echo state", run = function(db) ensure(db, "echoSeen"); ensure(db, "muted"); ensure(db, "tplRecent") end },
  [3] = { name = "v0.3 diary/arcs/warband", run = function(db)
    ensure(db, "settings")
    local s = db.settings
    if s.intensity == "quiet" or s.intensity == "normal" then -- rename = copy, keep old value
      s._legacy = s._legacy or {}; s._legacy.intensity = s._legacy.intensity or s.intensity
      s.intensity = s.intensity == "quiet" and "soft" or "present"
    end
    for _, k in ipairs({ "diary", "arcs", "family", "trail", "chars" }) do ensure(db, k) end
  end },
  [4] = { name = "v0.4 records/sharing", run = function(db)
    ensure(db, "records"); ensure(db, "share")
    for _, k in ipairs({ "trusted", "blocked", "peers", "inbox" }) do ensure(db.share, k) end
  end },
  [5] = { name = "v0.4.1 peer directory", run = function(db)
    for _, p in pairs(db.share and db.share.peers or {}) do if type(p) == "table" and p.shared == nil then p.shared = 0 end end
  end },
  [6] = { name = "v0.5 stable ids + safety tables", run = function(db)
    ensure(db, "quarantine"); ensure(db, "health"); ensure(db, "migrations")
    for _, e in ipairs(db.entries or {}) do if type(e) == "table" and not e.uid then e.uid = D.UID(e) end end
  end },
  [7] = { name = "v0.6 photos, death reports, quest tales", run = function(db)
    ensure(db, "photos"); ensure(db, "deathReports"); ensure(db, "quests")
  end },
  [8] = { name = "v0.7.1 fellowship + presets", run = function(db)
    ensure(db, "fellowship"); ensure(db.fellowship, "people"); ensure(db.fellowship, "archive")
    -- presets: an existing journal keeps every setting; it is only labelled "custom" (picker offered once)
    if type(db.settings) == "table" and db.settings.preset == nil then db.settings.preset = "custom"; db.settings.presetOffer = true end
  end },
}
function D.DetectSchema(db)
  if type(db.schema) == "number" then return db.schema end
  if type(db.share) == "table" then
    for _, p in pairs(db.share.peers or {}) do if type(p) == "table" and p.src then return 5 end end
    return 4
  end
  if db.records then return 4 end
  if db.diary or db.arcs or db.trail then return 3 end
  if db.echoSeen then return 2 end
  return 1
end
local function backupLog(rec)
  for _, b in ipairs({ JourneykeeperBackupDB, JourneykeeperVaultDB }) do
    if type(b) == "table" then b.log = b.log or {}; tinsert(b.log, rec); while #b.log > 50 do tremove(b.log, 1) end end
  end
end
-- returns migrated copy or nil, err. The original table is never touched.
function D.Migrate(db, target)
  target = target or D.SCHEMA
  local from = D.DetectSchema(db)
  if from >= target then return db, nil, from end
  local work = Codec.DeepCopy(db)
  local log = {}
  for v = from + 1, target do
    local m = D.MIGRATIONS[v]
    local ok, err = pcall(m.run, work)
    local rec = { from = v - 1, to = v, name = m.name, t = now(), ok = ok, err = not ok and tostring(err) or nil, addon = addonVersion() }
    tinsert(log, rec); backupLog(rec)
    if not ok then return nil, format("migration %d (%s) failed: %s", v, m.name, tostring(err)), from end
    work.schema = v
  end
  work.migrations = type(work.migrations) == "table" and work.migrations or {}
  for _, r in ipairs(log) do tinsert(work.migrations, r) end
  return work, nil, from
end

---------------------------------------------------------------- validation / quarantine (never delete)
local function quarantine(db, where, value, why)
  db.quarantine = type(db.quarantine) == "table" and db.quarantine or {}
  tinsert(db.quarantine, { t = now(), where = where, why = why, value = value, addon = addonVersion() })
  return #db.quarantine
end
local LISTS = { entries = true, deathSpots = true, diary = true, arcs = true, photos = true, deathReports = true, quests = true }
local MAPS = { "settings", "firstZone", "firstSub", "deathCount", "players", "firstLevel", "firstDungeon", "stats", "echoSeen", "family", "trail", "idCount", "tplRecent", "muted", "chars", "records", "share", "fellowship" }
function D.Validate(db)
  local fixed, q = 0, 0
  for _, k in ipairs(MAPS) do
    if db[k] ~= nil and type(db[k]) ~= "table" then quarantine(db, k, db[k], "not a table"); db[k] = {}; q = q + 1 end
  end
  for k in pairs(LISTS) do
    if db[k] ~= nil and type(db[k]) ~= "table" then quarantine(db, k, db[k], "not a table"); db[k] = {}; q = q + 1 end
  end
  -- entries: bad ones are replaced in place by a readable tombstone so indices (arcs, diary, pins) never shift
  for i, e in ipairs(db.entries or {}) do
    local bad
    if type(e) ~= "table" then bad = "not a table"
    elseif type(e.id) ~= "string" then bad = "missing id"
    else
      if type(e.t) ~= "number" then local n = tonumber(e.t); if n then e.t = n; fixed = fixed + 1 else bad = "missing time" end end
      if not bad and type(e.char) ~= "string" then e.char = "?"; fixed = fixed + 1 end
      if not bad and e.text ~= nil and type(e.text) ~= "string" then e.text = tostring(e.text); fixed = fixed + 1 end
      if not bad and (type(e.cat) ~= "string" or not C.CATS[e.cat]) then e._cat = e._cat or e.cat; e.cat = (C.EV[e.id] and C.EV[e.id].cat) or "fun"; fixed = fixed + 1 end
    end
    if bad then
      local qi = quarantine(db, "entries[" .. i .. "]", e, bad); q = q + 1
      db.entries[i] = { id = "_quarantined", cat = "fun", t = type(e) == "table" and tonumber(e.t) or 0, text = "(a damaged memory was set aside - see Data & Backups)", quarantined = qi, char = (type(e) == "table" and type(e.char) == "string" and e.char) or "?", uid = "Q" .. qi }
    end
  end
  for _, k in ipairs({ "deathSpots", "diary", "photos", "deathReports", "quests" }) do
    local list = db[k]
    if list then
      local keep = {}
      for i, v in ipairs(list) do
        if type(v) == "table" and type(tonumber(v.t)) == "number" then keep[#keep + 1] = v
        else quarantine(db, k .. "[" .. i .. "]", v, "malformed"); q = q + 1 end
      end
      if #keep ~= #list then db[k] = keep end
    end
  end
  for i, a in ipairs(db.arcs or {}) do
    if type(a) ~= "table" or type(a.entries) ~= "table" then quarantine(db, "arcs[" .. i .. "]", a, "malformed"); db.arcs[i] = { name = "(damaged arc)", entries = {}, t = 0 }; q = q + 1 end
  end
  return fixed, q
end

---------------------------------------------------------------- backups
local function counts(db)
  local function n(t) return type(t) == "table" and #t or 0 end
  local function m(t) local c = 0; if type(t) == "table" then for _ in pairs(t) do c = c + 1 end end; return c end
  return { entries = n(db.entries), diary = n(db.diary), deaths = n(db.deathSpots), arcs = n(db.arcs), players = m(db.players), places = m(db.firstSub) }
end
D.Counts = counts
-- JourneykeeperBackupDB lives in Journeykeeper.lua; JourneykeeperVaultDB lives in the companion addon Journeykeeper_Vault, i.e. a
-- different SavedVariables FILE (WoW writes one file per addon), so one damaged file cannot take every copy with it.
function D.VaultActive()
  local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local ok, loaded = pcall(f or function() end, "Journeykeeper_Vault")
  return (ok and loaded) and true or false
end
local function files()
  JourneykeeperBackupDB = type(JourneykeeperBackupDB) == "table" and JourneykeeperBackupDB or { ring = {}, seq = 0 }
  JourneykeeperVaultDB = type(JourneykeeperVaultDB) == "table" and JourneykeeperVaultDB or { ring = {}, seq = 0 }
  for _, b in ipairs({ JourneykeeperBackupDB, JourneykeeperVaultDB }) do b.ring = type(b.ring) == "table" and b.ring or {} end
  return JourneykeeperBackupDB, JourneykeeperVaultDB
end
-- Volatile caches are left out of snapshots (rebuilt automatically after a restore): echo cooldowns, template
-- rotation, health log. Everything the player made (entries, diary, arcs, trail, players, records...) is kept.
D.EXCLUDE = { echoSeen = true, tplRecent = true, health = true }
D.ROTATE = 6 * 3600          -- a new ring snapshot at most every 6 h; logouts in between refresh one "latest" slot
D.BIG = 1536 * 1024          -- above 1.5 MB per snapshot keep 1 ring snapshot per file instead of D.RING
D.PIN_DAYS = 14              -- the main file drops its pre-migration copy after 14 days (the vault keeps its own)
local function compact(db)
  local t = {}
  for k, v in pairs(db) do if not D.EXCLUDE[k] then t[k] = v end end
  return t
end
function D.Signature(db)
  local c = counts(db)
  local last = type(db.entries) == "table" and db.entries[#db.entries]
  local pts, grp = 0, 0
  for _, l in pairs(type(db.trail) == "table" and db.trail or {}) do pts = pts + (type(l) == "table" and #l or 0) end
  for _, p in pairs(type(db.players) == "table" and db.players or {}) do if type(p) == "table" then grp = grp + (p.count or 0) + (p.notes and #p.notes or 0) + (p.rating and 1 or 0) end end
  return format("%d/%d/%d/%d/%d/%d/%s/%d/%d/%s", c.entries, c.diary, c.deaths, c.arcs, c.players, c.places, tostring(last and last.t), pts, grp,
    Codec.Checksum(Codec.Serialize(type(db.settings) == "table" and db.settings or {}) .. Codec.Serialize(db.arcs or {}) .. Codec.Serialize(db.records or {})))
end
function D.MakeSnapshot(db, cdb, reason)
  local data = Codec.Serialize(compact(db))
  local cdata = cdb and Codec.Serialize(cdb) or ""
  return { t = now(), reason = reason, addon = addonVersion(), schema = D.DetectSchema(db), char = C.charKey(),
    counts = counts(db), size = #data + #cdata, sum = Codec.Checksum(data .. "\0" .. cdata), data = data, cdata = cdata, interface = interface() }
end
-- reason: logout | manual | pre-migration | pre-restore | pre-import
function D.Snapshot(reason, db, cdb)
  db, cdb = db or JourneykeeperDB, cdb or JourneykeeperCharDB
  if type(db) ~= "table" then return nil, "nothing to back up" end
  if reason ~= "pre-migration" and not D.writable then return nil, "read-only mode: backups frozen" end
  if reason == "logout" and counts(db).entries == 0 and D.LatestCount() > 0 then return nil, "refusing to rotate an empty DB over real backups" end
  local b1, b2 = files()
  local vault = D.VaultActive()
  local sig = D.Signature(db)
  if reason == "logout" and sig == b1.lastSig and D.List()[1] then
    D.lastSkipped = true; return D.List()[1].snap -- nothing changed since the last snapshot: no serialization at all
  end
  D.lastSkipped = false
  local t0 = debugprofilestop and debugprofilestop()
  local snap = D.MakeSnapshot(db, cdb, reason)
  if t0 then D.lastSnapMs = debugprofilestop() - t0 end
  b1.seq = math.max(b1.seq or 0, b2.seq or 0) + 1; b2.seq = b1.seq
  if reason == "pre-migration" then
    b1.pinned = snap; b2.pinned = Codec.DeepCopy(snap) -- both files carry the migration restore point
    return snap
  end
  b1.lastSig = sig
  if b1.pinned and b1.pinned.t and now() - b1.pinned.t > D.PIN_DAYS * 86400 and b2.pinned then b1.pinned = nil end
  local newest = 0
  for _, b in ipairs({ b1, b2 }) do for _, x in ipairs(b.ring) do if type(x) == "table" then newest = math.max(newest, x.t or 0) end end end
  if reason == "logout" and newest > 0 and now() - newest < D.ROTATE then
    -- inside the rotation window: refresh the single "latest" slot (vault file when available)
    if vault then b2.latest = snap; b1.latest = nil else b1.latest = snap end
    return snap
  end
  local depth = snap.size > D.BIG and 1 or D.RING
  if not vault then depth = depth * 2 end
  local target = (not vault or b1.seq % 2 == 1) and b1 or b2
  tinsert(target.ring, snap)
  while #target.ring > depth do tremove(target.ring, 1) end
  -- the vault always holds the newest snapshot, so the main file is never the only copy
  if vault and target == b1 then b2.latest = snap else b2.latest = nil end
  b1.latest = nil
  return snap
end
function D.List()
  local out = {}
  local b1, b2 = files()
  for fi, b in ipairs({ b1, b2 }) do
    for i, s in ipairs(b.ring) do if type(s) == "table" then out[#out + 1] = { snap = s, file = fi, slot = i } end end
    if type(b.pinned) == "table" then out[#out + 1] = { snap = b.pinned, file = fi, slot = "pinned" } end
    if type(b.latest) == "table" then out[#out + 1] = { snap = b.latest, file = fi, slot = "latest" } end
  end
  local seen, uniq = {}, {}
  for _, it in ipairs(out) do local k = tostring(it.snap.t) .. tostring(it.snap.sum); if not seen[k] then seen[k] = true; uniq[#uniq + 1] = it end end
  out = uniq
  table.sort(out, function(a, b) return (a.snap.t or 0) > (b.snap.t or 0) end)
  return out
end
function D.LatestCount() local l = D.List(); return l[1] and l[1].snap.counts and l[1].snap.counts.entries or 0 end
function D.Verify(snap)
  if type(snap) ~= "table" or type(snap.data) ~= "string" then return false, "malformed snapshot" end
  if Codec.Checksum(snap.data .. "\0" .. (snap.cdata or "")) ~= snap.sum then return false, "checksum mismatch" end
  local db, err = Codec.Deserialize(snap.data)
  if type(db) ~= "table" then return false, "unreadable: " .. tostring(err) end
  local c = counts(db)
  if snap.counts and c.entries ~= snap.counts.entries then return false, "entry count mismatch" end
  snap.verified = now()
  return true, format("ok: %d entries, %d diary, %d deaths", c.entries, c.diary, c.deaths), db
end
function D.Restore(snap)
  local ok, msg, db = D.Verify(snap)
  if not ok then return false, msg end
  if D.writable and type(JourneykeeperDB) == "table" and counts(JourneykeeperDB).entries > 0 then D.Snapshot("pre-restore") end
  JourneykeeperDB = db
  if snap.char == C.charKey() and snap.cdata and snap.cdata ~= "" then
    local cdb = Codec.Deserialize(snap.cdata); if type(cdb) == "table" then JourneykeeperCharDB = cdb end
  end
  JourneykeeperDB.restoredFrom = { t = now(), snapT = snap.t, reason = snap.reason }
  D.state, D.writable = "restored", false -- live tables are detached until reload
  backupLog({ t = now(), restore = snap.t, ok = true, addon = addonVersion() })
  if StaticPopup_Show then StaticPopup_Show("JOURNEYKEEPER_RELOAD") end
  return true, "restored; reload the UI to continue"
end

---------------------------------------------------------------- load
local function readonlyCopy(db, cdb, why)
  D.state, D.writable, D.reason = "readonly", false, why
  return C.InitDB(type(db) == "table" and Codec.DeepCopy(db) or {}, type(cdb) == "table" and Codec.DeepCopy(cdb) or {})
end
function D.Load()
  files()
  local db, cdb = JourneykeeperDB, JourneykeeperCharDB
  D.warnings = {}
  if db ~= nil and type(db) ~= "table" then
    warn("Journeykeeper: saved data is unreadable (" .. type(db) .. "). It was NOT overwritten. Read-only mode; restore a backup in Settings > Data & Backups.")
    return readonlyCopy(nil, cdb, "malformed SavedVariables")
  end
  if cdb ~= nil and type(cdb) ~= "table" then JourneykeeperCharDB = nil; cdb = nil end -- per-character cache: rebuilt; the account DB holds the chronicle
  if db == nil then
    if D.LatestCount() > 0 then
      D.state, D.writable, D.reason = "empty_with_backup", false, "data missing but backups exist"
      warn("Journeykeeper: your saved journal is missing but backups exist. Nothing was overwritten. Open Settings > Data & Backups to restore (or start fresh).")
      if StaticPopup_Show then StaticPopup_Show("JOURNEYKEEPER_RESTORE_OFFER") end
      return C.InitDB({}, cdb)
    end
    db = { schema = D.SCHEMA } -- genuine first run
    JourneykeeperDB = db
  end
  local schema = D.DetectSchema(db)
  if schema > D.SCHEMA then
    warn(format("Journeykeeper: data was saved by a newer version (schema %d > %d). Read-only mode so nothing is lost; update the addon.", schema, D.SCHEMA))
    return readonlyCopy(db, cdb, "newer schema")
  end
  if schema < D.SCHEMA then
    if counts(db).entries > 0 or next(db) then D.Snapshot("pre-migration", db, cdb) end
    local migrated, err = D.Migrate(db)
    if not migrated then
      warn("Journeykeeper: " .. err .. ". Your data is untouched (pre-migration backup kept). Read-only mode until fixed.")
      return readonlyCopy(db, cdb, err)
    end
    db = migrated; JourneykeeperDB = db
  end
  db.schema = D.SCHEMA
  local fixed, q = D.Validate(db)
  if q > 0 then warn(format("Journeykeeper: %d damaged item(s) were moved to quarantine (not deleted).", q)) end
  D.fixed, D.quarantined = fixed, q
  D.state, D.writable = "ok", true
  JourneykeeperCharDB = cdb or {}
  local live = C.InitDB(db, JourneykeeperCharDB)
  D.HealthStart(live)
  D.LegacyImport(live)
  return live
end

-- One-time, additive import of pre-rename test data ("Chronicle" builds). The old addon's SavedVariables are
-- only present when that addon is still installed + enabled (OptionalDeps makes it load first). The old table is
-- read, never modified; a pre-import snapshot is taken; entries are merged by stable uid (no duplicates).
function D.LegacyImport(live)
  local old = rawget(_G, "ChronicleDB")
  if type(old) ~= "table" or live.legacyImported or not D.writable then return false end
  -- another, unrelated addon (e.g. one whose folder is also called "Chronicle") may use the same global name:
  -- only accept data with this addon's own fingerprint
  local e1 = type(old.entries) == "table" and old.entries[1]
  if not (type(old.entries) == "table" and type(old.firstZone) == "table" and type(old.deathSpots) == "table"
    and (e1 == nil or (type(e1) == "table" and type(e1.id) == "string" and type(e1.cat) == "string" and e1.t))) then return false end
  local ok, res, err = pcall(function() return D.Import(D.Export(Codec.DeepCopy(old)), live) end)
  if ok and res then
    live.legacyImported = { t = now(), added = type(res) == "number" and res or nil }
    C.Print("imported your earlier Chronicle test data (one time, nothing was removed). You can now disable the old 'Chronicle' addon.")
    return true
  end
  warn("Journeykeeper: could not import the old Chronicle data (" .. tostring(ok and err or res) .. "). It is untouched; you can retry with /jkp import.")
  return false
end
function D.StartFresh()
  if D.state ~= "empty_with_backup" then return end
  JourneykeeperDB = { schema = D.SCHEMA }
  D.state, D.writable = "ok", true
  C.InitDB(JourneykeeperDB, JourneykeeperCharDB or {})
end

---------------------------------------------------------------- health: patch resilience
function D.HealthStart(db)
  db.health = type(db.health) == "table" and db.health or {}
  local h = db.health
  h.errors = type(h.errors) == "table" and h.errors or {}
  local itf = interface()
  if h.interface and h.interface ~= itf then
    tinsert(h.errors, { t = now(), msg = format("interface changed %s -> %s", tostring(h.interface), tostring(itf)) })
  end
  h.interface = itf; h.addon = addonVersion()
end
D.disabled = {}
function D.HandlerError(h, ev, err)
  local hl = C.db and C.db.health
  if hl and hl.errors then
    tinsert(hl.errors, { t = now(), mod = h.mod, ev = ev, msg = tostring(err):sub(1, 200), interface = interface() })
    while #hl.errors > 50 do tremove(hl.errors, 1) end
  end
  if h.errors >= 5 then
    h.off = true; D.disabled[h.mod .. "/" .. ev] = tostring(err):sub(1, 200)
    C.Print(format("|cffff6040%s stopped handling %s after repeated errors (other features keep working).|r", h.mod, ev))
  end
end

---------------------------------------------------------------- export / import
local HEADER = "!JKPR1!"
function D.Export(db)
  db = db or C.db
  local payload = { format = "journeykeeper", v = 1, schema = D.DetectSchema(db), addon = addonVersion(), t = now(), char = C.charKey(), db = db }
  local body = Codec.Serialize(payload)
  return HEADER .. Codec.Checksum(body) .. "!" .. Codec.B64Encode(body)
end
function D.Decode(str)
  if type(str) ~= "string" then return nil, "empty" end
  str = str:gsub("%s", "")
  local sum, b64 = str:match("^" .. HEADER:gsub("!", "%%!") .. "(%x+)!(.+)$")
  if not sum then sum, b64 = str:match("^!CHRONICLE1!(%x+)!(.+)$") end -- exports from the pre-rename test builds
  if not sum then return nil, "not a Journeykeeper export string" end
  local body, err = Codec.B64Decode(b64)
  if not body then return nil, "corrupt: " .. err end
  if Codec.Checksum(body) ~= sum then return nil, "checksum mismatch (string damaged or truncated)" end
  local p, perr = Codec.Deserialize(body)
  if type(p) ~= "table" or type(p.db) ~= "table" then return nil, "unreadable: " .. tostring(perr) end
  return p
end
function D.Import(str, into)
  into = into or C.db
  if not D.writable then return nil, "read-only mode" end
  local p, err = D.Decode(str)
  if not p then return nil, err end
  if (p.schema or 0) > D.SCHEMA then return nil, "export is from a newer Journeykeeper (schema " .. p.schema .. "); update first" end
  local src, merr = D.Migrate(p.db)
  if not src then return nil, merr end
  D.Validate(src)
  D.Snapshot("pre-import")
  local have, map, added = {}, {}, 0
  for i, e in ipairs(into.entries) do e.uid = e.uid or D.UID(e); have[e.uid] = i end
  for i, e in ipairs(src.entries or {}) do
    if e.id ~= "_quarantined" then
      e.uid = e.uid or D.UID(e)
      if have[e.uid] then map[i] = have[e.uid]
      else tinsert(into.entries, e); have[e.uid] = #into.entries; map[i] = #into.entries; added = added + 1 end
    end
  end
  local function addMissing(k) if type(src[k]) == "table" then into[k] = into[k] or {}; for kk, v in pairs(src[k]) do if into[k][kk] == nil then into[k][kk] = v end end end end
  for _, k in ipairs({ "firstZone", "firstSub", "players", "firstLevel", "firstDungeon", "chars", "trail", "records", "family" }) do addMissing(k) end
  local function dedupeList(k, keyf, remap)
    into[k] = into[k] or {}
    local seen = {}
    for _, v in ipairs(into[k]) do seen[keyf(v)] = true end
    for _, v in ipairs(src[k] or {}) do if not seen[keyf(v)] then if remap then remap(v) end; tinsert(into[k], v); seen[keyf(v)] = true end end
  end
  dedupeList("deathSpots", function(v) return tostring(v.t) .. tostring(v.char) end, function(v) v.entry = v.entry and map[v.entry] end)
  local function byUid(v) return tostring(v.uid or (tostring(v.t) .. tostring(v.char))) end
  dedupeList("photos", byUid); dedupeList("deathReports", byUid); dedupeList("quests", byUid)
  dedupeList("diary", function(v) return tostring(v.t) .. tostring(v.text) end, function(v) v.entry = v.entry and map[v.entry] end)
  dedupeList("arcs", function(v) return tostring(v.name) .. tostring(v.t) end, function(v)
    local ne = {}; for _, idx in ipairs(v.entries or {}) do if map[idx] then ne[#ne + 1] = map[idx] end end; v.entries = ne end)
  backupLog({ t = now(), import = p.t, from = p.char, added = added, ok = true })
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
  return added
end

---------------------------------------------------------------- hooks
C.On("PLAYER_LOGOUT", function() if D.writable then D.Snapshot("logout") end end) -- also fires on /reload
if StaticPopupDialogs then
  StaticPopupDialogs.JOURNEYKEEPER_RELOAD = { text = "Journeykeeper data restored. Reload the UI now?", button1 = RELOADUI or "Reload", button2 = CANCEL or "Later", OnAccept = function() ReloadUI() end, timeout = 0, whileDead = true, hideOnEscape = true }
  StaticPopupDialogs.JOURNEYKEEPER_RESTORE_OFFER = { text = "Journeykeeper: your saved journal is missing, but a backup exists.\nRestore the newest backup?", button1 = "Restore", button2 = "Start fresh",
    OnAccept = function() local l = D.List(); if l[1] then D.Restore(l[1].snap) end end, OnCancel = function() D.StartFresh() end, timeout = 0, whileDead = true }
end
