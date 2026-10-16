-- Adaptive emotional weighting for memories (journal entries).
local _, C = ...
C.BASE_WEIGHT = { death = 3, dungeon = 3, group = 2, level = 2, loot = 2, achieve = 2, warband = 3, thread = 3, zone = 1 }
local log2 = math.log(2)

function C.EntryWeight(e)
  if not e then return 0 end
  local s = C.set
  local base = C.BASE_WEIGHT[e.cat] or 1
  local n = C.db.idCount[e.id] or 1
  local rarity = math.max(0, 3 - math.log(math.max(n, 1)) / log2) * s.rarityWeight
  local context = (e.context or 0) * s.contextWeight / 2
  local anchor = e.anchor and s.anchorBoost or 0
  local reinforce = math.min(2, (e.reinf or 0) * s.reinforceStep)
  local decay = 0
  if not e.anchor and base <= 1 and rarity < 1 then
    decay = -math.min(3, (time() - (e.t or time())) / 86400 / s.decayDays * 3)
  end
  local boost = s.catBoost[e.cat] or 0
  local social = 0
  local p = e.guid and C.db.players[e.guid]
  if p and p.rating then
    social = (p.rating == "great" and s.ratingWeight * 0.6) or (p.rating == "avoid" and -s.ratingWeight) or -1
  end
  return base + rarity + context + anchor + reinforce + decay + boost + social
end

function C.Reinforce(i) local e = C.db.entries[i]; if e then e.reinf = (e.reinf or 0) + 1 end end

function C.Pin(list, on)
  local n = 0
  for _, i in ipairs(list) do
    local e = C.db.entries[i]
    if e then e.anchor = on ~= false or nil; n = n + 1 end
  end
  if n > 0 and on ~= false then C.Emit("moment_pinned", format("You pinned %d moment%s to remember.", n, n == 1 and "" or "s")) end
  C.Print(on == false and "unpinned" or ("pinned " .. n .. " moment(s)"))
end

-- top-N entries by weight
function C.TopEntries(n)
  local arr = {}
  for i, e in ipairs(C.db.entries) do arr[#arr + 1] = { i = i, w = C.EntryWeight(e) } end
  table.sort(arr, function(a, b) return a.w > b.w end)
  local out = {}
  for k = 1, math.min(n, #arr) do out[k] = arr[k] end
  return out
end
