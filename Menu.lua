-- Tiny reusable context menu (own frame). items = { {text=, func=, color={r,g,b}} }
local _, C = ...
local menu
function C.Menu(anchor, items, title)
  if not menu then
    menu = CreateFrame("Frame", "JourneykeeperMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP"); menu:SetClampedToScreen(true)
    menu:SetBackdrop({ bgFile = C.MEDIA .. "toast_dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu.btns = {}
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); menu.title:SetPoint("TOPLEFT", 12, -8)
    menu:SetScript("OnUpdate", function(self, el)
      if self:IsMouseOver(8, -8, -8, 8) or (self.anchor and self.anchor:IsMouseOver()) then self.away = 0 else self.away = (self.away or 0) + el; if self.away > 1.5 then self:Hide() end end
    end)
  end
  local y = title and -24 or -6
  menu.title:SetText(title or "")
  for _, b in ipairs(menu.btns) do b:Hide() end
  for i, it in ipairs(items) do
    local b = menu.btns[i]
    if not b then
      b = CreateFrame("Button", nil, menu); b:SetSize(236, 22)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); b.fs:SetPoint("LEFT", 8, 0)
      menu.btns[i] = b
    end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 7, y); y = y - 24
    b.fs:SetText(it.text); b.fs:SetTextColor(unpack(it.color or { 0.95, 0.92, 0.85 }))
    b:SetScript("OnClick", function() menu:Hide(); if it.func then it.func() end end)
    b:Show()
  end
  menu:SetSize(250, -y + 6)
  menu.anchor = anchor; menu.away = 0
  menu:ClearAllPoints()
  if anchor then menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 2) else menu:SetPoint("CENTER", UIParent, "CENTER") end
  menu:Show()
  return menu
end

-- common memory actions (used by toast + journal)
function C.MemoryMenuItems(item)
  local list = item.entries or (item.entry and { item.entry }) or {}
  local items = {}
  if #list > 0 then
    local pinned = C.db.entries[list[1]] and C.db.entries[list[1]].anchor
    tinsert(items, { text = pinned and "Unpin this moment" or (#list > 1 and "Pin these moments" or "Pin this moment"), func = function() C.Pin(list, not pinned) end, color = { 1, 0.85, 0.4 } })
    local arc = C.db.activeArc and C.db.arcs[C.db.activeArc]
    if arc then tinsert(items, { text = "Add to arc: " .. arc.name, func = function() C.ArcAdd(list) end }) end
    tinsert(items, { text = "Start a new arc with this...", func = function() C.ArcPrompt(list) end })
    tinsert(items, { text = "Open in journal", func = function() C.Journal.OpenAt(list[1]) end })
    local e1 = C.db.entries[list[1]]
    if #list == 1 and type(e1) == "table" and e1.id == "quick_note" and C.Notes then
      tinsert(items, { text = "Edit this note", func = function() C.Notes.Prompt(list[1]) end })
      tinsert(items, { text = "Archive this note (restore: /jkp note restore)", func = function() C.Notes.Archive(list[1]) end, color = { 1, 0.7, 0.5 } })
    end
  end
  if item.cat then
    tinsert(items, { text = "Remind me more about " .. ((C.CATS[item.cat] or {}).label or item.cat):lower(), func = function()
      C.set.catBoost[item.cat] = math.min(3, (C.set.catBoost[item.cat] or 0) + 1); C.Print("more " .. item.cat .. " echoes (boost " .. C.set.catBoost[item.cat] .. ")") end })
  end
  if item.key then tinsert(items, { text = "Never show this memory again", func = function() C.Echoes.Mute(item.key) end, color = { 1, 0.55, 0.45 } }) end
  return items
end
