-- Death reports: a "last moments" card per death. Builds on Logger's death entry/deathSpot (which run first,
-- Logger loads earlier) and adds: time alive, last target, falling/drowning flags, group members present.
-- Optional one-line announcement (off by default): party or guild, throttled, never during combat lockdown/encounters.
local _, C = ...
local DR = {}; C.DeathReport = DR
local S = C.S
local lastTarget, inBreath, lastAnnounce = nil, false, 0

C.On("PLAYER_TARGET_CHANGED", function()
  if not C.set.deathReports then return end
  if UnitExists("target") then
    local n = S(UnitName("target"))
    if n then lastTarget = { name = n, hostile = UnitCanAttack("player", "target") and true or false, level = S(UnitLevel("target")), t = time() } end
  end
end)
C.On("MIRROR_TIMER_START", function(timer) if timer == "BREATH" then inBreath = true end end)
C.On("MIRROR_TIMER_STOP", function(timer) if timer == "BREATH" then inBreath = false end end)

local function groupNames()
  local out = {}
  if not IsInGroup() then return out end
  local raid = IsInRaid()
  for i = 1, raid and GetNumGroupMembers() or GetNumSubgroupMembers() do
    local u = (raid and "raid" or "party") .. i
    local n = S(UnitName(u))
    if n and not UnitIsUnit(u, "player") then out[#out + 1] = n end
    if #out >= 10 then break end
  end
  return out
end

function DR.Record()
  local spot = C.db.deathSpots[#C.db.deathSpots]
  if not spot or spot.char ~= C.charKey() or time() - (spot.t or 0) > 5 then return end
  local e = spot.entry and C.db.entries[spot.entry]
  local prev
  for i = #C.db.deathReports, 1, -1 do if C.db.deathReports[i].char == spot.char then prev = C.db.deathReports[i]; break end end
  local n = 0
  for _, r in ipairs(C.db.deathReports) do if r.char == spot.char then n = n + 1 end end
  local created = (C.db.chars[spot.char] or {}).created
  local rep = { t = spot.t, char = spot.char, level = spot.level, zone = spot.zone, sub = spot.sub, map = spot.map, x = spot.x, y = spot.y,
    killer = spot.killer, cause = e and e.cause, entryUid = e and e.uid, number = n + 1,
    alive = prev and (spot.t - prev.t) or (created and spot.t - created) or nil,
    lastTarget = lastTarget and (spot.t - lastTarget.t < 60) and lastTarget.name or nil,
    falling = IsFalling() and true or nil, drowning = inBreath or (e and e.cause == "drowned") or nil,
    group = groupNames(), instance = (select(1, GetInstanceInfo())) }
  rep.uid = "D" .. C.Codec.Checksum(rep.char .. "|" .. rep.t .. "|" .. tostring(rep.zone))
  tinsert(C.db.deathReports, rep)
  if e then e.report = rep.uid end
  DR.Announce(rep)
  return rep
end
C.On("PLAYER_DEAD", function() if C.set.deathReports then DR.Record() end end)

function DR.Line(r)
  return format("Journeykeeper: %s fell (#%d) at level %d in %s%s.", r.char:match("^[^-]+"), r.number, r.level or 0,
    (r.sub and r.sub ~= "" and (r.sub .. ", ") or "") .. (r.zone or "?"), r.killer and (" - " .. r.killer) or (r.cause and (" - " .. r.cause) or ""))
end
function DR.Announce(r)
  local ch = C.set.deathAnnounce
  if not ch or ch == "off" then return false end
  if InCombatLockdown() or (IsEncounterInProgress and IsEncounterInProgress()) then return false end
  if time() - lastAnnounce < 300 then return false end
  if ch == "party" and not IsInGroup() then return false end
  if ch == "guild" and not IsInGuild() then return false end
  lastAnnounce = time()
  C.API("SendChatMessage", DR.Line(r), ch == "guild" and "GUILD" or (IsInRaid() and "RAID" or "PARTY"))
  return true
end

local function dur(s)
  if not s then return "unknown" end
  if s < 3600 then return format("%d min", floor(s / 60)) end
  if s < 86400 then return format("%.1f h", s / 3600) end
  return format("%.1f days", s / 86400)
end
DR.dur = dur

function DR.Card(r)
  local lines = {
    format("Level %d, %s%s", r.level or 0, (r.sub and r.sub ~= "" and (r.sub .. ", ") or ""), r.zone or "?") .. (r.x and format(" (%.1f, %.1f)", r.x, r.y) or "") .. ".",
    "Cause: " .. (r.killer and ("slain by " .. r.killer) or (r.cause or "unknown")) .. (r.falling and " - falling" or "") .. (r.drowning and " - out of breath" or "") .. ".",
    "Alive since the last fall: " .. dur(r.alive) .. ".",
  }
  if r.lastTarget then lines[#lines + 1] = "Last target: " .. r.lastTarget .. "." end
  lines[#lines + 1] = (#(r.group or {}) > 0) and ("Present: " .. table.concat(r.group, ", ") .. ".") or "Alone."
  return lines
end

function DR.Build(blocks, search, H)
  tinsert(blocks, { kind = "chapterhead", text = "Deaths" })
  local counts, total = {}, 0
  for _, r in ipairs(C.db.deathReports) do counts[r.char] = (counts[r.char] or 0) + 1; total = total + 1 end
  local legacy = 0
  for _, s in ipairs(C.db.deathSpots) do legacy = legacy + 1 end
  local cl = {}
  for ck, n in pairs(counts) do cl[#cl + 1] = format("%s %d", H.short(ck), n) end
  table.sort(cl)
  tinsert(blocks, { kind = "dash", stats = { { "Falls", legacy }, { "Reports", total } }, note = #cl > 0 and ("By character: " .. table.concat(cl, ", ")) or nil })
  for i = #C.db.deathReports, 1, -1 do
    local r = C.db.deathReports[i]
    local hay = (r.char .. " " .. (r.zone or "") .. " " .. (r.killer or "")):lower()
    if search == "" or hay:find(search:lower(), 1, true) then
      tinsert(blocks, H.row({ cat = "death", t = r.t, title = format("Death #%d", r.number or 0), char = r.char, zone = r.zone, text = H.clean(table.concat(DR.Card(r), " ")) }))
    end
  end
  -- older deaths without reports stay listed
  local list = {}
  for i, e in ipairs(C.db.entries) do if e.id == "death" and not e.report and H.matches(e) then list[#list + 1] = i end end
  if #list > 0 then tinsert(blocks, { kind = "divider" }); tinsert(blocks, { kind = "heading", text = "Earlier falls" }); H.dayBlocks(blocks, list) end
end

C.Init(function()
  C.Journal.PROVIDERS.Deaths = { enabled = function() return C.set.deathReports end, build = DR.Build }
end)
