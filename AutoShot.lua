-- v0.7.2 auto screenshots: the game's own Screenshot() a moment after a big memory (first boss kill, first dungeon
-- completion, level milestone, reunion, optionally achievements). Throttled, never during photo mode, never when
-- another screenshot is pending. Screenshot() is not a protected function; we never hide the UI (only, optionally,
-- our own popup for the one frame). WoW names files WoWScrnShot_MMDDYY_HHMMSS.<ext>; the event carries no name, so
-- the expected name is derived from the capture time (+-1 s) and stored on the memory (entry.shot) and in db.shots.
local _, C = ...
local A = {}; C.AutoShot = A
local CAP = 300
local pending, lastShot = nil, 0
-- event id -> setting key; instance_complete only counts the FIRST completion of that instance by this character
A.EVENTS = { boss_first_kill = "autoShotBoss", instance_complete = "autoShotDungeon", family_first_clear = "autoShotDungeon",
  level_milestone = "autoShotLevel", fellow_reunion = "autoShotReunion", achievement = "autoShotAchieve" }

local function ext()
  local f = C.API("GetCVar", "screenshotFormat") or "jpeg"
  return f == "png" and "png" or (f == "tga" and "tga" or "jpg")
end
function A.ExpectedName(t) return format("WoWScrnShot_%s.%s", date("%m%d%y_%H%M%S", t), ext()) end

local function firstClear(e, idx)
  for i = (idx or #C.db.entries) - 1, 1, -1 do
    local o = C.db.entries[i]
    if o and o.id == "instance_complete" and o.instance == e.instance and o.char == e.char then return false end
  end
  return true
end

-- why a shot would be skipped (nil = take it); exposed for tests and /jkp shot status
function A.Skip(id, e, idx)
  local key = A.EVENTS[id]
  if not key then return "not a big moment" end
  if not C.set.autoShot then return "off" end
  if not C.set[key] then return "event off" end
  if id == "instance_complete" and not firstClear(e, idx) then return "not the first completion" end
  if pending then return "busy" end
  if C.Photo and C.Photo.Active and C.Photo.Active() then return "photo mode" end
  if not C.Has("Screenshot") then return "no API" end
  if time() - lastShot < (tonumber(C.set.autoShotGap) or 60) then return "throttled" end
  return nil
end

local toastHidden
local function showToast() if toastHidden then local f = _G.JourneykeeperToast; if f then f:SetAlpha(toastHidden) end; toastHidden = nil end end
local function finish(ok)
  local p = pending; pending = nil
  showToast()
  if not p then return end
  if p.timer and p.timer.Cancel then p.timer:Cancel() end
  if not ok then if C.debug then C.Print("auto screenshot failed") end return end
  local file = A.ExpectedName(p.t)
  local e = p.entry and C.db.entries[p.entry]
  if e and e.uid ~= p.uid then e = nil end -- entries never move, but be safe
  local rec = { uid = "S" .. C.Codec.Checksum(tostring(p.t) .. "|" .. file .. "|" .. C.charKey()), t = p.t, file = file, event = p.id, char = C.charKey(),
    zone = GetRealZoneText(), entryUid = e and e.uid, text = p.text }
  -- build the full record, then commit
  C.db.shots = C.db.shots or {}
  tinsert(C.db.shots, rec); while #C.db.shots > CAP do tremove(C.db.shots, 1) end
  if e then e.shot = { t = p.t, file = file } end
  C.Emit("auto_screenshot", format("Screenshot taken: %s", (p.text or "a big moment"):gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1")), { shot = rec.uid, file = file })
  if C.debug then C.Print("screenshot: Screenshots\\" .. file) end
end
A._finish = finish
C.On("SCREENSHOT_SUCCEEDED", function() if pending and pending.t then finish(true) end end)
C.On("SCREENSHOT_FAILED", function() if pending and pending.t then finish(false) end end)

local function capture()
  if not pending then return end
  if C.Photo and C.Photo.Active and C.Photo.Active() then pending = nil; return end
  if C.set.autoShotHideToast then local f = _G.JourneykeeperToast; if f and f.IsShown and f:IsShown() then toastHidden = (f.GetAlpha and f:GetAlpha()) or 1; f:SetAlpha(0) end end
  pending.t = time(); lastShot = pending.t
  local ok = pcall(C.API, "Screenshot")
  if not ok then finish(false); return end
  -- no success event within 4 s: give up quietly (nothing recorded)
  pending.timer = C_Timer.NewTimer and C_Timer.NewTimer(4, function() if pending then finish(false) end end)
end

-- called from C.Emit for every memory (idx = journal index if the memory was stored)
function A.OnEmit(id, e, idx)
  if id == "auto_screenshot" or not A.EVENTS[id] then return end
  local why = A.Skip(id, e, idx)
  if why then return false, why end
  -- level milestones are not stored as their own entry: link the level-up written a moment before
  if not idx and id == "level_milestone" and C.lastEntry then
    local le = C.db.entries[C.lastEntry]; if le and le.id == "level_up" and math.abs((le.t or 0) - time()) <= 5 then idx = C.lastEntry end
  end
  local en = idx and C.db.entries[idx]
  pending = { id = id, entry = idx, uid = en and en.uid, text = e and e.text }
  C_Timer.After(tonumber(C.set.autoShotDelay) or 1.5, capture)
  return true
end
function A.Pending() return pending end
function A.Reset() pending = nil; lastShot = 0; showToast() end

-- journal: short line for a memory that has a screenshot
function A.Line(e)
  if not (e and type(e.shot) == "table" and e.shot.file) then return nil end
  return format("Screenshot taken %s  (Screenshots\\%s)", date("%H:%M", e.shot.t or 0), e.shot.file)
end
