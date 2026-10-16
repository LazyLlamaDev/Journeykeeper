-- "Friends & Sharing" Settings subcategory: player directory (from handshakes), add friend, trusted list,
-- and every sharing option grouped. Data lives in JourneykeeperDB.share (same as /jkp friend ...).
local _, C = ...
local FP = {}; C.FriendsPage = FP
local panel, sub, listRows, listContent, searchBox, trustedText, statusText, optRows = nil, nil, {}, nil, nil, nil, nil, {}
local sortKey, sortAsc = "seen", false
local ROW_H, LIST_H = 22, 198
local COLS = { -- key, label, x, width
  { "name", "Player", 6, 168 }, { "ver", "Ver", 178, 34 }, { "seen", "Last seen", 216, 76 }, { "src", "Source", 296, 58 },
  { "status", "Status", 358, 66 }, { "shared", "Shared", 428, 46 },
}
local BADGE = { Trusted = { 0.25, 0.75, 0.3 }, Known = { 0.45, 0.45, 0.5 }, Blocked = { 0.8, 0.2, 0.2 } }

local function ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 90 then return "just now" elseif d < 3600 then return format("%d min ago", d / 60) elseif d < 86400 then return format("%d h ago", d / 3600) end
  return format("%d d ago", d / 86400)
end
local function classColor(class)
  local c = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
  if c then return c.r, c.g, c.b end
  return 0.85, 0.85, 0.85
end
local function smallButton(parent, text, w, fn)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); b:SetSize(w, 18); b:SetText(text)
  if b.GetFontString and b:GetFontString() then b:GetFontString():SetFontObject("GameFontHighlightSmall") end
  b:SetScript("OnClick", fn); return b
end
local function sectionHeader(parent, text, y)
  local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", 8, y); h:SetText(text)
  local line = parent:CreateTexture(nil, "ARTWORK"); line:SetColorTexture(1, 0.82, 0, 0.25); line:SetHeight(1)
  line:SetPoint("TOPLEFT", 8, y - 16); line:SetPoint("TOPRIGHT", -8, y - 16)
  return h
end

---------------------------------------------------------------- data
function FP.Data()
  local rows, q = C.Share.Rows(), searchBox and searchBox:GetText():lower() or ""
  local out = {}
  for _, r in ipairs(rows) do if q == "" or r.name:lower():find(q, 1, true) then out[#out + 1] = r end end
  table.sort(out, function(a, b)
    local x, y = a[sortKey], b[sortKey]
    if x == y then return a.name < b.name end
    if x == nil then return false elseif y == nil then return true end
    if sortAsc then return x < y end
    return x > y
  end)
  return out
end
function FP.SetSort(k) if sortKey == k then sortAsc = not sortAsc else sortKey = k; sortAsc = (k == "name" or k == "src" or k == "status") end; FP.Refresh() end

---------------------------------------------------------------- list rows
local function makeRow(i)
  local r = CreateFrame("Button", nil, listContent); r:SetSize(700, ROW_H); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.08)
  r.cells = {}
  for c, col in ipairs(COLS) do
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("LEFT", col[3], 0); fs:SetWidth(col[4]); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    r.cells[col[1]] = fs
  end
  r.badge = r:CreateTexture(nil, "ARTWORK"); r.badge:SetSize(58, 15); r.badge:SetPoint("LEFT", COLS[5][3] - 3, 0)
  r.cells.status:SetJustifyH("CENTER"); r.cells.status:SetWidth(58); r.cells.status:ClearAllPoints(); r.cells.status:SetPoint("CENTER", r.badge)
  r.bTrust = smallButton(r, "Trust", 50, function() local n = r.data.name; if r.data.status == "Trusted" then C.Share.Untrust(n) else C.Share.Trust(n) end; FP.Refresh() end)
  r.bTrust:SetPoint("LEFT", 474, 0)
  r.bBlock = smallButton(r, "Block", 50, function() local n = r.data.name; if r.data.status == "Blocked" then C.Share.Unblock(n) else C.Share.Block(n) end; FP.Refresh() end)
  r.bBlock:SetPoint("LEFT", r.bTrust, "RIGHT", 2, 0)
  r.bRemove = smallButton(r, "Remove", 56, function() C.Share.Remove(r.data.name); FP.Refresh() end); r.bRemove:SetPoint("LEFT", r.bBlock, "RIGHT", 2, 0)
  r.bPing = smallButton(r, "Ping", 36, function() if C.Share.Ping(r.data.name) then statusText:SetText("Hello sent to " .. r.data.name .. " (queued, never in combat).") end end)
  r.bPing:SetPoint("LEFT", r.bRemove, "RIGHT", 2, 0)
  r:SetScript("OnEnter", function(self)
    local d = self.data; GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(d.name, classColor(d.class))
    GameTooltip:AddLine(d.ver and ("Journeykeeper v" .. d.ver) or "No handshake yet", 1, 1, 1)
    GameTooltip:AddLine(format("%d shared memor%s", d.shared, d.shared == 1 and "y" or "ies"), 1, 1, 1); GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end
local function fillRow(r, d)
  r.data = d
  r.cells.name:SetText(d.name); r.cells.name:SetTextColor(classColor(d.class))
  r.cells.ver:SetText(d.ver and ("v" .. d.ver) or "-")
  r.cells.seen:SetText(ago(d.seen)); r.cells.src:SetText(d.src or "-")
  r.cells.status:SetText(d.status); local b = BADGE[d.status]; r.badge:SetColorTexture(b[1], b[2], b[3], 0.55)
  r.cells.shared:SetText(d.shared > 0 and tostring(d.shared) or "-")
  r.bTrust:SetText(d.status == "Trusted" and "Untrust" or "Trust"); r.bTrust:SetEnabled(d.status ~= "Blocked")
  r.bBlock:SetText(d.status == "Blocked" and "Unblock" or "Block")
  r.bPing:SetEnabled(C.set.shareEnabled and d.status ~= "Blocked")
  r:Show()
end

function FP.Refresh()
  if not listContent then return end
  local data = FP.Data()
  for i, d in ipairs(data) do listRows[i] = listRows[i] or makeRow(i); fillRow(listRows[i], d) end
  for i = #data + 1, #listRows do listRows[i]:Hide() end
  listContent:SetHeight(math.max(LIST_H, #data * ROW_H))
  FP.empty:SetShown(#data == 0)
  local trusted = {}
  for n in pairs(C.db.share and C.db.share.trusted or {}) do trusted[#trusted + 1] = n end
  table.sort(trusted)
  trustedText:SetText(#trusted > 0 and table.concat(trusted, ",  ") or "|cff888888No trusted friends yet. Add one above or press Trust in the list.|r")
  for _, r in ipairs(optRows) do if r.w and r.w.Update then r.w.Update() end end
  FP.master:SetText(C.set.shareEnabled and "|cff40ff40Sharing is ON|r - only trusted friends receive your milestones." or "|cffff6040Sharing is OFF|r - nothing is sent. Incoming handshakes are still listed.")
  for _, h in ipairs(FP.headers) do h.arrow:SetText(h.key == sortKey and (sortAsc and "^" or "v") or "") end
  FP.lastData = data
end

---------------------------------------------------------------- build
function FP.Build(parentCategory)
  panel = CreateFrame("Frame"); panel.name = "Friends & Sharing"; FP.panel = panel
  local built = false
  local function content()
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -16); title:SetText("Friends & Sharing")
  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); note:SetPoint("TOPLEFT", 16, -38)
  note:SetText("Opt-in. Small milestone messages to trusted friends only; never in combat, no location unless you allow it.")
  local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate"); FP.sf = sf; sf:SetPoint("TOPLEFT", 8, -58); sf:SetPoint("BOTTOMRIGHT", -30, 8)
  local c = CreateFrame("Frame", nil, sf); c:SetSize(720, 1000); sf:SetScrollChild(c)
  local y = -4
  -- master line
  FP.master = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); FP.master:SetPoint("TOPLEFT", 8, y); y = y - 22
  -- 1) players
  sectionHeader(c, "Players running Journeykeeper", y); y = y - 24
  searchBox = CreateFrame("EditBox", nil, c, "SearchBoxTemplate"); searchBox:SetSize(180, 20); searchBox:SetPoint("TOPLEFT", 14, y)
  searchBox:SetScript("OnTextChanged", function(self) if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end; FP.Refresh() end)
  statusText = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); statusText:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
  statusText:SetText("Click a column header to sort.")
  y = y - 26
  FP.headers = {}
  local hb = CreateFrame("Frame", nil, c); hb:SetSize(700, 20); hb:SetPoint("TOPLEFT", 8, y)
  local hbg = hb:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); hbg:SetColorTexture(1, 0.82, 0, 0.12)
  for _, col in ipairs(COLS) do
    local b = CreateFrame("Button", nil, hb); b:SetSize(col[4], 20); b:SetPoint("LEFT", col[3], 0)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("LEFT"); fs:SetText(col[2])
    b.arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.arrow:SetPoint("LEFT", fs, "RIGHT", 3, 0)
    b.key = col[1]; b:SetScript("OnClick", function() FP.SetSort(col[1]) end)
    tinsert(FP.headers, b)
  end
  local act = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); act:SetPoint("LEFT", 474, 0); act:SetText("Actions")
  y = y - 22
  local box = CreateFrame("Frame", nil, c, "InsetFrameTemplate"); box:SetSize(704, LIST_H + 4); box:SetPoint("TOPLEFT", 6, y)
  local lsf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate"); lsf:SetPoint("TOPLEFT", 2, -2); lsf:SetPoint("BOTTOMRIGHT", -24, 2)
  listContent = CreateFrame("Frame", nil, lsf); listContent:SetSize(700, LIST_H); lsf:SetScrollChild(listContent)
  FP.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable"); FP.empty:SetPoint("CENTER")
  FP.empty:SetText("Nobody detected yet. Players appear here after a handshake (Ping, party or guild).")
  y = y - LIST_H - 14
  -- 2) add friend + trusted
  sectionHeader(c, "Trusted friends", y); y = y - 26
  local add = CreateFrame("EditBox", nil, c, "InputBoxTemplate"); add:SetSize(200, 20); add:SetPoint("TOPLEFT", 18, y); add:SetAutoFocus(false); add:SetMaxLetters(60)
  local hint = add:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("LEFT", 4, 0); hint:SetText("Name-Realm")
  add:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
  local function doAdd()
    local n = strtrim(add:GetText() or "")
    if n == "" then return end
    C.Share.Trust(n); add:SetText(""); add:ClearFocus(); statusText:SetText("Trusted " .. C.Share.norm(n) .. "."); FP.Refresh()
  end
  add:SetScript("OnEnterPressed", doAdd)
  local ab = CreateFrame("Button", nil, c, "UIPanelButtonTemplate"); ab:SetSize(110, 22); ab:SetPoint("LEFT", add, "RIGHT", 8, 0); ab:SetText("Add friend"); ab:SetScript("OnClick", doAdd)
  y = y - 28
  trustedText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); trustedText:SetPoint("TOPLEFT", 18, y); trustedText:SetWidth(680); trustedText:SetJustifyH("LEFT")
  y = y - 30
  -- 3) all sharing settings, grouped (two columns)
  sectionHeader(c, "Sharing settings", y); y = y - 26
  -- v0.6.9: single column. "What to share" and "Accept from" come after "Incoming" (they were cut off on the right).
  local ORDER = { ["Sharing"] = 1, ["Channels"] = 2, ["Incoming"] = 3, ["What to share"] = 4, ["Accept from"] = 5 }
  local secs = {}
  for i, sec in ipairs(C.OPTIONS) do if sec.page == "friends" then secs[#secs + 1] = { sec = sec, o = ORDER[sec.section] or (10 + i) } end end
  table.sort(secs, function(a, b) return a.o < b.o end)
  local colY = { y, y }; local col = 1
  for _, it in ipairs(secs) do local sec = it.sec
    local x = 10
    local g = CreateFrame("Frame", nil, c, "InsetFrameTemplate"); local h = 28 + #sec.items * 24
    g:SetSize(690, h); g:SetPoint("TOPLEFT", x, colY[col])
    local gt = g:CreateFontString(nil, "OVERLAY", "GameFontNormal"); gt:SetPoint("TOPLEFT", 8, -6); gt:SetText(sec.section)
    for i, o in ipairs(sec.items) do
      local r = C.OptionRow(o, g); r:SetSize(680, 24); r:SetPoint("TOPLEFT", 4, -22 - (i - 1) * 24)
      if r.lbl then r.lbl:SetWidth(440) end; optRows[#optRows + 1] = r
      if r.w and r.w.ClearAllPoints then r.w:ClearAllPoints(); r.w:SetPoint("RIGHT", r, "RIGHT", -4, 0) end
      if r.w and r.w.HookScript then r.w:HookScript("OnClick", function() FP.Refresh() end) end
    end
    colY[col] = colY[col] - h - 8
  end
  c:SetHeight(-colY[1] + 20)
  FP.content = c
  end
  FP.BuildContent = function() if not built then built = true; content() end end
  -- v0.6.8: the Settings canvas sizes a subcategory panel only AFTER its first OnShow, so content built lazily
  -- inside that OnShow got a zero-sized scroll frame and stayed blank until the page was shown again.
  -- Build eagerly, and on every show re-run layout once the panel has its real size (next frame).
  FP.BuildContent()
  local function relayout()
    if not panel:IsShown() then return end
    if FP.sf and FP.content and C.FitScroll then C.FitScroll(panel, FP.sf, FP.content, 724) end
    if FP.sf and FP.sf.UpdateScrollChildRect then FP.sf:UpdateScrollChildRect() end
    FP.Refresh()
  end
  panel:SetScript("OnShow", function() FP.BuildContent(); relayout(); C_Timer.After(0, relayout) end)
  panel:SetScript("OnSizeChanged", function() relayout() end)
  C.Share.OnPeersChanged = function() if panel:IsShown() then FP.Refresh() end end
  if parentCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
    sub = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
    FP.category = sub
  end
end
function FP.Open()
  if sub and Settings.OpenToCategory then Settings.OpenToCategory(sub:GetID()) else C.Print("Settings API unavailable") end
end
