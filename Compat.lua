-- Journeykeeper Compat (v0.8.0): small feature-detected shims so one build runs on every WoW flavor
-- (Forever 1.60.1, Retail/Midnight, Mists Classic, Anniversary/TBC, Classic Era). Never checks version
-- strings for behaviour: every shim asks "does this API exist?" and falls back or turns the feature off.
local _, C = ...
local CP = {}; C.Compat = CP

-- informational only (shown by /jkp perf), never used to branch behaviour
function CP.ClientInfo()
  local v, build, _, iface = "?", "?", nil, 0
  if GetBuildInfo then v, build, _, iface = GetBuildInfo() end
  return v, build, tonumber(iface) or 0
end

-- "BackdropTemplate" where the mixin exists (all current clients), nil on a client without it
CP.BACKDROP = (BackdropTemplateMixin and "BackdropTemplate") or nil
function CP.SetBackdrop(f, bd) if f and f.SetBackdrop then pcall(f.SetBackdrop, f, bd) end end

-- Settings panels: modern Settings API, else the legacy Interface Options list.
-- Returns a handle with :GetID() (works for both) or nil.
function CP.RegisterPanel(panel, parent)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    if parent and parent.isLegacy then parent = nil end
    if parent then return Settings.RegisterCanvasLayoutSubcategory and Settings.RegisterCanvasLayoutSubcategory(parent, panel, panel.name) or nil end
    do
      local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
      if Settings.RegisterAddOnCategory then Settings.RegisterAddOnCategory(cat) end
      return cat
    end
  end
  if InterfaceOptions_AddCategory then
    if parent and parent.panel then panel.parent = parent.panel.name end
    InterfaceOptions_AddCategory(panel)
    return { isLegacy = true, panel = panel, GetID = function() return panel.name end }
  end
  return nil
end
function CP.OpenPanel(cat)
  if not cat then return false end
  if cat.isLegacy then
    local open = InterfaceOptionsFrame_OpenToCategory
    if not open then return false end
    open(cat.panel); open(cat.panel) -- the legacy frame needs two calls the first time
    return true
  end
  if Settings and Settings.OpenToCategory then Settings.OpenToCategory(cat:GetID()); return true end
  return false
end

-- Unit tooltips: TooltipDataProcessor where it exists, else the classic OnTooltipSetUnit script.
-- fn(tooltip, guid, unit) is called for GameTooltip only.
local unitHooks, hooked = {}, false
local function runUnit(tt, guid, unit)
  if tt ~= GameTooltip or not guid then return end
  for _, fn in ipairs(unitHooks) do pcall(fn, tt, guid, unit) end
end
function CP.OnUnitTooltip(fn)
  tinsert(unitHooks, fn)
  if hooked then return true end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
      local guid = data and C.S(data.guid)
      local unit
      if not guid and tt and tt.GetUnit then local ok, _, u = pcall(tt.GetUnit, tt); unit = ok and u or nil; guid = unit and C.S(UnitGUID(unit)) end
      runUnit(tt, guid, unit)
    end)
    hooked = true
  elseif GameTooltip and GameTooltip.HookScript and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
      local ok, _, unit = pcall(tt.GetUnit, tt)
      unit = ok and unit or nil
      runUnit(tt, unit and C.S(UnitGUID(unit)), unit)
    end)
    hooked = true
  end
  return hooked
end

-- Quest title by id: C_QuestLog (modern + Classic), else the quest log scan of older clients
function CP.QuestTitle(q)
  if not q then return nil end
  local QL = C_QuestLog
  if QL and QL.GetTitleForQuestID then local ok, t = pcall(QL.GetTitleForQuestID, q); if ok and C.S(t) then return t end end
  if QL and QL.GetQuestInfo then local ok, t = pcall(QL.GetQuestInfo, q); if ok and type(C.S(t)) == "string" then return t end end
  if GetNumQuestLogEntries and GetQuestLogTitle then
    local ok, n = pcall(GetNumQuestLogEntries)
    for i = 1, (ok and tonumber(n) or 0) do
      local t, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
      if not isHeader and id == q then return t end
    end
  end
  return nil
end
-- QUEST_ACCEPTED is (questID) on modern clients and (questLogIndex, questID) on older ones
function CP.AcceptedQuestID(a, b) if type(b) == "number" and b > 0 then return b end return a end

function CP.SpellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellInfo then local ok, info = pcall(C_Spell.GetSpellInfo, id); if ok and type(info) == "table" and C.S(info.name) then return info.name end end
  if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok and C.S(n) then return n end end
  return nil
end

-- Professions: { {name=, rank=}, ... }. Modern GetProfessions(); else the skill list of Classic Era/Anniversary
-- (skills the player can unlearn, plus anything under the client's own "Professions"/"Secondary Skills" headers).
function CP.Professions()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ GetProfessions() }) do
      if idx then local name, _, rank = GetProfessionInfo(idx); if name then out[#out + 1] = { name = name, rank = rank } end end
    end
    return out
  end
  if not (GetNumSkillLines and GetSkillLineInfo) then return out end
  local want = {}
  for _, g in ipairs({ "TRADE_SKILLS", "SECONDARY_SKILLS" }) do if type(_G[g]) == "string" then want[_G[g]] = true end end
  local inProf = false
  for i = 1, (GetNumSkillLines() or 0) do
    local name, isHeader, _, rank, _, _, _, abandonable = GetSkillLineInfo(i)
    if isHeader then inProf = name and want[name] or false
    elseif name and (inProf or abandonable) then out[#out + 1] = { name = name, rank = rank } end -- only professions can be unlearned
  end
  return out
end

-- The two classic continents of the Journey map: uiMapIDs 1414/1415 on Classic-era map data (Forever, Classic),
-- 12/13 on Retail. Picks the pair the client reports as continents; other continents are shown when visited.
local function isContinent(id)
  local info = C.API("C_Map.GetMapInfo", id)
  return info and info.mapType == 2 and info.name and info.name ~= ""
end
function CP.ClassicContinents()
  if isContinent(1414) and isContinent(1415) then return 1414, 1415 end
  if isContinent(12) and isContinent(13) then return 12, 13 end
  return 1414, 1415
end
