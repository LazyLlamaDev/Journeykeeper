-- Person profiles (TRP3-lite, private, never sent): name, class, race/level when seen, guild, first met,
-- shared runs, rating, notes, tags. Only players already met are updated (on target/mouseover).
-- Open via modifier-click hint in the tooltip (TooltipDataProcessor elsewhere), /jkp who <name>, keybind.
local _, C = ...
local PR = {}; C.Profiles = PR
local S = C.S

function PR.Find(name)
  if not name or name == "" then return end
  local q = name:lower()
  for guid, p in pairs(C.db.players) do
    local n = (p.name or ""):lower()
    if n == q or n:match("^[^-]+") == q then return p, guid end
  end
end

local function update(unit)
  if not C.set.profiles or not UnitIsPlayer(unit) then return end
  local guid = S(UnitGUID(unit)); if not guid then return end
  local p = C.db.players[guid]; if not p then return end
  local race, lvl, guild = S(UnitRace(unit)), S(UnitLevel(unit)), S(GetGuildInfo(unit))
  if race then p.race = race end
  if lvl and lvl > 0 then p.level = lvl; p.levelSeen = time() end
  if guild then p.guild = guild end
end
C.On("PLAYER_TARGET_CHANGED", function() if UnitExists("target") then update("target") end end)
C.On("UPDATE_MOUSEOVER_UNIT", function() update("mouseover") end)

function PR.Rate(p, n) p.rating = math.max(0, math.min(5, tonumber(n) or 0)) end
function PR.Tag(p, tag)
  p.tags = p.tags or {}
  tag = tag:gsub("[^%w%-_ ]", ""):sub(1, 20)
  for i, t in ipairs(p.tags) do if t == tag then tremove(p.tags, i) return false end end
  if #p.tags < 8 then tinsert(p.tags, tag) end
  return true
end

function PR.ShareStatus(p)
  if not C.Share or not C.db.share then return nil end
  local peer = C.db.share.peers and C.db.share.peers[C.Share.norm(p.name or "")]
  local trusted = C.db.share.trusted and C.db.share.trusted[C.Share.norm(p.name or "")]
  if trusted then return "Journeykeeper friend" .. (peer and peer.ver and (" (v" .. peer.ver .. ")") or "") end
  if peer then return "uses Journeykeeper" .. (peer.ver and (" v" .. peer.ver) or "") end
end

function PR.Lines(p)
  local out = {}
  out[#out + 1] = format("%s%s%s", p.level and ("level " .. p.level .. " ") or "", p.race and (p.race .. " ") or "", p.class or "")
  if p.guild then out[#out + 1] = "<" .. p.guild .. ">" end
  out[#out + 1] = format("First met %s%s. Shared runs: %d.", p.first and C.dateStr(p.first) or "?", p.firstWhere and (" in " .. p.firstWhere) or "", p.count or 0)
  if p.last then out[#out + 1] = format("Last seen %s%s.", C.dateStr(p.last), p.lastWhere and (" in " .. p.lastWhere) or "") end
  if (p.rating or 0) > 0 then out[#out + 1] = "Rating: " .. string.rep("*", p.rating) .. string.rep("-", 5 - p.rating) end
  if p.tags and #p.tags > 0 then out[#out + 1] = "Tags: " .. table.concat(p.tags, ", ") end
  local ss = PR.ShareStatus(p); if ss then out[#out + 1] = ss end
  if type(p.notes) == "table" and #p.notes > 0 then out[#out + 1] = "Notes: \"" .. (p.notes[#p.notes].text or "") .. "\"" .. (#p.notes > 1 and format(" (+%d)", #p.notes - 1) or "") end
  return out
end

-- profile card (own frame, lazy)
local card
function PR.Show(name)
  if not C.set.profiles then C.Print("Person profiles are turned off in Settings"); return end
  if not name or name == "" then name = UnitExists("target") and S(UnitName("target")) end
  local p = PR.Find(name)
  if not p then C.Print("no one by that name in your journal yet"); return end
  if not card then
    card = CreateFrame("Frame", "JourneykeeperProfileCard", UIParent, "BackdropTemplate")
    card:SetSize(320, 300); card:SetPoint("CENTER", 300, 0); card:SetFrameStrata("DIALOG"); card:EnableMouse(true); card:SetMovable(true)
    card:RegisterForDrag("LeftButton"); card:SetScript("OnDragStart", card.StartMoving); card:SetScript("OnDragStop", card.StopMovingOrSizing)
    card.bg = card:CreateTexture(nil, "BACKGROUND"); card.bg:SetAllPoints(); card.bg:SetTexture(C.MEDIA .. "card")
    card.name = card:CreateFontString(nil, "OVERLAY"); card.name:SetFont("Fonts\\MORPHEUS.TTF", 22, ""); card.name:SetPoint("TOP", 0, -18); card.name:SetTextColor(0.45, 0.1, 0.05)
    card.body = card:CreateFontString(nil, "OVERLAY"); card.body:SetFont("Fonts\\FRIZQT__.TTF", 12, ""); card.body:SetPoint("TOPLEFT", 22, -54); card.body:SetWidth(276)
    card.body:SetJustifyH("LEFT"); card.body:SetTextColor(0.24, 0.16, 0.08); card.body:SetSpacing(3)
    local close = CreateFrame("Button", nil, card, "UIPanelCloseButtonNoScripts"); close:SetPoint("TOPRIGHT", -2, -2); close:SetScript("OnClick", function() card:Hide() end)
    local stars = {}
    for i = 1, 5 do
      local b = CreateFrame("Button", nil, card, "UIPanelButtonTemplate"); b:SetSize(26, 20); b:SetPoint("BOTTOMLEFT", 20 + (i - 1) * 28, 16); b:SetText(i)
      b:SetScript("OnClick", function() PR.Rate(card.p, (card.p.rating == i) and 0 or i); PR.Show(card.p.name) end); stars[i] = b
    end
  end
  card.p = p
  card.name:SetText(p.name or "?")
  card.body:SetText(table.concat(PR.Lines(p), "\n"))
  card:Show()
  return card
end

function PR.Command(rest)
  local cmd, a, b = rest:match("^(%S*)%s*(%S*)%s*(.*)$")
  if cmd == "who" then return PR.Show(a ~= "" and a or nil) end
  if cmd == "tag" then
    local p = PR.Find(a); if not p or b == "" then C.Print("usage: /jkp tag <name> <tag>") return end
    C.Print((PR.Tag(p, b) and "tagged " or "untagged ") .. p.name .. ": " .. b)
  elseif cmd == "rate" then
    local p = PR.Find(a); if not p then C.Print("usage: /jkp rate <name> <0-5>") return end
    PR.Rate(p, b); C.Print(p.name .. " rated " .. p.rating)
  end
end

function PR.Build(blocks, search, H)
  tinsert(blocks, { kind = "chapterhead", text = "Allies" })
  local list = {}
  for _, p in pairs(C.db.players) do
    local hay = ((p.name or "") .. " " .. (p.guild or "") .. " " .. table.concat(p.tags or {}, " ") .. " " .. (type(p.notes) == "table" and p.notes[1] and p.notes[#p.notes].text or "")):lower()
    if search == "" or hay:find(search:lower(), 1, true) then list[#list + 1] = p end
  end
  table.sort(list, function(a, b) if (a.rating or 0) ~= (b.rating or 0) then return (a.rating or 0) > (b.rating or 0) end return (a.count or 0) > (b.count or 0) end)
  if #list == 0 then tinsert(blocks, { kind = "para", dropcap = true, text = "No companions yet. Group with someone and their page begins." }) end
  if #list > 0 then tinsert(blocks, { kind = "dash", stats = { { "Companions", #list } } }) end
  for _, p in ipairs(list) do
    tinsert(blocks, H.row({ cat = "group", t = p.last, title = p.name or "?", text = H.clean(table.concat(PR.Lines(p), "  ·  ")), onClick = function() PR.Show(p.name) end }))
  end
end

C.Init(function()
  C.Journal.PROVIDERS.Allies = { enabled = function() return C.set.profiles end, build = PR.Build }
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
      if not (C.set.profiles and C.set.profileTooltip) or tt ~= GameTooltip then return end
      local _, unit = tt:GetUnit(); if not unit then return end
      local guid = S(UnitGUID(unit)); local p = guid and C.db.players[guid]
      if p and ((p.rating or 0) > 0 or (p.tags and #p.tags > 0)) then
        tt:AddLine(format("|cffd8b26aJourneykeeper:|r %s%s", (p.rating or 0) > 0 and string.rep("*", p.rating) .. " " or "", table.concat(p.tags or {}, ", ")))
      end
    end)
  end
end)
