-- Journal v2: a real book. Leather-bound spread, two paginated parchment pages, ribbon bookmarks,
-- chapter title pages with drop caps, prose grouped by day, page curls + flip animation, deep links.
local _, C = ...
local J = {}; C.Journal = J
local BW, BH = 1000, 500                         -- book size (texture 1024x512)
local RIBBON_LEN, RIBBON_TUCK = 104, 14            -- side tabs: length, part hidden under the cover
local PAGE_W, PAGE_H = 400, 382                  -- text area per page
local LEFT_X, RIGHT_X, TOP_Y = 64, 536, -58
local FONT_HEAD, FONT_BODY = "Fonts\\MORPHEUS.TTF", "Fonts\\FRIZQT__.TTF"
local INK, RED, FADED = { 0.24, 0.14, 0.05 }, { 0.5, 0.1, 0.04 }, { 0.45, 0.35, 0.22 }
local TABS = { { "Chapters", 0.55, 0.12, 0.1 }, { "Timeline", 0.18, 0.3, 0.55 }, { "Firsts", 0.75, 0.6, 0.15 }, { "Deaths", 0.25, 0.25, 0.25 },
  { "Allies", 0.2, 0.45, 0.25 }, { "Arcs", 0.45, 0.25, 0.55 }, { "Echoes", 0.7, 0.4, 0.2 }, { "Journey", 0.25, 0.5, 0.55 }, { "Warband", 0.6, 0.5, 0.2 }, { "Fellowship", 0.3, 0.55, 0.45 } }
-- Modules provide whole chapters: J.PROVIDERS[tab] = { enabled = fn, build = fn(blocks, search, helpers) }
J.PROVIDERS = {}
local titlePage = {}
local PIN_ICON = "|T" .. C.MEDIA .. "icon_thread:12:12:0:-1|t "
local win, measure, pages, spread, tab, search = nil, nil, {}, 1, "Chapters", ""
local entryPage = {}

local function short(ck) return ((ck or "?"):match("^[^-]+")) end
local function dayKey(t) return date("%Y-%m-%d", t) end
local function dayLabel(t) return (date("%A, %d %B %Y", t):gsub(" 0", " ")) end

------------------------------------------------------------------ content model
-- block kinds: title{char}, heading{text}, para{text, dropcap, entries}, divider
local function measureHeight(text, width, size, font, spacing)
  measure:SetFont(font or FONT_BODY, size or 13, ""); measure:SetSpacing(spacing or ((size or 13) == 13 and 2 or 0))
  measure:SetWidth(width); measure:SetText(text)
  return measure:GetStringHeight()
end

-- per-character stats (keys normalized; places = zone/subzone firsts; quests = turn-ins; deaths = real deaths only)
local function stats(ck)
  local n = { quests = 0, places = 0, deaths = 0, allies = 0, bosses = 0, entries = 0 }
  local first, last
  local key = C.NormKey and C.NormKey(ck) or ck
  for _, e in ipairs(C.db.entries) do
    if e.char and (e.char == ck or (C.NormKey and C.NormKey(e.char) == key)) then
      n.entries = n.entries + 1
      if e.t then first = math.min(first or e.t, e.t); last = math.max(last or e.t, e.t) end
      local id = e.id or ""
      if id == "quest_turnin" or id == "quest_story" then n.quests = n.quests + 1
      elseif id:find("^zone_first") or id:find("^sub_first") then n.places = n.places + 1
      elseif id == "death" then n.deaths = n.deaths + 1
      elseif id == "group_join" or id == "dungeon_party" or id == "ally_first" then n.allies = n.allies + 1
      elseif id == "boss_first_kill" then n.bosses = n.bosses + 1 end
    end
  end
  local ci = C.db.chars[ck] or {}
  first = first or ci.created
  n.first, n.last = first, last
  return n
end
J.Stats = stats
local function summary(ck, ci)
  local n = stats(ck)
  local who = format("%s, %s %s", short(ck), ci.race or "", ci.class or "")
  return format("Here begins the account of %s. The first page was written on %s. Since then you have completed %d quest%s, discovered %d place%s, stood with %d companion%s and fallen %d time%s. %s",
    who, n.first and dayLabel(n.first) or "a day not yet recorded", n.quests, n.quests == 1 and "" or "s", n.places, n.places == 1 and "" or "s",
    n.allies, n.allies == 1 and "" or "s", n.deaths, n.deaths == 1 and "" or "s",
    n.bosses > 0 and format("%d great foes lie defeated behind you.", n.bosses) or "The great foes of Azeroth still await."), n
end

local function clean(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1"):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("\n", " ")) end
-- shared structured row: { kind="row", cat, t, title, text, char, entries, onClick, icon, color }
local function row(o) o.kind = "row"; return o end
local function entryRow(i)
  local e = C.db.entries[i]
  return row({ cat = e.cat, t = e.t, title = (C.CATS[e.cat or ""] or {}).label, text = (e.anchor and PIN_ICON or "") .. clean(e.text) .. (e.photo and "  |cff6b4a2a[photo]|r" or ""),
    char = e.char, entries = { i }, zone = e.zone })
end

local echoFilter -- nil = all categories
local function matches(e) if C.BadCombatText(e) or e.archived then return false end return search == "" or ((e.text or "") .. " " .. (e.zone or "") .. " " .. (e.char or "")):lower():find(search:lower(), 1, true) end

local function dayBlocks(blocks, list, firstDrop, newestFirst)
  local curDay
  local a, b, step = 1, #list, 1
  if newestFirst then a, b, step = #list, 1, -1 end
  for k = a, b, step do
    local i = list[k]; local e = C.db.entries[i]
    if e then
      local dk = dayKey(e.t or 0)
      if dk ~= curDay then curDay = dk; tinsert(blocks, { kind = "heading", text = dayLabel(e.t or 0) }) end
      tinsert(blocks, entryRow(i))
    end
  end
end

-- small dashboard: { kind="dash", title, stats={{label,value}}, chips={{cat,n}}, lines={...} }
local function catCounts(src)
  local counts, total = {}, 0
  for _, d in ipairs(src) do if not C.BadCombatText(d) then counts[d.cat or "?"] = (counts[d.cat or "?"] or 0) + 1; total = total + 1 end end
  local chips = {}
  for _, k in ipairs(C.CAT_ORDER) do if counts[k] then chips[#chips + 1] = { cat = k, n = counts[k] } end end
  return chips, total
end

local function buildBlocks()
  local blocks = {}
  local prov = J.PROVIDERS[tab]
  if prov then
    if prov.enabled() then prov.build(blocks, search, J.helpers)
    else tinsert(blocks, { kind = "chapterhead", text = tab }); tinsert(blocks, { kind = "para", dropcap = true, text = "This chapter is turned off. Enable it in Settings > Journeykeeper." }) end
    return blocks
  end
  if tab == "Chapters" then
    local chars = {}
    for ck in pairs(C.db.chars) do chars[#chars + 1] = ck end
    for _, e in ipairs(C.db.entries) do if e.char and not C.db.chars[e.char] then C.db.chars[e.char] = {}; chars[#chars + 1] = e.char end end
    table.sort(chars, function(a, b) return (C.db.chars[a].created or 0) < (C.db.chars[b].created or 0) end)
    -- account dashboard
    if search == "" then
      local tot = { quests = 0, places = 0, deaths = 0, played = 0 }
      local lines = {}
      for _, ck in ipairs(chars) do
        local n, ci = stats(ck), C.db.chars[ck] or {}
        tot.quests, tot.places, tot.deaths = tot.quests + n.quests, tot.places + n.places, tot.deaths + n.deaths
        tot.played = tot.played + (ci.played or 0)
        lines[#lines + 1] = { char = ck, text = format("level %s  ·  %d quests  ·  %d places  ·  %d deaths  ·  %s  ·  since %s", tostring(ci.level or "?"), n.quests, n.places, n.deaths,
          ci.played and C.FormatDuration(ci.played) or "time n/a", n.first and C.dateStr(n.first) or "?") }
      end
      tinsert(blocks, { kind = "chapterhead", text = "The Book" })
      tinsert(blocks, { kind = "dash", stats = { { "Characters", #chars }, { "Memories", #C.db.entries }, { "Quests", tot.quests }, { "Places", tot.places }, { "Deaths", tot.deaths },
        { "Played", tot.played > 0 and C.FormatDuration(tot.played) or "n/a" } }, chars = lines })
    end
    for _, ck in ipairs(chars) do
      tinsert(blocks, { kind = "title", char = ck })
      local list = {}
      local key = C.NormKey and C.NormKey(ck) or ck
      for i, e in ipairs(C.db.entries) do if e.char and (e.char == ck or (C.NormKey and C.NormKey(e.char) == key)) and matches(e) then list[#list + 1] = i end end
      dayBlocks(blocks, list, true)
    end
  elseif tab == "Arcs" then
    local live, archived = 0, {}
    for ai, arc in ipairs(C.db.arcs) do if arc.archived then archived[#archived + 1] = ai else live = live + 1 end end
    if live == 0 then
      tinsert(blocks, { kind = "chapterhead", text = "Arcs" })
      tinsert(blocks, { kind = "para", dropcap = true, text = "No arcs yet. Right-click an echo or click a paragraph in this book and choose 'Start a new arc', or type /jkp arc new <name>." })
    end
    for ai, arc in ipairs(C.db.arcs) do if not arc.archived then
      tinsert(blocks, { kind = "arctitle", arc = arc, idx = ai })
      local list = {}
      for _, i in ipairs(C.ArcEntries and C.ArcEntries(arc) or arc.entries) do if C.db.entries[i] and matches(C.db.entries[i]) then list[#list + 1] = i end end
      dayBlocks(blocks, list, true)
    end end
    if #archived > 0 and search == "" then
      tinsert(blocks, { kind = "heading", text = "Archived arcs" })
      for _, ai in ipairs(archived) do
        local a = C.db.arcs[ai]
        tinsert(blocks, row({ cat = "thread", t = a.archivedAt, title = "Archived", text = format("%s  ·  %d moment%s  ·  click to restore", a.name or "?", #(a.entries or {}), #(a.entries or {}) == 1 and "" or "s"),
          onClick = function() C.ArcRestore(ai) end }))
      end
    end
  elseif tab == "Echoes" then
    tinsert(blocks, { kind = "chapterhead", text = "Echoes" })
    local chips, total = catCounts(C.db.diary)
    local latest
    for k = #C.db.diary, 1, -1 do if not C.BadCombatText(C.db.diary[k]) then latest = C.db.diary[k]; break end end
    tinsert(blocks, { kind = "dash", stats = { { "Echoes", total }, { "Categories", #chips }, { "Latest", latest and date("%d %b %H:%M", latest.t) or "-" } }, chips = chips,
      note = latest and ("Latest: " .. (latest.title or "Echo") .. " - " .. clean(latest.text)) or "No echoes yet. They appear when you return to places and moments you have lived before." })
    tinsert(blocks, { kind = "filterbar" })
    local curDay, shown = nil, 0
    for k = #C.db.diary, 1, -1 do
      local d = C.db.diary[k]
      if not C.BadCombatText(d) and (not echoFilter or d.cat == echoFilter)
        and (search == "" or ((d.text or "") .. (d.title or "")):lower():find(search:lower(), 1, true)) then
        local dk = dayKey(d.t)
        if dk ~= curDay then curDay = dk; tinsert(blocks, { kind = "heading", text = dayLabel(d.t) }) end
        local e = d.entry and C.db.entries[d.entry]
        tinsert(blocks, row({ cat = d.cat, t = d.t, title = d.title or "Echo", text = (e and e.anchor and PIN_ICON or "") .. clean(d.text), char = d.char, entries = (e and { d.entry }) or nil,
          zone = e and e.zone, echo = d, detail = true }))
        shown = shown + 1
      end
    end
    if shown == 0 and total > 0 then tinsert(blocks, { kind = "para", text = "No echoes in this category yet." }) end
    if C.Dialogue and C.set.dialogue then C.Dialogue.Blocks(blocks, search) end
  elseif tab == "Allies" then
    tinsert(blocks, { kind = "chapterhead", text = "Companions of the Road" })
    local arr = {}
    for _, p in pairs(C.db.players) do if search == "" or (p.name or ""):lower():find(search:lower(), 1, true) then arr[#arr + 1] = p end end
    table.sort(arr, function(a, b) return (a.count or 0) > (b.count or 0) end)
    for i, p in ipairs(arr) do
      local txt = format("%s  ·  together %d time%s, %d min  ·  last in %s", (p.class or "traveller"):lower(), p.count or 0, (p.count or 0) == 1 and "" or "s", floor((p.secs or 0) / 60), p.lastWhere or "?")
      for _, n in ipairs(p.notes or {}) do txt = txt .. format("  ·  \"%s\"", n.text) end
      tinsert(blocks, row({ cat = "group", t = p.last, title = p.name or "?", text = txt }))
    end
  else
    local head = { Timeline = "The Whole Tale", Firsts = "Firsts & Discoveries", Deaths = "The Fallen" }
    tinsert(blocks, { kind = "chapterhead", text = head[tab] })
    if tab == "Deaths" then
      local arr = {}
      for k, n in pairs(C.db.deathCount) do arr[#arr + 1] = { k = k, n = n } end
      table.sort(arr, function(a, b) return a.n > b.n end)
      if #arr > 0 then
        local parts = {}
        for i = 1, math.min(3, #arr) do local z, s = arr[i].k:match("^(.-)|(.*)$"); parts[#parts + 1] = format("%s%s (%d)", s ~= "" and (s .. ", ") or "", z or "?", arr[i].n) end
        tinsert(blocks, { kind = "dash", stats = { { "Falls", #C.db.deathSpots } }, note = "Most dangerous: " .. table.concat(parts, "; ") })
        tinsert(blocks, { kind = "divider" })
      end
    end
    local list = {}
    for i, e in ipairs(C.db.entries) do
      local keep = tab == "Timeline" or (tab == "Deaths" and e.cat == "death") or (tab == "Firsts" and (e.accountFirst or (e.text or ""):lower():find("first")))
      if keep and matches(e) then list[#list + 1] = i end
    end
    dayBlocks(blocks, list, false, tab == "Timeline")
  end
  return blocks
end

-- heights for structured blocks (must match the renderer below)
local ROW_TXT_W = PAGE_W - 36
function J.BlockHeight(b)
  if b.kind == "row" then
    b._h = b._h or math.max(30, 15 + measureHeight(b.text or "", ROW_TXT_W, 12)) + 6
    return b._h
  elseif b.kind == "filterbar" then return 28
  elseif b.kind == "dash" then
    local h = 8 + math.ceil(#(b.stats or {}) / 3) * 38
    if b.chips and #b.chips > 0 then h = h + math.ceil(#b.chips / 3) * 24 + 6 end
    if b.chars then for _, l in ipairs(b.chars) do h = h + 16 + measureHeight(l.text, PAGE_W - 12, 11) end end
    if b.note then h = h + measureHeight(b.note, PAGE_W - 12, 11) + 8 end
    return math.min(PAGE_H - 80, h + 6)
  end
  return 0
end

-- paginate blocks into pages {items = {...}}
local function paginate(blocks)
  wipe(pages); wipe(entryPage); wipe(titlePage)
  local page, used = { items = {} }, 0
  local function newPage() page.used = used; tinsert(pages, page); page, used = { items = {} }, 0 end
  for _, b in ipairs(blocks) do
    if b.kind == "title" or b.kind == "arctitle" then
      if #page.items > 0 then newPage() end
      if #pages % 2 == 1 then newPage() end -- title pages start on the left
      if b.kind == "title" then titlePage[b.char] = #pages + 1 end
      tinsert(page.items, b); newPage()
    elseif b.kind == "sketch" then
      if #page.items > 0 then newPage() end
      tinsert(page.items, b); newPage()
    elseif b.kind == "arctitle" then
      local a = b.arc
      p.crestBg:Show(); p.crest:Show(); p.crest:SetTexture(C.CATS.thread.icon); p.crest:SetTexCoord(0, 1, 0, 1)
      p.tName:SetText(a.name); p.tName:Show()
      p.tSub:SetText(format("An arc  ·  %d moment%s%s", #a.entries, #a.entries == 1 and "" or "s", b.idx == C.db.activeArc and "  ·  active" or "")); p.tSub:Show()
      p.tDiv:Show()
      local first, last = a.entries[1] and C.db.entries[a.entries[1]], a.entries[#a.entries] and C.db.entries[a.entries[#a.entries]]
      p.tBody:SetText(format("Begun by %s on %s. %s", short(a.char), C.dateStr(a.created),
        first and format("It runs from %s to %s.", C.dateStr(first.t), C.dateStr(last.t)) or "No moments have been added yet.")); p.tBody:Show()
      p.tStats:SetText("Click any paragraph to add more moments to the active arc"); p.tStats:Show()
    elseif b.kind == "chapterhead" then
      if #page.items > 0 then newPage() end
      tinsert(page.items, b); used = 70
    elseif b.kind == "row" or b.kind == "dash" or b.kind == "filterbar" then
      local h = J.BlockHeight(b)
      if used + h > PAGE_H then newPage() end
      tinsert(page.items, b); used = used + h
      for _, i in ipairs(b.entries or {}) do entryPage[i] = entryPage[i] or (#pages + 1) end
    elseif b.kind == "heading" or b.kind == "divider" then
      local h = b.kind == "heading" and 26 or 22
      if used + h + 40 > PAGE_H then newPage() end
      tinsert(page.items, b); used = used + h
    elseif b.kind == "para" then
      local width = b.dropcap and (PAGE_W - 50) or (b.icon and (PAGE_W - 34)) or PAGE_W
      local h = math.max(b.dropcap and 46 or 0, b.icon and 30 or 0, measureHeight(b.text, width)) + 10
      if used + h <= PAGE_H then
        tinsert(page.items, b); used = used + h
        for _, i in ipairs(b.entries or {}) do entryPage[i] = #pages + 1 end
      else
        -- split by sentences across pages
        local rest, sentences = {}, {}
        for s in b.text:gmatch("[^%.!?]+[%.!?]+%s*") do sentences[#sentences + 1] = s end
        if #sentences == 0 then sentences = { b.text } end
        local chunk, first = "", true
        for _, s in ipairs(sentences) do
          local try = chunk .. s
          local w = (first and b.dropcap) and (PAGE_W - 50) or PAGE_W
          if used + measureHeight(try, w) + 10 > PAGE_H and chunk ~= "" then
            tinsert(page.items, { kind = "para", text = chunk, dropcap = first and b.dropcap, cont = not first, entries = b.entries, cat = b.cat })
            first = false; newPage(); chunk = s
          else chunk = try end
        end
        if chunk ~= "" then
          local h2 = measureHeight(chunk, PAGE_W) + 10
          tinsert(page.items, { kind = "para", text = chunk, dropcap = first and b.dropcap, cont = not first, entries = b.entries, cat = b.cat }); used = used + h2
        end
        for _, i in ipairs(b.entries or {}) do entryPage[i] = entryPage[i] or #pages + 1 end
      end
    end
  end
  if #page.items > 0 then page.used = used; tinsert(pages, page) end
  if #pages == 0 then pages[1] = { items = { { kind = "chapterhead", text = "Empty pages" }, { kind = "para", text = "Nothing has been written here yet. Go out and live a little; the ink will follow.", dropcap = true } } } end
end

------------------------------------------------------------------ rendering
local function fs(parent, font, size, color, layer)
  local f = parent:CreateFontString(nil, layer or "OVERLAY")
  f:SetFont(font, size, ""); f:SetTextColor(unpack(color)); f:SetJustifyH("LEFT"); f:SetJustifyV("TOP"); f:SetShadowOffset(0, 0)
  return f
end

local function makePage(x)
  local p = CreateFrame("Frame", nil, win); p:SetSize(PAGE_W, PAGE_H + 30); p:SetPoint("TOPLEFT", x, TOP_Y)
  if p.SetClipsChildren then p:SetClipsChildren(true) end -- nothing may draw outside the page
  p:EnableMouse(true) -- clicks on the page are not book drags (book drag = leather border)
  p:EnableMouseWheel(true); p:SetScript("OnMouseWheel", function(_, d) J.Flip(d > 0 and -1 or 1) end)
  p.texts, p.decos, p.hits = {}, {}, {}
  p.num = fs(p, FONT_HEAD, 13, FADED); p.num:SetPoint("BOTTOM", 0, 8); p.num:SetJustifyH("CENTER")
  -- title page parts
  p.crestBg = p:CreateTexture(nil, "ARTWORK"); p.crestBg:SetSize(96, 96); p.crestBg:SetPoint("TOP", 0, -20); p.crestBg:SetTexture(C.MEDIA .. "dropcap")
  p.crest = p:CreateTexture(nil, "ARTWORK", nil, 1); p.crest:SetSize(62, 62); p.crest:SetPoint("CENTER", p.crestBg)
  p.tName = fs(p, FONT_HEAD, 30, RED); p.tName:SetPoint("TOP", p.crestBg, "BOTTOM", 0, -12); p.tName:SetJustifyH("CENTER")
  p.tSub = fs(p, FONT_HEAD, 15, INK); p.tSub:SetPoint("TOP", p.tName, "BOTTOM", 0, -6); p.tSub:SetJustifyH("CENTER")
  p.tDiv = p:CreateTexture(nil, "ARTWORK"); p.tDiv:SetTexture(C.MEDIA .. "divider"); p.tDiv:SetSize(320, 20); p.tDiv:SetPoint("TOP", p.tSub, "BOTTOM", 0, -10)
  p.tBody = fs(p, FONT_BODY, 13, INK); p.tBody:SetPoint("TOP", p.tDiv, "BOTTOM", 0, -10); p.tBody:SetWidth(PAGE_W - 30)
  p.tStats = fs(p, FONT_HEAD, 14, FADED); p.tStats:SetPoint("BOTTOM", 0, 24); p.tStats:SetJustifyH("CENTER")
  return p
end

local function getText(p, i, font, size, color)
  local t = p.texts[i]
  if not t then t = fs(p, font, size, color); p.texts[i] = t end
  t:SetFont(font, size, ""); t:SetTextColor(unpack(color)); t:ClearAllPoints(); t:SetWordWrap(true); t:SetSpacing(0); t:Show()
  return t
end
local function getDeco(p, i)
  local d = p.decos[i]
  if not d then d = { tex = p:CreateTexture(nil, "ARTWORK"), letter = fs(p, FONT_HEAD, 34, { 1, 0.86, 0.5 }) }; d.letter:SetJustifyH("CENTER"); p.decos[i] = d end
  d.tex:ClearAllPoints(); d.letter:ClearAllPoints(); d.tex:SetTexCoord(0, 1, 0, 1); d.tex:SetVertexColor(1, 1, 1); d.tex:Show()
  return d
end

local function getHit(p, i)
  local hit = p.hits[i]
  if not hit then
    hit = CreateFrame("Button", nil, p); p.hits[i] = hit
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit.hl = hit:CreateTexture(nil, "HIGHLIGHT"); hit.hl:SetAllPoints(hit); hit.hl:SetColorTexture(0.6, 0.4, 0.1, 0.10)
    hit:SetScript("OnClick", function(self, btn)
      if self.onClick then self.onClick(self, btn) return end
      if self.entries and #self.entries > 0 then C.Menu(self, C.MemoryMenuItems({ entries = self.entries, cat = self.cat }), #self.entries > 1 and "These moments" or "This moment") end
    end)
  end
  hit:ClearAllPoints(); hit:Show()
  return hit
end
local function catColor(cat) local c = C.CATS[cat or ""]; return c and c.color or { 0.55, 0.42, 0.25 } end
local function hexOf(c, k) k = k or 1; return format("ff%02x%02x%02x", floor(math.min(1, c[1] * k) * 255), floor(math.min(1, c[2] * k) * 255), floor(math.min(1, c[3] * k) * 255)) end

local function renderPage(p, page, number)
  for _, t in ipairs(p.texts) do t:Hide() end
  for _, h in ipairs(p.hits) do h:Hide() end
  for _, d in ipairs(p.decos) do d.tex:Hide(); d.letter:Hide() end
  for _, k in ipairs({ "crestBg", "crest", "tName", "tSub", "tDiv", "tBody", "tStats" }) do p[k]:Hide() end
  for _, o in ipairs(rawget(p, "sketchObjs") or {}) do o:Hide() end
  if rawget(p, "mapClip") then p.mapClip:Hide() end
  if rawget(p, "filterDD") then p.filterDD:Hide() end
  if not page then p.num:SetText(""); return end
  p.num:SetText(format("- %d -", number))
  local y, ti, di, hi = 0, 0, 0, 0
  local function seal(x, yy, cat, size, icon)
    size = size or 26
    di = di + 1; local d = getDeco(p, di); d.tex:SetTexture(C.MEDIA .. "pin_seal"); d.tex:SetSize(size, size); d.tex:SetPoint("TOPLEFT", x, -yy)
    local c = catColor(cat); d.tex:SetVertexColor(c[1] * 0.85, c[2] * 0.85, c[3] * 0.85)
    di = di + 1; local ic = getDeco(p, di); ic.tex:SetTexture(icon or (C.CATS[cat or ""] or C.CATS.thread).icon); ic.tex:SetSize(size * 0.62, size * 0.62); ic.tex:SetPoint("CENTER", d.tex, "CENTER")
  end
  for _, b in ipairs(page.items) do
    if b.kind == "title" then
      local ci = C.db.chars[b.char] or {}
      p.crestBg:Show(); p.crest:Show()
      if ci.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[ci.classFile] then
        p.crest:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles"); p.crest:SetTexCoord(unpack(CLASS_ICON_TCOORDS[ci.classFile]))
      else p.crest:SetTexture(C.CATS.level.icon); p.crest:SetTexCoord(0, 1, 0, 1) end
      p.tName:SetText(short(b.char)); p.tName:Show()
      p.tSub:SetText(format("%s %s  ·  level %s", ci.race or "", ci.class or "", tostring(ci.level or "?"))); p.tSub:Show()
      p.tDiv:Show()
      local text, n = summary(b.char, ci)
      p.tBody:SetText(text); p.tBody:Show()
      local era = C.Flavor and C.Flavor.Era()
      local rec = C.Combat and C.Combat.TitleLine and C.Combat.TitleLine(b.char or C.charKey())
      p.tStats:SetText(format("%sBegun %s  ·  %d places  ·  %d deaths%s", era and (era .. "\n") or "", ci.created and C.dateStr(ci.created) or "?", n.places, n.deaths, rec and ("\n" .. rec) or "")); p.tStats:Show()
    elseif b.kind == "arctitle" then
      local a = b.arc
      p.crestBg:Show(); p.crest:Show(); p.crest:SetTexture(C.CATS.thread.icon); p.crest:SetTexCoord(0, 1, 0, 1)
      p.tName:SetText(a.name); p.tName:Show()
      p.tSub:SetText(format("An arc  ·  %d moment%s%s", #a.entries, #a.entries == 1 and "" or "s", b.idx == C.db.activeArc and "  ·  active" or "")); p.tSub:Show()
      p.tDiv:Show()
      local list = C.ArcEntries and C.ArcEntries(a) or a.entries
      local first, last = list[1] and C.db.entries[list[1]], list[#list] and C.db.entries[list[#list]]
      local from, to = a.startT or (first and first.t), a.endT or (last and last.t)
      p.tBody:SetText(format("Begun by %s on %s. %s%s", short(a.char), C.dateStr(a.created),
        from and format("It runs from %s to %s.", C.dateStr(from), to and C.dateStr(to) or "today") or "No moments have been added yet.",
        a.note and ("\n\n" .. a.note) or "")); p.tBody:Show()
      p.tStats:SetText("Click the title to edit, rename or archive this arc"); p.tStats:Show()
      hi = hi + 1; local hit = getHit(p, hi); hit.entries = nil; local idx = b.idx
      hit.onClick = function() C.ArcEdit(idx) end
      hit:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0); hit:SetSize(PAGE_W, 190)
    elseif b.kind == "chapterhead" then
      ti = ti + 1; local t = getText(p, ti, FONT_HEAD, 26, RED); t:SetPoint("TOP", p, "TOP", 0, -y - 6); t:SetJustifyH("CENTER"); t:SetWidth(PAGE_W); t:SetText(b.text)
      di = di + 1; local d = getDeco(p, di); d.tex:SetTexture(C.MEDIA .. "divider"); d.tex:SetSize(300, 18); d.tex:SetPoint("TOP", p, "TOP", 0, -y - 40)
      y = y + 70
    elseif b.kind == "heading" then
      ti = ti + 1; local t = getText(p, ti, FONT_HEAD, 16, RED); t:SetPoint("TOPLEFT", 0, -y); t:SetWidth(PAGE_W); t:SetJustifyH("LEFT"); t:SetText(b.text)
      y = y + 26
    elseif b.kind == "divider" then
      di = di + 1; local d = getDeco(p, di); d.tex:SetTexture(C.MEDIA .. "divider"); d.tex:SetSize(260, 16); d.tex:SetPoint("TOP", p, "TOP", 0, -y - 2)
      y = y + 22
    elseif b.kind == "sketch" then
      J.DrawSketch(p, b)
    elseif b.kind == "row" then
      local h = J.BlockHeight(b)
      seal(0, y + 2, b.cat, 26, b.icon)
      local c = catColor(b.cat)
      ti = ti + 1; local m = getText(p, ti, FONT_BODY, 10, FADED); m:SetPoint("TOPLEFT", 34, -y); m:SetWidth(ROW_TXT_W); m:SetJustifyH("LEFT"); m:SetSpacing(0)
      local meta = {}
      if b.t then meta[#meta + 1] = date("%H:%M", b.t) end
      meta[#meta + 1] = format("|c%s%s|r", hexOf(c, 0.75), (b.title or (C.CATS[b.cat or ""] or {}).label or "Memory"):upper())
      if b.char then meta[#meta + 1] = short(b.char) end
      if b.zone and b.zone ~= "" then meta[#meta + 1] = b.zone end
      m:SetText(table.concat(meta, "  ·  ")); m:SetWordWrap(false)
      ti = ti + 1; local tx = getText(p, ti, FONT_BODY, 12, INK); tx:SetPoint("TOPLEFT", 34, -y - 14); tx:SetWidth(ROW_TXT_W); tx:SetJustifyH("LEFT"); tx:SetSpacing(0); tx:SetWordWrap(true)
      tx:SetText(b.text or "")
      di = di + 1; local ln = getDeco(p, di); ln.tex:SetColorTexture(0.45, 0.35, 0.22, 0.18); ln.tex:SetSize(PAGE_W - 34, 1); ln.tex:SetPoint("TOPLEFT", 34, -y - h + 3)
      -- v0.6.8: every row is clickable. Left-click opens the detail card; right-click the memory menu (if linked).
      hi = hi + 1; local hit = getHit(p, hi); hit.entries, hit.cat = b.entries or {}, b.cat
      hit.onClick = b.onClick or function(self, btn)
        if btn == "RightButton" and #self.entries > 0 then C.Menu(self, C.MemoryMenuItems({ entries = self.entries, cat = self.cat }), "This moment") return end
        J.ShowDetail(b, self)
      end
      hit:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y); hit:SetSize(PAGE_W, math.max(1, h - 2))
      y = y + h
    elseif b.kind == "filterbar" then
      di = di + 1; local bg = getDeco(p, di); bg.tex:SetColorTexture(0.45, 0.3, 0.12, 0.14); bg.tex:SetSize(PAGE_W, 22); bg.tex:SetPoint("TOPLEFT", 0, -y)
      local fc = echoFilter and C.CATS[echoFilter]
      if fc then seal(4, y + 1, echoFilter, 20) end
      ti = ti + 1; local f = getText(p, ti, FONT_HEAD, 14, RED); f:SetPoint("TOPLEFT", fc and 30 or 8, -y - 4); f:SetWidth(90); f:SetJustifyH("LEFT")
      f:SetText("Filter:")
      local dd = J.FilterDropdown(p)
      if dd then
        dd:ClearAllPoints(); dd:SetPoint("TOPLEFT", p, "TOPLEFT", (fc and 30 or 8) + 56, -y + 1); dd:Show()
      else -- fallback: click opens our own list menu
        f:SetText(format("Filter:  %s  |cff7a6040v|r", fc and fc.label or "All categories")); f:SetWidth(PAGE_W - 40)
        hi = hi + 1; local hit = getHit(p, hi); hit.entries = nil
        hit.onClick = function(self) C.Menu(self, J.FilterMenuItems(), "Show echoes of") end
        hit:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y); hit:SetSize(PAGE_W, 22)
      end
      y = y + 28
    elseif b.kind == "dash" then
      local h = J.BlockHeight(b)
      di = di + 1; local bg = getDeco(p, di); bg.tex:SetColorTexture(0.55, 0.38, 0.15, 0.10); bg.tex:SetSize(PAGE_W, h - 6); bg.tex:SetPoint("TOPLEFT", 0, -y)
      local yy = y + 6
      for i, s in ipairs(b.stats or {}) do
        local col, r = (i - 1) % 3, floor((i - 1) / 3)
        local x = 6 + col * (PAGE_W - 12) / 3
        ti = ti + 1; local v = getText(p, ti, FONT_HEAD, 18, RED); v:SetPoint("TOPLEFT", x, -yy - r * 38); v:SetWidth((PAGE_W - 12) / 3 - 4); v:SetJustifyH("LEFT"); v:SetWordWrap(false); v:SetText(tostring(s[2]))
        ti = ti + 1; local l = getText(p, ti, FONT_BODY, 10, FADED); l:SetPoint("TOPLEFT", x, -yy - r * 38 - 20); l:SetWidth((PAGE_W - 12) / 3 - 4); l:SetJustifyH("LEFT"); l:SetWordWrap(false); l:SetText(s[1]:upper())
      end
      yy = yy + math.ceil(#(b.stats or {}) / 3) * 38
      if b.chips and #b.chips > 0 then
        for i, ch in ipairs(b.chips) do
          local col, r = (i - 1) % 3, floor((i - 1) / 3)
          local x = 6 + col * (PAGE_W - 12) / 3
          seal(x, yy + r * 24, ch.cat, 20)
          ti = ti + 1; local l = getText(p, ti, FONT_BODY, 11, INK); l:SetPoint("TOPLEFT", x + 24, -yy - r * 24 - 4); l:SetWidth((PAGE_W - 12) / 3 - 28); l:SetWordWrap(false); l:SetJustifyH("LEFT")
          l:SetText(format("%s |c%s%d|r", (C.CATS[ch.cat] or {}).label or ch.cat, hexOf(catColor(ch.cat), 0.7), ch.n))
        end
        yy = yy + math.ceil(#b.chips / 3) * 24 + 6
      end
      for _, ln in ipairs(b.chars or {}) do
        ti = ti + 1; local nm = getText(p, ti, FONT_HEAD, 13, RED); nm:SetPoint("TOPLEFT", 6, -yy); nm:SetWidth(PAGE_W - 12); nm:SetJustifyH("LEFT"); nm:SetWordWrap(false); nm:SetText(short(ln.char))
        ti = ti + 1; local tx = getText(p, ti, FONT_BODY, 11, INK); tx:SetPoint("TOPLEFT", 6, -yy - 15); tx:SetWidth(PAGE_W - 12); tx:SetJustifyH("LEFT"); tx:SetWordWrap(true); tx:SetText(ln.text)
        local lh = 16 + tx:GetStringHeight()
        hi = hi + 1; local hit = getHit(p, hi); hit.entries = nil; hit.onClick = function() J.OpenChapter(ln.char) end
        hit:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -yy); hit:SetSize(PAGE_W, lh)
        yy = yy + lh
      end
      if b.note then ti = ti + 1; local nt = getText(p, ti, FONT_BODY, 11, FADED); nt:SetPoint("TOPLEFT", 6, -yy - 2); nt:SetWidth(PAGE_W - 12); nt:SetJustifyH("LEFT"); nt:SetWordWrap(true); nt:SetText(b.note) end
      y = y + h
    elseif b.kind == "para" then
      ti = ti + 1
      local t = getText(p, ti, FONT_BODY, 13, INK); t:SetJustifyH("LEFT"); t:SetSpacing(2)
      local text = b.text
      if b.dropcap then
        di = di + 1; local d = getDeco(p, di)
        d.tex:SetTexture(C.MEDIA .. "dropcap"); d.tex:SetSize(44, 44); d.tex:SetPoint("TOPLEFT", 0, -y)
        local first = text:sub(1, 1); text = text:sub(2)
        d.letter:SetText(first:upper()); d.letter:SetPoint("CENTER", d.tex, "CENTER", 0, -1); d.letter:Show()
        t:SetPoint("TOPLEFT", 50, -y); t:SetWidth(PAGE_W - 50)
      elseif b.icon then
        di = di + 1; local d = getDeco(p, di)
        d.tex:SetTexture(C.MEDIA .. "pin_seal"); d.tex:SetSize(30, 30); d.tex:SetPoint("TOPLEFT", 0, -y + 2)
        local c = b.iconColor or { 0.6, 0.45, 0.25 }; d.tex:SetVertexColor(c[1] * 0.85, c[2] * 0.85, c[3] * 0.85)
        di = di + 1; local ic = getDeco(p, di)
        ic.tex:SetTexture(b.icon); ic.tex:SetVertexColor(1, 1, 1); ic.tex:SetSize(18, 18); ic.tex:SetPoint("CENTER", d.tex, "CENTER", 0, 0)
        t:SetPoint("TOPLEFT", 34, -y); t:SetWidth(PAGE_W - 34)
      else
        t:SetPoint("TOPLEFT", b.cont and 0 or 0, -y); t:SetWidth(PAGE_W)
      end
      t:SetText((b.cont or b.dropcap) and text or ("    " .. text))
      local h = math.max(b.dropcap and 46 or 0, b.icon and 30 or 0, t:GetStringHeight())
      if (b.entries and #b.entries > 0) or b.onClick then
        hi = hi + 1; local hit = getHit(p, hi)
        hit.onClick = b.onClick
        hit.entries, hit.cat = b.entries or {}, b.cat or (b.entries and C.db.entries[b.entries[1]] or {}).cat
        hit:SetPoint("TOPLEFT", p, "TOPLEFT", b.dropcap and 50 or 0, -y); hit:SetSize(b.dropcap and (PAGE_W - 50) or PAGE_W, h)
      end
      y = y + h + 10
    end
  end
end

-- v0.6.8: Echoes filter = real dropdown (Mainline WowStyle1DropdownTemplate + radio menu). Created once per page;
-- if the template is missing the caller falls back to our own C.Menu list.
function J.FilterMenuItems()
  local items = { { text = (echoFilter and "" or "> ") .. "All categories", func = function() J.SetEchoFilter(nil); spread = 1; J.Refresh() end } }
  for _, k in ipairs(C.CAT_ORDER) do local c = C.CATS[k]
    if c then items[#items + 1] = { text = (echoFilter == k and "> " or "") .. c.label, color = c.color, func = function() J.SetEchoFilter(k); spread = 1; J.Refresh() end } end
  end
  return items
end
-- v0.6.9: our own parchment dropdown (the Blizzard WowStyle1 dropdown looked black/gold on the page).
-- Button: parchment fill, warm brown border, serif dark-brown text, small brown arrow. List: own frame on the book,
-- parchment background, accent hover, seal dot for the current choice. Closes on pick, on mouse-away, or when the book hides.
local PARCH, BROWN, ACCENT = { 0.93, 0.85, 0.66 }, { 0.42, 0.26, 0.11 }, { 0.62, 0.38, 0.12 }
local ddList
local function border(f, c, a)
  local t = {}
  for i, pt in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
    local x = f:CreateTexture(nil, "BORDER"); x:SetColorTexture(c[1], c[2], c[3], a or 1)
    x:SetPoint(pt[1]); x:SetPoint(pt[2]); if pt[3] then x:SetWidth(1) else x:SetHeight(1) end; t[i] = x
  end
  return t
end
local function filterLabel() local c = echoFilter and C.CATS[echoFilter]; return c and c.label or "All categories" end
function J.FilterList(anchor)
  if not ddList then
    ddList = CreateFrame("Frame", nil, win); ddList:SetFrameStrata("FULLSCREEN_DIALOG"); ddList:SetClampedToScreen(true); ddList:EnableMouse(true)
    local bg = ddList:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(PARCH[1], PARCH[2], PARCH[3], 0.98)
    local sh = ddList:CreateTexture(nil, "BACKGROUND", nil, -1); sh:SetPoint("TOPLEFT", 3, -3); sh:SetPoint("BOTTOMRIGHT", 4, -4); sh:SetColorTexture(0, 0, 0, 0.35)
    border(ddList, BROWN, 0.9)
    ddList.rows = {}
    ddList:SetScript("OnUpdate", function(self, el)
      if self:IsMouseOver(6, -6, -6, 6) or (self.anchor and self.anchor:IsMouseOver()) then self.away = 0
      else self.away = (self.away or 0) + el; if self.away > 1.2 then self:Hide() end end
    end)
    win:HookScript("OnHide", function() ddList:Hide() end)
  end
  local opts = { { false, "All categories" } }
  for _, k in ipairs(C.CAT_ORDER) do if C.CATS[k] then opts[#opts + 1] = { k, C.CATS[k].label } end end
  for _, r in ipairs(ddList.rows) do r:Hide() end
  for i, o in ipairs(opts) do
    local r = ddList.rows[i]
    if not r then
      r = CreateFrame("Button", nil, ddList); r:SetHeight(20); ddList.rows[i] = r
      r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
      r.dot = r:CreateTexture(nil, "ARTWORK"); r.dot:SetSize(12, 12); r.dot:SetPoint("LEFT", 6, 0); r.dot:SetTexture(C.MEDIA .. "pin_seal")
      r.fs = r:CreateFontString(nil, "OVERLAY"); r.fs:SetFont(FONT_HEAD, 13, ""); r.fs:SetPoint("LEFT", 22, 0); r.fs:SetJustifyH("LEFT")
    end
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20); r:SetPoint("RIGHT", ddList, "RIGHT", -4, 0)
    local sel = (echoFilter or false) == o[1]
    local col = o[1] and catColor(o[1]) or BROWN
    r.dot:SetVertexColor(col[1], col[2], col[3]); r.dot:SetAlpha(sel and 1 or 0.35)
    r.fs:SetText(o[2]); r.fs:SetTextColor(sel and 0.5 or INK[1], sel and 0.1 or INK[2], sel and 0.04 or INK[3])
    r.value = o[1]
    r:SetScript("OnClick", function(self) ddList:Hide(); J.SetEchoFilter(self.value or nil); spread = 1; J.Refresh() end)
    r:Show()
  end
  ddList.anchor = anchor
  ddList:SetSize(math.max(200, anchor:GetWidth() or 200), 8 + #opts * 20)
  ddList:ClearAllPoints(); ddList:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  ddList:SetFrameLevel(win:GetFrameLevel() + 40); ddList.away = 0; ddList:Show()
  return ddList
end
function J.FilterDropdown(p)
  local dd = rawget(p, "filterDD")
  if dd then dd.text:SetText(filterLabel()); return dd end
  dd = CreateFrame("Button", nil, p); p.filterDD = dd
  dd:SetSize(220, 22); dd:SetFrameLevel(p:GetFrameLevel() + 10)
  local bg = dd:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(PARCH[1], PARCH[2], PARCH[3], 0.95)
  border(dd, BROWN, 0.85)
  local hl = dd:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
  dd.text = dd:CreateFontString(nil, "OVERLAY"); dd.text:SetFont(FONT_HEAD, 13, ""); dd.text:SetTextColor(INK[1], INK[2], INK[3])
  dd.text:SetPoint("LEFT", 8, 0); dd.text:SetPoint("RIGHT", -22, 0); dd.text:SetJustifyH("LEFT"); dd.text:SetWordWrap(false)
  dd.arrow = dd:CreateFontString(nil, "OVERLAY"); dd.arrow:SetFont(FONT_BODY, 10, ""); dd.arrow:SetTextColor(BROWN[1], BROWN[2], BROWN[3])
  dd.arrow:SetPoint("RIGHT", -7, 0); dd.arrow:SetText("v")
  local sep = dd:CreateTexture(nil, "ARTWORK"); sep:SetColorTexture(BROWN[1], BROWN[2], BROWN[3], 0.5); sep:SetWidth(1); sep:SetPoint("TOPRIGHT", -18, -4); sep:SetPoint("BOTTOMRIGHT", -18, 4)
  dd:SetScript("OnClick", function(self) if ddList and ddList:IsShown() then ddList:Hide() else J.FilterList(self) end end)
  dd.text:SetText(filterLabel())
  return dd
end
J.FilterLabel = filterLabel

local function render()
  if #pages == 0 then return end
  spread = math.max(1, math.min(spread, #pages))
  if spread % 2 == 0 then spread = spread - 1 end
  renderPage(win.left, pages[spread], spread)
  renderPage(win.right, pages[spread + 1], spread + 1)
  win.prev:SetShown(spread > 1); win.next:SetShown(spread + 1 < #pages)
  for _, r in ipairs(win.ribbons) do
    local active = r.name == tab
    r:SetWidth(active and RIBBON_LEN + 12 or RIBBON_LEN)
    r.shadow:SetAlpha(active and 0.55 or 0.35)
    r.label:SetTextColor(active and 1 or 0.92, active and 0.95 or 0.86, active and 0.8 or 0.7)
  end
end

J.helpers = { dayBlocks = function(...) return dayBlocks(...) end, matches = function(e) return matches(e) end, short = short, dayLabel = dayLabel, row = row, entryRow = entryRow, clean = clean }
-- test hook: layout of the current tab (page count, per-page used height, kinds)
function J._Layout()
  paginate(buildBlocks())
  local out = { PAGE_H = PAGE_H, pages = {} }
  for i, pg in ipairs(pages) do local kinds = {}; for _, b in ipairs(pg.items) do kinds[#kinds + 1] = b.kind end; out.pages[i] = { used = pg.used or 0, kinds = table.concat(kinds, ",") } end
  return out
end
function J.Refresh()
  if not (win and win:IsShown()) then return end
  paginate(buildBlocks()); render()
end

local function flip(dir)
  local target = spread + dir * 2
  if target < 1 or target > #pages then return end
  if win.flipAnim:IsPlaying() then return end
  win.flipDir = dir; win.flipTarget = target
  win.flipAnim:Play()
end

J.Flip = function(dir) flip(dir) end
------------------------------------------------------------------ frame
-- v0.6.8: book size. Auto scale from the UI height (UIParent units, so it follows UI scale and resolution:
-- ~1.15 at 1080p default UI, more on 1440p/4K with a small UI scale), times the user's "Book size" slider,
-- clamped so the whole book (+ side ribbons) always fits on screen.
function J.AutoScale()
  local h = (UIParent and UIParent:GetHeight()) or 768
  return math.max(0.8, math.min(2.2, (h * 0.74) / BH))
end
function J.ComputeScale()
  local pct = tonumber(C.set and C.set.bookSize) or 100
  local s = J.AutoScale() * math.max(0.5, math.min(1.6, pct / 100))
  local uw, uh = (UIParent and UIParent:GetWidth()) or 1024, (UIParent and UIParent:GetHeight()) or 768
  local fit = math.min((uw * 0.96) / (BW + RIBBON_LEN), (uh * 0.94) / (BH + 30))
  return math.max(0.4, math.min(s, fit))
end
function J.ApplyScale()
  if not win then return end
  local s = J.ComputeScale()
  if math.abs((win:GetScale() or 1) - s) > 0.001 then win:SetScale(s) end
  return s
end
C.On("DISPLAY_SIZE_CHANGED", function() J.ApplyScale() end)
C.On("UI_SCALE_CHANGED", function() J.ApplyScale() end)

local function create()
  local M = C.MEDIA
  win = CreateFrame("Frame", "JourneykeeperJournal", UIParent)
  win:SetSize(BW, BH); win:SetPoint("CENTER", 0, -20); win:SetFrameStrata("DIALOG"); win:SetToplevel(true)
  win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton"); win:SetClampedToScreen(true)
  win:SetClampRectInsets(0, RIBBON_LEN - RIBBON_TUCK, 0, 0) -- keep the side ribbons on screen too
  -- drag only via Shift or the leather border, so clicks/wheel on the pages never nudge the book
  win:SetScript("OnDragStart", function(self) self:StartMoving() end)
  win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); local p, _, rp, x, y = self:GetPoint(); if C.set then C.set.bookPos = { p, rp, x, y } end end)
  win:SetUserPlaced(false)
  local bp = C.set and C.set.bookPos
  if type(bp) == "table" and bp[1] then win:ClearAllPoints(); win:SetPoint(bp[1], UIParent, bp[2] or bp[1], tonumber(bp[3]) or 0, tonumber(bp[4]) or 0) end
  win:HookScript("OnShow", function() J.ApplyScale() end)
  tinsert(UISpecialFrames, "JourneykeeperJournal")
  local bg = win:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(M .. "book"); bg:SetAllPoints()
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButtonNoScripts"); close:SetPoint("TOPRIGHT", -2, -2); close:SetScript("OnClick", function() win:Hide() end)
  if C.Photo then win.cam = C.Photo.Button(win, function() return C.lastEchoEntry or C.lastEntry end); win.cam:SetPoint("RIGHT", close, "LEFT", -4, 0)
    win:HookScript("OnShow", function() win.cam:SetShown(C.set.photoMode) end) end
  measure = win:CreateFontString(nil, "OVERLAY"); measure:SetFont(FONT_BODY, 13, ""); measure:SetSpacing(2); measure:Hide()
  win.left, win.right = makePage(LEFT_X), makePage(RIGHT_X)
  -- page flip: fade + slide both pages, swap content at midpoint
  local content = { win.left, win.right }
  -- v0.6.8: the old Translation animation ran on the whole book frame, so every wheel step / page turn made the
  -- book jump sideways. The flip is now a pure timer-driven fade of the two page frames; the book never moves.
  win.flipAnim = win:CreateAnimationGroup()
  local out = win.flipAnim:CreateAnimation("Alpha"); out:SetFromAlpha(1); out:SetToAlpha(1); out:SetDuration(0.12)
  win.flipAnim:SetScript("OnPlay", function() for _, p in ipairs(content) do p:SetAlpha(0.15) end end)
  win.flipAnim:SetScript("OnFinished", function()
    spread = win.flipTarget; render()
    for _, p in ipairs(content) do p:SetAlpha(1) end
    PlaySound((SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN) or 836, "SFX")
  end)
  -- page curls
  local function curl(side)
    local b = CreateFrame("Button", nil, win); b:SetFrameLevel(win:GetFrameLevel() + 8)
    local t = b:CreateTexture(nil, "OVERLAY"); t:SetAllPoints(); t:SetTexture(M .. "curl")
    b:SetSize(40, 40)
    if side == "left" then b:SetPoint("BOTTOMLEFT", 22, 22); t:SetTexCoord(1, 0, 0, 1) else b:SetPoint("BOTTOMRIGHT", -22, 22) end
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(M .. "curl"); hl:SetBlendMode("ADD"); hl:SetAlpha(0.35)
    if side == "left" then hl:SetTexCoord(1, 0, 0, 1) end
    b:SetScript("OnClick", function() flip(side == "left" and -1 or 1) end)
    return b
  end
  win.prev, win.next = curl("left"), curl("right")
  win:EnableMouseWheel(true); win:SetScript("OnMouseWheel", function(_, d) flip(d > 0 and -1 or 1) end)
  J.ApplyScale()
  -- v0.6.8: silk bookmark ribbons are side tabs sticking out of the RIGHT edge of the cover (never over the pages).
  -- Same ribbon_silk texture, rotated 90 degrees with texcoords (no new file, /reload is enough).
  win.ribbons = {}
  local RH, RTOP = 34, 34
  local RGAP = math.min(50, floor((BH - RTOP - RH - 12) / math.max(1, #TABS - 1))) -- v0.7.1: 10 ribbons still fit the cover
  for i, def in ipairs(TABS) do
    local r = CreateFrame("Button", nil, win); r:SetSize(RIBBON_LEN, RH)
    r:SetPoint("LEFT", win, "TOPRIGHT", -RIBBON_TUCK, -(RTOP + (i - 1) * RGAP) - RH / 2); r:SetFrameLevel(math.max(1, win:GetFrameLevel() - 1))
    r.shadow = r:CreateTexture(nil, "BACKGROUND"); r.shadow:SetTexture(M .. "ribbon_shadow"); r.shadow:SetPoint("TOPLEFT", 4, -3); r.shadow:SetPoint("BOTTOMRIGHT", 6, -5)
    r.shadow:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
    local tx = r:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints(); tx:SetTexture(M .. "ribbon_silk"); tx:SetVertexColor(def[2] * 1.25, def[3] * 1.25, def[4] * 1.25)
    tx:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1) -- texture top -> left (tucked under the cover), tail -> right
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(M .. "ribbon_silk"); hl:SetBlendMode("ADD"); hl:SetAlpha(0.25)
    hl:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
    r.label = r:CreateFontString(nil, "OVERLAY"); r.label:SetFont(FONT_HEAD, 11, ""); r.label:SetPoint("LEFT", RIBBON_TUCK + 4, 1); r.label:SetWidth(RIBBON_LEN - RIBBON_TUCK - 18)
    r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
    r.label:SetShadowOffset(1, -1); r.label:SetShadowColor(0, 0, 0, 0.8); r.label:SetText(def[1])
    r.name = def[1]
    r:SetScript("OnClick", function() tab = def[1]; spread = 1; J.Refresh() end)
    win.ribbons[i] = r
  end
  -- footer: one even button bar inside the bottom leather band; search right-aligned
  local bar = CreateFrame("Frame", nil, win); bar:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 70, 4); bar:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -70, 4); bar:SetHeight(20)
  bar:SetFrameLevel(win:GetFrameLevel() + 4)
  local acts = { { "HTML", function() J.ExportHTML() end }, { "Export", function() J.Export() end }, { "Note", function() C.Notes.Prompt() end },
    { "Settings", function() C.OpenSettings() end }, { "Test echo", function() C.Toast.Test() end } }
  local BTN_W, BTN_GAP = 78, 8
  for i, a in ipairs(acts) do
    local b = CreateFrame("Button", nil, bar); b:SetSize(BTN_W, 20); b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (BTN_W + BTN_GAP), 0)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.12, 0.07, 0.03, 0.55)
    local edge = b:CreateTexture(nil, "BORDER"); edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetHeight(1); edge:SetColorTexture(0.85, 0.65, 0.3, 0.6)
    local f = b:CreateFontString(nil, "OVERLAY"); f:SetFont(FONT_HEAD, 12, ""); f:SetTextColor(0.92, 0.8, 0.52); f:SetPoint("CENTER"); f:SetText(a[1])
    b:SetScript("OnEnter", function() f:SetTextColor(1, 0.95, 0.75); bg:SetColorTexture(0.25, 0.14, 0.05, 0.7) end)
    b:SetScript("OnLeave", function() f:SetTextColor(0.92, 0.8, 0.52); bg:SetColorTexture(0.12, 0.07, 0.03, 0.55) end)
    b:SetScript("OnClick", a[2])
  end
  local sb = CreateFrame("EditBox", nil, bar); sb:SetSize(200, 20); sb:SetPoint("RIGHT", bar, "RIGHT", 0, 0); sb:SetAutoFocus(false); sb:SetTextInsets(6, 6, 0, 0)
  sb:SetFont(FONT_BODY, 12, ""); sb:SetTextColor(0.95, 0.88, 0.7)
  local sbg = sb:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints(); sbg:SetColorTexture(0.12, 0.07, 0.03, 0.55)
  local line = sb:CreateTexture(nil, "BORDER"); line:SetColorTexture(0.85, 0.65, 0.3, 0.6); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  local ph = sb:CreateFontString(nil, "OVERLAY"); ph:SetFont(FONT_HEAD, 12, ""); ph:SetTextColor(0.8, 0.68, 0.45); ph:SetPoint("LEFT", 6, 0); ph:SetText("Search the journal...")
  sb:SetScript("OnTextChanged", function(self) search = self:GetText() or ""; ph:SetShown(search == ""); spread = 1; J.Refresh() end)
  sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  win.footer = bar
end

function J.Toggle()
  if not win then create() end
  if win:IsShown() then win:Hide() else win:Show(); J.Refresh() end
end

function J.SetEchoFilter(cat) echoFilter = (cat and C.CATS[cat]) and cat or nil end
function J.CycleEchoFilter(dir)
  local list = { false }
  for _, k in ipairs(C.CAT_ORDER) do if C.CATS[k] then list[#list + 1] = k end end
  local idx = 1
  for i, v in ipairs(list) do if v == (echoFilter or false) then idx = i end end
  idx = (idx - 1 + (dir or 1)) % #list + 1
  J.SetEchoFilter(list[idx] or nil); spread = 1; J.Refresh()
end
function J.OpenTab(name)
  if name == "Diary" then name = "Echoes" end
  if not win then create() end
  tab, search, spread = name, "", 1
  win:Show(); J.Refresh()
end

-- open the Chapters tab at a character's title page
function J.OpenChapter(ck)
  if not win then create() end
  tab, search = "Chapters", ""
  win:Show(); paginate(buildBlocks())
  spread = titlePage[ck] or 1
  render()
end
function J.OpenSearch(name, text)
  if not win then create() end
  tab, search, spread = name, text or "", 1
  win:Show(); J.Refresh()
end

-- Sketch page: ink dots at relative positions (0..1) joined by ink lines, numbered, with a title/caption.
-- Used by the Journey chapter (continent overview). Objects are pooled per page.
-- Zoomable map: a clipping frame on the page holds a canvas we re-layout on zoom/pan.
-- Everything on the canvas is positioned from normalized 0..1 coords, so dots/lines stay exact.
local ZMAX = 6
local function mapLayout(clip)
  local W, H, z = clip.W, clip.H, clip.zoom
  local cw, ch = W * z, H * z
  clip.ox = math.min(0, math.max(W - cw, clip.ox)); clip.oy = math.min(0, math.max(H - ch, clip.oy))
  local function px(nx, ny) return clip.ox + nx * cw, -(clip.oy + ny * ch) end
  for _, it in ipairs(clip.items) do
    local o = it.o
    if it.kind == "tile" or it.kind == "bg" then
      o:ClearAllPoints(); local x, y = px(it.nx, it.ny); o:SetPoint("TOPLEFT", clip, "TOPLEFT", x, y); o:SetSize(math.max(1, it.nw * cw), math.max(1, it.nh * ch))
    elseif it.kind == "line" then
      local x1, y1 = px(it.a[1], it.a[2]); local x2, y2 = px(it.b[1], it.b[2])
      o:SetStartPoint("TOPLEFT", clip, x1, y1); o:SetEndPoint("TOPLEFT", clip, x2, y2)
    elseif it.kind == "pt" then
      o:ClearAllPoints(); local x, y = px(it.nx, it.ny); o:SetPoint("CENTER", clip, "TOPLEFT", x, y)
    end
  end
  if clip.zlabel then clip.zlabel:SetText(z > 1.01 and format("%.1fx", z) or "") end
end
function J.MapZoom(clip, factor, cx, cy)
  local z1 = clip.zoom; local z2 = math.max(1, math.min(ZMAX, z1 * factor))
  if z2 == z1 then return end
  cx, cy = cx or clip.W / 2, cy or clip.H / 2
  clip.ox = cx - (cx - clip.ox) * (z2 / z1); clip.oy = cy - (cy - clip.oy) * (z2 / z1)
  clip.zoom = z2; mapLayout(clip)
end
function J.MapReset(clip) clip.zoom, clip.ox, clip.oy = 1, 0, 0; mapLayout(clip) end
local function cursorIn(clip)
  local x, y = GetCursorPosition(); local s = clip:GetEffectiveScale()
  local l, tp = clip:GetLeft() or 0, clip:GetTop() or 0
  return x / s - l, tp - y / s
end

local function getClip(p)
  local clip = rawget(p, "mapClip")
  if clip then return clip end
  clip = CreateFrame("Frame", nil, p); p.mapClip = clip
  if clip.SetClipsChildren then clip:SetClipsChildren(true) end
  clip:EnableMouse(true); clip:EnableMouseWheel(true)
  clip.pool, clip.items = {}, {}
  clip:SetScript("OnMouseWheel", function(self, d) local cx, cy = cursorIn(self); J.MapZoom(self, d > 0 and 1.25 or 0.8, cx, cy) end)
  clip:SetScript("OnMouseDown", function(self, btn)
    if btn ~= "LeftButton" then return end
    local now = GetTime()
    if self.lastDown and now - self.lastDown < 0.35 then self.lastDown = nil; J.MapReset(self); return end
    self.lastDown = now
    if self.zoom > 1 then local cx, cy = cursorIn(self); self.drag = { cx, cy, self.ox, self.oy } end
  end)
  clip:SetScript("OnMouseUp", function(self) self.drag = nil end)
  clip:SetScript("OnHide", function(self) self.drag = nil end)
  clip:SetScript("OnUpdate", function(self)
    if not self.drag then return end
    if not IsMouseButtonDown("LeftButton") then self.drag = nil return end
    local cx, cy = cursorIn(self); self.ox = self.drag[3] + (cx - self.drag[1]); self.oy = self.drag[4] + (cy - self.drag[2]); mapLayout(self)
  end)
  -- controls: + / - / fit (own fontstring buttons, top-right of the map)
  local function ctl(label, xoff, fn, tip)
    local bt = CreateFrame("Button", nil, clip); bt:SetSize(20, 18); bt:SetPoint("TOPRIGHT", clip, "TOPRIGHT", xoff, -2); bt:SetFrameLevel(clip:GetFrameLevel() + 20)
    local bg = bt:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.2, 0.13, 0.06, 0.55)
    local fs = bt:CreateFontString(nil, "OVERLAY"); fs:SetFont(FONT_HEAD, 13, ""); fs:SetPoint("CENTER"); fs:SetTextColor(1, 0.86, 0.55); fs:SetText(label)
    bt:SetScript("OnClick", fn)
    bt:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end)
    bt:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return bt
  end
  ctl("+", -48, function() J.MapZoom(clip, 1.5) end, "Zoom in (or mouse wheel)")
  ctl("-", -26, function() J.MapZoom(clip, 1 / 1.5) end, "Zoom out")
  ctl("o", -4, function() J.MapReset(clip) end, "Fit the whole map (or double-click)")
  -- continent switcher (top-left), styled like the world map's continent picker
  clip.tabs = {}
  for i, c in ipairs(C.Journey and C.Journey.CONTS or {}) do
    local bt = CreateFrame("Button", nil, clip); bt:SetSize(i == 1 and 70 or 112, 18); bt:SetFrameLevel(clip:GetFrameLevel() + 20)
    bt:SetPoint("TOPLEFT", clip, "TOPLEFT", i == 1 and 4 or 78, -2)
    bt.bg = bt:CreateTexture(nil, "BACKGROUND"); bt.bg:SetAllPoints()
    bt.fs = bt:CreateFontString(nil, "OVERLAY"); bt.fs:SetFont(FONT_HEAD, 12, ""); bt.fs:SetPoint("CENTER"); bt.fs:SetText(c.name)
    bt.id = c.id
    bt:SetScript("OnClick", function() C.Journey.SetCont(c.id) end)
    clip.tabs[i] = bt
  end
  clip.zlabel = clip:CreateFontString(nil, "OVERLAY"); clip.zlabel:SetFont(FONT_BODY, 10, ""); clip.zlabel:SetPoint("TOPRIGHT", clip, "TOPRIGHT", -72, -5); clip.zlabel:SetTextColor(1, 0.9, 0.7)
  return clip
end

function J.DrawSketch(p, b)
  p.sketchObjs = rawget(p, "sketchObjs") or {}
  local n = 0
  local function obj(kind)
    n = n + 1
    local o = p.sketchObjs[n]
    if not o or o.kind ~= kind then
      if kind == "line" then o = p:CreateLine(nil, "ARTWORK"); o:SetThickness(2)
      else o = p:CreateFontString(nil, "OVERLAY"); o:SetFont(kind == "title" and FONT_HEAD or FONT_BODY, kind == "title" and 22 or 10, "") end
      o.kind = kind; p.sketchObjs[n] = o
    end
    o:ClearAllPoints(); o:Show(); return o
  end
  local W, H, top = PAGE_W, PAGE_H - 90, 46
  local t = obj("title"); t:SetPoint("TOP", p, "TOP", 0, -4); t:SetTextColor(unpack(RED)); t:SetText(b.title or "")
  local frame = obj("line"); frame:SetColorTexture(0.45, 0.35, 0.22, 0.5); frame:SetStartPoint("TOPLEFT", p, 0, -top); frame:SetEndPoint("TOPLEFT", p, W, -top)
  local frame2 = obj("line"); frame2:SetColorTexture(0.45, 0.35, 0.22, 0.5); frame2:SetStartPoint("TOPLEFT", p, 0, -top - H); frame2:SetEndPoint("TOPLEFT", p, W, -top - H)
  if b.caption then local c = obj("label"); c:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -top - H - 8); c:SetWidth(W); c:SetJustifyH("LEFT"); c:SetTextColor(unpack(FADED)); c:SetText(b.caption .. "  (wheel: zoom · drag: pan · double-click: fit)") end

  local clip = getClip(p)
  clip:ClearAllPoints(); clip:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -top); clip:SetSize(W, H); clip:Show()
  local key = tostring(b.contID or b.title) .. "#" .. #(b.points or {})
  if clip.key ~= key then clip.key = key; clip.zoom, clip.ox, clip.oy = 1, 0, 0 end
  clip.W, clip.H = W, H
  for _, bt in ipairs(clip.tabs or {}) do
    bt:SetShown(b.switcher and true or false)
    local on = bt.id == b.contID
    bt.bg:SetColorTexture(on and 0.45 or 0.2, on and 0.12 or 0.13, on and 0.06 or 0.06, on and 0.85 or 0.55)
    bt.fs:SetTextColor(on and 1 or 0.85, on and 0.92 or 0.75, on and 0.7 or 0.5)
  end
  for _, o in ipairs(clip.pool) do o:Hide() end
  wipe(clip.items)
  local used = {}
  local function cobj(kind)
    used[kind] = (used[kind] or 0) + 1
    clip.pool[kind] = clip.pool[kind] or {}
    local o = clip.pool[kind][used[kind]]
    if not o then
      if kind == "line" then o = clip:CreateLine(nil, "ARTWORK"); o:SetThickness(2)
      elseif kind == "tile" or kind == "bg" then o = clip:CreateTexture(nil, "BORDER")
      elseif kind == "tint" then o = clip:CreateTexture(nil, "BORDER", nil, 3)
      elseif kind == "dot" then o = clip:CreateTexture(nil, "OVERLAY"); o:SetTexture(C.MEDIA .. "dot")
      elseif kind == "seal" then o = clip:CreateTexture(nil, "OVERLAY", nil, 2); o:SetTexture(C.MEDIA .. "pin_seal"); o:SetSize(22, 22)
      else o = clip:CreateFontString(nil, "OVERLAY"); o:SetFont(FONT_BODY, 10, "") end
      clip.pool[kind][used[kind]] = o; tinsert(clip.pool, o)
    end
    o:Show(); return o
  end
  local art = C.set.journeyRealMap ~= false and C.Journey and C.Journey.MapTiles and C.Journey.MapTiles(b.contID)
  local drewArt = false
  if art then
    drewArt = pcall(function()
      for r = 0, art.rows - 1 do
        for c = 0, art.cols - 1 do
          local i = r * art.cols + c + 1
          local vw = math.min(art.tw, art.lw - c * art.tw); local vh = math.min(art.th, art.lh - r * art.th)
          local tl = cobj("tile"); tl:SetTexture(art.tex[i]); tl:SetVertexColor(1, 0.94, 0.82, 0.92); tl:SetTexCoord(0, vw / art.tw, 0, vh / art.th)
          tinsert(clip.items, { kind = "tile", o = tl, nx = c * art.tw / art.lw, ny = r * art.th / art.lh, nw = vw / art.lw, nh = vh / art.lh })
        end
      end
    end)
  end
  if not drewArt and b.map then
    local m = cobj("bg"); m:SetTexture(b.map); m:SetTexCoord(0, 1, 0, 1); m:SetVertexColor(1, 1, 1, 0.95)
    tinsert(clip.items, { kind = "bg", o = m, nx = 0, ny = 0, nw = 1, nh = 1 })
  end
  local full = drewArt or b.map
  if drewArt then -- fixed parchment vignette over the clip (does not zoom)
    local v = cobj("tint"); v:SetTexture(C.MEDIA .. "vignette"); v:SetTexCoord(0, 1, 0, 1); v:SetVertexColor(0.55, 0.4, 0.2, 0.55); v:ClearAllPoints(); v:SetAllPoints(clip)
  end
  local function norm(pt) if full then return pt.x, pt.y end return (10 + pt.x * (W - 20)) / W, (10 + pt.y * (H - 20)) / H end
  local prev
  for i, pt in ipairs(b.points or {}) do
    local nx, ny = norm(pt)
    if prev then
      local l = cobj("line"); l:SetColorTexture(INK[1], INK[2], INK[3], 0.6)
      tinsert(clip.items, { kind = "line", o = l, a = prev, b = { nx, ny } })
    end
    if pt.first then local s = cobj("seal"); s:SetVertexColor(0.75, 0.2, 0.12); tinsert(clip.items, { kind = "pt", o = s, nx = nx, ny = ny }) end
    local d = cobj("dot")
    if pt.level then d:SetSize(12, 12); d:SetVertexColor(1, 0.78, 0.2) else d:SetSize(10, 10); d:SetVertexColor(0.5, 0.1, 0.05) end
    tinsert(clip.items, { kind = "pt", o = d, nx = nx, ny = ny })
    local lb = cobj("label"); lb:ClearAllPoints(); lb:SetPoint("LEFT", d, "RIGHT", 4, 0); lb:SetTextColor(unpack(pt.first and RED or INK)); lb:SetText(pt.label or tostring(i))
    prev = { nx, ny }
  end
  mapLayout(clip)
end

-- Deep link: open the Timeline at the spread containing entry index i.
function J.OpenAt(i)
  if not win then create() end
  tab, search = "Timeline", ""
  win:Show(); paginate(buildBlocks())
  spread = entryPage[i] or 1
  render()
end

-- v0.6.8: detail card for one row (echo or memory). Own frame, anchored next to the book.
local det
function J.ShowDetail(b, anchor)
  if not det then
    det = CreateFrame("Frame", "JourneykeeperDetail", UIParent, "BasicFrameTemplateWithInset")
    det:SetSize(380, 220); det:SetFrameStrata("FULLSCREEN_DIALOG"); det:SetClampedToScreen(true); det:SetToplevel(true)
    tinsert(UISpecialFrames, "JourneykeeperDetail")
    det.meta = det:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); det.meta:SetPoint("TOPLEFT", 14, -32); det.meta:SetWidth(352); det.meta:SetJustifyH("LEFT")
    det.text = det:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); det.text:SetPoint("TOPLEFT", det.meta, "BOTTOMLEFT", 0, -8); det.text:SetWidth(352); det.text:SetJustifyH("LEFT"); det.text:SetJustifyV("TOP")
    det.open = CreateFrame("Button", nil, det, "UIPanelButtonTemplate"); det.open:SetSize(150, 22); det.open:SetPoint("BOTTOMLEFT", 12, 10); det.open:SetText("Show in Timeline")
    det.more = CreateFrame("Button", nil, det, "UIPanelButtonTemplate"); det.more:SetSize(110, 22); det.more:SetPoint("BOTTOMRIGHT", -12, 10); det.more:SetText("Options...")
  end
  if det.TitleText then det.TitleText:SetText(b.title or (C.CATS[b.cat or ""] or {}).label or "Memory") end
  local meta = {}
  if b.t then meta[#meta + 1] = date("%A, %d %B %Y  %H:%M", b.t) end
  if b.char then meta[#meta + 1] = short(b.char) end
  if b.zone and b.zone ~= "" then meta[#meta + 1] = b.zone end
  local c = (C.CATS[b.cat or ""] or {}).label; if c then meta[#meta + 1] = c end
  det.meta:SetText(table.concat(meta, "  ·  "))
  local body = b.text or ""
  local ent = b.entries and b.entries[1] and C.db.entries[b.entries[1]]
  if b.echo and ent and ent.text then body = body .. "\n\n|cffb0a080Remembered moment:|r " .. clean(ent.text) end
  det.text:SetText(body)
  local linked = b.entries and #b.entries > 0
  det.open:SetShown(linked); det.more:SetShown(linked)
  det.open:SetScript("OnClick", function() det:Hide(); J.OpenAt(b.entries[1]) end)
  det.more:SetScript("OnClick", function(self) C.Menu(self, C.MemoryMenuItems({ entries = b.entries, cat = b.cat }), "This moment") end)
  det:SetHeight(math.max(140, 90 + (det.text:GetStringHeight() or 40)))
  det:ClearAllPoints()
  if win and win:IsShown() then det:SetPoint("CENTER", win, "CENTER", 0, 0) else det:SetPoint("CENTER") end
  det:Show()
  J.lastDetail = b
  return det
end

-- simple note prompt (own frame)
local np
function J.NotePrompt()
  if not np then
    np = CreateFrame("Frame", "JourneykeeperNotePrompt", UIParent, "BasicFrameTemplateWithInset")
    np:SetSize(360, 80); np:SetPoint("CENTER", 0, 160); np:SetFrameStrata("FULLSCREEN_DIALOG")
    np.TitleText:SetText("Note on target (or last ally)")
    local eb = CreateFrame("EditBox", nil, np, "InputBoxTemplate"); eb:SetSize(320, 20); eb:SetPoint("BOTTOM", 0, 16); eb:SetAutoFocus(true)
    eb:SetScript("OnEnterPressed", function(self) C.AddNote(self:GetText()); self:SetText(""); np:Hide(); J.Refresh() end)
    eb:SetScript("OnEscapePressed", function() np:Hide() end)
    np.eb = eb
  end
  np:Show(); np.eb:SetFocus()
end

-- export
local exf
function J.Export(htmlText)
  if not exf then
    exf = CreateFrame("Frame", "JourneykeeperExport", UIParent, "BasicFrameTemplateWithInset")
    exf:SetSize(640, 440); exf:SetPoint("CENTER"); exf:SetFrameStrata("FULLSCREEN_DIALOG")
    exf.TitleText:SetText("Journeykeeper export - Ctrl+A, Ctrl+C")
    exf:SetMovable(true); exf:EnableMouse(true); exf:RegisterForDrag("LeftButton")
    exf:SetScript("OnDragStart", exf.StartMoving); exf:SetScript("OnDragStop", exf.StopMovingOrSizing)
    tinsert(UISpecialFrames, "JourneykeeperExport")
    local sf = CreateFrame("ScrollFrame", nil, exf, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -32); sf:SetPoint("BOTTOMRIGHT", -32, 12)
    local eb = CreateFrame("EditBox", nil, sf); eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(580); eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() exf:Hide() end)
    sf:SetScrollChild(eb); exf.eb = eb
  end
  local out = { "Journeykeeper — Echoes of Your Journey", "Exported " .. date("%d %b %Y %H:%M"), "" }
  for _, e in ipairs(C.db.entries) do
    out[#out + 1] = format("%s  [%s]  %s", date("%Y-%m-%d %H:%M", e.t), (C.CATS[e.cat] or {}).label or e.cat, e.text or "")
  end
  out[#out + 1] = ""; out[#out + 1] = "Allies:"
  for _, p in pairs(C.db.players) do
    local notes = {}
    for _, n in ipairs(p.notes or {}) do notes[#notes + 1] = n.text end
    out[#out + 1] = format("  %s (%s) grouped %dx, last %s%s", p.name or "?", p.class or "?", p.count or 0, p.lastWhere or "?",
      #notes > 0 and (" - " .. table.concat(notes, "; ")) or "")
  end
  exf.TitleText:SetText(htmlText and "Journeykeeper HTML book - Ctrl+A, Ctrl+C, save as .html" or "Journeykeeper export - Ctrl+A, Ctrl+C")
  exf.eb:SetText(htmlText or table.concat(out, "\n")); exf:Show(); exf.eb:HighlightText(); exf.eb:SetFocus()
end

-- HTML book of the highest-weight memories (copy from the box into a .html file)
local function esc(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1"):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
function J.ExportHTML()
  local top = C.TopEntries(C.set.htmlTop)
  table.sort(top, function(a, b) return C.db.entries[a.i].t < C.db.entries[b.i].t end)
  local out = { '<!doctype html><html><head><meta charset="utf-8"><title>Journeykeeper</title><style>',
    'body{background:#2b1d14;margin:0;padding:40px;font-family:Georgia,serif}.book{max-width:820px;margin:auto;background:#ecd9ae;padding:56px 64px;border:14px solid #5a2418;border-radius:10px;box-shadow:0 10px 40px #000;color:#3d240c}',
    'h1{font-variant:small-caps;color:#7e1a0a;text-align:center;font-size:42px;margin:0}h2{color:#7e1a0a;font-variant:small-caps;border-bottom:1px solid #b08850;margin-top:36px}',
    'p{line-height:1.6;text-indent:1.5em}.pin{color:#a06010}.w{float:right;color:#a08860;font-size:12px}.sub{text-align:center;font-style:italic}',
    '</style></head><body><div class="book"><h1>Journeykeeper</h1><p class="sub">Journeykeeper - the ' .. #top .. ' weightiest memories, ' .. date("%d %B %Y") .. '</p>' }
  local day
  for _, it in ipairs(top) do
    local e = C.db.entries[it.i]
    local d = date("%A, %d %B %Y", e.t)
    if d ~= day then day = d; out[#out + 1] = "<h2>" .. d .. "</h2>" end
    out[#out + 1] = format('<p>%s%s <span class="w">%s · weight %.1f</span></p>', e.anchor and '<span class="pin">&#10022; </span>' or "", esc(e.text), esc((e.char or ""):match("^[^-]+")), it.w)
  end
  out[#out + 1] = "</div></body></html>"
  J.Export(table.concat(out, "\n"))
end
