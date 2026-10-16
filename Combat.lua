-- Combat metrics via Blizzard's built-in damage meter (C_DamageMeter, 12.0+, listed for Forever 1.60.1).
-- Facts (warcraft.wiki.gg API pages): session data is SecretWhenInCombat; after combat ends values are readable
-- (non-secret) for untainted-allowed reads. We ONLY read after PLAYER_REGEN_ENABLED (+delay), check every number
-- with C.S()/issecretvalue, and never compare or do arithmetic on anything secret. If a value is still secret we
-- skip it (we do not try to launder secrets through string.format).
-- There is no per-hit maximum in the API: "biggest hit" becomes "strongest ability in one fight" (per-spell total).
local _, C = ...
local S = C.S
local M = {}; C.Combat = M
local DM = C_DamageMeter

function M.Available()
  if not (DM and DM.GetCombatSessionFromType and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then return false, "no C_DamageMeter in this client" end
  if DM.IsDamageMeterAvailable then
    local ok, avail, reason = pcall(DM.IsDamageMeterAvailable)
    if ok and avail == false then return false, reason or "damage meter disabled" end
  end
  return true
end

local function num(v) v = S(v); return type(v) == "number" and v or nil end

-- returns { amount, perSecond } for the local player in a session, or nil
local function localSource(sessionType, mtype)
  local ok, session = pcall(DM.GetCombatSessionFromType, sessionType, mtype)
  if not ok or type(session) ~= "table" then return nil end
  local dur = num(session.durationSeconds)
  for _, src in ipairs(session.combatSources or {}) do
    if src.isLocalPlayer then return { amount = num(src.totalAmount), aps = num(src.amountPerSecond), dur = dur } end
  end
  return { dur = dur }
end

local function topSpell(sessionType)
  if not DM.GetCombatSessionSourceFromType then return nil end
  local ok, src = pcall(DM.GetCombatSessionSourceFromType, sessionType, Enum.DamageMeterType.DamageDone, UnitGUID("player"))
  if not ok or type(src) ~= "table" then return nil end
  local best, bestID
  for _, sp in ipairs(src.combatSpells or {}) do
    local a, id = num(sp.totalAmount), num(sp.spellID)
    if a and id and (not best or a > best) then best, bestID = a, id end
  end
  if not best then return nil end
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bestID)
  return { amount = best, spellID = bestID, name = info and S(info.name) or ("spell " .. bestID) }
end

local function short(n)
  if n >= 1e6 then return format("%.1fM", n / 1e6) elseif n >= 1e3 then return format("%.1fk", n / 1e3) end
  return tostring(floor(n))
end
M.short = short

local function record(key, value, label, extra)
  C.db.records = C.db.records or {}
  local me = C.charKey()
  C.db.records[me] = C.db.records[me] or {}
  local r = C.db.records[me][key]
  if r and r.v >= value then return false end
  C.db.records[me][key] = { v = value, t = time(), label = label, zone = GetRealZoneText(), extra = extra }
  return true, r
end

M.lastFight = nil
-- Own combat clock (GetTime, seconds). C_DamageMeter's session duration has been seen returning
-- uptime-like values (e.g. 71571 minutes) on Forever, so we trust our own regen-disabled→enabled span.
local combatStart, lastCombatSecs
C.On("PLAYER_REGEN_DISABLED", function() combatStart = GetTime() end)
C.On("PLAYER_REGEN_ENABLED", function() if combatStart then lastCombatSecs = GetTime() - combatStart; combatStart = nil end end)
function M.PickDuration(apiDur, measured)
  if measured and measured > 0 then
    if apiDur and apiDur > 0 and apiDur <= measured + 5 then return apiDur end
    return measured
  end
  if apiDur and apiDur > 0 and apiDur <= C.MAX_FIGHT_SECONDS then return apiDur end
  return nil
end
function M.ReadFight(bossName)
  if not C.set.combatMetrics then return end
  local ok, why = M.Available()
  if not ok then M.status = why; return end
  if InCombatLockdown() or UnitAffectingCombat("player") then return end -- values would be secret
  local T, ST = Enum.DamageMeterType, Enum.DamageMeterSessionType
  local dmg = localSource(ST.Current, T.DamageDone)
  local heal = localSource(ST.Current, T.HealingDone)
  if not dmg then M.status = "no session"; return end
  local dur = M.PickDuration(dmg.dur, lastCombatSecs); lastCombatSecs = nil
  if not dur then M.status = "no valid fight duration"; return end
  if dur > C.MAX_FIGHT_SECONDS then M.status = "fight duration rejected"; return end
  if dur < C.set.minFightSeconds then return end
  -- recompute per-second values from our duration when the API ones look off
  if dmg.amount and dmg.amount > 0 and (not dmg.aps or dmg.aps <= 0) then dmg.aps = dmg.amount / dur end
  if heal and heal.amount and heal.amount > 0 and (not heal.aps or heal.aps <= 0) then heal.aps = heal.amount / dur end
  local spell = topSpell(ST.Current)
  local fight = { t = time(), dur = dur, dmg = dmg.amount, dps = dmg.aps, heal = heal and heal.amount, hps = heal and heal.aps, spell = spell, boss = bossName, zone = GetRealZoneText() }
  M.lastFight = fight; M.status = "ok"
  local who = (C.charKey()):match("^[^-]+")
  local function rec(key, v, ev, text, title)
    if not v or not C.ValidRecord(key, v) then return end
    local new, old = record(key, v, text)
    if new and old then C.Emit(ev, text, { value = v }, C.set.recordEchoes and { title = title, key = "rec" .. key, text = text .. format(" (previous best %s)", short(old.v)) } or nil)
    elseif new then C.Emit(ev, text, { value = v, noLog = false }) end
  end
  rec("dps", fight.dps, "combat_record_dps", format("%s's fiercest fight yet: %s damage per second%s.", who, short(fight.dps or 0), bossName and (" against " .. bossName) or ""), "New personal best")
  rec("dmg", fight.dmg, "combat_record_damage", format("%s dealt %s damage in a single fight.", who, short(fight.dmg or 0)), "Heaviest fight")
  rec("dur", dur, "combat_longest_fight", format("%s's longest fight: %s.", who, C.FormatDuration(dur)), "Longest fight")
  rec("hps", fight.hps, "combat_record_heal", format("%s healed %s per second, a new high.", who, short(fight.hps or 0)), "Healing record")
  if spell then rec("spell", spell.amount, "combat_top_spell", format("%s's %s struck for %s in one fight, a new high.", who, spell.name, short(spell.amount)), "Strongest ability") end
  if bossName and fight.dmg and fight.dmg > 0 then
    C.Emit("combat_boss_stats", format("Against %s: %s damage (%s per second) over %s%s.", bossName, short(fight.dmg or 0), short(fight.dps or 0), C.FormatDuration(dur),
      fight.heal and fight.heal > 0 and format(", %s healed", short(fight.heal)) or ""), { boss = bossName, fight = fight })
  end
end

local pendingBoss
C.On("ENCOUNTER_END", function(_, name, _, _, success) if S(success) == 1 then pendingBoss = S(name) end end)
C.On("PLAYER_REGEN_ENABLED", function()
  C_Timer.After(1.5, function() local b = pendingBoss; pendingBoss = nil; M.ReadFight(b) end)
end)

function M.RecordsText(ck)
  local r = C.db.records and C.db.records[ck or C.charKey()]
  if not r then return nil end
  local parts = {}
  if r.dps then parts[#parts + 1] = format("best %s DPS", short(r.dps.v)) end
  if r.dmg then parts[#parts + 1] = format("%s damage in one fight", short(r.dmg.v)) end
  if r.dur and C.ValidRecord("dur", r.dur.v) then parts[#parts + 1] = "longest fight " .. C.FormatDuration(r.dur.v) end
  if r.hps then parts[#parts + 1] = format("best %s HPS", short(r.hps.v)) end
  if r.spell then parts[#parts + 1] = format("strongest ability %s", short(r.spell.v)) end
  return #parts > 0 and table.concat(parts, ", ") or nil
end
M.TitleLine = M.RecordsText
