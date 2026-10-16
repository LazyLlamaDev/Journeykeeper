-- Toast popups: custom art, slide+fade AnimationGroups, category accent, queue (max 3 waiting).
local _, C = ...
local T = {}; C.Toast = T
local queue, f, busy, cam = {}, nil, false, nil
local HOLD = 6
local SLIDE = 24
-- saved final position (after the slide-in); nil = default TOP 0,-174
T.PRESETS = {
  top = { "TOP", "TOP", 0, -150 - SLIDE },
  center = { "CENTER", "CENTER", 0, 120 },
  bottom = { "BOTTOM", "BOTTOM", 0, 200 },
}
local function pos()
  local p = C.set and C.set.toastPos
  if type(p) == "table" and p[1] then return p[1], p[2] or p[1], p[3] or 0, p[4] or 0 end
  local pr = T.PRESETS[C.set and C.set.toastAnchor or "top"] or T.PRESETS.top
  return pr[1], pr[2], pr[3], pr[4]
end
local function place(offset)
  local a, r, x, y = pos()
  f:ClearAllPoints(); f:SetPoint(a, UIParent, r, x, y + (offset or 0))
end
T.moveMode = false
local dragging, justDragged, holdToken = false, false, nil

local function build()
  local M = C.MEDIA
  f = CreateFrame("Frame", "JourneykeeperToast", UIParent)
  f:SetSize(400, 100); f:SetPoint("TOP", 0, -150); f:SetFrameStrata("HIGH"); f:Hide()
  f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetTexCoord(0, 1, 0, 100 / 128)
  f.glow = f:CreateTexture(nil, "BORDER"); f.glow:SetTexture(M .. "glow"); f.glow:SetSize(130, 130); f.glow:SetPoint("CENTER", f, "LEFT", 44, 0); f.glow:SetBlendMode("ADD")
  f.accent = f:CreateTexture(nil, "ARTWORK"); f.accent:SetTexture(M .. "accent"); f.accent:SetSize(10, 84); f.accent:SetPoint("LEFT", 8, 0)
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(54, 54); f.icon:SetPoint("LEFT", 20, 0)
  f.border = f:CreateTexture(nil, "OVERLAY"); f.border:SetTexture(M .. "border_ornate"); f.border:SetAllPoints(); f.border:SetTexCoord(0, 1, 0, 1)
  f.cat = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f.cat:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, 2)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", f.cat, "BOTTOMLEFT", 0, -2); f.title:SetWidth(300); f.title:SetJustifyH("LEFT")
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3); f.text:SetWidth(300); f.text:SetJustifyH("LEFT")
  -- animations
  local ain = f:CreateAnimationGroup()
  local a1 = ain:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.35)
  local t1 = ain:CreateAnimation("Translation"); t1:SetOffset(0, -24); t1:SetDuration(0.35); t1:SetSmoothing("OUT")
  ain:SetScript("OnFinished", function() place(0); f:SetAlpha(1); T.ScheduleOut() end)
  local aout = f:CreateAnimationGroup()
  local a2 = aout:CreateAnimation("Alpha"); a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.5)
  local t2 = aout:CreateAnimation("Translation"); t2:SetOffset(0, 18); t2:SetDuration(0.5); t2:SetSmoothing("IN")
  aout:SetScript("OnFinished", function() f:Hide(); busy = false; C_Timer.After(0.3, T.Next) end)
  f.inA, f.out = ain, aout
  f.dismiss = function() if not aout:IsPlaying() then ain:Stop(); aout:Play() end end
  f:EnableMouse(true)
  f:SetMovable(true); f:SetClampedToScreen(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if not (IsShiftKeyDown() or T.moveMode) then return end
    ain:Stop(); aout:Stop(); self:SetAlpha(1); dragging = true; self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    if not dragging then return end
    self:StopMovingOrSizing(); dragging = false; justDragged = true
    local a, _, r, x, y = self:GetPoint(1)
    C.set.toastPos = { a, r, floor(x + 0.5), floor(y + 0.5) }; C.set.toastAnchor = "custom"
    place(0); T.ScheduleOut()
  end)
  f:SetScript("OnMouseUp", function(_, btn)
    if justDragged then justDragged = false return end
    if T.moveMode then return end
    if btn == "RightButton" then T.Menu(f.item) return end
    if f.item and f.item.entry then C.Journal.OpenAt(f.item.entry) end
    f.dismiss()
  end)
  f:SetScript("OnEnter", function() f.x:Show() end)
  f:SetScript("OnLeave", function() if not f:IsMouseOver() then f.x:Hide() end end)
  f.x = CreateFrame("Button", nil, f, "UIPanelCloseButtonNoScripts"); f.x:SetSize(22, 22); f.x:SetPoint("TOPRIGHT", -6, -6); f.x:Hide()
  f.x:SetScript("OnClick", function() if T.moveMode then T.moveMode = false; C.Print("popup position locked") end; holdToken = nil; f.dismiss() end)
  -- v0.7.0: the hint sits between the left edge and the camera button, wraps to 2 lines max, and is short;
  -- "Shift-drag to move" is shown while hovering (it was clipped as one long line).
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.hint:SetPoint("BOTTOMLEFT", 16, 10); f.hint:SetPoint("BOTTOMRIGHT", -40, 10)
  f.hint:SetJustifyH("RIGHT"); f.hint:SetWordWrap(true); if f.hint.SetMaxLines then f.hint:SetMaxLines(2) end
  f:HookScript("OnEnter", function() if not T.moveMode then f.hint:SetText("Shift-drag to move") end end)
  f:HookScript("OnLeave", function() if not f:IsMouseOver() and f.hintText then f.hint:SetText(f.hintText) end end)
end

function T.HintText(item)
  if T.moveMode then return "Drag to move · X to lock" end
  return (item and item.entry) and "Click: open · Right-click: options" or "Right-click: options"
end

function T.Next()
  if busy then return end
  local item = tremove(queue, 1); if not item then return end
  if not f then build() end
  busy = true; f.item = item
  if C.Photo and not cam then cam = C.Photo.Button(f, function() return f.item and f.item.entry end); cam:SetPoint("BOTTOMRIGHT", -14, 10) end
  if cam then cam:SetShown(C.set.photoMode and item.entry ~= nil) end
  f.hintText = T.HintText(item)
  f.hint:SetText(f.hintText)
  local cat = C.CATS[item.cat] or C.CATS.zone
  local r, g, b = unpack(cat.color)
  local dark = C.set.toastStyle == "dark"
  f.bg:SetTexture(C.MEDIA .. (dark and "toast_dark" or "toast_parchment"))
  f.icon:SetTexture(cat.icon); f.accent:SetVertexColor(r, g, b); f.glow:SetVertexColor(r, g, b, 0.55)
  f.cat:SetText(cat.label:upper()); f.cat:SetTextColor(r, g, b)
  f.title:SetText(item.title or cat.label)
  f.title:SetTextColor(dark and 1 or 0.35, dark and 0.85 or 0.18, dark and 0.4 or 0.05)
  f.text:SetText(item.text or "")
  if dark then f.text:SetTextColor(0.92, 0.88, 0.8) else f.text:SetTextColor(0.2, 0.12, 0.05) end
  f:SetHeight(math.max(96, 46 + f.title:GetStringHeight() + f.text:GetStringHeight()))
  place(SLIDE); f:SetAlpha(0); f:Show(); f.inA:Play()
  if C.set.sound then PlaySound((SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST) or 31578, "SFX") end
end

function T.Show(item, text, title)
  if type(item) ~= "table" then item = { cat = item, text = text, title = title } end
  if #queue >= 3 then tremove(queue, 1) end
  tinsert(queue, item)
  T.Next()
end

-- context menu: pin / arcs / remind more / never show / open
function T.Menu(item)
  if not item then return end
  C.Menu(f, C.MemoryMenuItems(item), "This memory")
end

function T.ScheduleOut()
  local token = {}; holdToken = token
  C_Timer.After(HOLD, function()
    if holdToken ~= token or T.moveMode or dragging or f:IsMouseOver() then if holdToken == token and not T.moveMode and f:IsShown() then T.ScheduleOut() end return end
    if f.out and not f.out:IsPlaying() and f:IsShown() then f.out:Play() end
  end)
end

function T.SetPreset(name)
  if not T.PRESETS[name] then return false end
  C.set.toastPos = nil; C.set.toastAnchor = name
  if f and f:IsShown() then place(0) end
  C.Print("echo popups: " .. name)
  return true
end

function T.ResetPosition()
  C.set.toastPos = nil; C.set.toastAnchor = "top"
  if f and f:IsShown() then place(0) end
  C.Print("echo popup position reset")
end

function T.ToggleMove()
  T.moveMode = not T.moveMode
  if T.moveMode then
    T.Show({ cat = "zone", key = "move", title = "Drag me", text = "Drag this popup where you want echoes to appear, then type /jkp toast move again to lock it." })
    C.Print("popup unlocked: drag it, then /jkp toast move to lock (Shift-drag also works any time)")
  else
    C.Print("popup position locked")
    if f and f:IsShown() then T.ScheduleOut() end
  end
end

function T.Test()
  T.Show({ cat = "zone", key = "test", text = "You have stood here before - 12 Oct 2026, as a level 7 Orc Warrior. You have fallen here 2 times.", title = "Razor Hill", entry = #C.db.entries > 0 and #C.db.entries or nil })
end
