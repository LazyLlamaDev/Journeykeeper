-- v0.7.2 "Your journey so far": a replay on our Journey map. Walks the memories in time order, one step per tick,
-- drops a pin for each place, shows a short caption and switches continents when the road does. Read-only:
-- it never changes a memory. Only runs while the journal page with the map is visible (pauses otherwise).
local _, C = ...
local R = {}; C.Replay = R
R.IDS = { zone_first_char = true, zone_first_account = true, dungeon_enter_first = true, boss_first_kill = true, instance_complete = true,
  level_up = true, death = true, fellow_first = true, fellow_reunion = true, mount_first = true, achievement = true, quick_note = true,
  rare_kill = true, loot_first_epic = true, loot_first_legendary = true, raid_first = true, guild_join = true, flight_learn = true }
local MAXSTEPS, TRAIL = 600, 40
local steps, idx, playing, ticker = nil, 0, false, nil
local block = { kind = "sketch", replay = true, clipKey = "replay", points = {}, switcher = false }
R.block = block

local function clean(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1"):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("\n", " ")) end
-- continent position of a memory (zone map + x/y in 0..100), via the cached zone rect from Journey
local function where(e)
  if not (e.map and C.Journey) then return nil end
  local pl = C.Journey.PlacePoint and C.Journey.PlacePoint(e.map, e.x, e.y)
  return pl
end

function R.Steps()
  local out, want, ck = {}, C.set.replayChars, C.charKey()
  for _, e in ipairs(C.db.entries) do
    if (R.IDS[e.id] or e.anchor) and not e.archived and e.id ~= "_quarantined" and (want == "all" or e.char == ck) then
      local pl = where(e)
      out[#out + 1] = { t = e.t or 0, char = e.char, text = clean(e.text), zone = e.zone, cont = pl and pl.cont, x = pl and pl.x, y = pl and pl.y,
        level = e.id == "level_up" }
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end) -- stable enough: entries are already in time order
  while #out > MAXSTEPS do tremove(out, 1) end
  return out
end

local function short(ck) return ((ck or "?"):match("^[^-]+")) end
-- refresh the shared block for the current step (points on the current continent, newest highlighted)
function R.Update()
  steps = steps or R.Steps()
  local cur = steps[idx]
  local cont = block.contID
  if cur and cur.cont then cont = cur.cont end
  if not cont then for i = 1, #steps do if steps[i].cont then cont = steps[i].cont; break end end end
  cont = cont or (C.Journey and C.Journey.CONTS[1].id) or 1414
  local pts = {}
  for i = idx, 1, -1 do
    local s = steps[i]
    if s.cont == cont then
      tinsert(pts, 1, { x = s.x, y = s.y, level = s.level, label = "", first = false })
      if #pts >= TRAIL then break end
    end
  end
  if #pts > 0 and cur and cur.cont == cont then pts[#pts].first = true; pts[#pts].label = cur.zone or "" end
  local name = C.Journey and C.Journey.ContName(cont) or "?"
  block.contID, block.title, block.map, block.points = cont, name, C.Journey and C.Journey.MapArt(cont, name), pts
  if cur then
    block.replayCaption = format("%s  ·  %s%s  ·  %s", C.dateStr(cur.t), C.set.replayChars == "all" and (short(cur.char) .. "  ·  ") or "", cur.zone or "?", cur.text)
  elseif #steps == 0 then
    block.replayCaption = "No memories with a place yet. Step into a new zone and the road begins."
  else
    block.replayCaption = format("%d memories on the road so far. Press Play to walk it again.", #steps)
  end
  block.replayState = format("%d / %d", idx, #steps)
  block.caption = (C.set.replayChars == "all" and "Your warband's journey so far." or ("The journey of " .. short(C.charKey()) .. " so far."))
  return block
end
function R.Block() if not steps then R.Update() end return block end

local function redraw()
  if C.Journal and C.Journal.RedrawSketch then return C.Journal.RedrawSketch(block) end
  return false
end
local function stopTicker() if ticker and ticker.Cancel then ticker:Cancel() end; ticker = nil end
function R.Step()
  steps = steps or R.Steps()
  if idx >= #steps then R.Pause(); return false end
  idx = idx + 1
  R.Update()
  if not redraw() and playing then R.Pause() end -- the map is no longer on screen: pause
  if idx >= #steps then R.Pause() end
  return true
end
function R.Interval() return 1.5 / (tonumber(C.set.replaySpeed) or 1) end
function R.Play()
  if not C.set.replay then return false end
  steps = R.Steps()
  if idx >= #steps then idx = 0 end
  playing = true; stopTicker()
  if C_Timer.NewTicker then ticker = C_Timer.NewTicker(R.Interval(), function() if playing then R.Step() end end) end
  R.Update(); redraw()
  return true
end
function R.Pause() playing = false; stopTicker(); R.Update(); redraw() end
function R.Toggle() if playing then R.Pause() else R.Play() end end
function R.Restart() idx = 0; steps = R.Steps(); R.Update(); redraw() end
function R.CycleSpeed()
  local nxt = ({ ["1"] = "2", ["2"] = "4", ["4"] = "1" })[tostring(C.set.replaySpeed)] or "1"
  C.set.replaySpeed = nxt
  if playing then R.Play() else R.Update(); redraw() end
end
function R.CycleChars()
  C.set.replayChars = C.set.replayChars == "all" and "current" or "all"
  local was = playing
  idx = 0; steps = R.Steps(); R.Update(); redraw()
  if was then R.Play() end
end
function R.Playing() return playing end
function R.Index() return idx, steps and #steps or 0 end
function R.Invalidate() steps = nil end
C.On("PLAYER_LOGOUT", function() stopTicker() end)
