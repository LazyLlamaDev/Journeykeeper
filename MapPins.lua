-- World map pins for memorable spots (death spots, account firsts).
-- Lightweight overlay: Frame (not Button) on the map canvas, positioned from normalized coords.
-- No data provider/pin-template mixins (those need XML templates and touch Blizzard's pin pools),
-- no hooks on Blizzard frames, and we never update while in combat lockdown.
local _, C = ...
local P = {}; C.MapPins = P
local pool, used, lastMap, lastScale = {}, 0, nil, nil

local function acquire(canvas)
  used = used + 1
  local pin = pool[used]
  if not pin then
    pin = CreateFrame("Frame", nil, canvas)
    pin:SetSize(20, 20); pin:EnableMouse(true)
    pin.tex = pin:CreateTexture(nil, "OVERLAY"); pin.tex:SetAllPoints(); pin.tex:SetTexture(C.MEDIA .. "pin_seal")
    pin.icon = pin:CreateTexture(nil, "OVERLAY", nil, 1); pin.icon:SetPoint("CENTER"); pin.icon:SetSize(12, 12)
    pin:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.title, 1, 0.82, 0.3)
      GameTooltip:AddLine(self.text, 0.9, 0.85, 0.75, true)
      if self.entry then GameTooltip:AddLine("Click to open in your journal", 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnMouseUp", function(self) if self.entry then C.Journal.OpenAt(self.entry) end end)
    pool[used] = pin
  end
  pin:SetParent(canvas)
  return pin
end

local function place(canvas, scale, x, y, cat, title, text, entry)
  local pin = acquire(canvas)
  local c = C.CATS[cat].color
  pin.tex:SetVertexColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8)
  pin.icon:SetTexture(C.CATS[cat].icon)
  pin.title, pin.text, pin.entry = title, text, entry
  -- counter-scale so pins keep a constant size while zooming; SetPoint offsets are in the pin's own scale, hence * scale
  pin:SetScale(1 / math.max(scale, 0.1))
  pin:ClearAllPoints()
  pin:SetPoint("CENTER", canvas, "TOPLEFT", (x / 100) * canvas:GetWidth() * scale, -(y / 100) * canvas:GetHeight() * scale)
  pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
  pin:Show()
end

local dots, dotsUsed = {}, 0
function P.Dot(canvas, scale)
  dotsUsed = dotsUsed + 1
  local d = dots[dotsUsed]
  if not d then
    d = CreateFrame("Frame", nil, canvas); d:SetSize(7, 7)
    d.tex = d:CreateTexture(nil, "OVERLAY"); d.tex:SetAllPoints(); d.tex:SetTexture(C.MEDIA .. "dot")
    d:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(self.title, 0.9, 0.85, 0.75); GameTooltip:Show() end)
    d:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dots[dotsUsed] = d
  end
  d:SetParent(canvas); d:SetScale(1 / math.max(scale, 0.1)); d:SetFrameLevel(canvas:GetFrameLevel() + 1900)
  return d
end

function P.Refresh(force)
  if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
  if InCombatLockdown() then return end
  local mapID = WorldMapFrame:GetMapID()
  local canvas = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  if not canvas or not mapID then return end
  local scale = WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
  if not force and mapID == lastMap and scale == lastScale then return end
  lastMap, lastScale = mapID, scale
  for i = 1, used do pool[i]:Hide() end
  for i = 1, dotsUsed do dots[i]:Hide() end
  used, dotsUsed = 0, 0
  if not C.set.mapPins then return end
  for _, d in ipairs(C.db.deathSpots) do
    if d.map == mapID and d.x then
      place(canvas, scale, d.x, d.y, "death", (d.char or "?"):match("^[^-]+") .. " fell here",
        format("%s, level %d%s", C.dateStr(d.t), d.level or 0, d.killer and (", slain by " .. d.killer) or ""), d.entry)
    end
  end
  if C.set.ghostTrail and C.Warband then
    for _, pt in ipairs(C.Warband.PointsFor(mapID, 400)) do
      local dot = P.Dot(canvas, scale)
      local c = C.Warband.Color(pt.ck)
      dot.tex:SetVertexColor(c[1], c[2], c[3], 0.55)
      dot:ClearAllPoints(); dot:SetPoint("CENTER", canvas, "TOPLEFT", (pt.x / 100) * canvas:GetWidth() * scale, -(pt.y / 100) * canvas:GetHeight() * scale)
      dot.title = pt.ck:match("^[^-]+") .. " passed here"
      dot:Show()
    end
  end
  if C.Journey then C.Journey.DrawOverlay(canvas, mapID, scale) end
  for i, e in ipairs(C.db.entries) do
    if e.map == mapID and e.x and (e.accountFirst or e.anchor or e.cat == "dungeon" or e.cat == "rare" or e.cat == "warband") then
      place(canvas, scale, e.x, e.y, e.cat, (C.CATS[e.cat] or {}).label or "Memory", e.text or "", i)
    end
  end
end

C.Init(function()
  local watcher = CreateFrame("Frame")
  local t = 0
  watcher:SetScript("OnUpdate", function(_, el)
    t = t + el; if t < 0.3 then return end; t = 0
    if WorldMapFrame and WorldMapFrame:IsShown() then P.Refresh() else lastMap = nil end
  end)
end)
