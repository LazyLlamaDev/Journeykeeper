-- v0.7.1 quick notes: a few words straight into the journal, stamped with zone, time and character.
-- Entry points: /jkp note <text>, /note <text> (only when no other addon owns it), key binding, the journal's
-- Note button, Shift-click on the minimap icon. Notes are normal journal entries (id "quick_note"):
-- edit keeps the first wording in e.orig; delete only archives (e.archived), restore with /jkp note restore.
-- Also: Addon Compartment handlers (toc ## AddonCompartmentFunc*) and the key-binding API.
local _, C = ...
local N = {}; C.Notes = N
local MAXLEN = 500

local function clean(text)
  text = tostring(text or ""):gsub("|", "/"):gsub("^%s+", ""):gsub("%s+$", "")
  if #text > MAXLEN then text = text:sub(1, MAXLEN) end
  return text
end
N.Clean = clean

function N.Add(text)
  if not C.set.quickNotes then C.Print("quick notes are turned off (Settings > Quick Notes)") return nil end
  text = clean(text)
  if text == "" then N.Prompt() return nil end
  if not (C.Data and C.Data.writable) then C.Print("read-only mode: the note was not saved") return nil end
  local e = C.Emit("quick_note", text, { note = true })
  if not e then C.Print("quick notes are off in Settings > Social & Allies (Quick note event)") return nil end
  C.Print(format("note saved in %s.", e.zone ~= "" and e.zone or "the journal"))
  return e
end

local function noteAt(i) local e = C.db.entries[i]; if type(e) == "table" and e.id == "quick_note" then return e end end
N.Get = noteAt
function N.Edit(i, text)
  local e = noteAt(i); text = clean(text)
  if not e or text == "" then return false end
  if text == e.text then return true end
  e.orig = e.orig or e.text; e.text = text; e.edited = time()
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
  return true
end
function N.Archive(i)
  local e = noteAt(i); if not e or e.archived then return false end
  e.archived = time()
  C.Print("note moved to the archive (nothing deleted). Undo: /jkp note restore")
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
  return true
end
function N.Restore(i)
  if not i then -- newest archived note
    local best
    for k, e in ipairs(C.db.entries) do if type(e) == "table" and e.id == "quick_note" and e.archived and (not best or e.archived >= C.db.entries[best].archived) then best = k end end
    i = best
  end
  local e = noteAt(i); if not e or not e.archived then C.Print("no archived note to restore") return false end
  e.archived = nil; C.Print("note restored")
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
  return true
end
function N.List(archived)
  local out = {}
  for i, e in ipairs(C.db.entries) do if type(e) == "table" and e.id == "quick_note" and (not e.archived) == (not archived) then out[#out + 1] = i end end
  return out
end

-- small own prompt; used for new notes (i = nil) and edits
local np
function N.Prompt(i)
  if not C.set.quickNotes then C.Print("quick notes are turned off (Settings > Quick Notes)") return end
  if not np then
    np = CreateFrame("Frame", "JourneykeeperQuickNote", UIParent, "BasicFrameTemplateWithInset")
    np:SetSize(380, 84); np:SetPoint("CENTER", 0, 180); np:SetFrameStrata("FULLSCREEN_DIALOG")
    local eb = CreateFrame("EditBox", nil, np, "InputBoxTemplate"); eb:SetSize(340, 20); eb:SetPoint("BOTTOM", 0, 16); eb:SetAutoFocus(true); eb:SetMaxLetters(MAXLEN)
    eb:SetScript("OnEnterPressed", function(self)
      local t = self:GetText()
      if np.editIndex then N.Edit(np.editIndex, t) else N.Add(t) end
      self:SetText(""); np:Hide()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(""); np:Hide() end)
    np.eb = eb
    tinsert(UISpecialFrames, "JourneykeeperQuickNote")
  end
  np.editIndex = i
  local e = i and noteAt(i)
  if np.TitleText then np.TitleText:SetText(e and "Edit note" or ("Quick note - " .. (GetRealZoneText() or ""))) end
  np.eb:SetText(e and e.text or "")
  np:Show(); np.eb:SetFocus()
end

function N.Command(rest)
  local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  if sub == "restore" then N.Restore(tonumber(arg))
  elseif sub == "archive" and tonumber(arg) then N.Archive(tonumber(arg))
  elseif sub == "edit" and tonumber(arg:match("^%d+")) then local n, t = arg:match("^(%d+)%s*(.*)$"); if t ~= "" then N.Edit(tonumber(n), t) else N.Prompt(tonumber(n)) end
  elseif sub == "list" then
    local l = N.List(false)
    if #l == 0 then C.Print("no notes yet - /jkp note <text>") end
    for k = math.max(1, #l - 9), #l do local e = C.db.entries[l[k]]; C.Print(format("#%d  %s  %s: %s", l[k], date("%d %b %H:%M", e.t), e.zone or "", e.text)) end
  else N.Add(rest) end
end

-- /note only if nobody else has it (another addon or a future Blizzard command)
local function slashTaken(cmd)
  cmd = cmd:lower()
  for key in pairs(SlashCmdList) do
    if key ~= "JOURNEYKEEPER_NOTE" then
      for n = 1, 12 do local v = _G["SLASH_" .. key .. n]; if type(v) == "string" and v:lower() == cmd then return key end end
    end
  end
  if hash_SlashCmdList and hash_SlashCmdList[cmd:upper()] and hash_SlashCmdList[cmd:upper()] ~= SlashCmdList.JOURNEYKEEPER_NOTE then return "?" end
  return nil
end
N.SlashTaken = slashTaken
function N.RegisterSlash()
  if not C.set.noteSlash or N.slash then return N.slash end
  local owner = slashTaken("/note")
  if owner then N.slashOwner = owner; return false end
  SLASH_JOURNEYKEEPER_NOTE1 = "/note"
  SlashCmdList.JOURNEYKEEPER_NOTE = function(msg) N.Command(msg) end
  N.slash = true
  return true
end
C.On("PLAYER_LOGIN", function() if C.set then N.RegisterSlash() end end)

-- Addon Compartment (toc ## AddonCompartmentFunc / OnEnter / OnLeave)
function Journeykeeper_OnAddonCompartmentClick(_, button)
  if not C.set then return end
  if not C.set.compartment then C.Print("the Addon Compartment entry is turned off (Settings > Addon Compartment). /jkp opens the journal.") return end
  if button == "RightButton" then C.OpenSettings()
  elseif IsShiftKeyDown and IsShiftKeyDown() and C.set.quickNotes then N.Prompt()
  else C.Journal.Toggle() end
end
function Journeykeeper_OnAddonCompartmentEnter(_, frame)
  if not GameTooltip then return end
  GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
  GameTooltip:AddLine("Journeykeeper", 1, 0.82, 0.3)
  local n = C.Atmos and C.Atmos.unread or 0
  GameTooltip:AddLine(n > 0 and format("%d new echo%s", n, n == 1 and "" or "es") or "Echoes of your journey", 0.9, 0.85, 0.75)
  GameTooltip:AddLine("Click: journal  ·  Right-click: settings", 0.6, 0.6, 0.6)
  if C.set and C.set.quickNotes then GameTooltip:AddLine("Shift-click: quick note", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end
function Journeykeeper_OnAddonCompartmentLeave() if GameTooltip then GameTooltip:Hide() end end

-- key bindings (Bindings.xml); names shown under the "Journeykeeper" header in Key Bindings > AddOns
BINDING_NAME_JOURNEYKEEPER_JOURNEY = "Open the journey map"
BINDING_NAME_JOURNEYKEEPER_NOTE = "Quick note"
BINDING_NAME_JOURNEYKEEPER_FELLOWSHIP = "Open the Fellowship page"
C.Init(function()
  if not JourneykeeperAPI then return end
  JourneykeeperAPI.Journal.Journey = function() return C.Journal.OpenTab("Journey") end
  JourneykeeperAPI.Journal.Fellowship = function() return C.Journal.OpenTab("Fellowship") end
  JourneykeeperAPI.Notes = { Prompt = function() return N.Prompt() end }
end)
