-- Tooltip lines on player units via TooltipDataProcessor (no frame hooks).
local _, C = ...
local S = C.S
local function ago(t) return t and C.dateStr(t) or "?" end
local RATE = { great = "|cff66dd66Great run|r", forgettable = "|cffaaaaaaForgettable|r", avoid = "|cffff5544Avoid|r" }
-- v0.7.2: Fellowship lines + boss memory hints. Cheap: guid -> fellow key and boss name -> first kill are cached;
-- the boss cache is rebuilt only when the number of journal entries changed. Every lookup is pcall-guarded.
local TT = {}; C.TooltipLines = TT
local keyCache = {}             -- [guid] = "Name-Realm" | false
local bossCache, bossN = nil, -1
function TT.FellowKey(guid)
  local k = keyCache[guid]
  if k ~= nil then return k or nil end
  local p = C.db.players[guid]
  k = p and p.name
  if not k and C.Has("GetPlayerInfoByGUID") then
    local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
    name, realm = ok and S(name), ok and S(realm)
    if name then k = name .. "-" .. ((realm and realm ~= "") and realm or GetNormalizedRealmName() or "") end
  end
  keyCache[guid] = k or false
  return k
end
function TT.FellowLines(guid)
  if not (C.set.fellowship and C.set.fellowTooltip and C.Fellowship) then return nil end
  local full = TT.FellowKey(guid); if not full then return nil end
  local f = C.db.fellowship; local p = f and f.people and f.people[full]
  if not p or C.Fellowship.Excluded(full) then return nil end -- archived people live in f.archive, never here
  local runs, r = #(p.runs or {}), p.runs and p.runs[#p.runs]
  local a
  if runs > 0 then a = format("|cffd8b26aJourneykeeper:|r %d run%s together  ·  last: %s, %s", runs, runs == 1 and "" or "s", r.w or "?", date("%b %Y", r.t or 0))
  else a = format("|cffd8b26aJourneykeeper:|r grouped %d time%s  ·  together %s", p.groups or 1, (p.groups or 1) == 1 and "" or "s", C.FormatDuration(p.secs or 0)) end
  local b = format("|cffbba27a  First met: %s, %s|r", p.firstZone or "?", p.first and date("%d %b %Y", p.first) or "?")
  return a, b
end
function TT.BossLine(name)
  if not (C.set.bossTooltip and name) then return nil end
  if not bossCache or bossN ~= #C.db.entries then
    bossCache, bossN = {}, #C.db.entries
    for _, e in ipairs(C.db.entries) do
      if e.id == "boss_first_kill" and e.boss and not bossCache[e.boss] then bossCache[e.boss] = e end
    end
  end
  local e = bossCache[name]
  if not e then return nil end
  return format("|cffd8b26aJourneykeeper:|r |cffbba27aYou first defeated %s on %s%s.|r", name, C.dateStr(e.t), (e.char and e.char ~= C.charKey()) and (" (as " .. e.char:match("^[^-]+") .. ")") or "")
end
C.Init(function()
  if not (TooltipDataProcessor and Enum.TooltipDataType) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
    if tt ~= GameTooltip then return end
    local guid = data and S(data.guid)
    if not guid then return end
    if guid:find("^Creature") or guid:find("^Vehicle") then
      local ok, name = pcall(function() return S((tt:GetUnit())) end)
      local line = ok and TT.BossLine(name)
      if line then tt:AddLine(line) end
      return
    end
    if not guid:find("^Player") then return end
    local okf, fa, fb = pcall(TT.FellowLines, guid)
    if okf and fa then tt:AddLine(fa); if fb then tt:AddLine(fb) end end
    if not C.set.socialTooltip then return end
    local p = C.db.players[guid]
    if not p then return end
    tt:AddLine(format("|cff4ce566Journeykeeper:|r grouped %dx%s  ·  last seen %s", p.count or 0, (p.runs or 0) > 0 and format(", %d shared run%s", p.runs, p.runs == 1 and "" or "s") or "", ago(p.last)))
    tt:AddLine(format("|cffbbbbbb  %s, on %s%s|r", p.lastWhere or "?", (p.lastChar or "?"):match("^[^-]+"), p.rating and ("  ·  " .. RATE[p.rating]) or ""))
    for i = math.max(1, #p.notes - 1), #p.notes do
      if p.notes[i] then tt:AddLine("|cffaaaaaa  \"" .. p.notes[i].text .. "\"|r", 1, 1, 1, true) end
    end
  end)
end)

-- Mouseover echo for known players when the group channel is chat/toast.
C.On("UPDATE_MOUSEOVER_UNIT", function()
  if C.set.channel.group_echo == "tooltip" or not S(UnitIsPlayer("mouseover")) then return end
  local guid = S(UnitGUID("mouseover"))
  local p = guid and C.db.players[guid]
  if not p then return end
  C.Echo("group_echo", "m" .. guid, format("You grouped with %s %dx, last in %s on %s.", p.name or "?", p.count or 0, p.lastWhere or "?", ago(p.last)),
    "Echo: a familiar face")
end)
