-- Book-style dialogue (DialogueUI-lite). OFF by default. Non-invasive: we only listen to QUEST_* events and read
-- GetTitleText/GetQuestText/GetObjectiveText/GetProgressText/GetRewardText. Blizzard's quest frame is never
-- replaced, re-parented, hooked or given scripts; accept/complete stay on Blizzard's own buttons.
-- Our own frames are parented to UIParent and only *positioned* next to QuestFrame.
local _, C = ...
local DG = {}; C.Dialogue = DG
local S = C.S
local current, btn, parch

local function clean(s) s = S(s); if not s then return "" end return (s:gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1"):gsub("\r", "")) end
local function questID() return S(GetQuestID and GetQuestID()) end
local function isStory(id)
  if C.set.dialogueAll then return true end
  if not id then return false end
  local cls = C.API("C_QuestInfoSystem.GetQuestClassification", id)
  if cls and Enum and Enum.QuestClassification then
    return cls == Enum.QuestClassification.Campaign or cls == Enum.QuestClassification.Important or cls == Enum.QuestClassification.Legendary
  end
  return C.API("C_CampaignInfo.IsCampaignQuest", id) and true or false
end

local function capture(stage)
  if not (C.set.dialogue) then return end
  local id = questID()
  local title = clean(GetTitleText())
  local body
  if stage == "detail" then body = clean(GetQuestText()); local o = clean(GetObjectiveText()); if o ~= "" then body = body .. "\n\n" .. o end
  elseif stage == "progress" then body = clean(GetProgressText())
  else body = clean(GetRewardText()) end
  current = { id = id, title = title, stage = stage, text = body }
  if C.set.dialogueCapture and body ~= "" and isStory(id) then DG.Store(current) end
  DG.ShowButton()
  if C.set.dialogueOverlay then DG.ShowParchment() end
end

function DG.Store(c)
  for _, q in ipairs(C.db.quests) do if q.id == c.id and q.stage == c.stage and q.char == C.charKey() then return false end end
  local rec = { t = time(), id = c.id, title = c.title, stage = c.stage, text = c.text:sub(1, 4000), char = C.charKey(), zone = GetRealZoneText() }
  rec.uid = "Q" .. C.Codec.Checksum(rec.char .. "|" .. tostring(rec.id) .. "|" .. rec.stage)
  tinsert(C.db.quests, rec)
  local verb = c.stage == "detail" and "took up" or (c.stage == "progress" and "returned to" or "completed")
  C.Emit("quest_story", format("%s %s the tale \"%s\".", C.charKey():match("^[^-]+"), verb, c.title), { quest = c.id, story = rec.uid })
  return true
end

C.On("QUEST_DETAIL", function() capture("detail") end)
C.On("QUEST_PROGRESS", function() capture("progress") end)
C.On("QUEST_COMPLETE", function() capture("complete") end)
C.On("QUEST_FINISHED", function() current = nil; if btn then btn:Hide() end; if parch then parch:Hide() end end)

local function anchorBeside(f, dx)
  f:ClearAllPoints()
  if QuestFrame and QuestFrame:IsShown() then f:SetPoint("TOPLEFT", QuestFrame, "TOPRIGHT", dx or 4, 0) else f:SetPoint("CENTER", 260, 60) end
end

function DG.ShowButton()
  if not btn then
    btn = CreateFrame("Button", "JourneykeeperReadButton", UIParent, "UIPanelButtonTemplate")
    btn:SetSize(140, 22); btn:SetText("Read in Journeykeeper"); btn:SetFrameStrata("HIGH")
    btn:SetScript("OnClick", function() DG.ShowParchment() end)
  end
  anchorBeside(btn, 4); btn:Show()
end

function DG.ShowParchment()
  if not current then return end
  if not parch then
    parch = CreateFrame("Frame", "JourneykeeperParchment", UIParent)
    parch:SetSize(380, 470); parch:SetFrameStrata("HIGH"); parch:EnableMouse(true)
    parch.bg = parch:CreateTexture(nil, "BACKGROUND"); parch.bg:SetAllPoints(); parch.bg:SetTexture(C.MEDIA .. "toast_parchment")
    parch.title = parch:CreateFontString(nil, "OVERLAY"); parch.title:SetFont("Fonts\\MORPHEUS.TTF", 22, ""); parch.title:SetPoint("TOP", 0, -26)
    parch.title:SetWidth(320); parch.title:SetTextColor(0.45, 0.1, 0.05)
    parch.body = parch:CreateFontString(nil, "OVERLAY"); parch.body:SetFont("Fonts\\FRIZQT__.TTF", 13, ""); parch.body:SetPoint("TOPLEFT", 30, -66)
    parch.body:SetWidth(320); parch.body:SetJustifyH("LEFT"); parch.body:SetJustifyV("TOP"); parch.body:SetTextColor(0.24, 0.16, 0.08); parch.body:SetSpacing(3)
    parch.hint = parch:CreateFontString(nil, "OVERLAY"); parch.hint:SetFont("Fonts\\FRIZQT__.TTF", 10, ""); parch.hint:SetPoint("BOTTOM", 0, 18)
    parch.hint:SetTextColor(0.45, 0.35, 0.22); parch.hint:SetText("Accept or complete with the quest window's own buttons.")
    local close = CreateFrame("Button", nil, parch, "UIPanelCloseButtonNoScripts"); close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() parch:Hide() end)
  end
  parch.title:SetText(current.title); parch.body:SetText(current.text)
  anchorBeside(parch, 150); parch:Show()
  return parch
end

-- Journal: full captured texts appear as "Tales" at the end of the Diary chapter.
function DG.Blocks(blocks, search)
  if #C.db.quests == 0 then return end
  tinsert(blocks, { kind = "chapterhead", text = "Tales" })
  for i = #C.db.quests, 1, -1 do
    local q = C.db.quests[i]
    if search == "" or (q.title or ""):lower():find(search:lower(), 1, true) then
      tinsert(blocks, { kind = "heading", text = q.title .. (q.stage == "complete" and " (ending)" or "") })
      tinsert(blocks, { kind = "para", text = (q.text or ""):gsub("\n+", " ") })
    end
  end
end
