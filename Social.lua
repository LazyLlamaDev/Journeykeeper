-- Soft social: private ratings after a group ends. Nothing is sent to anyone.
-- Opt-in friend sharing lives in Share.lua / FriendsPage.lua.
local _, C = ...
local S = {}; C.Social = S
local prompt, pendingList

local function apply(rating)
  if not pendingList then return end
  local names = {}
  for _, m in ipairs(pendingList) do
    local p = C.db.players[m.guid]
    if p then p.rating = rating; p.ratedAt = time(); names[#names + 1] = (p.name or "?"):match("^[^-]+") end
  end
  local label = ({ great = "a great run", forgettable = "forgettable", avoid = "someone to avoid" })[rating]
  C.Emit("ally_rating", format("You remembered the group with %s as %s.", table.concat(names, ", "), label), { guids = pendingList })
  pendingList = nil
  if prompt then prompt:Hide() end
end

local function build()
  prompt = CreateFrame("Frame", "JourneykeeperRatePrompt", UIParent)
  prompt:SetSize(300, 86); prompt:SetPoint("BOTTOMRIGHT", -260, 220); prompt:SetFrameStrata("MEDIUM")
  local bg = prompt:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(C.MEDIA .. "toast_parchment"); bg:SetTexCoord(0, 1, 0, 0.67)
  local br = prompt:CreateTexture(nil, "OVERLAY"); br:SetAllPoints(); br:SetTexture(C.MEDIA .. "border_ornate")
  prompt.q = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormal"); prompt.q:SetPoint("TOPLEFT", 14, -12); prompt.q:SetWidth(272); prompt.q:SetJustifyH("LEFT")
  prompt.q:SetTextColor(0.35, 0.18, 0.05)
  local defs = { { "Great run", "great", { 0.2, 0.55, 0.2 } }, { "Forgettable", "forgettable", { 0.4, 0.33, 0.25 } }, { "Avoid", "avoid", { 0.6, 0.15, 0.1 } }, { "Skip", nil, { 0.45, 0.4, 0.35 } } }
  for i, d in ipairs(defs) do
    local b = CreateFrame("Button", nil, prompt); b:SetSize(66, 22); b:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 70, 12)
    local t = b:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(d[3][1], d[3][2], d[3][3], 0.85)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("CENTER"); fs:SetText(d[1])
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function() if d[2] then apply(d[2]) else pendingList = nil; prompt:Hide() end end)
  end
  prompt:Hide()
end

function S.OnGroupEnd(list)
  if not C.set.ratingPrompt then return end
  local keep = {}
  for _, m in ipairs(list) do if m.secs >= C.set.ratingMinMinutes * 60 and C.db.players[m.guid] then keep[#keep + 1] = m end end
  if #keep == 0 then return end
  pendingList = keep
  local show = function()
    if not prompt then build() end
    local names = {}
    for i = 1, math.min(4, #keep) do names[i] = (keep[i].name or "?"):match("^[^-]+") end
    prompt.q:SetText(format("How was the time with %s%s?", table.concat(names, ", "), #keep > 4 and " and others" or ""))
    prompt:Show()
    C_Timer.After(60, function() if prompt:IsShown() then prompt:Hide() end end)
  end
  if UnitAffectingCombat("player") then C_Timer.After(5, function() if not UnitAffectingCombat("player") then show() end end) else show() end
end
S.Apply = apply
