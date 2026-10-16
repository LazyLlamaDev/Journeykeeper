-- Narrative templates (2nd person, understated). Several per kind, rotated deterministically per kind.
local _, C = ...
C.TPL = {
  revisit_self = {
    "You have stood here before - {date}, as a level {level} {class}.",
    "{place}. You remember it from {date}.",
    "The paths of {place} feel familiar. You first came here on {date}.",
    "Back in {place}. The last time felt different; that was {date}.",
  },
  revisit_alt = {
    { f = "walk", "{name} walked these roads before you, on {date}." },
    { f = "line", "Another of your line, {name}, passed through {place} on {date}." },
    { f = "memory", "Somewhere in memory: {name}, level {level}, here on {date}." },
    { f = "walk", "{name} knew {place} first. That was {date}." },
  },
  warband = {
    { f = "verb", "Your {name} once {verb} here, a level {level} {class}, on {date}." },
    { f = "verb", "{place} remembers your {class}, {name}, who {verb} here at level {level}." },
    { f = "quiet", "{name} stood where you stand now. {date}, level {level}." },
    { f = "family", "The {class} {name} found {place} before you did." },
  },
  family = {
    { f = "first", "A first for your whole warband: {what}." },
    { f = "house", "No one of your line had done this before: {what}." },
  },
  thread_grave = {
    { f = "count", "This is the {ord} time you have returned to where you first fell." },
    { f = "pull", "Something keeps drawing you back here. {Ord} return to your first grave." },
  },
  thread_zone = {
    { f = "home", "Back in {place}, where it all began. You were level {from}; now {to}." },
    { f = "small", "{place} looks smaller than you remember. Level {from} then, {to} now." },
  },
  deaths_suffix = { " You have fallen here {n} time{s}.", " This place has claimed you {n} time{s}.", " {n} grave{s} of yours lie near." },
  anniversary = { "One year ago today, {name} first came to {place}.", "{years} year{s} to the day since {name} first saw {place}." },
  absence = { "It has been {days} days since you were last in {place}.", "{place}, after {days} days away." },
  grave = {
    "The ground here remembers. {name} fell on {date}{killer}.",
    "You pause. This is where {name} died, at level {level}.",
    "A quiet spot. Not so quiet on {date}{killer}.",
  },
  ally = {
    "{name}. You have shared the road {n} time{s}; last in {where}.",
    "A familiar face: {name}, last seen in {where} on {date}.",
    "{name} again. {n} journey{s} together so far.",
  },
  milestone = {
    "Level {level}. {name} reached it first, on {date}.",
    "Level {level}, a mark first set by {name} on {date}.",
  },
  milestone_new = { "Level {level} - further than anyone in your line has gone.", "Level {level}. No one before you has come this far." },
}

-- Variety: each template may be { f = "family", "text" }. We rotate, skipping templates whose family
-- was used in the last 2 picks for this kind (simple clustering by flavour).
local function famOf(t, i) return type(t) == "table" and t.f or ("#" .. i) end
local function txtOf(t) return type(t) == "table" and t[1] or t end
function C.Tpl(kind, vars)
  local list = C.TPL[kind]; if not list then return "" end
  C.db.tplIdx = C.db.tplIdx or {}; C.db.tplRecent = C.db.tplRecent or {}
  local recent = C.db.tplRecent[kind] or {}; C.db.tplRecent[kind] = recent
  local start = C.db.tplIdx[kind] or 0
  local i
  for step = 1, #list do
    local cand = (start + step - 1) % #list + 1
    local f = famOf(list[cand], cand)
    if f ~= recent[1] and f ~= recent[2] then i = cand; break end
  end
  i = i or (start % #list + 1)
  C.db.tplIdx[kind] = i
  tinsert(recent, 1, famOf(list[i], i)); recent[3] = nil
  local n = tonumber(vars and (vars.n or vars.years))
  return (txtOf(list[i]):gsub("{(%w+)}", function(k)
    if k == "s" then return (n and n ~= 1) and "s" or "" end
    local v = vars and vars[k]
    return v ~= nil and tostring(v) or ""
  end))
end

-- v0.6.9: settings sub-pages with a fixed design width. Content is scaled down to the panel width (down to 80%),
-- and anything still wider gets a horizontal scrollbar under the vertical one. Nothing is ever clipped.
-- Shift + mouse wheel scrolls horizontally. Own frames only (Settings canvas panels are not secure).
function C.FitScroll(panel, sf, content, designW)
  local hbar = rawget(sf, "jkH")
  if not hbar then
    hbar = CreateFrame("Slider", nil, panel); sf.jkH = hbar
    hbar:SetOrientation("HORIZONTAL"); hbar:SetHeight(12); hbar:SetPoint("BOTTOMLEFT", 8, 2); hbar:SetPoint("BOTTOMRIGHT", -30, 2)
    local bg = hbar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
    hbar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob"); hbar:SetMinMaxValues(0, 0); hbar:SetValueStep(1)
    hbar:SetScript("OnValueChanged", function(_, v) sf:SetHorizontalScroll(v) end)
    sf:HookScript("OnMouseWheel", function(_, d)
      if IsShiftKeyDown() and hbar:IsShown() then local lo, hi = hbar:GetMinMaxValues(); hbar:SetValue(math.max(lo, math.min(hi, hbar:GetValue() - d * 40))) end
    end)
  end
  local w = sf:GetWidth() or 0
  if w <= 1 then return 1 end
  local scale = math.max(0.8, math.min(1, w / designW))
  content:SetScale(scale)
  local over = designW * scale - w
  if over > 1 then
    hbar:SetMinMaxValues(0, over / scale); hbar:Show()
    sf:ClearAllPoints(); sf:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -58); sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 18)
  else
    hbar:SetValue(0); hbar:SetMinMaxValues(0, 0); hbar:Hide(); sf:SetHorizontalScroll(0)
  end
  if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
  return scale
end
