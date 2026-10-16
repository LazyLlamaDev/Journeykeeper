-- Journeykeeper Core: namespace, DB, helpers. Never touches secret values.
local ADDON, C = ...
Journeykeeper = C
C.name = ADDON

local M = "Interface\\AddOns\\Journeykeeper\\media\\"
C.MEDIA = M
local function cat(label, r, g, b) return { label = label, color = { r, g, b } } end
C.CATS = {
  zone = cat("Exploration", 0.35, 0.75, 1.0), death = cat("Deaths", 0.86, 0.2, 0.2), dungeon = cat("Dungeons", 1.0, 0.5, 0.15),
  quest = cat("Quests", 1.0, 0.82, 0.0), loot = cat("Treasures", 0.64, 0.21, 0.93), collect = cat("Collections", 0.2, 0.8, 0.75),
  prof = cat("Professions", 0.6, 0.45, 0.25), gold = cat("Wealth", 1.0, 0.85, 0.3), group = cat("Allies", 0.3, 0.9, 0.4),
  travel = cat("Travel", 0.55, 0.65, 0.95), level = cat("Progression", 0.75, 0.45, 1.0), achieve = cat("Achievements", 0.95, 0.75, 0.2),
  pvp = cat("PvP", 0.9, 0.3, 0.3), holiday = cat("Holidays", 1.0, 0.45, 0.7), fun = cat("Oddities", 0.5, 0.9, 0.9),
  warband = cat("Warband", 0.47, 0.78, 1.0), thread = cat("Threads", 0.9, 0.67, 0.47),
  fight = cat("Fights", 0.95, 0.55, 0.25),
}
for k, v in pairs(C.CATS) do v.icon = M .. "icon_" .. k end
C.CATS.fight.icon = M .. "icon_achieve"
C.CAT_ORDER = {}
for _, c in ipairs(C.EVENT_CATS) do tinsert(C.CAT_ORDER, c.key) end
C.CHANNELS = { "toast", "chat", "echoes", "tooltip", "journal", "off" }

local defaults = { catBoost = {}, ev = {}, channel = {}, intensity = "present", sound = true, toastStyle = "parchment", quietInstances = true, mapPins = false, collapsed = {} }
for _, e in ipairs(C.EVENTS) do defaults.ev[e.id] = e.on; defaults.channel[e.id] = e.channel end
C.defaults = defaults

-- Return v unless it is a secret value (Midnight-era API); nil otherwise.
function C.S(v)
  if issecretvalue and v ~= nil and issecretvalue(v) then return nil end
  return v
end

local function normRealm(r) return ((r or "?"):gsub("[%s%-']", "")) end
function C.charKey()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if not realm or realm == "" then realm = normRealm(GetRealmName and GetRealmName()) end
  return (UnitName("player") or "?") .. "-" .. realm
end
-- "Rokk-Forever Beta" and "Rokk-ForeverBeta" are the same character
function C.NormKey(ck)
  if type(ck) ~= "string" then return ck end
  local n, r = ck:match("^(.-)%-(.*)$")
  if not n then return ck end
  return n .. "-" .. normRealm(r)
end

function C.charDesc()
  local cls = UnitClass("player")
  return format("level %d %s %s", UnitLevel("player"), UnitRace("player") or "", cls or "")
end

function C.pos()
  local map = C.S(C_Map.GetBestMapForUnit("player"))
  if not map then return nil end
  local p = C_Map.GetPlayerMapPosition(map, "player")
  if not p then return map end
  local x, y = p:GetXY()
  x, y = C.S(x), C.S(y)
  if not x then return map end
  return map, floor(x * 1000) / 10, floor(y * 1000) / 10
end

function C.dateStr(t) return date("%d %b %Y", t) end

function C.UpdateCharInfo(level)
  local db, cdb = C.db, C.cdb
  local _, classFile = UnitClass("player")
  local ci = db.chars[C.charKey()] or {}
  ci.race = UnitRace("player"); ci.class = UnitClass("player"); ci.classFile = classFile
  ci.level = level or UnitLevel("player"); ci.created = cdb.created; ci.seen = time()
  db.chars[C.charKey()] = ci
end

-- Fight sanity. Durations in seconds; a single fight over 3 h is a broken reading.
C.MAX_FIGHT_SECONDS = 3 * 3600
function C.ValidRecord(key, v)
  if type(v) ~= "number" or v ~= v then return false end
  if key == "dur" then return v > 0 and v <= C.MAX_FIGHT_SECONDS end
  if key == "dps" or key == "dmg" or key == "hps" or key == "spell" then return v > 0 end
  return true
end
function C.FormatDuration(s)
  s = floor(tonumber(s) or 0)
  if s < 60 then return format("%d second%s", s, s == 1 and "" or "s") end
  local m, sec = floor(s / 60), s % 60
  if m < 60 then return sec > 0 and format("%d min %d s", m, sec) or format("%d min", m) end
  return format("%d h %d min", floor(m / 60), m % 60)
end
-- Display filter for old broken combat lines (kept in the data, just not shown)
function C.BadCombatText(e)
  if type(e) ~= "table" or type(e.id) ~= "string" or not e.id:find("^combat_") then return false end
  local txt = e.text or ""
  if txt:find(": 0 damage per second") or txt:find(" 0 damage in a single fight") or txt:find("healed 0 per second") then return true end
  local mins = tonumber(txt:match("longest fight: (%d+) minutes"))
  if mins and mins * 60 > C.MAX_FIGHT_SECONDS then return true end
  if type(e.value) == "number" and e.id == "combat_longest_fight" and e.value > C.MAX_FIGHT_SECONDS then return true end
  if type(e.value) == "number" and e.value <= 0 then return true end
  return false
end

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then dst[k] = dst[k] or {}; merge(dst[k], v)
    elseif dst[k] == nil then dst[k] = v end
  end
end

-- Additive defaults only: never removes or overwrites existing values. Called by Data.Load with the
-- table chosen by the safety layer (the live SavedVariables, or a read-only copy).
function C.InitDB(db, cdb)
  db = db or {}
  db.settings = db.settings or {}
  merge(db.settings, defaults)
  db.entries = db.entries or {}
  db.firstZone = db.firstZone or {}   -- [zone] = {char, desc, t}
  db.firstSub = db.firstSub or {}     -- [zone|sub] = {char, desc, t}
  db.deathCount = db.deathCount or {} -- [zone|sub] = n
  db.deathSpots = db.deathSpots or {} -- list {map,x,y,t,char,level,zone,sub,killer}
  db.players = db.players or {}       -- [guid] = {name, class, count, first, last, lastWhere, lastChar, notes, secs}
  db.firstLevel = db.firstLevel or {} -- [level] = {char, t}
  db.firstDungeon = db.firstDungeon or {}
  db.stats = db.stats or {}
  db.echoSeen = db.echoSeen or {}; db.diary = db.diary or {}; db.arcs = db.arcs or {}; db.family = db.family or {}; db.trail = db.trail or {}; db.idCount = db.idCount or {}; db.tplRecent = db.tplRecent or {}; db.muted = db.muted or {}; db.chars = db.chars or {}
  db.photos = db.photos or {}; db.deathReports = db.deathReports or {}; db.quests = db.quests or {}
  db.fellowship = db.fellowship or {}; db.fellowship.people = db.fellowship.people or {}; db.fellowship.archive = db.fellowship.archive or {}
  -- v0.6.7: one key per character (realm spacing / early-login "?" realm produced duplicate chapters with 0 stats)
  do
    local canon = {}
    for _, e in ipairs(db.entries) do if type(e) == "table" and type(e.char) == "string" then e.char = C.NormKey(e.char); canon[e.char] = true end end
    for _, d in ipairs(db.diary) do if type(d) == "table" and type(d.char) == "string" then d.char = C.NormKey(d.char) end end
    for _, s in ipairs(db.deathSpots) do if type(s) == "table" and type(s.char) == "string" then s.char = C.NormKey(s.char) end end
    local function target(k)
      local nk = C.NormKey(k)
      local name, realm = nk:match("^(.-)%-(.*)$")
      if realm == "?" or realm == "" then -- unknown realm: attach to the one same-named character if unambiguous
        local hit
        for ck in pairs(canon) do if ck:match("^(.-)%-") == name then if hit then return nk end hit = ck end end
        return hit or nk
      end
      return nk
    end
    for k, ci in pairs(db.chars) do
      local nk = target(k)
      if nk ~= k and type(ci) == "table" then
        local into = db.chars[nk] or {}
        for f, v in pairs(ci) do
          if into[f] == nil then into[f] = v
          elseif f == "created" and type(v) == "number" and type(into[f]) == "number" then into[f] = math.min(into[f], v)
          elseif (f == "seen" or f == "level" or f == "played") and type(v) == "number" and type(into[f]) == "number" then into[f] = math.max(into[f], v) end
        end
        db.chars[nk] = into; db.chars[k] = nil
        db.charAliases = db.charAliases or {}; db.charAliases[k] = nk
      end
    end
    if type(db.records) == "table" then
      for k, r in pairs(db.records) do local nk = target(k); if nk ~= k and db.records[nk] == nil then db.records[nk] = r; db.records[k] = nil end end
    end
  end
  -- v0.6.2: combat records were filed under "death"; move them to their own category (cat label only)
  for _, e in ipairs(db.entries) do if type(e) == "table" and type(e.id) == "string" and e.id:find("^combat_") then e.cat = "fight" end end
  for _, d in ipairs(db.diary) do if type(d) == "table" and type(d.id) == "string" and d.id:find("^combat_") then d.cat = "fight" end end
  -- quarantine impossible fight records (0 DPS, durations > 3 h); kept aside, never deleted
  if type(db.records) == "table" then
    db.quarantine = db.quarantine or {}
    for ck, r in pairs(db.records) do
      if type(r) == "table" then
        for key, rec in pairs(r) do
          if type(rec) == "table" and not C.ValidRecord(key, rec.v) then
            tinsert(db.quarantine, { kind = "record", char = ck, key = key, rec = rec, t = time(), why = "invalid fight value" }); r[key] = nil
          end
        end
      end
    end
  end
  if db.settings.intensity == "quiet" then db.settings.intensity = "soft" elseif db.settings.intensity == "normal" then db.settings.intensity = "present" end
  cdb = cdb or {}
  cdb.zones = cdb.zones or {}; cdb.subs = cdb.subs or {}; cdb.gold = cdb.gold or {}
  cdb.dungeons = cdb.dungeons or {}; cdb.clears = cdb.clears or {}; cdb.flags = cdb.flags or {}; cdb.slots = cdb.slots or {}; cdb.created = cdb.created or time(); cdb.lastSeen = cdb.lastSeen or {}
  C.db, C.cdb, C.set = db, cdb, db.settings
  C.UpdateCharInfo()
  return db, cdb
end

-- Emit a registered event: log entry (if enabled) and optional echo {title=, key=, force=, text=}.
function C.Emit(id, text, extra, echo)
  local ev = C.EV[id]
  if not ev then if C.debug then C.Print("unknown event " .. id) end return end
  if not C.set.ev[id] then return end
  local map, x, y = C.pos()
  local e = extra or {}
  e.t = e.t or time(); e.id = id; e.cat = ev.cat; e.text = text; e.char = C.charKey(); e.level = UnitLevel("player")
  e.zone = e.zone or GetRealZoneText(); e.sub = e.sub or GetSubZoneText(); e.map, e.x, e.y = map, x, y
  local log = not e.noLog; e.noLog = nil
  if log and C.Data then e.uid = e.uid or C.Data.UID(e) end
  -- commit: the record is complete before it is stored
  C.db.idCount[id] = (C.db.idCount[id] or 0) + 1
  if log then tinsert(C.db.entries, e); C.lastEntry = #C.db.entries end
  if echo then
    local meta = echo.meta or {}
    if log then meta.entry = #C.db.entries end
    C.Echoes.Fire(id, echo.key, echo.text or text, echo.title, echo.force, meta)
  end
  if C.Share and C.Share.OnEmit then pcall(C.Share.OnEmit, id, e) end
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
  return e
end
-- Echo only (no journal entry), still gated by the event toggle.
function C.Echo(id, key, text, title, force, meta)
  if C.EV[id] and C.set.ev[id] then C.Echoes.Fire(id, key, text, title, force, meta) end
end

function C.Print(msg) print("|cffd8b26aJourneykeeper|r " .. msg) end

-- event dispatch shared by modules
local frame = CreateFrame("Frame")
local handlers = {}
local function callerModule()
  local st = (debugstack and debugstack(3, 1, 0)) or (debug and debug.traceback and debug.traceback("", 3)) or ""
  return st:match("([%w_]+)%.lua") or "?"
end
function C.On(ev, fn)
  if not handlers[ev] then handlers[ev] = {}; pcall(frame.RegisterEvent, frame, ev) end
  tinsert(handlers[ev], { fn = fn, mod = callerModule() })
end
-- each handler is isolated: an error is logged; a handler that keeps failing (e.g. after a WoW patch changed an API)
-- is disabled for the session instead of breaking the addon or writing half-built data.
frame:SetScript("OnEvent", function(_, ev, ...)
  for _, h in ipairs(handlers[ev]) do
    if not h.off then
      local ok, err = pcall(h.fn, ...)
      if not ok then
        h.errors = (h.errors or 0) + 1
        if C.Data then C.Data.HandlerError(h, ev, err) end
        if C.debug then C.Print("error in " .. h.mod .. "/" .. ev .. ": " .. tostring(err)) end
      end
    end
  end
end)
C.handlers = handlers
C.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  C.Data.Load()
  if C.OnInit then for _, fn in ipairs(C.OnInit) do fn() end end
end)
C.OnInit = {}
function C.Init(fn) tinsert(C.OnInit, fn) end

SLASH_JOURNEYKEEPER1 = "/jkp"; SLASH_JOURNEYKEEPER2 = "/journeykeeper"
SlashCmdList.JOURNEYKEEPER = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "show" then C.Journal.Toggle()
  elseif cmd == "config" or cmd == "settings" then C.OpenSettings()
  elseif cmd == "export" then C.Journal.Export()
  elseif cmd == "note" or cmd == "notes" then C.Notes.Command(rest)
  elseif cmd == "allynote" then C.AddNote(rest)
  elseif cmd == "fellowship" or cmd == "fellows" then C.Journal.OpenTab("Fellowship")
  elseif cmd == "preset" then if rest ~= "" and C.Presets.VALUES[rest:lower()] then C.Presets.Apply(rest:lower()) else C.Presets.ShowPicker(true) end
  elseif cmd == "test" then C.Toast.Test()
  elseif cmd == "toast" then
    if rest == "reset" then C.Toast.ResetPosition() elseif rest == "move" then C.Toast.ToggleMove() elseif C.Toast.SetPreset(rest) then C.Toast.Test() else C.Print("/jkp toast top | center | bottom | move | reset  (or Shift-drag any popup)") end
  elseif cmd == "pin" then C.Pin({ tonumber(rest) or C.lastEchoEntry or C.lastEntry })
  elseif cmd == "arc" then C.Threads.ArcCommand(rest)
  elseif cmd == "html" then C.Journal.ExportHTML()
  elseif cmd == "digest" then C.Threads.ShowDigest(C.cdb.lastLogout and C.Threads.DigestLines() or { "No previous session recorded yet." })
  elseif cmd == "diary" or cmd == "echoes" then
    local want
    if rest ~= "" then for k, v in pairs(C.CATS) do if k == rest:lower() or v.label:lower() == rest:lower() then want = k end end end
    C.Journal.SetEchoFilter(want); C.Journal.OpenTab("Echoes")
  elseif cmd == "unmute" then wipe(C.db.muted); C.Print("all memories unmuted")
  elseif cmd == "page" then C.Journal.Toggle()
  elseif cmd == "data" or cmd == "backup" or cmd == "verify" or cmd == "exportall" or cmd == "import" then C.DataPage.Command(cmd, rest)
  elseif cmd == "perf" then C.Perf.Report()
  elseif cmd == "records" then C.Print((C.Combat.RecordsText(C.charKey()) or "no fight records yet") .. "  [damage meter: " .. (C.Combat.status or (C.Combat.Available() and "available" or "unavailable")) .. "]")
  elseif cmd == "friend" then C.Share.Command(rest)
  elseif cmd == "photo" then
    if rest == "snap" or rest == "shoot" then if not C.Photo.Snap() then C.Print("not in photo mode - type /jkp photo first") end
    elseif rest == "exit" or rest == "off" then C.Photo.Exit()
    elseif C.Photo.Active() then C.Photo.Snap()
    else C.Photo.Take(tonumber(rest), (rest ~= "" and not tonumber(rest)) and rest or nil) end
  elseif cmd == "who" or cmd == "tag" or cmd == "rate" then C.Profiles.Command(cmd .. " " .. rest)
  elseif cmd == "played" then if C.WarbandTOC.RequestPlayed() then C.Print("asked the server for time played") end
  elseif cmd == "journey" then C.Journal.OpenTab("Journey")
  elseif cmd == "warband" then C.Journal.OpenTab("Warband")
  elseif cmd == "debug" then C.debug = not C.debug; C.Print("debug " .. tostring(C.debug))
  else C.Print("/jkp [show] | config | export | html | note <text>|list|edit #|restore | allynote <text> | fellowship | preset [essentials|storyteller|chronicler] | pin [#] | arc ... | echoes [category] | digest | photo [snap|exit] | who <name> | tag | rate | played | journey | warband | test | toast top|center|bottom|move|reset | unmute | debug") end
end

-- realm name is reliable only after login
C.On("PLAYER_LOGIN", function() if C.db then C.UpdateCharInfo() end end)
