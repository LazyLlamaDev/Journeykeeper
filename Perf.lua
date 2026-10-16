-- /jkp perf: Journeykeeper's own footprint, measured with the game's APIs (nothing runs unless you ask).
local _, C = ...
local P = {}; C.Perf = P
local function kb(n) return n and (n >= 1024 and format("%.1f MB", n / 1024) or format("%.0f KB", n)) or "?" end
local function ms(v) return v and format("%.3f ms", v) or "n/a" end

function P.Lines()
  local out = {}
  if C.Has("UpdateAddOnMemoryUsage") then
    C.API("UpdateAddOnMemoryUsage") -- walks every addon; only on demand
    local a, v = C.API("GetAddOnMemoryUsage", "Journeykeeper"), C.API("GetAddOnMemoryUsage", "Journeykeeper_Vault")
    out[#out + 1] = format("Memory: Journeykeeper %s%s (includes saved data + backups loaded from disk)", kb(a), v and ("  ·  Vault " .. kb(v)) or "")
  else
    out[#out + 1] = format("Memory: API unavailable; Lua total (all addons) %s", kb(collectgarbage("count")))
  end
  local E = Enum and Enum.AddOnProfilerMetric
  if E and C.Has("C_AddOnProfiler.GetAddOnMetric") then
    local function m(k) return C.API("C_AddOnProfiler.GetAddOnMetric", "Journeykeeper", E[k]) end
    out[#out + 1] = format("CPU per frame: recent avg %s  ·  session avg %s  ·  peak %s", ms(m("RecentAverageTime")), ms(m("SessionAverageTime")), ms(m("PeakTime")))
    out[#out + 1] = format("Frames over 1 ms: %s  ·  over 5 ms: %s  ·  over 50 ms: %s", tostring(m("CountTimeOver1Ms") or "?"), tostring(m("CountTimeOver5Ms") or "?"), tostring(m("CountTimeOver50Ms") or "?"))
    local all = C.Has("C_AddOnProfiler.GetOverallMetric") and C.API("C_AddOnProfiler.GetOverallMetric", E.RecentAverageTime)
    local mine = m("RecentAverageTime")
    if all and all > 0 and mine then out[#out + 1] = format("Share of all addon CPU (recent): %.1f%%", mine / all * 100) end
  else
    out[#out + 1] = "CPU: C_AddOnProfiler not available in this client"
  end
  local D = C.Data
  local list = D.List()
  local total = 0
  for _, it in ipairs(list) do total = total + (it.snap.size or 0) end
  local c = D.Counts(C.db)
  out[#out + 1] = format("Data: %d memories, %d diary, %d players  ·  newest snapshot %s  ·  %d snapshots = %s in backups", c.entries, c.diary, c.players,
    list[1] and kb((list[1].snap.size or 0) / 1024) or "-", #list, kb(total / 1024))
  out[#out + 1] = format("Last backup: %s%s", D.lastSnapMs and format("%.0f ms", D.lastSnapMs) or "not this session", D.lastSkipped and " (skipped: nothing changed)" or "")
  out[#out + 1] = format("Combat log listener: %s  ·  ghost trail sampling: %s", C.set.combatLog and "ON" or "off", C.set.ghostTrail and C.set.ghostDensity or "off")
  return out
end
function P.Report() for _, l in ipairs(P.Lines()) do C.Print(l) end end
