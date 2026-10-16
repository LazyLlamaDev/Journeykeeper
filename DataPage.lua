-- "Data & Backups" Settings subcategory: status, snapshot list (verify/restore), export/import, migration log,
-- quarantine and module health. All actions go through C.Data (Data.lua).
local _, C = ...
local DP = {}; C.DataPage = DP
local D = C.Data
local panel, sub, rows, listContent, statusFS, detailFS, logFS, healthFS, ioFrame = nil, nil, {}, nil, nil, nil, nil, nil, nil
local ROW_H, LIST_H = 22, 176
local STATE = { ok = { "OK - saving normally", 0.3, 1, 0.3 }, readonly = { "READ-ONLY - your data is protected, nothing is written", 1, 0.4, 0.25 },
  empty_with_backup = { "DATA MISSING - backups found, restore offered", 1, 0.6, 0.2 }, restored = { "RESTORED - reload the UI to continue", 1, 0.82, 0 }, init = { "starting", 0.7, 0.7, 0.7 } }

local function btn(parent, text, w, fn) local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); b:SetSize(w, 20); b:SetText(text); b:SetScript("OnClick", fn); return b end
local function header(parent, text, y)
  local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", 8, y); h:SetText(text)
  local l = parent:CreateTexture(nil, "ARTWORK"); l:SetColorTexture(1, 0.82, 0, 0.25); l:SetHeight(1); l:SetPoint("TOPLEFT", 8, y - 16); l:SetPoint("TOPRIGHT", -8, y - 16)
end
local function kb(n) return n and (n >= 1024 and format("%.0f KB", n / 1024) or (n .. " B")) or "?" end

function DP.ShowIO(mode, text)
  if not ioFrame then
    ioFrame = CreateFrame("Frame", "JourneykeeperDataIO", UIParent, "ButtonFrameTemplate"); ioFrame:SetSize(620, 420); ioFrame:SetPoint("CENTER"); ioFrame:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "JourneykeeperDataIO")
    local sf = CreateFrame("ScrollFrame", nil, ioFrame, "UIPanelScrollFrameTemplate"); sf:SetPoint("TOPLEFT", 16, -64); sf:SetPoint("BOTTOMRIGHT", -34, 44)
    local eb = CreateFrame("EditBox", nil, sf); eb:SetMultiLine(true); eb:SetFontObject("ChatFontSmall"); eb:SetWidth(560); eb:SetAutoFocus(false); sf:SetScrollChild(eb)
    ioFrame.eb = eb
    ioFrame.go = btn(ioFrame, "Import (merge)", 140, function()
      local added, err = D.Import(eb:GetText())
      ioFrame.msg:SetText(added and format("|cff40ff40Imported: %d new memories (duplicates skipped). A pre-import backup was taken.|r", added) or ("|cffff6040Import failed: " .. tostring(err) .. " - nothing changed.|r"))
      DP.Refresh()
    end)
    ioFrame.go:SetPoint("BOTTOMRIGHT", -16, 14)
    ioFrame.msg = ioFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ioFrame.msg:SetPoint("BOTTOMLEFT", 16, 18); ioFrame.msg:SetWidth(430); ioFrame.msg:SetJustifyH("LEFT")
  end
  local f = ioFrame
  if f.TitleText then f.TitleText:SetText(mode == "export" and "Journeykeeper full export - Ctrl+A, Ctrl+C" or "Journeykeeper import - paste an export string") end
  f.eb:SetText(text or ""); f.go:SetShown(mode == "import"); f.msg:SetText(mode == "export" and format("%d characters, versioned + checksummed.", #(text or "")) or "Merges by stable memory id; nothing is overwritten.")
  f:Show(); f.eb:SetFocus(); if mode == "export" then f.eb:HighlightText() end
end

local function makeRow(i)
  local r = CreateFrame("Frame", nil, listContent); r:SetSize(700, ROW_H); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
  r.c = {}
  for k, spec in pairs({ date = { 6, 120 }, reason = { 130, 94 }, ver = { 228, 82 }, counts = { 314, 150 }, size = { 460, 44 }, state = { 506, 20 } }) do
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("LEFT", spec[1], 0); fs:SetWidth(spec[2]); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false); r.c[k] = fs
  end
  r.verify = btn(r, "Verify", 56, function() local ok, msg = D.Verify(r.item.snap); detailFS:SetText((ok and "|cff40ff40" or "|cffff6040") .. "Snapshot " .. date("%d %b %H:%M", r.item.snap.t) .. ": " .. msg .. "|r"); DP.Refresh() end)
  r.verify:SetPoint("LEFT", 528, 0)
  r.restore = btn(r, "Restore", 64, function()
    local ok, msg = D.Restore(r.item.snap); detailFS:SetText((ok and "|cff40ff40" or "|cffff6040") .. msg .. "|r"); DP.Refresh() end)
  r.restore:SetPoint("LEFT", r.verify, "RIGHT", 4, 0)
  return r
end

function DP.Refresh()
  if not statusFS then return end
  local st = STATE[D.state] or STATE.init
  statusFS:SetText(format("Status: %s", st[1])); statusFS:SetTextColor(st[2], st[3], st[4])
  local db = C.db or {}
  local c = D.Counts(db)
  local list = D.List()
  statusFS:SetText(statusFS:GetText() .. (D.VaultActive() and "   |cff40ff40· second backup file (Journeykeeper_Vault) active|r" or "   |cffffaa40· Journeykeeper_Vault not installed: backups share one file|r"))
  detailFS:SetText(detailFS:GetText() ~= "" and detailFS:GetText() or format("Schema %d (this version understands %d)  ·  %d memories, %d diary lines, %d deaths  ·  %d backups%s",
    D.DetectSchema(db), D.SCHEMA, c.entries, c.diary, c.deaths, #list, list[1] and ("  ·  newest " .. date("%d %b %H:%M", list[1].snap.t)) or ""))
  for i, it in ipairs(list) do
    rows[i] = rows[i] or makeRow(i); local r = rows[i]; r.item = it; local s = it.snap
    r.c.date:SetText(date("%d %b %Y %H:%M", s.t or 0)); r.c.reason:SetText((s.reason or "?") .. (it.slot == "pinned" and " *" or ""))
    r.c.ver:SetText(format("v%s / s%d", tostring(s.addon), s.schema or 0))
    local n = s.counts or {}; r.c.counts:SetText(format("%d mem · %d diary · %d deaths", n.entries or 0, n.diary or 0, n.deaths or 0))
    r.c.size:SetText(kb(s.size)); r.c.state:SetText(s.verified and "|cff40ff40ok|r" or "")
    r.restore:SetEnabled(D.state ~= "restored"); r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  listContent:SetHeight(math.max(LIST_H, #list * ROW_H)); DP.empty:SetShown(#list == 0)
  local log = {}
  for i = #(db.migrations or {}), math.max(1, #(db.migrations or {}) - 5), -1 do
    local m = db.migrations[i]
    if m then log[#log + 1] = format("%s  schema %d -> %d  %s  %s", date("%d %b %H:%M", m.t or 0), m.from or 0, m.to or 0, m.name or "", m.ok and "|cff40ff40ok|r" or ("|cffff6040" .. tostring(m.err) .. "|r")) end
  end
  logFS:SetText(#log > 0 and table.concat(log, "\n") or "|cff888888No migrations yet.|r")
  local h = {}
  h[#h + 1] = format("Quarantine: %d item(s) set aside, never deleted.", #(db.quarantine or {}))
  for k, err in pairs(D.disabled) do h[#h + 1] = "|cffff6040Paused this session:|r " .. k .. " - " .. err end
  for k, err in pairs(D.apiFail) do h[#h + 1] = "|cffffaa40API unavailable:|r " .. k .. " (" .. err .. ")" end
  for _, w in ipairs(D.warnings) do h[#h + 1] = "|cffff6040" .. w .. "|r" end
  if #h == 1 then h[#h + 1] = "|cff40ff40All modules healthy; no API failures this session.|r" end
  healthFS:SetText(table.concat(h, "\n"))
end

function DP.Build(parentCategory)
  panel = CreateFrame("Frame"); panel.name = "Data & Backups"; DP.panel = panel
  local built = false
  local function content()
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -16); title:SetText("Data & Backups")
  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); note:SetPoint("TOPLEFT", 16, -38)
  note:SetText("Your Journeykeeper journal is backed up on every logout/reload into two separate files. Nothing is ever deleted; damaged items go to quarantine.")
  local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate"); DP.sf = sf; sf:SetPoint("TOPLEFT", 8, -58); sf:SetPoint("BOTTOMRIGHT", -30, 8)
  local c = CreateFrame("Frame", nil, sf); c:SetSize(720, 760); sf:SetScrollChild(c) DP.content = c
  statusFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); statusFS:SetPoint("TOPLEFT", 8, -4)
  detailFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); detailFS:SetPoint("TOPLEFT", 8, -24); detailFS:SetWidth(700); detailFS:SetJustifyH("LEFT")
  local b1 = btn(c, "Back up now", 110, function() local s, e = D.Snapshot("manual"); detailFS:SetText(s and "|cff40ff40Backup taken.|r" or ("|cffff6040" .. e .. "|r")); DP.Refresh() end); b1:SetPoint("TOPLEFT", 8, -46)
  local b2 = btn(c, "Verify all", 100, function()
    local good, bad = 0, 0; for _, it in ipairs(D.List()) do if D.Verify(it.snap) then good = good + 1 else bad = bad + 1 end end
    detailFS:SetText(format("%s%d backup(s) verified, %d failed.|r", bad == 0 and "|cff40ff40" or "|cffff6040", good, bad)); DP.Refresh() end); b2:SetPoint("LEFT", b1, "RIGHT", 6, 0)
  local b3 = btn(c, "Export...", 90, function() DP.ShowIO("export", D.Export()) end); b3:SetPoint("LEFT", b2, "RIGHT", 6, 0)
  local b4 = btn(c, "Import...", 90, function() DP.ShowIO("import") end); b4:SetPoint("LEFT", b3, "RIGHT", 6, 0)
  local y = -80
  header(c, "Snapshots (newest first; * = pinned pre-migration restore point)", y); y = y - 24
  local hb = CreateFrame("Frame", nil, c); hb:SetSize(700, 18); hb:SetPoint("TOPLEFT", 8, y)
  local hbg = hb:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); hbg:SetColorTexture(1, 0.82, 0, 0.12)
  for _, h in ipairs({ { "Date", 6 }, { "Reason", 130 }, { "Version", 228 }, { "Contents", 314 }, { "Size", 460 }, { "Actions", 528 } }) do
    local fs = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("LEFT", h[2], 0); fs:SetText(h[1]) end
  y = y - 20
  local box = CreateFrame("Frame", nil, c, "InsetFrameTemplate"); box:SetSize(704, LIST_H + 4); box:SetPoint("TOPLEFT", 6, y)
  local lsf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate"); lsf:SetPoint("TOPLEFT", 2, -2); lsf:SetPoint("BOTTOMRIGHT", -24, 2)
  listContent = CreateFrame("Frame", nil, lsf); listContent:SetSize(700, LIST_H); lsf:SetScrollChild(listContent)
  DP.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable"); DP.empty:SetPoint("CENTER"); DP.empty:SetText("No backups yet - one is taken at every logout or /reload.")
  y = y - LIST_H - 16
  header(c, "Migration log", y); y = y - 24
  logFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); logFS:SetPoint("TOPLEFT", 14, y); logFS:SetWidth(690); logFS:SetJustifyH("LEFT"); y = y - 96
  header(c, "Integrity & health", y); y = y - 24
  healthFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); healthFS:SetPoint("TOPLEFT", 14, y); healthFS:SetWidth(690); healthFS:SetJustifyH("LEFT")
  local qb = btn(c, "Export quarantine", 130, function() DP.ShowIO("export", C.Codec.Serialize(C.db.quarantine or {})) end); qb:SetPoint("TOPRIGHT", -12, y + 4)
  end
  DP.BuildContent = function() if not built then built = true; content() end end
  -- v0.6.8: the Settings canvas sizes a subcategory panel only AFTER its first OnShow, so content built lazily
  -- inside that OnShow got a zero-sized scroll frame and stayed blank until the page was shown again.
  -- Build eagerly, and on every show re-run layout once the panel has its real size (next frame).
  DP.BuildContent()
  local function relayout()
    if not panel:IsShown() then return end
    if DP.sf and DP.content and C.FitScroll then C.FitScroll(panel, DP.sf, DP.content, 724) end
    if DP.sf and DP.sf.UpdateScrollChildRect then DP.sf:UpdateScrollChildRect() end
    DP.Refresh()
  end
  panel:SetScript("OnShow", function() DP.BuildContent(); detailFS:SetText(""); relayout(); C_Timer.After(0, relayout) end)
  panel:SetScript("OnSizeChanged", function() relayout() end)
  if parentCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then sub = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name); DP.category = sub end
end
function DP.Open() if sub and Settings.OpenToCategory then Settings.OpenToCategory(sub:GetID()) else C.Print("Settings API unavailable") end end

function DP.Command(cmd, rest)
  if cmd == "backup" then local s, e = D.Snapshot("manual"); C.Print(s and "backup taken" or e)
  elseif cmd == "verify" then for _, it in ipairs(D.List()) do local ok, msg = D.Verify(it.snap); C.Print(date("%d %b %H:%M", it.snap.t) .. " " .. (it.snap.reason or "") .. ": " .. msg) end
  elseif cmd == "exportall" then DP.ShowIO("export", D.Export())
  elseif cmd == "import" then DP.ShowIO("import")
  else DP.Open() end
end
