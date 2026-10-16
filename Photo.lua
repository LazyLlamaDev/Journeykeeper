-- Photo mode (Narcissus-inspired, minimal): out of combat only. Hides the UI (UIParent:Hide, never in combat),
-- optional camera preset (CameraZoomIn/Out + GetCameraZoom, restored afterwards), frame/vignette + caption overlay,
-- Screenshot(), then restores everything. The photo is linked to a journal entry by stable uid.
-- WoW cannot show screenshots in-game: the journal shows a placeholder card; the HTML tool links the real file.
local _, C = ...
local PH = {}; C.Photo = PH
local S = C.S
local overlay, busy, pendingRestore, savedZoom, timeoutTimer
local PRESETS = { none = nil, close = 4, medium = 10, wide = 22 }

local function uid(t, file) return "P" .. C.Codec.Checksum(tostring(t) .. "|" .. tostring(file) .. "|" .. C.charKey()) end
local function ext()
  local f = C.API("GetCVar", "screenshotFormat") or "jpeg"
  return f == "png" and "png" or (f == "tga" and "tga" or "jpg")
end
-- Screenshot() names files WoWScrnShot_MMDDYY_HHMMSS.<ext>; the event carries no name, so we derive it (+-1 s)
function PH.ExpectedName(t) return format("WoWScrnShot_%s.%s", date("%m%d%y_%H%M%S", t), ext()) end

local function buildOverlay()
  overlay = CreateFrame("Frame", "JourneykeeperPhotoOverlay", nil) -- parentless: stays visible while UIParent is hidden
  overlay:SetAllPoints(WorldFrame); overlay:SetFrameStrata("FULLSCREEN_DIALOG"); overlay:Hide()
  overlay.vig = overlay:CreateTexture(nil, "BACKGROUND"); overlay.vig:SetAllPoints(); overlay.vig:SetTexture(C.MEDIA .. "vignette")
  overlay.frame = overlay:CreateTexture(nil, "BORDER"); overlay.frame:SetPoint("TOPLEFT", 24, -24); overlay.frame:SetPoint("BOTTOMRIGHT", -24, 24)
  overlay.frame:SetTexture(C.MEDIA .. "border_ornate")
  overlay.cap = overlay:CreateFontString(nil, "OVERLAY"); overlay.cap:SetFont("Fonts\\MORPHEUS.TTF", 26, "OUTLINE"); overlay.cap:SetPoint("BOTTOM", 0, 52)
  overlay.cap:SetTextColor(1, 0.92, 0.75)
  overlay.sub = overlay:CreateFontString(nil, "OVERLAY"); overlay.sub:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE"); overlay.sub:SetPoint("TOP", overlay.cap, "BOTTOM", 0, -4)
  overlay.sub:SetTextColor(0.95, 0.85, 0.65)
end

function PH.Caption(entry)
  local zone, sub = GetRealZoneText() or "", GetSubZoneText() or ""
  local main = entry and entry.text and entry.text:gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1"):gsub("|H.-|h(.-)|h", "%1") or ((sub ~= "" and (sub .. ", ") or "") .. zone)
  return main, format("%s  ·  %s  ·  level %d  ·  %s", C.charKey():match("^[^-]+"), zone, UnitLevel("player") or 0, date("%d %B %Y"))
end

local function restore()
  if timeoutTimer and timeoutTimer.Cancel then timeoutTimer:Cancel() end; timeoutTimer = nil
  if overlay then overlay:Hide() end
  if savedZoom and C.Has("GetCameraZoom") then
    local now = C.API("GetCameraZoom") or savedZoom
    if now < savedZoom then C.API("CameraZoomOut", savedZoom - now) elseif now > savedZoom then C.API("CameraZoomIn", now - savedZoom) end
  end
  savedZoom = nil
  if InCombatLockdown() then pendingRestore = true; C.Print("combat started: the UI returns as soon as combat ends")
  else UIParent:Show(); pendingRestore = false end
  busy = false
end
PH.restore = restore
C.On("PLAYER_REGEN_ENABLED", function() if pendingRestore then UIParent:Show(); pendingRestore = false end end)
C.On("PLAYER_REGEN_DISABLED", function() if busy then PH.pending = nil; PH.session = nil; if overlay and overlay.EnableKeyboard then overlay:EnableKeyboard(false) end; restore() end end)

-- v0.6.8: Take() only ENTERS photo mode (UI hidden, overlay shown, player can move/turn the camera freely).
-- Nothing is captured until the player clicks the shutter (or the Snap key binding / "/jkp photo snap").
-- Exit with the X button, Escape, the photo key again (when "photoKeySnaps" is off) or "/jkp photo exit".
-- The overlay never takes the mouse except on its two small buttons; it is parentless, never secure.
local function ensureControls()
  if rawget(overlay, "shutter") then return end
  local function mk(w, label, tip, fn)
    local b = CreateFrame("Button", nil, overlay); b:SetSize(w, 30); b:SetFrameStrata("FULLSCREEN_DIALOG")
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.05, 0.02, 0.7)
    local edge = b:CreateTexture(nil, "BORDER"); edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetHeight(1); edge:SetColorTexture(0.85, 0.65, 0.3, 0.8)
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE"); b.fs:SetPoint("CENTER"); b.fs:SetTextColor(1, 0.9, 0.65); b.fs:SetText(label)
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function() bg:SetColorTexture(0.25, 0.14, 0.05, 0.85) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(0.08, 0.05, 0.02, 0.7) end)
    b.tip = tip
    return b
  end
  overlay.shutter = mk(110, "Take photo", nil, function() PH.Snap() end)
  overlay.shutter:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -150, 34)
  overlay.exit = mk(70, "Exit", nil, function() PH.Exit() end)
  overlay.exit:SetPoint("LEFT", overlay.shutter, "RIGHT", 8, 0)
  overlay.hint = overlay:CreateFontString(nil, "OVERLAY"); overlay.hint:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
  overlay.hint:SetPoint("BOTTOMRIGHT", overlay.exit, "TOPRIGHT", 0, 6); overlay.hint:SetTextColor(0.95, 0.85, 0.65)
  overlay.hint:SetText("Move freely. Esc to exit.")
  -- Escape exits; every other key passes through to the game (movement, camera). Out of combat only.
  overlay:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      if not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, false) end
      PH.Exit()
    elseif not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, true) end
  end)
end
local function controls(show)
  if not overlay or not rawget(overlay, "shutter") then return end
  overlay.shutter:SetShown(show); overlay.exit:SetShown(show); overlay.hint:SetShown(show)
end

function PH.Active() return busy and true or false end

-- entryIdx: journal entry to link (default: last echoed/last entry); preset: none|close|medium|wide
function PH.Take(entryIdx, preset)
  if not C.set.photoMode then C.Print("Photo mode is turned off in Settings"); return false end
  if busy then return false end
  if InCombatLockdown() or UnitAffectingCombat("player") then C.Print("photo mode is only available out of combat"); return false end
  if not C.Has("Screenshot") then C.Print("Screenshot() is not available"); return false end
  busy = true
  if not overlay then buildOverlay() end
  ensureControls()
  entryIdx = entryIdx or C.lastEchoEntry or C.lastEntry
  local entry = entryIdx and C.db.entries[entryIdx]
  local cap, sub = PH.Caption(entry)
  overlay.vig:SetShown(C.set.photoVignette); overlay.frame:SetShown(C.set.photoFrame)
  overlay.cap:SetShown(C.set.photoCaption); overlay.sub:SetShown(C.set.photoCaption)
  overlay.cap:SetText(cap); overlay.sub:SetText(sub)
  preset = preset or C.set.photoPreset
  local dist = PRESETS[preset]
  if dist and C.Has("GetCameraZoom") then
    savedZoom = C.API("GetCameraZoom")
    if savedZoom and savedZoom > dist then C.API("CameraZoomIn", savedZoom - dist) elseif savedZoom then C.API("CameraZoomOut", dist - savedZoom) end
  end
  if C.set.photoHideUI then UIParent:Hide() end
  overlay:Show(); controls(true)
  if overlay.EnableKeyboard then overlay:EnableKeyboard(true); pcall(overlay.SetPropagateKeyboardInput, overlay, true) end
  PH.session = { entry = entryIdx, cap = cap, sub = sub }
  C.Print("photo mode: frame your shot, then click 'Take photo' (or the Snap key binding / /jkp photo snap). Esc exits.")
  return true
end

-- shutter: hide our buttons for one frame, capture, then bring them back. Stays in photo mode.
function PH.Snap()
  if not busy or PH.pending then return false end
  if InCombatLockdown() then restore(); return false end
  local s = PH.session or {}
  controls(false)
  PH.pending = { entry = s.entry, cap = s.cap, sub = s.sub }
  C_Timer.After(C.set.photoDelay or 0.15, function()
    if not (busy and PH.pending) then return end
    PH.pending.t = time()
    C.API("Screenshot")
    timeoutTimer = C_Timer.NewTimer and C_Timer.NewTimer(3, function() if PH.pending then PH.Done(false) end end)
  end)
  return true
end

function PH.Exit()
  if not busy then return false end
  PH.pending = nil; PH.session = nil
  if overlay and overlay.EnableKeyboard then overlay:EnableKeyboard(false) end
  restore()
  return true
end

-- key binding: enters photo mode, or snaps when already in it
function PH.Key() if busy then return PH.Snap() end return PH.Take() end

function PH.Done(ok)
  local p = PH.pending; PH.pending = nil
  if timeoutTimer and timeoutTimer.Cancel then timeoutTimer:Cancel() end; timeoutTimer = nil
  if busy then controls(true) end
  if not (ok and p) then if p then C.Print("screenshot failed") end return end
  local file = PH.ExpectedName(p.t)
  local e = p.entry and C.db.entries[p.entry]
  local rec = { uid = uid(p.t, file), t = p.t, file = file, caption = p.cap, sub = p.sub, char = C.charKey(), zone = GetRealZoneText(),
    entryUid = e and e.uid, entryText = e and e.text }
  -- build the full record, then commit
  tinsert(C.db.photos, rec)
  if e then e.photo = rec.uid end
  C.Emit("photo_taken", format("%s captured a memory photo in %s.", C.charKey():match("^[^-]+"), GetRealZoneText() or "?"), { photo = rec.uid })
  C.Print(format("photo saved as Screenshots\\%s%s", file, e and " - linked to the memory" or ""))
  if overlay and rawget(overlay, "hint") then overlay.hint:SetText("Saved " .. file .. ". Another, or Esc to exit.") end
end
C.On("SCREENSHOT_SUCCEEDED", function() if PH.pending and PH.pending.t then PH.Done(true) end end)
C.On("SCREENSHOT_FAILED", function() if PH.pending then PH.Done(false) end end)

-- Journal: album section (appended to the Journey chapter)
function PH.AlbumBlocks(blocks, search)
  if #C.db.photos == 0 then return end
  tinsert(blocks, { kind = "chapterhead", text = "Album" })
  tinsert(blocks, { kind = "para", dropcap = true, text = "The game cannot show pictures inside the book; each card names the file in your Screenshots folder. The HTML export shows the real images." })
  for i = #C.db.photos, 1, -1 do
    local ph = C.db.photos[i]
    if search == "" or ((ph.caption or "") .. (ph.zone or "")):lower():find(search:lower(), 1, true) then
      tinsert(blocks, { kind = "heading", text = "[photo]  " .. (ph.caption or "A memory") })
      tinsert(blocks, (H and H.row or C.Journal.helpers.row)({ cat = "fun", t = ph.t, title = "Photo", text = format("%s  ·  Screenshots\\%s%s", ph.sub or C.dateStr(ph.t), ph.file, ph.entryText and ("  ·  " .. ph.entryText) or "") }))
    end
  end
end

-- small camera button (journal header, toasts); hidden when photo mode is off
function PH.Button(parent, getEntry)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(20, 20)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
  b:SetScript("OnClick", function() PH.Take(getEntry and getEntry() or nil) end)
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Photo mode"); GameTooltip:AddLine("Hide the UI and frame the moment; click Take photo when ready. The shot is linked to this memory.", 1, 1, 1, true); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetShown(C.set.photoMode)
  return b
end

-- key bindings (Bindings.xml) call into this small public table
BINDING_HEADER_JOURNEYKEEPER = "Journeykeeper"
BINDING_NAME_JOURNEYKEEPER_PHOTO = "Photo mode"
BINDING_NAME_JOURNEYKEEPER_PROFILE = "Profile of target"
BINDING_NAME_JOURNEYKEEPER_JOURNAL = "Open the journal"
BINDING_NAME_JOURNEYKEEPER_PHOTO_SNAP = "Photo mode: take photo"
JourneykeeperAPI = { Photo = { Take = function() return PH.Key() end, Snap = function() return PH.Snap() end, Exit = function() return PH.Exit() end },
  Profiles = { Show = function() return C.Profiles.Show() end }, Journal = { Toggle = function() return C.Journal.Toggle() end } }
