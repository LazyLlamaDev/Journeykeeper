-- v0.7.1 Fellowship: the people you group with. Stored per account in JourneykeeperDB.fellowship.people,
-- keyed by "Name-Realm". Only name, realm and class are stored about the other player, plus when/where you met
-- (from your side), time together, shared dungeon runs and boss kills. Never sent anywhere.
-- Fed by Logger's roster tracking (OnJoin / OnLeave); runs + kills from instance entry and ENCOUNTER_END.
local _, C = ...
local F = {}; C.Fellowship = F
local S = C.S
local CAP = 30                 -- runs / kills kept per person (newest)
local ECHO_GAP = 6 * 3600      -- at most one fellowship echo per person per 6 h
local present = {}             -- [key] = { start, unit }

local function store()
  local f = C.db.fellowship
  if type(f) ~= "table" then f = {}; C.db.fellowship = f end
  f.people = type(f.people) == "table" and f.people or {}
  f.archive = type(f.archive) == "table" and f.archive or {}
  return f
end
F.Store = store
local function split(full) local n, r = (full or ""):match("^([^-]+)%-?(.*)$"); return n or full, r or "" end
local function me() return C.charKey() end

function F.Excluded(full)
  local name, realm = split(full)
  local list = (C.set.fellowExclude or ""):lower()
  for item in list:gmatch("[^,;]+") do
    item = item:gsub("^%s+", ""):gsub("%s+$", "")
    if item ~= "" then
      local n, r = split(item)
      if n == (name or ""):lower() and (r == "" or r:gsub("[%s%-']", "") == (realm or ""):lower():gsub("[%s%-']", "")) then return true end
    end
  end
  return false
end

local function cap(list) while #list > CAP do tremove(list, 1) end end
local function instName() local inInst, kind = IsInInstance(); if inInst and (kind == "party" or kind == "raid") then return (GetInstanceInfo()) end end

local function addRun(p, inst, t)
  p.runs = p.runs or {}
  local last = p.runs[#p.runs]
  if last and last.w == inst and (t - (last.t or 0)) < 3 * 3600 then return false end -- same run
  tinsert(p.runs, { w = inst, t = t, c = me() }); cap(p.runs)
  return true
end

-- the strongest shared memory with a fellow, as echo text (nil if nothing shared yet)
function F.EchoText(p)
  local short = (p.name or "?")
  local k, r = p.kills and p.kills[#p.kills], p.runs and p.runs[#p.runs]
  if r then
    return format("You ran %s with %s on %s.", r.w or "a dungeon", short, C.dateStr(r.t or time())) .. (k and format(" Together you brought down %s.", k.b or "a boss") or "")
  end
  if k then return format("You and %s defeated %s on %s.", short, k.b or "a boss", C.dateStr(k.t or time())) end
  return nil
end

-- v0.7.2 reunion: what happened on OUR side since we last played together (from our own journal), plus, for a
-- trusted friend who also runs Journeykeeper with sharing on, up to 5 of their shared milestones since then.
local SINCE_IDS = { zone_first_char = "zones", dungeon_enter_first = "dungeons", instance_complete = "dungeons", boss_first_kill = "bosses" }
function F.Since(since, ck)
  local out = { zones = 0, dungeons = 0, bosses = 0, lastBoss = nil, lastZone = nil }
  for i = #C.db.entries, 1, -1 do
    local e = C.db.entries[i]
    if (e.t or 0) <= since then break end
    local k = SINCE_IDS[e.id]
    if k and (not ck or e.char == ck) then
      out[k] = out[k] + 1
      if k == "bosses" and not out.lastBoss then out.lastBoss = e.boss end
      if k == "zones" and not out.lastZone then out.lastZone = e.zone end
    end
  end
  return out
end
local function plural(n, w) return format("%d %s", n, n == 1 and w or (w:sub(-1) == "s" and (w .. "es") or (w .. "s"))) end
function F.ReunionText(p, now, theirs)
  now = now or time()
  local days = floor((now - (p.last or now)) / 86400)
  local s = F.Since(p.last or now, C.charKey())
  local parts = {}
  local lvl, was = UnitLevel("player") or 0, tonumber(p.lastLevel)
  if was and p.lastChar == C.charKey() and lvl > was then parts[#parts + 1] = format("grew from level %d to %d", was, lvl) end
  if s.zones > 0 then parts[#parts + 1] = "found " .. plural(s.zones, "new place") .. (s.lastZone and (" (lately " .. s.lastZone .. ")") or "") end
  if s.dungeons > 0 then parts[#parts + 1] = "saw " .. plural(s.dungeons, "dungeon") end
  if s.bosses > 0 then parts[#parts + 1] = "defeated " .. plural(s.bosses, "boss") .. (s.lastBoss and (", last " .. s.lastBoss) or "") end
  local txt = format("%d day%s since you last travelled with %s.", days, days == 1 and "" or "s", p.name or "?")
  if #parts > 0 then txt = txt .. " Since then you " .. table.concat(parts, ", ") .. "." else txt = txt .. " Your road has been quiet since." end
  if theirs and #theirs > 0 then
    local t = {}
    for i = 1, math.min(5, #theirs) do t[i] = theirs[i] end
    txt = txt .. format("\nFrom %s's journal: %s", p.name or "?", table.concat(t, " "))
  end
  return txt
end
local reunionWait = {} -- [full] = { p, t } while a trusted friend's reply is awaited (max 4 s)
local function fireReunion(full, p, theirs)
  local txt = F.ReunionText(p, nil, theirs)
  C.Emit("fellow_reunion", txt, { fellow = full }, { title = "A reunion", key = "f" .. full, force = true, text = txt })
end
-- called by Share when a trusted friend answered our reunion request
function F.OnReunionReply(full, lines)
  local w = reunionWait[full]; if not w then return false end
  reunionWait[full] = nil
  fireReunion(full, w.p, lines)
  return true
end
function F.StartReunion(full, p, prevSeen, now, prevLevel, prevChar)
  p.reunionAt = now
  local snap = { name = p.name, last = prevSeen, lastLevel = prevLevel, lastChar = prevChar }
  local SH = C.Share
  if C.set.reunionShared and SH and C.set.shareEnabled and SH.IsTrusted(full) and SH.RequestSince then
    reunionWait[full] = { p = snap, t = now }
    SH.RequestSince(full, prevSeen)
    C_Timer.After(4, function() local w = reunionWait[full]; if w then reunionWait[full] = nil; fireReunion(full, w.p, nil) end end)
  else
    fireReunion(full, snap, nil)
  end
  return true
end

-- called from Logger's roster handler for every newly seen group member. Returns true if an echo was fired.
function F.OnJoin(unit, full, classFile, inGuild)
  if not C.set.fellowship or not full or full == "?" then return false end
  if C.set.fellowGuild and inGuild then return false end
  if F.Excluded(full) then return false end
  local f = store()
  local name, realm = split(full)
  local now = time()
  local p = f.people[full]
  local isNew = not p
  if isNew then
    p = { name = name, realm = realm, class = classFile, first = now, firstZone = GetRealZoneText(), firstChar = me(), groups = 0, secs = 0 }
    f.people[full] = p
  end
  p.class = classFile or p.class
  local prevSeen = p.last
  local prevLevel, prevChar = p.myLevel, p.myChar -- what we were when we last met (for the reunion)
  p.groups = (p.groups or 0) + 1; p.last = now; p.lastZone = GetRealZoneText()
  p.myLevel, p.myChar = UnitLevel("player"), me() -- our own level/character at this meeting
  present[full] = { start = now }
  local inst = instName()
  if inst then addRun(p, inst, now) end
  if isNew then
    C.Emit("fellow_first", format("%s met %s for the first time, in %s.", (me():match("^[^-]+")), name, p.firstZone or "?"), { fellow = full })
    return false
  end
  -- reunion after a long gap replaces the normal fellowship echo (same 6 h throttle, never both)
  local gapDays = tonumber(C.set.reunionDays) or 3
  if C.set.fellowReunion and prevSeen and (now - prevSeen) >= gapDays * 86400 and (now - (p.echoed or 0)) > ECHO_GAP then
    p.echoed = now
    return F.StartReunion(full, p, prevSeen, now, prevLevel, prevChar)
  end
  if C.set.fellowEchoes and prevSeen and (now - prevSeen) > 600 and (now - (p.echoed or 0)) > ECHO_GAP then
    local txt = F.EchoText(p)
    if txt then
      p.echoed = now
      C.Echo("fellow_echo", "f" .. full, txt, "An old companion", nil, { fellow = full })
      return true
    end
  end
  return false
end

function F.OnLeave(full)
  local m = present[full]; if not m then return end
  present[full] = nil
  local p = C.db.fellowship and C.db.fellowship.people and C.db.fellowship.people[full]
  if p then p.secs = (p.secs or 0) + math.max(0, time() - m.start) end
end
C.On("PLAYER_LOGOUT", function() for k in pairs(present) do F.OnLeave(k) end end)

-- shared dungeon runs: entering an instance with fellows already in the group
C.On("PLAYER_ENTERING_WORLD", function()
  if not C.set or not C.set.fellowship then return end
  local inst = instName(); if not inst then return end
  local people = store().people
  for full in pairs(present) do local p = people[full]; if p then addRun(p, inst, time()) end end
end)
C.On("ENCOUNTER_END", function(_, encName, _, _, success)
  if not C.set or not C.set.fellowship or S(success) ~= 1 then return end
  local boss, inst, now = S(encName) or "a boss", (GetInstanceInfo()), time()
  local people = store().people
  for full in pairs(present) do
    local p = people[full]
    if p then p.kills = p.kills or {}; tinsert(p.kills, { b = boss, w = inst, t = now }); cap(p.kills) end
  end
end)

-- forget = move to the archive (the journal never deletes people silently)
function F.Forget(full)
  local f = store(); local p = f.people[full]; if not p then return false end
  p.archivedAt = time(); f.archive[full] = p; f.people[full] = nil
  return true
end
function F.Restore(full)
  local f = store(); local p = f.archive[full]; if not p then return false end
  p.archivedAt = nil; if not f.people[full] then f.people[full] = p end; f.archive[full] = nil
  return true
end
function F.Exclude(full)
  local cur = C.set.fellowExclude or ""
  if F.Excluded(full) then return false end
  C.set.fellowExclude = (cur ~= "" and (cur .. ", ") or "") .. full
  if C.Touched then C.Touched("fellowExclude") end
  return true
end

-- retention (setting, 0 = keep forever). Snapshot first, then remove; returns number removed.
function F.Prune(now)
  local days = tonumber(C.set.fellowRetention) or 0
  if days <= 0 then return 0 end
  now = now or time()
  local f, old = store(), {}
  for full, p in pairs(f.people) do if (now - (p.last or p.first or now)) > days * 86400 then old[#old + 1] = full end end
  if #old == 0 then return 0 end
  if not (C.Data and C.Data.writable) then return 0 end
  if C.Data.Snapshot then pcall(C.Data.Snapshot, "fellowship-retention") end
  for _, full in ipairs(old) do f.people[full] = nil end
  return #old
end

F.SORTS = { "recent", "time", "runs", "name", "met" }
F.SORT_LABEL = { recent = "last seen", time = "time together", runs = "shared runs", name = "name", met = "first met" }
function F.List(search, sort)
  local arr = {}
  search = (search or ""):lower()
  for full, p in pairs(store().people) do
    if search == "" or full:lower():find(search, 1, true) or (p.firstZone or ""):lower():find(search, 1, true) then arr[#arr + 1] = { key = full, p = p } end
  end
  sort = sort or "recent"
  table.sort(arr, function(a, b)
    local x, y = a.p, b.p
    if sort == "name" then return a.key:lower() < b.key:lower()
    elseif sort == "time" then if (x.secs or 0) ~= (y.secs or 0) then return (x.secs or 0) > (y.secs or 0) end
    elseif sort == "runs" then local rx, ry = #(x.runs or {}), #(y.runs or {}); if rx ~= ry then return rx > ry end
    elseif sort == "met" then if (x.first or 0) ~= (y.first or 0) then return (x.first or 0) < (y.first or 0) end end
    if (x.last or 0) ~= (y.last or 0) then return (x.last or 0) > (y.last or 0) end
    return a.key < b.key
  end)
  return arr
end

function F.Build(blocks, search, H)
  local f = store()
  F.sort = F.sort or "recent"
  local list = F.List(search, F.sort)
  local runs, total = 0, 0
  for _, it in ipairs(list) do runs = runs + #(it.p.runs or {}); total = total + (it.p.secs or 0) end
  tinsert(blocks, { kind = "chapterhead", text = "The Fellowship" })
  tinsert(blocks, { kind = "dash", stats = { { "Fellows", #list }, { "Shared runs", runs }, { "Together", total > 0 and C.FormatDuration(total) or "-" } },
    note = "Everyone you grouped with: name, realm and class only. Use the search box below; click a person for options." })
  tinsert(blocks, H.row({ cat = "group", title = "Sorted by " .. F.SORT_LABEL[F.sort], text = "Click to change the order.", onClick = function()
    local idx = 1; for i, s in ipairs(F.SORTS) do if s == F.sort then idx = i end end
    F.sort = F.SORTS[idx % #F.SORTS + 1]; C.Journal.Refresh()
  end }))
  for _, it in ipairs(list) do
    local p, full = it.p, it.key
    local txt = format("%s  ·  first met %s in %s  ·  together %d time%s, %s  ·  %d run%s, %d boss kill%s",
      (p.class or "traveller"):lower(), p.first and C.dateStr(p.first) or "?", p.firstZone or "?", p.groups or 0, (p.groups or 0) == 1 and "" or "s",
      C.FormatDuration(p.secs or 0), #(p.runs or {}), #(p.runs or {}) == 1 and "" or "s", #(p.kills or {}), #(p.kills or {}) == 1 and "" or "s")
    local r = p.runs and p.runs[#p.runs]
    if r then txt = txt .. format("  ·  last run: %s, %s", r.w or "?", C.dateStr(r.t or 0)) end
    tinsert(blocks, H.row({ cat = "group", t = p.last, title = full, text = txt, onClick = function(self)
      C.Menu(self, {
        { text = "Never record " .. (p.name or full) .. " again", func = function() F.Exclude(full); F.Forget(full); C.Journal.Refresh() end, color = { 1, 0.55, 0.45 } },
        { text = "Forget (moves to the archive)", func = function() F.Forget(full); C.Journal.Refresh() end, color = { 1, 0.7, 0.5 } },
      }, full)
    end }))
  end
  local nArch = 0; for _ in pairs(f.archive) do nArch = nArch + 1 end
  if nArch > 0 and (search or "") == "" then
    tinsert(blocks, { kind = "heading", text = "Archived" })
    for full, p in pairs(f.archive) do
      tinsert(blocks, H.row({ cat = "group", t = p.archivedAt, title = full, text = "Archived  ·  click to restore", onClick = function() F.Restore(full); C.Journal.Refresh() end }))
    end
  end
end

C.Init(function()
  store()
  C.Journal.PROVIDERS.Fellowship = { enabled = function() return C.set.fellowship end, build = F.Build }
  C_Timer.After(20, function() local n = F.Prune(); if n > 0 then C.Print(format("Fellowship: %d fellow%s not seen for %d days forgotten (snapshot taken).", n, n == 1 and "" or "s", C.set.fellowRetention)) end end)
end)
