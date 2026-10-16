-- Warband resonance: ghost-trail sampling (positions only, outside instances, low density).
local _, C = ...
local W = {}; C.Warband = W
local INTERVAL = { low = 120, medium = 60, high = 30 }
local MAX_PER_CHAR = 3000
local PALETTE = { { 0.4, 0.8, 1 }, { 1, 0.6, 0.3 }, { 0.6, 1, 0.5 }, { 1, 0.45, 0.75 }, { 0.85, 0.8, 0.35 }, { 0.7, 0.55, 1 }, { 0.4, 1, 0.9 } }

function W.Color(ck)
  local h = 0
  for i = 1, #ck do h = (h * 31 + ck:byte(i)) % 1000003 end
  return PALETTE[h % #PALETTE + 1]
end

local elapsed = 0
C.Init(function()
  C_Timer.NewTicker(10, function()
    if not C.set.ghostTrail then return end
    elapsed = elapsed + 10
    if elapsed < (INTERVAL[C.set.ghostDensity] or 120) then return end
    elapsed = 0
    if IsInInstance() or UnitOnTaxi("player") then return end
    local map, x, y = C.pos()
    if not x then return end
    local ck = C.charKey()
    local t = C.db.trail[ck] or {}; C.db.trail[ck] = t
    local last = t[#t]
    if last and last[1] == map and math.abs(last[2] - x) < 1 and math.abs(last[3] - y) < 1 then return end
    t[#t + 1] = { map, x, y, time() }
    while #t > MAX_PER_CHAR do tremove(t, 1) end
  end)
end)

-- points for a map, thinned to at most `max` total
function W.PointsFor(mapID, max)
  local out, me = {}, C.charKey()
  for ck, list in pairs(C.db.trail) do
    if ck ~= me or C.set.ghostSelf then
      for _, p in ipairs(list) do if p[1] == mapID then out[#out + 1] = { ck = ck, x = p[2], y = p[3] } end end
    end
  end
  if #out > max then
    local step, thin = #out / max, {}
    for i = 1, max do thin[i] = out[floor((i - 1) * step) + 1] end
    out = thin
  end
  return out
end
