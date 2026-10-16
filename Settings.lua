-- Settings canvas in Blizzard Settings. Generic sections from C.OPTIONS (toggle/slider/cycle/button),
-- then collapsible per-category event groups (toggle + channel). Own widgets only.
local _, C = ...
local panel, category, content, groups, optRows

local function cycleButton(parent, values, get, set, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 90, 20)
  b.Update = function() b:SetText(tostring(get())) end
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, btn)
    local cur, idx = get(), 1
    for i, v in ipairs(values) do if v == cur then idx = i end end
    idx = btn == "RightButton" and ((idx - 2) % #values + 1) or (idx % #values + 1)
    set(values[idx]); b.Update()
  end)
  return b
end

local function slider(parent, o)
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL"); s:SetSize(170, 14); s:SetMinMaxValues(o.min, o.max); s:SetValueStep(o.step); s:SetObeyStepOnDrag(true)
  local bar = s:CreateTexture(nil, "BACKGROUND"); bar:SetPoint("LEFT"); bar:SetPoint("RIGHT"); bar:SetHeight(4); bar:SetColorTexture(0.35, 0.28, 0.18, 0.9)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s.val = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); s.val:SetPoint("LEFT", s, "RIGHT", 8, 0)
  s:SetScript("OnValueChanged", function(self, v)
    v = floor(v / o.step + 0.5) * o.step
    local old = C.set[o.key]; C.set[o.key] = v; if old ~= v then C.Touched(o.key) end; self.val:SetText(o.step < 1 and format("%.2f", v) or tostring(v))
    if o.apply then pcall(o.apply) end
  end)
  s.Update = function() s:SetValue(C.set[o.key] or o.default); s.val:SetText(tostring(C.set[o.key])) end
  return s
end

local FEAS = { OK = "|cff66dd66OK|r", partial = "|cffffbb33partial|r" }

local function header(text, color, icon, key)
  local h = CreateFrame("Button", nil, content); h:SetSize(620, 24)
  local hb = h:CreateTexture(nil, "BACKGROUND"); hb:SetAllPoints(); hb:SetColorTexture(color[1], color[2], color[3], 0.18)
  h.arrow = h:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h.arrow:SetPoint("LEFT", 4, 0)
  local x = 18
  if icon then local ic = h:CreateTexture(nil, "ARTWORK"); ic:SetSize(20, 20); ic:SetPoint("LEFT", 18, 0); ic:SetTexture(icon); x = 42 end
  local lbl = h:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lbl:SetPoint("LEFT", x, 0); lbl:SetText(text); lbl:SetTextColor(unpack(color))
  h.count = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); h.count:SetPoint("RIGHT", -100, 0)
  h:SetScript("OnClick", function() C.set.collapsed[key] = not C.set.collapsed[key]; C.SettingsLayout() end)
  return h
end

function C.SettingsLayout()
  local y = -4
  for _, g in ipairs(groups) do
    g.header:ClearAllPoints(); g.header:SetPoint("TOPLEFT", 0, y); y = y - 26
    local open = not C.set.collapsed[g.key]
    g.header.arrow:SetText(open and "-" or "+")
    for _, r in ipairs(g.rows) do
      if open then r:ClearAllPoints(); r:SetPoint("TOPLEFT", 18, y); r:Show(); y = y - (r.h or 24) else r:Hide() end
    end
    if g.isOpt and g.last then y = y - 6 end
  end
  content:SetHeight(-y + 10)
end

local function refreshAll()
  if not groups then return end
  for _, g in ipairs(groups) do
    if g.isOpt then for _, r in ipairs(g.rows) do if r.w and r.w.Update then r.w.Update() end end
    else
      local on = 0
      for _, r in ipairs(g.rows) do r.cb:SetChecked(C.set.ev[r.id]); r.ch.Update(); if C.set.ev[r.id] then on = on + 1 end end
      g.header.count:SetText(format("%d/%d on", on, #g.rows))
    end
  end
  C.SettingsLayout()
end

local function optionRow(o, parent)
  local r = CreateFrame("Frame", nil, parent or content); r:SetSize(600, 24)
  local lbl = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); lbl:SetPoint("LEFT", 4, 0); lbl:SetWidth(300); lbl:SetJustifyH("LEFT"); lbl:SetText(o.label); r.lbl = lbl
  if o.help then
    r:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(o.label, 1, 0.82, 0); GameTooltip:AddLine(o.help, 1, 1, 1, true); GameTooltip:Show() end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local w
  if o.type == "toggle" then
    w = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate"); w:SetSize(22, 22); w:SetPoint("LEFT", 310, 0)
    w:SetScript("OnClick", function(self) C.set[o.key] = self:GetChecked() and true or false; C.Touched(o.key); if o.apply then pcall(o.apply) end; if C.Atmos then C.Atmos.UpdateMinimap() end; if C.MapPins then C.MapPins.Refresh(true) end end)
    w.Update = function() w:SetChecked(C.set[o.key]) end
  elseif o.type == "slider" then
    w = slider(r, o); w:SetPoint("LEFT", 316, 0)
  elseif o.type == "cycle" then
    w = cycleButton(r, o.values, function() return C.set[o.key] end, function(v) C.set[o.key] = v; C.Touched(o.key); if o.apply then pcall(o.apply) end end, 110); w:SetPoint("LEFT", 310, 0)
  elseif o.type == "input" then
    w = CreateFrame("EditBox", nil, r, "InputBoxTemplate"); w:SetSize(160, 20); w:SetPoint("LEFT", 316, 0); w:SetAutoFocus(false); w:SetMaxLetters(o.maxLetters or 40)
    w:SetScript("OnEnterPressed", function(self) local v = self:GetText(); if v ~= C.set[o.key] then C.set[o.key] = v; C.Touched(o.key); if o.apply then pcall(o.apply) end end; self:ClearFocus() end)
    w:SetScript("OnEditFocusLost", function(self) local v = self:GetText(); if v ~= C.set[o.key] then C.set[o.key] = v; C.Touched(o.key); if o.apply then pcall(o.apply) end end end)
    w.Update = function() w:SetText(C.set[o.key] or "") end
  elseif o.type == "button" then
    w = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); w:SetSize(110, 20); w:SetPoint("LEFT", 310, 0); w:SetText("Run")
    w:SetScript("OnClick", function() o.run(); refreshAll() end)
  end
  r.w = w
  return r
end

C.OptionRow = function(o, parent) return optionRow(o, parent) end
local function build()
  panel = CreateFrame("Frame"); panel.name = "Journeykeeper"
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Journeykeeper — Echoes of Your Journey")
  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); note:SetPoint("TOPLEFT", 16, -38)
  note:SetText("Everything is stored locally; nothing is sent to other players. Hover a setting for details. Click/right-click cycles values.")
  -- heavy content (~120 rows of widgets) is created on first open, not at login
  local built = false
  local function buildContent()
  local tb = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); tb:SetSize(110, 22); tb:SetPoint("TOPLEFT", 16, -58); tb:SetText("Test popup")
  tb:SetScript("OnClick", function() C.Toast.Test() end)
  local jb = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); jb:SetSize(110, 22); jb:SetPoint("LEFT", tb, "RIGHT", 6, 0); jb:SetText("Open journal")
  jb:SetScript("OnClick", function() C.Journal.Toggle() end)
  local db = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); db:SetSize(110, 22); db:SetPoint("LEFT", jb, "RIGHT", 6, 0); db:SetText("Show digest")
  db:SetScript("OnClick", function() SlashCmdList.JOURNEYKEEPER("digest") end)
  local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 12, -88); sf:SetPoint("BOTTOMRIGHT", -30, 10)
  content = CreateFrame("Frame", nil, sf); content:SetSize(640, 100); sf:SetScrollChild(content)
  groups = {}
  for _, sec in ipairs(C.OPTIONS) do if not sec.page then
    local key = "opt_" .. sec.section
    local g = { key = key, rows = {}, isOpt = true, last = true }
    g.header = header(sec.section, { 1, 0.82, 0.35 }, nil, key)
    for _, o in ipairs(sec.items) do tinsert(g.rows, optionRow(o)) end
    tinsert(groups, g)
  end end
  local evHead = { key = "opt_events", rows = {}, isOpt = true }
  evHead.header = header("Events & channels (per category)", { 0.9, 0.9, 0.9 }, nil, "opt_events")
  tinsert(groups, evHead)
  for _, cdef in ipairs(C.EVENT_CATS) do
    local g = { key = cdef.key, rows = {} }
    local cat = C.CATS[cdef.key]
    g.header = header(cdef.label, cat.color, cat.icon, cdef.key)
    local all = CreateFrame("Button", nil, g.header, "UIPanelButtonTemplate"); all:SetSize(80, 18); all:SetPoint("RIGHT", -6, 0); all:SetText("all on/off")
    all:SetScript("OnClick", function()
      local anyOff = false
      for _, r in ipairs(g.rows) do if not C.set.ev[r.id] then anyOff = true end end
      for _, r in ipairs(g.rows) do C.set.ev[r.id] = anyOff end
      C.Touched("ev"); refreshAll()
    end)
    for _, e in ipairs(C.EVENTS) do
      if e.cat == cdef.key then
        local r = CreateFrame("Frame", nil, content); r:SetSize(600, 22); r.id = e.id
        r.cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate"); r.cb:SetSize(22, 22); r.cb:SetPoint("LEFT")
        r.cb:SetScript("OnClick", function(self) C.set.ev[e.id] = self:GetChecked() and true or false; C.Touched("ev"); refreshAll() end)
        local d = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); d:SetPoint("LEFT", 26, 0); d:SetWidth(390); d:SetJustifyH("LEFT"); d:SetWordWrap(false)
        d:SetText(e.desc .. "  " .. (FEAS[e.feas] or ""))
        r.ch = cycleButton(r, C.CHANNELS, function() return C.set.channel[e.id] end, function(v) C.set.channel[e.id] = v; C.Touched("channel") end, 80)
        r.ch:SetPoint("RIGHT", -40, 0)
        tinsert(g.rows, r)
      end
    end
    tinsert(groups, g)
  end
  -- default: option sections open, event categories collapsed
  for _, cdef in ipairs(C.EVENT_CATS) do if C.set.collapsed[cdef.key] == nil then C.set.collapsed[cdef.key] = true end end
  end
  C.SettingsBuildContent = function() if not built then built = true; buildContent() end end
  panel:SetScript("OnShow", function() C.SettingsBuildContent(); refreshAll() end)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
  end
  C.SettingsCategory = category
  if C.FriendsPage then C.FriendsPage.Build(category) end
  if C.DataPage then C.DataPage.Build(category) end
end
C.Init(build)

function C.OpenSettings()
  if category and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID())
  else C.Print("Settings API unavailable") end
end
C.SettingsRefresh = function() if refreshAll then refreshAll() end end
