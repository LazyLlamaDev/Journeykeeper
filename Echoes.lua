-- Echo engine: relevance scoring, intensity thresholds, combat/instance suppression, mute list, channels.
local _, C = ...
local E = {}; C.Echoes = E
local lastGlobal, pending = 0, {}
C.INTENSITY = {
  silent = nil,
  soft = { min = 5, global = 180, key = 3600 },
  present = { min = 3, global = 30, key = 900 },
  storyteller = { min = 1, global = 8, key = 240 },
}
C.INTENSITY_ORDER = { "silent", "soft", "present", "storyteller" }

-- meta: first, anniversary, absenceDays, shared (count), entry (journal index)
function E.Score(id, key, meta, force)
  local ev = C.EV[id]; meta = meta or {}
  if ev.cat == "warband" and not C.set.warbandEcho and id == "warband_echo" then return -99 end
  local e = meta.entry and C.db.entries[meta.entry]
  local s = e and C.EntryWeight(e) or ((C.BASE_WEIGHT[ev.cat] or 1) + (C.set.catBoost[ev.cat] or 0))
  if meta.guid and C.db.players[meta.guid] then s = s + C.EntryWeight({ cat = "group", id = "x", guid = meta.guid, anchor = false }) - (C.BASE_WEIGHT.group or 2) end
  if meta.first then s = s + 2 end
  if meta.anniversary then s = s + 3 end
  if meta.absenceDays and meta.absenceDays >= 30 then s = s + 2 end
  if meta.shared and meta.shared >= 3 then s = s + 1 end
  local seen = key and C.db.echoSeen[key]
  if seen then
    local h = (time() - seen) / 3600
    if h < 24 then s = s - 3 elseif h < 168 then s = s - 1 end
  end
  if force then s = s + 5 end
  return s
end

local function echoChatFrame()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local name = GetChatWindowInfo(i)
    if name == "Echoes" then return _G["ChatFrame" .. i] end
  end
  return DEFAULT_CHAT_FRAME
end

-- automatic intensity curve: returns a delta on the minimum score
function E.CurveDelta()
  if not C.set.autoCurve then return 0 end
  local d = 0
  local inInst, itype = IsInInstance()
  if itype == "raid" then d = d + 2 elseif inInst then d = d + 1 end
  if C.sessionStart and time() - C.sessionStart > 2 * 3600 then d = d + 1 end
  if IsResting() then d = d - 1 end
  return d
end

local function deliver(item)
  if C.Flavor and item.id ~= "friend_milestone" then item.text = C.Flavor.Apply(item.text, item.cat) end
  local ch, cat = item.ch, C.CATS[item.cat]
  C.db.echoSeen[item.key or item.text] = time()
  if item.entry then C.Reinforce(item.entry); C.lastEchoEntry = item.entry end
  tinsert(C.db.diary, { t = time(), id = item.id, cat = item.cat, title = item.title, text = item.text, entry = item.entry, score = item.score, char = C.charKey() })
  while #C.db.diary > 500 do tremove(C.db.diary, 1) end
  if C.Atmos then C.Atmos.OnEcho(item) end
  if ch == "chat" or ch == "echoes" then
    local c = cat.color
    local msg = format("|cff%02x%02x%02x%s|r |cffe8dcc0%s|r", c[1] * 255, c[2] * 255, c[3] * 255, item.title or cat.label, item.text)
    if ch == "echoes" then echoChatFrame():AddMessage("|cffd8b26aEcho|r " .. msg) else C.Print(msg) end
  else C.Toast.Show(item) end
end

local function suppressed()
  if UnitAffectingCombat("player") then return true end
  if C.set.quietInstances and IsInInstance() then return true end
end

function E.Flush()
  if suppressed() then return end
  local item = tremove(pending, 1)
  while item do deliver(item); item = tremove(pending, 1) end
end

function E.Fire(id, key, text, title, force, meta)
  local ev = C.EV[id]; if not ev then return end
  local ch = C.set.channel[id] or "off"
  if ch ~= "toast" and ch ~= "chat" and ch ~= "echoes" then return end
  if key and C.db.muted[key] then return end
  local lim = C.INTENSITY[C.set.intensity]
  if not lim then return end
  local score = E.Score(id, key, meta, force)
  if C.debug then C.Print(format("echo %s key=%s score=%d", id, tostring(key), score)) end
  local min = lim.min + E.CurveDelta()
  if C.set.quietMode then min = math.max(min, C.set.quietMin) end
  if score < min then return end
  local now = GetTime()
  if not force then
    if key and C.db.echoSeen[key] and time() - C.db.echoSeen[key] < lim.key then return end
    if now - lastGlobal < lim.global then return end
  end
  lastGlobal = now
  local item = { id = id, cat = ev.cat, key = key, text = text, title = title, ch = ch, entry = meta and meta.entry, score = score }
  if suppressed() then
    if #pending >= 5 then tremove(pending, 1) end
    tinsert(pending, item); return
  end
  deliver(item)
end

function E.Mute(key) if key then C.db.muted[key] = true; C.Print("This memory will not be shown again. (/jkp unmute to reset)") end end

C.On("PLAYER_REGEN_ENABLED", function() C_Timer.After(2, E.Flush) end)
C.On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(3, E.Flush) end)

-- Returning to death spots: poll position every 5s.
local warned = {}
C.Init(function()
  C_Timer.NewTicker(5, function()
    if not C.set.ev.death_spot_echo then return end
    local map, x, y = C.pos()
    if not x then return end
    for i, d in ipairs(C.db.deathSpots) do
      if d.map == map and d.x and not warned[i] and math.abs(d.x - x) < 1.5 and math.abs(d.y - y) < 1.5 then
        warned[i] = true
        d.returns = (d.returns or 0) + 1
        if C.Threads then C.Threads.OnGraveReturn(d, i) end
        C.Echo("death_spot_echo", "spot" .. i, C.Tpl("grave", { name = d.char == C.charKey() and "you" or d.char:match("^[^-]+"), date = C.dateStr(d.t),
          level = d.level or "?", killer = d.killer and (", to " .. d.killer) or "" }):gsub("^%l", string.upper), "An old grave", nil, { entry = d.entry })
      end
    end
  end)
end)
