-- Atmosphere: vignette, minimap icon, ambient sounds. Own frames only.
local _, C = ...
local A = {}; C.Atmos = A
local vig, mm
A.unread = 0
local SOUNDS = {
  chime = { "UI_EPICLOOT_TOAST", 31578 },
  parchment = { "IG_QUEST_LIST_OPEN", 875 },
  horn = { "PVP_THROUGH_QUEUE", 8459 },
}
local function play(kind)
  local s = SOUNDS[kind]; if not s then return end
  local id = (SOUNDKIT and SOUNDKIT[s[1]]) or s[2]
  pcall(PlaySound, id, "SFX")
end

local function vignette()
  if not vig then
    vig = CreateFrame("Frame", nil, UIParent); vig:SetAllPoints(UIParent); vig:SetFrameStrata("BACKGROUND"); vig:EnableMouse(false)
    local t = vig:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetTexture(C.MEDIA .. "vignette")
    local ag = vig:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(0.45); a1:SetDuration(1.2); a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(0.45); a2:SetToAlpha(0); a2:SetDuration(2.5); a2:SetStartDelay(3); a2:SetOrder(2)
    ag:SetScript("OnFinished", function() vig:Hide() end)
    vig.ag = ag
  end
  vig:SetAlpha(0); vig:Show(); vig.ag:Stop(); vig.ag:Play()
end

function A.OnEcho(item)
  local strong = (item.score or 0) >= C.set.vignetteMin
  if C.set.vignette and strong then vignette() end
  if strong and C.set.ambient ~= "off" then play(C.set.ambient) end
  A.unread = A.unread + 1; A.UpdateMinimap()
end

-- Minimap button: NEVER parent to Minimap (secure hierarchy → ACTION_FORBIDDEN / "blocked from an
-- action only available to the Blizzard UI" when the click opens our journal or Settings).
-- Parent to MinimapCluster (or UIParent), position relative to Minimap. Default angle 225° (SW)
-- keeps us off the Issue Reporter "i" that sits on the SE rim. Drag to reposition; angle saved.
local DEFAULT_MM_ANGLE = 225
local function mmRadius()
  if not Minimap then return 80 end
  return (math.min(Minimap:GetWidth(), Minimap:GetHeight()) / 2) + 5
end
local function placeMinimap()
  if not mm or not Minimap then return end
  local ang = math.rad((C.set and C.set.mmAngle) or C.db.mmAngle or DEFAULT_MM_ANGLE)
  local r = mmRadius()
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(ang) * r, math.sin(ang) * r)
end
function A.PlaceMinimap() placeMinimap() end

local function buildMinimap()
  if not Minimap then return end
  local parent = (MinimapCluster and MinimapCluster) or UIParent
  mm = CreateFrame("Button", "JourneykeeperMinimapButton", parent)
  mm:SetSize(31, 31)
  mm:SetFrameStrata("MEDIUM")
  mm:SetFrameLevel((MinimapCluster and MinimapCluster.GetFrameLevel and MinimapCluster:GetFrameLevel() or 8) + 8)
  mm:SetMovable(true); mm:SetClampedToScreen(true)
  local ring = mm:CreateTexture(nil, "BACKGROUND"); ring:SetAllPoints(); ring:SetTexture(C.MEDIA .. "mm_ring")
  local ic = mm:CreateTexture(nil, "ARTWORK"); ic:SetSize(19, 19); ic:SetPoint("CENTER"); ic:SetTexture(C.MEDIA .. "icon_thread")
  mm.glow = mm:CreateTexture(nil, "OVERLAY"); mm.glow:SetSize(56, 56); mm.glow:SetPoint("CENTER"); mm.glow:SetTexture(C.MEDIA .. "glow"); mm.glow:SetBlendMode("ADD")
  mm.glow:SetVertexColor(1, 0.8, 0.4)
  local pulse = mm.glow:CreateAnimationGroup(); pulse:SetLooping("BOUNCE")
  local a = pulse:CreateAnimation("Alpha"); a:SetFromAlpha(0.2); a:SetToAlpha(0.9); a:SetDuration(1.1)
  mm.pulse = pulse
  mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mm:RegisterForDrag("LeftButton")
  mm:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then self:StartMoving() end
  end)
  mm:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if not Minimap then return end
    local mx, my = Minimap:GetCenter()
    local bx, by = self:GetCenter()
    if not mx or not bx then return end
    local scale = Minimap:GetEffectiveScale()
    local dx, dy = (bx - mx) * scale, (by - my) * scale
    -- atan2(y,x) → degrees; LibDBIcon convention (0° = east, CCW)
    local deg = math.deg(math.atan2(dy, dx)) % 360
    C.db.mmAngle = deg
    if C.set then C.set.mmAngle = deg end
    placeMinimap()
  end)
  mm:SetScript("OnClick", function(_, btn)
    if mm.isDragging then return end
    A.unread = 0; A.UpdateMinimap()
    if btn == "LeftButton" and IsShiftKeyDown() and C.set.minimapNoteClick and C.set.quickNotes then C.Notes.Prompt() return end
    if btn == "RightButton" then C.OpenSettings() else C.Journal.OpenTab("Echoes") end
  end)
  mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Journeykeeper", 1, 0.82, 0.3)
    GameTooltip:AddLine(A.unread > 0 and format("%d new echo%s", A.unread, A.unread == 1 and "" or "es") or "No new echoes", 0.9, 0.85, 0.75)
    GameTooltip:AddLine("Left-click: Echoes  ·  Right-click: settings", 0.6, 0.6, 0.6)
    if C.set.minimapNoteClick and C.set.quickNotes then GameTooltip:AddLine("Shift-click: quick note", 0.6, 0.6, 0.6) end
    GameTooltip:AddLine("Shift-drag: move icon on the rim", 0.55, 0.55, 0.55)
    GameTooltip:Show()
  end)
  mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
  placeMinimap()
  if Minimap then Minimap:HookScript("OnSizeChanged", function() placeMinimap() end) end
end

function A.UpdateMinimap()
  if not C.set.minimapIcon then if mm then mm:Hide() end return end
  if not mm then buildMinimap() end
  if not mm then return end
  placeMinimap()
  mm:Show()
  if A.unread > 0 then mm.glow:Show(); if not mm.pulse:IsPlaying() then mm.pulse:Play() end else mm.pulse:Stop(); mm.glow:Hide() end
end
C.Init(function() C_Timer.After(2, A.UpdateMinimap) end)
