-- Journey map: per-character path through the world. Book chapter (zone sequence with first-visit dates,
-- level-ups, firsts, plus a continent sketch page per continent) and an optional world-map path overlay
-- drawn from the existing ghost-trail samples. Computation only when the journal/map is opened.
local _, C = ...
local JY = {}; C.Journey = JY
local placeCache = {}

-- position of a zone map on its continent (0..1), via C_Map; cached per session
local function continentOf(mapID)
  local id, guard = mapID, 0
  while id and guard < 8 do
    local info = C.API("C_Map.GetMapInfo", id)
    if not info then return nil end
    if info.mapType == 2 then return id, info.name end -- Enum.UIMapType.Continent
    id = info.parentMapID; guard = guard + 1
  end
end
function JY.Place(mapID)
  if not mapID then return nil end
  if placeCache[mapID] ~= nil then return placeCache[mapID] or nil end
  local cont, cname = continentOf(mapID)
  local res = false
  if cont then
    local l, r, t, b = C.API("C_Map.GetMapRectOnMap", mapID, cont)
    if l and r and t and b then res = { cont = cont, cname = cname, x = (l + r) / 2, y = (t + b) / 2 } end
  end
  placeCache[mapID] = res
  return res or nil
end

-- Stylized continent art (media/map_*.tga, drawn by tools/make_maps.py in the same 0..1 continent space
-- that C_Map.GetMapRectOnMap returns: x right, y down). Classic/Forever uiMapIDs: 1414 Kalimdor, 1415 Eastern Kingdoms.
function JY.MapArt(cont, cname)
  local n = (cname or ""):lower()
  if cont == 1414 or n:find("kalimdor") then return C.MEDIA .. "map_kalimdor" end
  if cont == 1415 or n:find("eastern") or n:find("östliche") or n:find("royaumes de l'est") then return C.MEDIA .. "map_eastern" end
  return nil
end

-- Real Blizzard map art for a uiMapID: { cols, rows, tw, th, lw, lh, tex = {...} } or nil.
-- Read-only C_Map calls; textures go on OUR frames only (never the Blizzard world map frame).
local artCache = {}
function JY.MapTiles(id)
  if not id then return nil end
  if artCache[id] ~= nil then return artCache[id] or nil end
  local res = false
  local ok, layers = pcall(C_Map.GetMapArtLayers, id)
  local L = ok and type(layers) == "table" and layers[1]
  if L and L.layerWidth and L.tileWidth and L.layerWidth > 0 and L.tileWidth > 0 then
    local ok2, tex = pcall(C_Map.GetMapArtLayerTextures, id, 1)
    if ok2 and type(tex) == "table" and #tex > 0 then
      local cols, rows = math.ceil(L.layerWidth / L.tileWidth), math.ceil(L.layerHeight / L.tileHeight)
      if #tex >= cols * rows then res = { cols = cols, rows = rows, tw = L.tileWidth, th = L.tileHeight, lw = L.layerWidth, lh = L.layerHeight, tex = tex } end
    end
  end
  artCache[id] = res
  return res or nil
end

JY.CONTS = { { id = 1414, name = "Kalimdor" }, { id = 1415, name = "Eastern Kingdoms" } }
function JY.ContName(id)
  local info = C.API("C_Map.GetMapInfo", id)
  if info and info.name and info.name ~= "" then return info.name end
  for _, c in ipairs(JY.CONTS) do if c.id == id then return c.name end end
  return "A distant land"
end
-- remembered choice; else the continent of the most recent stop; else Kalimdor
function JY.SelectedCont(stops)
  local sel = C.set.journeyCont
  for _, c in ipairs(JY.CONTS) do if c.id == sel then return sel end end
  for i = #(stops or {}), 1, -1 do local pl = JY.Place(stops[i].map); if pl then for _, c in ipairs(JY.CONTS) do if c.id == pl.cont then return pl.cont end end end end
  return 1414
end
function JY.SetCont(id) C.set.journeyCont = id; if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end end

-- ordered stops for a character: first visit per zone, with level-ups and firsts attached
function JY.Stops(ck)
  local stops, byZone, lvls = {}, {}, {}
  for i, e in ipairs(C.db.entries) do
    if e.char == ck then
      if (e.id == "zone_first_char" or e.id == "zone_first_account") and e.zone and not byZone[e.zone] then
        local st = { zone = e.zone, t = e.t, level = e.level, map = e.map, firsts = {}, levels = {}, entry = i }
        byZone[e.zone] = st; stops[#stops + 1] = st
      elseif e.id == "level_milestone" or e.id == "level_up" then
        local st = byZone[e.zone or ""]; if st then st.levels[#st.levels + 1] = e.newLevel or e.level end
      elseif e.accountFirst or e.id == "boss_first_kill" or e.id == "dungeon_enter_first" then
        local st = byZone[e.zone or ""]; if st and #st.firsts < 3 then st.firsts[#st.firsts + 1] = (e.text or ""):gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1") end
      end
    end
  end
  return stops
end

function JY.Build(blocks, search, H)
  local chars = {}
  for ck in pairs(C.db.chars) do chars[#chars + 1] = ck end
  table.sort(chars, function(a, b) if a == C.charKey() then return true elseif b == C.charKey() then return false end return a < b end)
  for _, ck in ipairs(chars) do
    if search == "" or ck:lower():find(search:lower(), 1, true) then
      local stops = JY.Stops(ck)
      if #stops > 0 then
        tinsert(blocks, { kind = "chapterhead", text = "The Road of " .. H.short(ck) })
        -- one map page per character, for the selected continent (switchable like the world map)
        if C.set.journeySketch then
          local cont = JY.SelectedCont(stops)
          local pts, n = {}, 0
          for i, st in ipairs(stops) do
            local pl = JY.Place(st.map)
            if pl and pl.cont == cont then
              n = n + 1
              pts[#pts + 1] = { x = pl.x, y = pl.y, label = tostring(i) .. (n == 1 and ("  " .. (st.zone or "")) or ""), level = #st.levels > 0, first = n == 1 }
            end
          end
          local name = JY.ContName(cont)
          tinsert(blocks, { kind = "sketch", title = name, points = pts, map = JY.MapArt(cont, name), contID = cont, switcher = true,
            caption = #pts > 0 and format("%s's path across %s: %d place%s, in the order first seen. Gold dots mark level-ups.", H.short(ck), name, #pts, #pts == 1 and "" or "s")
              or format("%s has not set foot in %s yet.", H.short(ck), name) })
        end
        for i, st in ipairs(stops) do
          local txt = format("%d.  %s, first reached on %s at level %d.", i, st.zone, C.dateStr(st.t), st.level or 0)
          if #st.levels > 0 then txt = txt .. format(" Grew to level %s here.", table.concat(st.levels, ", ")) end
          if #st.firsts > 0 then txt = txt .. " " .. table.concat(st.firsts, " ") end
          tinsert(blocks, H.row({ cat = (st.levels and #st.levels > 0) and "level" or "zone", t = st.t, title = format("%d. %s", i, st.zone or "?"), text = txt:gsub("^%d+%.%s+", ""), entries = { st.entry } }))
        end
      end
    end
  end
  if #blocks == 0 then tinsert(blocks, { kind = "chapterhead", text = "Journey" }); tinsert(blocks, { kind = "para", dropcap = true, text = "No journey yet - step into a new zone and the road begins." }) end
  if C.Photo then C.Photo.AlbumBlocks(blocks, search) end
end

-- world map overlay: ink path through this character's ghost-trail samples on the shown map (max 300 segments)
local lines, used = {}, 0
function JY.DrawOverlay(canvas, mapID, scale)
  for i = 1, used do lines[i]:Hide() end
  used = 0
  if not (C.set.journey and C.set.journeyOverlay) then return end
  local pts = {}
  for _, p in ipairs(C.db.trail[C.charKey()] or {}) do if p[1] == mapID then pts[#pts + 1] = p end end
  if #pts < 2 then return end
  local step = math.max(1, math.ceil(#pts / 300))
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local prev
  for i = 1, #pts, step do
    local p = pts[i]
    local x, y = p[2] / 100 * w, -p[3] / 100 * h
    if prev and math.abs(prev[1] - x) + math.abs(prev[2] - y) < w * 0.15 then -- skip teleports/flights
      used = used + 1
      local l = lines[used]
      if not l then l = canvas:CreateLine(nil, "OVERLAY"); lines[used] = l end
      l:SetThickness(2 / (scale or 1)); l:SetColorTexture(0.85, 0.65, 0.3, 0.75)
      l:SetStartPoint("TOPLEFT", canvas, prev[1], prev[2]); l:SetEndPoint("TOPLEFT", canvas, x, y); l:Show()
    end
    prev = { x, y }
  end
end

C.Init(function()
  C.Journal.PROVIDERS.Journey = { enabled = function() return C.set.journey end, build = JY.Build }
end)
