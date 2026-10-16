-- Threads: chains, player-made arcs, login digest.
local _, C = ...
local T = {}; C.Threads = T
local ORD = { "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth" }

function T.OnGraveReturn(d, i)
  if not C.set.threads then return end
  -- is this the character's first death spot?
  local firstIdx
  for k, s in ipairs(C.db.deathSpots) do if s.char == d.char then firstIdx = k; break end end
  if firstIdx ~= i or d.char ~= C.charKey() or (d.returns or 0) < 2 then return end
  local ord = ORD[d.returns] or (d.returns .. "th")
  C.Emit("thread_return", format("You returned for the %s time to where you first fell.", ord), { entryRef = d.entry }, {
    title = "A thread", key = "thread" .. i .. "_" .. d.returns, meta = { first = true, entry = d.entry },
    text = C.Tpl("thread_grave", { ord = ord, Ord = ord:gsub("^%l", string.upper) }) })
end

---------------------------------------------------------------- arcs
function C.ArcNew(name, list)
  if not name or name == "" then C.Print("usage: /jkp arc new <name>") return end
  tinsert(C.db.arcs, { name = name, created = time(), char = C.charKey(), entries = {} })
  C.db.activeArc = #C.db.arcs
  C.Print("new arc: " .. name .. " (now active)")
  if list then C.ArcAdd(list) end
end
function C.ArcAdd(list, arcIdx)
  local arc = C.db.arcs[arcIdx or C.db.activeArc or 0]
  if not arc then C.Print("no active arc - /jkp arc new <name>") return end
  for _, i in ipairs(list) do
    local dup = false
    for _, j in ipairs(arc.entries) do if j == i then dup = true end end
    if not dup and C.db.entries[i] then tinsert(arc.entries, i) end
  end
  table.sort(arc.entries)
  C.Emit("arc_add", format("You added %d moment%s to the arc \"%s\".", #list, #list == 1 and "" or "s", arc.name))
end
local arcPrompt
function C.ArcPrompt(list)
  if not arcPrompt then
    arcPrompt = CreateFrame("Frame", "JourneykeeperArcPrompt", UIParent, "BasicFrameTemplateWithInset")
    arcPrompt:SetSize(320, 80); arcPrompt:SetPoint("CENTER", 0, 160); arcPrompt:SetFrameStrata("FULLSCREEN_DIALOG")
    arcPrompt.TitleText:SetText("Name your new arc")
    local eb = CreateFrame("EditBox", nil, arcPrompt, "InputBoxTemplate"); eb:SetSize(280, 20); eb:SetPoint("BOTTOM", 0, 16); eb:SetAutoFocus(true)
    eb:SetScript("OnEnterPressed", function(self) C.ArcNew(self:GetText(), arcPrompt.list); self:SetText(""); arcPrompt:Hide() end)
    eb:SetScript("OnEscapePressed", function() arcPrompt:Hide() end)
    arcPrompt.eb = eb
  end
  arcPrompt.list = list; arcPrompt:Show(); arcPrompt.eb:SetFocus()
end
-- v0.6.9: arc editing. All fields are optional additions to the arc record (old versions simply ignore them):
--   note (string), startT/endT (unix time; nil = open), archived (bool) + archivedAt, removed (indices taken out, restorable),
--   edited (time). Nothing is ever hard-deleted: "Delete" archives the arc, Undo/restore brings it back unchanged.
local function trim(x) return ((x or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function arcAt(i) local a = C.db.arcs[tonumber(i) or 0]; if type(a) == "table" then return a end end
function C.ParseDay(s, endOfDay)
  s = trim(s)
  if s == "" then return nil, true end
  local y, m, d = s:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not (y and m and d) or m < 1 or m > 12 or d < 1 or d > 31 then return nil, false end
  return time({ year = y, month = m, day = d, hour = endOfDay and 23 or 0, min = endOfDay and 59 or 0, sec = endOfDay and 59 or 0 }), true
end
function C.ArcUpdate(i, f)
  local a = arcAt(i); if not a then return false, "no such arc" end
  if f.name ~= nil then local n = trim(f.name); if n == "" then return false, "the arc needs a name" end; a.name = n end
  if f.note ~= nil then a.note = f.note ~= "" and f.note or nil end
  if f.startT ~= nil then a.startT = f.startT or nil end
  if f.endT ~= nil then a.endT = f.endT or nil end
  if f.clearStart then a.startT = nil end
  if f.clearEnd then a.endT = nil end
  if a.startT and a.endT and a.endT < a.startT then a.startT, a.endT = a.endT - 86399, a.startT + 86399 end
  a.edited = time()
  return true
end
function C.ArcRemoveEntry(i, entryIdx)
  local a = arcAt(i); if not a then return false end
  for k, j in ipairs(a.entries) do if j == entryIdx then
    tremove(a.entries, k); a.removed = a.removed or {}; tinsert(a.removed, entryIdx); a.edited = time(); return true end end
  return false
end
function C.ArcRestoreEntry(i, entryIdx)
  local a = arcAt(i); if not a then return false end
  for k, j in ipairs(a.removed or {}) do if j == entryIdx then tremove(a.removed, k); tinsert(a.entries, entryIdx); table.sort(a.entries); a.edited = time(); return true end end
  return false
end
function C.ArcArchive(i)
  local a = arcAt(i); if not a or a.archived then return false end
  a.archived, a.archivedAt = true, time()
  if C.db.activeArc == tonumber(i) then C.db.activeArc = nil end
  C.lastArchivedArc = tonumber(i)
  C.Print(format("arc \"%s\" moved to the archive (nothing deleted). Undo: /jkp arc restore %d", a.name or "?", i))
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
  return true
end
function C.ArcRestore(i)
  i = tonumber(i) or C.lastArchivedArc
  local a = arcAt(i); if not a or not a.archived then return false end
  a.archived, a.archivedAt = nil, nil
  C.Print(format("arc \"%s\" restored", a.name or "?"))
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
  return true
end
-- arc moments after the optional start/end range
function C.ArcEntries(a)
  local out = {}
  for _, i in ipairs(a.entries or {}) do
    local e = C.db.entries[i]
    if e and (not a.startT or (e.t or 0) >= a.startT) and (not a.endT or (e.t or 0) <= a.endT) then out[#out + 1] = i end
  end
  return out
end

-- editor (own frame)
local ed
local function day(t) return t and date("%Y-%m-%d", t) or "" end
function C.ArcEdit(i)
  local a = arcAt(i); if not a then C.Print("no such arc"); return end
  if not ed then
    ed = CreateFrame("Frame", "JourneykeeperArcEditor", UIParent, "BasicFrameTemplateWithInset")
    ed:SetSize(460, 470); ed:SetPoint("CENTER", 0, 40); ed:SetFrameStrata("FULLSCREEN_DIALOG"); ed:SetToplevel(true)
    ed:SetMovable(true); ed:EnableMouse(true); ed:RegisterForDrag("LeftButton")
    ed:SetScript("OnDragStart", ed.StartMoving); ed:SetScript("OnDragStop", ed.StopMovingOrSizing)
    tinsert(UISpecialFrames, "JourneykeeperArcEditor")
    local function lbl(text, y) local f = ed:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f:SetPoint("TOPLEFT", 16, y); f:SetText(text); return f end
    local function box(w, y, x) local e = CreateFrame("EditBox", nil, ed, "InputBoxTemplate"); e:SetSize(w, 20); e:SetPoint("TOPLEFT", x or 20, y); e:SetAutoFocus(false); e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end); return e end
    lbl("Title", -32); ed.name = box(410, -46); ed.name:SetMaxLetters(80)
    lbl("Notes", -74)
    local nb = CreateFrame("Frame", nil, ed, "InsetFrameTemplate"); nb:SetPoint("TOPLEFT", 14, -88); nb:SetSize(428, 74)
    local nsf = CreateFrame("ScrollFrame", nil, nb, "UIPanelScrollFrameTemplate"); nsf:SetPoint("TOPLEFT", 6, -6); nsf:SetPoint("BOTTOMRIGHT", -26, 6)
    ed.note = CreateFrame("EditBox", nil, nsf); ed.note:SetMultiLine(true); ed.note:SetFontObject("ChatFontNormal"); ed.note:SetWidth(390); ed.note:SetAutoFocus(false); ed.note:SetMaxLetters(1000)
    ed.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end); nsf:SetScrollChild(ed.note)
    nb:EnableMouse(true); nb:SetScript("OnMouseDown", function() ed.note:SetFocus() end)
    lbl("From (YYYY-MM-DD, empty = open)", -170); ed.from = box(120, -184)
    local tl = ed:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); tl:SetPoint("TOPLEFT", 230, -170); tl:SetText("To")
    ed.to = box(120, -184, 234)
    lbl("Moments in this arc (uncheck to take out; nothing is deleted)", -214)
    local lb = CreateFrame("Frame", nil, ed, "InsetFrameTemplate"); lb:SetPoint("TOPLEFT", 14, -228); lb:SetSize(428, 172)
    local lsf = CreateFrame("ScrollFrame", nil, lb, "UIPanelScrollFrameTemplate"); lsf:SetPoint("TOPLEFT", 4, -4); lsf:SetPoint("BOTTOMRIGHT", -26, 4)
    ed.list = CreateFrame("Frame", nil, lsf); ed.list:SetSize(396, 160); lsf:SetScrollChild(ed.list); ed.rows = {}
    ed.msg = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ed.msg:SetPoint("BOTTOMLEFT", 16, 40); ed.msg:SetWidth(428); ed.msg:SetJustifyH("LEFT")
    local function b(text, w, fn) local x = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate"); x:SetSize(w, 22); x:SetText(text); x:SetScript("OnClick", fn); return x end
    ed.save = b("Save", 90, function() C.ArcEditSave() end); ed.save:SetPoint("BOTTOMRIGHT", -14, 12)
    ed.cancel = b("Close", 80, function() ed:Hide() end); ed.cancel:SetPoint("RIGHT", ed.save, "LEFT", -6, 0)
    ed.active = b("Make active", 100, function() C.db.activeArc = ed.idx; ed.msg:SetText("|cff40ff40This arc is now active: click moments in the book to add them.|r"); if C.Journal then C.Journal.Refresh() end end)
    ed.active:SetPoint("BOTTOMLEFT", 14, 12)
    ed.del = b("Delete...", 90, function()
      if not ed.confirm then ed.confirm = true; ed.del:SetText("Confirm?"); ed.msg:SetText("|cffff8040Click 'Confirm?' to archive this arc. It can be restored any time (Arcs page or /jkp arc restore).|r"); return end
      C.ArcArchive(ed.idx); ed:Hide()
    end)
    ed.del:SetPoint("LEFT", ed.active, "RIGHT", 6, 0)
    ed:SetScript("OnHide", function() ed.confirm = nil end)
  end
  ed.idx = tonumber(i); ed.confirm = nil; ed.del:SetText("Delete...")
  if ed.TitleText then ed.TitleText:SetText("Edit arc") end
  ed.name:SetText(a.name or ""); ed.note:SetText(a.note or ""); ed.from:SetText(day(a.startT)); ed.to:SetText(day(a.endT))
  ed.msg:SetText(a.archived and "|cffffaa40This arc is archived.|r" or "")
  -- moment list: current + removed (unchecked)
  local items = {}
  for _, j in ipairs(a.entries or {}) do items[#items + 1] = { j, true } end
  for _, j in ipairs(a.removed or {}) do items[#items + 1] = { j, false } end
  table.sort(items, function(x, y) return x[1] < y[1] end)
  for _, r in ipairs(ed.rows) do r:Hide() end
  for k, it in ipairs(items) do
    local r = ed.rows[k]
    if not r then
      r = CreateFrame("CheckButton", nil, ed.list, "UICheckButtonTemplate"); r:SetSize(20, 20); ed.rows[k] = r
      r.fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.fs:SetPoint("LEFT", r, "RIGHT", 2, 0); r.fs:SetWidth(368); r.fs:SetJustifyH("LEFT"); r.fs:SetWordWrap(false)
    end
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 2, -(k - 1) * 22)
    local e = C.db.entries[it[1]] or {}
    r.fs:SetText(format("%s  %s", e.t and date("%d %b %Y", e.t) or "?", ((e.text or "?"):gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1"):gsub("|H.-|h(.-)|h", "%1"))))
    r:SetChecked(it[2]); r.entry = it[1]; r:Show()
  end
  ed.list:SetHeight(math.max(160, #items * 22))
  ed:Show()
  return ed
end
function C.ArcEditSave()
  if not ed or not ed.idx then return false end
  local s, okS = C.ParseDay(ed.from:GetText(), false)
  local e, okE = C.ParseDay(ed.to:GetText(), true)
  if not okS or not okE then ed.msg:SetText("|cffff6040Dates must look like 2026-11-04 (or stay empty).|r"); return false end
  local ok, err = C.ArcUpdate(ed.idx, { name = ed.name:GetText() or "", note = ed.note:GetText() or "", startT = s or false, endT = e or false, clearStart = not s, clearEnd = not e })
  if not ok then ed.msg:SetText("|cffff6040" .. err .. "|r"); return false end
  for _, r in ipairs(ed.rows) do if r:IsShown() then
    if r:GetChecked() then C.ArcRestoreEntry(ed.idx, r.entry) else C.ArcRemoveEntry(ed.idx, r.entry) end
  end end
  ed.msg:SetText("|cff40ff40Saved.|r")
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
  return true
end

function T.ArcCommand(rest)
  local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  if sub == "new" then C.ArcNew(arg)
  elseif sub == "add" then C.ArcAdd({ tonumber(arg) or C.lastEntry })
  elseif sub == "edit" then C.ArcEdit(tonumber(arg) or C.db.activeArc)
  elseif sub == "delete" and tonumber(arg) then C.ArcArchive(tonumber(arg))
  elseif sub == "restore" then if not C.ArcRestore(tonumber(arg)) then C.Print("nothing to restore") end
  elseif sub == "rename" then local n, name = arg:match("^(%d+)%s+(.+)$"); if n and C.ArcUpdate(tonumber(n), { name = name }) then C.Print("renamed") else C.Print("usage: /jkp arc rename <n> <name>") end
  elseif sub == "use" and tonumber(arg) then C.db.activeArc = tonumber(arg); C.Print("active arc: " .. ((C.db.arcs[tonumber(arg)] or {}).name or "?"))
  else
    C.Print("arcs: /jkp arc new <name> | add [entry#] | use <n> | edit <n> | rename <n> <name> | delete <n> | restore [n]")
    for i, a in ipairs(C.db.arcs) do C.Print(format("  %d. %s (%d moments)%s%s", i, a.name, #a.entries, i == C.db.activeArc and " *" or "", a.archived and "  [archived]" or "")) end
  end
end

---------------------------------------------------------------- digest
local panel
local function digestLines()
  local since = C.cdb.lastLogout
  local lines, me = {}, C.charKey()
  local away = time() - since
  local days, hours = floor(away / 86400), floor((away % 86400) / 3600)
  tinsert(lines, format("You have been away %s.", days > 0 and format("%d day%s and %d hour%s", days, days == 1 and "" or "s", hours, hours == 1 and "" or "s") or format("%d hour%s", hours, hours == 1 and "" or "s")))
  local per = {}
  for i, e in ipairs(C.db.entries) do
    if e.t > since and e.char ~= me then
      local p = per[e.char] or { n = 0, best = nil, bw = -99 }; per[e.char] = p
      p.n = p.n + 1
      local w = C.EntryWeight(e); if w > p.bw then p.bw, p.best = w, e end
    end
  end
  for ck, p in pairs(per) do
    tinsert(lines, format("Meanwhile, %s wrote %d new line%s. Most memorable: %s", ck:match("^[^-]+"), p.n, p.n == 1 and "" or "s",
      ((p.best.text or ""):gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1"):gsub("|H.-|h(.-)|h", "%1"))))
  end
  local today = date("*t")
  for _, e in ipairs(C.db.entries) do
    local d = date("*t", e.t)
    if d.month == today.month and d.day == today.day and d.year < today.year and C.EntryWeight(e) >= 4 then
      tinsert(lines, format("On this day %d year%s ago: %s", today.year - d.year, today.year - d.year == 1 and "" or "s", e.text)); break
    end
  end
  local pinned = 0
  for _, e in ipairs(C.db.entries) do if e.anchor then pinned = pinned + 1 end end
  if pinned > 0 then tinsert(lines, format("You carry %d pinned moment%s.", pinned, pinned == 1 and "" or "s")) end
  return lines
end
function T.ShowDigest(lines)
  if not panel then
    panel = CreateFrame("Frame", "JourneykeeperDigest", UIParent); panel:SetSize(460, 240); panel:SetPoint("CENTER", 0, 120); panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true); panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving); panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    local bg = panel:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(C.MEDIA .. "card")
    local br = panel:CreateTexture(nil, "OVERLAY"); br:SetAllPoints(); br:SetTexture(C.MEDIA .. "border_ornate")
    panel.title = panel:CreateFontString(nil, "OVERLAY"); panel.title:SetFont("Fonts\\MORPHEUS.TTF", 22, ""); panel.title:SetPoint("TOP", 0, -18)
    panel.title:SetTextColor(0.5, 0.1, 0.04); panel.title:SetText("Since you were last here")
    local dv = panel:CreateTexture(nil, "ARTWORK"); dv:SetTexture(C.MEDIA .. "divider"); dv:SetSize(300, 18); dv:SetPoint("TOP", 0, -46)
    panel.body = panel:CreateFontString(nil, "OVERLAY"); panel.body:SetFont("Fonts\\FRIZQT__.TTF", 12, ""); panel.body:SetTextColor(0.24, 0.14, 0.05)
    panel.body:SetPoint("TOPLEFT", 26, -70); panel.body:SetWidth(408); panel.body:SetJustifyH("LEFT"); panel.body:SetSpacing(3)
    local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); close:SetSize(110, 22); close:SetPoint("BOTTOMRIGHT", -20, 16); close:SetText("Onward")
    close:SetScript("OnClick", function() panel:Hide() end)
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); open:SetSize(110, 22); open:SetPoint("RIGHT", close, "LEFT", -6, 0); open:SetText("Open journal")
    open:SetScript("OnClick", function() panel:Hide(); C.Journal.OpenTab("Timeline") end)
  end
  panel.body:SetText("- " .. table.concat(lines, "\n- "))
  panel:SetHeight(math.max(200, 120 + panel.body:GetStringHeight()))
  panel:Show()
end
C.On("PLAYER_ENTERING_WORLD", function(isLogin)
  if not isLogin or not C.set.digest or not C.cdb.lastLogout then return end
  if time() - C.cdb.lastLogout < C.set.digestHours * 3600 then return end
  C_Timer.After(5, function()
    local lines = digestLines()
    C.Emit("digest_login", "You returned after time away. " .. lines[1])
    T.ShowDigest(lines)
  end)
end)
C.On("PLAYER_LOGOUT", function() C.cdb.lastLogout = time() end)
T.DigestLines = digestLines
