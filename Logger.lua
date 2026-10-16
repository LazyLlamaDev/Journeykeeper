-- Logger: event handlers -> C.Emit(eventId, ...). See Registry.lua / docs/EVENT_CATALOG.md.
-- Anything that may be a secret value goes through C.S() and degrades to nil/"unknown".
-- Adding an event: add a row in tools/catalog.py (impl=1), regenerate, then call C.Emit("<id>", text, extra, echo) here.
local _, C = ...
local S = C.S
local L = {}; C.Logger = L

local function key(z, s) return (z or "?") .. "|" .. (s or "") end
local function me() return C.charKey() end
local function short(ck) return ((ck or me()):match("^[^-]+")) end
local function bump(stat) C.db.stats[stat] = (C.db.stats[stat] or 0) + 1; return C.db.stats[stat] end
local function cbump(stat) C.cdb.flags[stat] = (C.cdb.flags[stat] or 0) + 1; return C.cdb.flags[stat] end
local function once(flag) if C.cdb.flags[flag] then return false end C.cdb.flags[flag] = time(); return true end

---------------------------------------------------------------- Exploration
local VERB = { Hunter = "hunted", Warrior = "fought", Mage = "studied the winds", Priest = "prayed", Rogue = "slipped through the shadows",
  Shaman = "listened to the spirits", Warlock = "bargained with dark things", Druid = "walked with the wild", Paladin = "kept vigil" }
local function revisitText(f, label, k)
  local self = f.char == me()
  local lvl, cls = (f.desc or ""):match("level (%d+) %S+ (.+)$")
  local kind = self and "revisit_self" or ((C.set.warbandEcho and "warband") or "revisit_alt")
  local txt = C.Tpl(kind, { name = short(f.char), date = C.dateStr(f.t), level = lvl or "?", class = cls or "", place = label, verb = VERB[cls or ""] or "walked" })
  local meta = { shared = 0 }
  local d = C.db.deathCount[k] or 0
  if d > 0 then txt = txt .. C.Tpl("deaths_suffix", { n = d }); meta.shared = d end
  local ft, nt = date("*t", f.t), date("*t")
  if ft.month == nt.month and ft.day == nt.day and nt.year > ft.year then
    meta.anniversary = true
    txt = C.Tpl("anniversary", { name = self and "you" or short(f.char), place = label, years = nt.year - ft.year }):gsub("^%l", string.upper) .. " " .. txt
  end
  local last = C.cdb.lastSeen[k]
  if last then
    local days = floor((time() - last) / 86400)
    if days >= 30 then meta.absenceDays = days; txt = C.Tpl("absence", { days = days, place = label }) .. " " .. txt end
  end
  meta.warband = not self
  -- intensity context: you died here long ago at a much lower level
  local now = UnitLevel("player")
  -- incremental index of death entries (was a full scan of every entry on each zone change)
  local list = C.db.entries
  if L.deathScanned and L.deathScanned > #list then L.deathScanned, L.deathIdx = nil, nil end
  L.deathIdx = L.deathIdx or {}
  for i = (L.deathScanned or 0) + 1, #list do if list[i].id == "death" then L.deathIdx[#L.deathIdx + 1] = i end end
  L.deathScanned = #list
  for _, i in ipairs(L.deathIdx) do
    local e = list[i]
    if e and e.id == "death" and (e.sub == label or e.zone == label) and (e.level or 99) <= now - 10 and not e.context then
      e.context = 2; meta.entry = meta.entry or i
    end
  end
  return txt, meta
end
local function visit(store, accStore, k, label, zone, sub, kind)
  local f = accStore[k]
  if store[k] then
    if f then
      local txt, meta = revisitText(f, label, k)
      C.Echo(meta.warband and C.set.warbandEcho and "warband_echo" or "echo_revisit", "z" .. k, txt, label, nil, meta)
    end
    C.cdb.lastSeen[k] = time()
    return
  end
  store[k] = time(); C.cdb.lastSeen[k] = time()
  if not f then
    accStore[k] = { char = me(), desc = C.charDesc(), t = time() }
    C.Emit(kind .. "_first_account", format("%s set foot in %s - the first of your line to do so.", short(), label),
      { zone = zone, sub = sub, accountFirst = true }, { title = "Discovered: " .. label, key = "d" .. k, meta = { first = true } })
  else
    C.Emit(kind .. "_first_char", format("%s reached %s, where %s once walked before.", short(), label, short(f.char)), { zone = zone, sub = sub })
    local txt, meta = revisitText(f, label, k)
    C.Echo(meta.warband and C.set.warbandEcho and "warband_echo" or "echo_revisit", "z" .. k, txt, label, nil, meta)
  end
end
local function onZone()
  local zone, sub = S(GetRealZoneText()), S(GetSubZoneText())
  if not zone or zone == "" then return end
  if not C.cdb.firstZone then C.cdb.firstZone, C.cdb.firstZoneLevel = zone, UnitLevel("player") end
  if C.set.threads and zone == C.cdb.firstZone and UnitLevel("player") >= C.cdb.firstZoneLevel + 10 and once("homecoming" .. floor(UnitLevel("player") / 10)) then
    C.Emit("thread_zone_return", format("%s returned to %s, where the story began.", short(), zone), nil,
      { title = "Homecoming", text = C.Tpl("thread_zone", { place = zone, from = C.cdb.firstZoneLevel, to = UnitLevel("player") }), meta = { first = true } })
  end
  visit(C.cdb.zones, C.db.firstZone, zone, zone, zone, sub, "zone")
  if sub and sub ~= "" then visit(C.cdb.subs, C.db.firstSub, key(zone, sub), sub, zone, sub, "sub") end
end
L.onZone = onZone
C.On("ZONE_CHANGED_NEW_AREA", onZone); C.On("ZONE_CHANGED", onZone); C.On("ZONE_CHANGED_INDOORS", onZone)
C.On("PLAYER_UPDATE_RESTING", function()
  if not IsResting() then return end
  local sub = GetSubZoneText(); local k = "rest|" .. GetRealZoneText() .. "|" .. sub
  if once(k) then C.Emit("rest_area_first", format("%s rested for the first time in %s.", short(), sub ~= "" and sub or GetRealZoneText())) end
end)

---------------------------------------------------------------- Combat & deaths
local lastAttacker, lastHostile, breath, exhaust, fallStart, lastFallEnd, lastFallDur
local recentDeaths = {}
L.rareSeen = {}
C.On("PLAYER_TARGET_CHANGED", function()
  if not UnitExists("target") or not S(UnitCanAttack("player", "target")) then return end
  lastHostile = S(UnitName("target"))
  local cls = S(UnitClassification("target"))
  if cls == "rare" or cls == "rareelite" then L.rareTarget = { guid = S(UnitGUID("target")), name = lastHostile } end
end)
C.On("NAME_PLATE_UNIT_ADDED", function(unit)
  local cls = S(UnitClassification(unit))
  if cls ~= "rare" and cls ~= "rareelite" then return end
  local name = S(UnitName(unit)); if not name or L.rareSeen[name] then return end
  L.rareSeen[name] = true
  C.Emit("rare_seen", format("%s spotted the rare %s.", short(), name), { target = name }, { title = "Rare spotted", key = "rs" .. name })
end)
-- Combat log is opt-in: it is the busiest event in WoW (hundreds/s in groups) and Midnight-era clients restrict it
-- for addons (registering can raise ADDON_ACTION_FORBIDDEN). Without it, killer names fall back to the last hostile target.
local cleuFrame
function L.UpdateCombatLog()
  if not cleuFrame then cleuFrame = CreateFrame("Frame"); cleuFrame:SetScript("OnEvent", function() pcall(L.OnCLEU) end) end
  if C.set.combatLog and CombatLogGetCurrentEventInfo then pcall(cleuFrame.RegisterEvent, cleuFrame, "COMBAT_LOG_EVENT_UNFILTERED")
  else pcall(cleuFrame.UnregisterEvent, cleuFrame, "COMBAT_LOG_EVENT_UNFILTERED") end
end
C.Init(function() L.UpdateCombatLog() end)
local playerGUID
function L.OnCLEU()
  if not CombatLogGetCurrentEventInfo then return end
  local ok, _, sub, _, srcGUID, srcName, _, _, dstGUID = pcall(CombatLogGetCurrentEventInfo)
  if not ok then return end
  sub, srcName, dstGUID, srcGUID = S(sub), S(srcName), S(dstGUID), S(srcGUID)
  if type(sub) ~= "string" then return end
  playerGUID = playerGUID or S(UnitGUID("player"))
  local pg = playerGUID
  if dstGUID == pg and srcName and srcGUID ~= pg and sub:find("_DAMAGE") then lastAttacker = srcName end
  if (sub == "PARTY_KILL" or sub == "UNIT_DIED") and L.rareTarget and dstGUID == L.rareTarget.guid then L.RareKilled(L.rareTarget.name) end
end
C.On("PLAYER_REGEN_ENABLED", function()
  if L.rareTarget and UnitExists("target") and S(UnitGUID("target")) == L.rareTarget.guid and S(UnitIsDead("target")) then L.RareKilled(L.rareTarget.name) end
end)
local function family(kind, k, what)
  if not C.set.familyFirsts or not k then return end
  C.db.family[kind] = C.db.family[kind] or {}
  if C.db.family[kind][k] then return end
  C.db.family[kind][k] = { char = me(), t = time() }
  C.Emit("family_first_" .. kind, format("%s achieved a first for the warband: %s.", short(), what), nil,
    { title = "Warband first", text = C.Tpl("family", { what = what }), force = true, meta = { first = true } })
end
L.family = family
function L.RareKilled(name)
  L.rareTarget = nil
  family("rare", name, "the rare " .. (name or "?") .. " has fallen")
  C.Emit("rare_kill", format("%s brought down the rare %s.", short(), name or "creature"), { target = name },
    { title = "Rare slain", text = (name or "A rare foe") .. " has fallen.", key = "rk" .. (name or ""), force = true })
end
C.On("MIRROR_TIMER_START", function(timer) if timer == "BREATH" then breath = true elseif timer == "EXHAUSTION" then exhaust = true end end)
C.On("MIRROR_TIMER_STOP", function(timer)
  if timer == "BREATH" then breath = nil elseif timer == "EXHAUSTION" then exhaust = nil end
end)
-- falling tracker (IsFalling is a plain boolean)
C.Init(function()
  C_Timer.NewTicker(0.25, function()
    if IsFalling() then fallStart = fallStart or GetTime()
    elseif fallStart then
      lastFallDur = GetTime() - fallStart; lastFallEnd = GetTime(); fallStart = nil
      if lastFallDur > 3 then
        C_Timer.After(1, function()
          if not UnitIsDeadOrGhost("player") then
            C.Emit("fun_fall", format("%s survived a %.1f second fall in %s.", short(), lastFallDur, GetSubZoneText() ~= "" and GetSubZoneText() or GetRealZoneText()))
          end
        end)
      end
    end
  end)
end)
C.On("PLAYER_DEAD", function()
  local zone, sub = GetRealZoneText(), GetSubZoneText()
  local killer = lastAttacker or lastHostile
  local k = key(zone, sub)
  C.db.deathCount[k] = (C.db.deathCount[k] or 0) + 1
  local map, x, y = C.pos()
  local spot = { map = map, x = x, y = y, t = time(), char = me(), level = UnitLevel("player"), zone = zone, sub = sub, killer = killer }
  tinsert(C.db.deathSpots, spot)
  local where = (sub ~= "" and sub .. ", " or "") .. zone
  local cause = killer and ("slain by " .. killer) or "cause unknown"
  local fell = (fallStart and GetTime() - fallStart > 1) or (lastFallEnd and GetTime() - lastFallEnd < 3 and (lastFallDur or 0) > 1)
  if breath then cause = "drowned" elseif exhaust then cause = "lost to fatigue in deep water" elseif fell then cause = "fell to their death" end
  bump("deaths"); cbump("deaths")
  C.Emit("death", format("%s fell at level %d in %s, %s. (death #%d here)", short(), UnitLevel("player"), where, cause, C.db.deathCount[k]),
    { killer = killer, cause = cause })
  spot.entry = #C.db.entries
  if killer and not breath and not fell then C.Emit("death_killer", format("%s was slain by %s.", short(), killer), { killer = killer, noLog = true }) end
  if breath then C.Emit("death_drowning", format("%s drowned in %s.", short(), where), nil, { title = "Drowned", force = true })
  elseif exhaust then C.Emit("death_fatigue", format("%s succumbed to fatigue in %s.", short(), where), nil, { title = "Lost at sea" })
  elseif fell then C.Emit("death_falling", format("%s fell to their death in %s.", short(), where), nil, { title = "Gravity wins", force = true }) end
  tinsert(recentDeaths, { t = time(), k = k })
  local n = 0
  for _, d in ipairs(recentDeaths) do if d.k == k and time() - d.t < 600 then n = n + 1 end end
  if n >= 3 then C.Emit("death_streak", format("%s has died %d times in %s within ten minutes.", short(), n, where), nil, { title = "A cursed place", key = "streak" .. k }) end
  lastAttacker, breath, exhaust = nil, nil, nil
end)

---------------------------------------------------------------- Social
local current = {}
L.currentGroup = current
local function where() local inInst = IsInInstance(); local n = GetInstanceInfo(); if inInst then return n, true end return GetRealZoneText(), false end
local justLeft = {}
local function closeMember(guid, m)
  local p = C.db.players[guid]
  if p then p.secs = (p.secs or 0) + (time() - m.start) end
  tinsert(justLeft, { guid = guid, name = m.name, secs = time() - m.start, inst = m.inst })
  if C.Fellowship then pcall(C.Fellowship.OnLeave, m.name) end
end
C.On("GROUP_ROSTER_UPDATE", function()
  local seen, raid = {}, IsInRaid()
  local n = raid and GetNumGroupMembers() or (GetNumGroupMembers() - 1)
  for i = 1, math.max(0, n) do
    local unit = (raid and "raid" or "party") .. i
    local guid = S(UnitGUID(unit))
    if guid and guid ~= UnitGUID("player") and S(UnitIsPlayer(unit)) then
      seen[guid] = true
      if not current[guid] then
        local name, realm = UnitName(unit); name, realm = S(name), S(realm)
        local _, cls = UnitClass(unit)
        local full = name and (name .. "-" .. ((realm and realm ~= "") and realm or GetNormalizedRealmName() or "")) or "?"
        current[guid] = { name = full, start = time(), inst = select(2, where()) and (where()) or nil }
        local fechoed = false
        if C.Fellowship then local okf, r = pcall(C.Fellowship.OnJoin, unit, full, S(cls), S(UnitIsInMyGuild and UnitIsInMyGuild(unit))); fechoed = okf and r end
        local p = C.db.players[guid]; local isNew = not p
        p = p or { name = full, first = time(), count = 0, notes = {}, secs = 0 }
        C.db.players[guid] = p
        local prevWhere, prevT, prevChar = p.lastWhere, p.last, p.lastChar
        p.name, p.class = full, S(cls) or p.class
        p.count = p.count + 1; p.last = time()
        local w, inst = where(); p.lastWhere = w; p.lastChar = me()
        if inst then p.runs = (p.runs or 0) + 1 end
        C.Emit(inst and "dungeon_party" or "group_join", format("%s joined forces with %s in %s.", short(), full, w or "?"), { guid = guid, instance = inst and w or nil })
        if not isNew and not fechoed then
          C.Echo("group_echo", "g" .. guid, C.Tpl("ally", { name = full, n = p.count - 1, where = prevWhere or "?", date = prevT and C.dateStr(prevT) or "?" })
            .. ((#p.notes > 0) and ("\n\"" .. p.notes[#p.notes].text .. "\"") or ""), "An old ally", nil, { shared = p.count - 1, guid = guid })
        end
      end
    end
  end
  for guid, m in pairs(current) do if not seen[guid] then closeMember(guid, m); current[guid] = nil end end
  if next(current) == nil and #justLeft > 0 then
    local list = justLeft; justLeft = {}
    if C.Social then C.Social.OnGroupEnd(list) end
  end
end)
C.On("PLAYER_LOGOUT", function() for g, m in pairs(current) do closeMember(g, m) end end)
function C.AddNote(text)
  if not text or text == "" then C.Print("usage: /jkp allynote <text>  (targets a player, else your most recent ally)") return end
  local guid = UnitExists("target") and S(UnitIsPlayer("target")) and S(UnitGUID("target"))
  local name
  if guid then local n, r = UnitName("target"); n, r = S(n), S(r); name = n and (n .. "-" .. ((r and r ~= "") and r or GetNormalizedRealmName() or "")) end
  if not guid then
    for g, p in pairs(C.db.players) do if not guid or (p.last or 0) > (C.db.players[guid].last or 0) then guid = g end end
  end
  if not guid then C.Print("no player to annotate") return end
  local p = C.db.players[guid] or { name = name or "?", first = time(), count = 0, notes = {}, secs = 0 }
  C.db.players[guid] = p
  tinsert(p.notes, { t = time(), text = text, by = me() })
  C.Emit("ally_note", format("%s noted about %s: \"%s\"", short(), p.name or "?", text), { guid = guid })
  C.Print("note added to " .. (p.name or "?"))
end
C.On("PLAYER_GUILD_UPDATE", function()
  local g = IsInGuild() and S(GetGuildInfo("player"))
  if g and C.cdb.flags.guild ~= g then
    C.cdb.flags.guild = g
    C.Emit("guild_join", format("%s joined the guild <%s>.", short(), g), { guild = g }, { title = "Guild joined" })
  end
end)
C.On("DUEL_REQUESTED", function(name) local n = S(name); C.Emit("duel", format("%s was challenged to a duel by %s.", short(), n or "someone"), { opponent = n }) end)

---------------------------------------------------------------- Quests
local accepted = {}
C.On("QUEST_ACCEPTED", function(q)
  accepted[q] = S(C_QuestLog.GetTitleForQuestID(q))
  C.Emit("quest_accept", format("%s took up \"%s\".", short(), accepted[q] or ("quest " .. q)), { q = q })
end)
local turnedIn = {}
C.On("QUEST_TURNED_IN", function(q)
  turnedIn[q] = true
  local title = S(C_QuestLog.GetTitleForQuestID(q)) or accepted[q] or ("quest " .. q)
  local story
  if C_QuestLog.IsQuestCampaign then story = S(C_QuestLog.IsQuestCampaign(q)) and "story" end
  if C_QuestLine and C_QuestLine.GetQuestLineInfo then
    local ok, info = pcall(C_QuestLine.GetQuestLineInfo, q)
    if ok and info and S(info.questLineName) then story = info.questLineName end
  end
  local n = cbump("quests"); bump("quests")
  C.Emit("quest_turnin", format("%s completed \"%s\".", short(), title), { q = q })
  if story then C.Emit("quest_story", format("%s advanced the tale of %s with \"%s\".", short(), story, title), { q = q, story = story, noLog = false }) end
  for _, m in ipairs({ 10, 50, 100, 250, 500, 1000 }) do
    if n == m then C.Emit("quest_count", format("%s has completed %d quests.", short(), m), nil, { title = m .. " quests", force = true }) end
  end
end)
C.On("QUEST_REMOVED", function(q)
  C_Timer.After(0.5, function()
    if not turnedIn[q] and accepted[q] then C.Emit("quest_abandon", format("%s abandoned \"%s\".", short(), accepted[q]), { q = q }) end
    accepted[q] = nil; turnedIn[q] = nil
  end)
end)

---------------------------------------------------------------- Progression
C.On("PLAYER_LEVEL_UP", function(level)
  C.UpdateCharInfo(level)
  local first = C.db.firstLevel[level]
  if not first then C.db.firstLevel[level] = { char = me(), t = time() } end
  C.Emit("level_up", format("%s reached level %d%s.", short(), level, first and "" or ", a first for your account"), { newLevel = level })
  if level == 5 or level % 10 == 0 then
    C.Emit("level_milestone", format("Level %d.", level), { newLevel = level, noLog = true },
      { title = "Level " .. level, force = true, meta = { first = not first },
        text = first and C.Tpl("milestone", { level = level, name = first.char == me() and "you" or short(first.char), date = C.dateStr(first.t) }) or C.Tpl("milestone_new", { level = level }) })
  end
end)
local function spellLearned(spellID)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
  local name = info and S(info.name) or (GetSpellInfo and S(GetSpellInfo(spellID)))
  if name then C.Emit("spell_learn", format("%s learned %s.", short(), name), { spell = spellID }) end
end
C.On("LEARNED_SPELL_IN_SKILL_LINE", spellLearned)
C.On("LEARNED_SPELL_IN_TAB", spellLearned)
C.On("TRAIT_CONFIG_UPDATED", function() if once("talent") then C.Emit("talent_first", format("%s chose their first talents.", short()), nil, { title = "Talents" }) end end)
C.On("PLAYER_TALENT_UPDATE", function() if UnitLevel("player") >= 10 and once("talent") then C.Emit("talent_first", format("%s chose their first talents.", short()), nil, { title = "Talents" }) end end)
C.On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(msg)
  msg = S(msg); if not msg then return end
  local std = msg:match("now (%a+) with") or msg:match("You are now (%a+)")
  local fac = msg:match("with (.+)%.$")
  if std and fac then C.Emit("rep_tier", format("%s is now %s with %s.", short(), std, fac), { faction = fac, standing = std }, { title = std .. ": " .. fac }) end
end)
C.On("ACHIEVEMENT_EARNED", function(id)
  local _, name = GetAchievementInfo(id)
  name = S(name)
  if name then C.Emit("achievement", format("%s earned the achievement \"%s\".", short(), name), { ach = id }, { title = "Achievement", force = true }) end
end)

---------------------------------------------------------------- Dungeons & PvP
local instStart
C.On("PLAYER_ENTERING_WORLD", function(isLogin)
  onZone()
  if isLogin then L.SessionStart() end
  local inInst, itype = IsInInstance()
  if instStart and not inInst then
    C.Emit("dungeon_time", format("%s spent %d minutes in %s.", short(), floor((time() - instStart.t) / 60), instStart.name), { instance = instStart.name })
    instStart = nil
  end
  if inInst and (itype == "party" or itype == "raid") then
    local name, _, _, diffName, _, _, _, instID = GetInstanceInfo()
    instStart = instStart or { t = time(), name = name }
    local k = tostring(instID)
    if not C.cdb.dungeons[k] then
      C.cdb.dungeons[k] = time()
      local acc = not C.db.firstDungeon[k]
      if acc then C.db.firstDungeon[k] = { char = me(), t = time(), name = name } end
      C.Emit("dungeon_enter_first", format("%s entered %s%s for the first time%s.", short(), name, diffName and diffName ~= "" and (" (" .. diffName .. ")") or "", acc and " on this account" or ""),
        { instance = name, accountFirst = acc or nil }, { title = name, force = true })
      if itype == "raid" and once("raid") then C.Emit("raid_first", format("%s stepped into a raid for the first time: %s.", short(), name), nil, { title = "First raid" }) end
    end
  elseif inInst and itype == "pvp" and once("bg") then
    C.Emit("bg_first", format("%s entered a battleground for the first time: %s.", short(), (GetInstanceInfo())), nil, { title = "To battle!" })
  end
end)
C.On("ENCOUNTER_END", function(encID, encName, _, _, success)
  encID, encName, success = S(encID), S(encName), S(success)
  local inst = GetInstanceInfo()
  if success ~= 1 then
    if success == 0 then C.Emit("boss_wipe", format("%s's group wiped on %s.", short(), encName or "a boss"), { boss = encName }) end
    return
  end
  local k = tostring(encID or encName)
  if C.cdb.clears[k] then return end
  C.cdb.clears[k] = time(); bump("bosses")
  family("boss", k, (encName or "a boss") .. " defeated")
  C.Emit("boss_first_kill", format("%s defeated %s in %s for the first time.", short(), encName or "a boss", inst or "?"), { boss = encName, instance = inst },
    { title = "Victory: " .. (encName or "boss"), force = true })
end)
local function instanceDone()
  local name = GetInstanceInfo(); bump("instances")
  family("clear", name, (name or "an instance") .. " completed")
  C.Emit("instance_complete", format("%s completed %s.", short(), name or "an instance"), { instance = name, complete = true }, { title = "Completed", force = true })
end
C.On("LFG_COMPLETION_REWARD", instanceDone); C.On("SCENARIO_COMPLETED", instanceDone)
C.On("PLAYER_PVP_KILLS_CHANGED", function() C.Emit("pvp_kill", format("%s scored an honorable kill.", short())) end)

---------------------------------------------------------------- Items & collections
local QNAME = { [2] = "uncommon", [3] = "rare", [4] = "epic", [5] = "legendary" }
local QID = { [2] = "loot_first_green", [3] = "loot_first_blue", [4] = "loot_first_epic", [5] = "loot_first_legendary" }
local BIND = { [1] = "Bind on Pickup", [2] = "Bind on Equip", [3] = "Bind on Use", [4] = "Quest item" }
local function itemInfo(link)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, _, quality, _, _, _, _, _, equipLoc, _, _, classID, subID, bindType = f(link)
  return name, quality, equipLoc, classID, subID, bindType
end
local function handleItem(link, retry)
  local name, q, equipLoc, classID, subID, bindType = itemInfo(link)
  if not q then if not retry then C_Timer.After(1, function() handleItem(link, true) end) end return end
  if QID[q] and once("q" .. q) then
    C.Emit(QID[q], format("%s found a first %s item: %s.", short(), QNAME[q], link), { item = link }, { title = "First " .. QNAME[q] .. "!", text = link, force = q >= 4 })
  end
  if q >= 2 and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
    local slot = _G[equipLoc] or equipLoc
    local prev = C.cdb.slots[equipLoc] or 0
    if q > prev then
      C.cdb.slots[equipLoc] = q
      C.Emit("loot_slot_quality", format("%s's first %s %s: %s.", short(), QNAME[q] or "", slot, link), { item = link, slot = equipLoc })
    end
  end
  if q >= 3 and bindType and BIND[bindType] then
    C.Emit("loot_boe_bop", format("%s looted %s (%s).", short(), link, BIND[bindType]), { item = link, bind = bindType })
  end
  if classID == 15 and subID == 5 then C.Emit("mount_item", format("%s found a mount: %s.", short(), link), { item = link }, { title = "A mount!", text = link, force = true }) end
end
C.On("CHAT_MSG_LOOT", function(msg, _, _, _, _, _, _, _, _, _, _, guid)
  msg = S(msg); if not msg then return end
  local g = S(guid); if g and g ~= UnitGUID("player") then return end
  if not g and not (LOOT_ITEM_SELF and msg:find((LOOT_ITEM_SELF:gsub("%%s.*", "")), 1, true)) then
    if not (LOOT_ITEM_PUSHED_SELF and msg:find((LOOT_ITEM_PUSHED_SELF:gsub("%%s.*", "")), 1, true)) then return end
  end
  local link = msg:match("|c.-|Hitem:.-|h.-|h|r")
  if link then handleItem(link) end
end)
C.On("PLAYER_EQUIPMENT_CHANGED", function(slot, empty)
  if empty then return end
  local link = GetInventoryItemLink("player", slot); if not link then return end
  local q = GetInventoryItemQuality("player", slot) or 0
  local k = "eq" .. slot
  if q > (C.cdb.flags[k] or 0) then
    local had = C.cdb.flags[k]; C.cdb.flags[k] = q
    if had then C.Emit("equip_upgrade", format("%s equipped %s.", short(), link), { item = link }) end
  end
end)
C.On("NEW_MOUNT_ADDED", function(id)
  local name = C_MountJournal and C_MountJournal.GetMountInfoByID and S(C_MountJournal.GetMountInfoByID(id))
  if once("mount") then C.Emit("mount_first", format("%s earned a first mount%s.", short(), name and (": " .. name) or ""), nil, { title = "First mount!", text = name, force = true }) end
end)
C.On("NEW_PET_ADDED", function() C.Emit("pet_new", format("%s gained a new companion.", short())) end)
C.On("NEW_TOY_ADDED", function(item) local n = itemInfo(item); C.Emit("toy_new", format("%s added a toy%s.", short(), n and (": " .. n) or "")) end)

---------------------------------------------------------------- Professions
C.On("SKILL_LINES_CHANGED", function()
  if not GetProfessions then return end
  for _, idx in ipairs({ GetProfessions() }) do
    if idx then
      local name, _, rank = GetProfessionInfo(idx)
      if name and once("prof" .. name) then C.Emit("prof_learn", format("%s took up %s.", short(), name), { prof = name }, { title = "New profession" }) end
      for _, m in ipairs({ 75, 150, 225, 300 }) do
        if name and rank and rank >= m and once("prof" .. name .. m) then C.Emit("prof_milestone", format("%s reached %d in %s.", short(), m, name), { prof = name }) end
      end
    end
  end
end)
C.On("NEW_RECIPE_LEARNED", function(id)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
  C.Emit("recipe_learn", format("%s learned the recipe %s.", short(), info and S(info.name) or "?"))
end)

---------------------------------------------------------------- Economy
C.On("PLAYER_MONEY", function()
  local g = floor((S(GetMoney()) or 0) / 10000)
  for _, th in ipairs({ 1, 10, 100, 500, 1000, 5000, 10000 }) do
    if g >= th and once("gold" .. th) then
      C.Emit("gold_threshold", format("%s's purse first held %d gold.", short(), th), { gold = th }, { title = "Wealth", key = "g" .. th, text = format("Your purse holds %d gold for the first time.", th) })
    end
  end
end)
C.On("CHAT_MSG_SYSTEM", function(msg)
  msg = S(msg); if not msg then return end
  if ERR_AUCTION_SOLD_S and msg:find((ERR_AUCTION_SOLD_S:gsub("%%s", "")), 1, true) and once("ahsold") then
    C.Emit("ah_first_sale", format("%s sold a first auction.", short()), nil, { title = "First auction sold" })
  end
end)

---------------------------------------------------------------- Travel
C.On("UI_INFO_MESSAGE", function(_, msg)
  if ERR_NEWTAXIPATH and S(msg) == ERR_NEWTAXIPATH then
    local sub = GetSubZoneText()
    C.Emit("flight_learn", format("%s discovered the flight path at %s.", short(), sub ~= "" and sub or GetRealZoneText()), nil, { title = "New flight path" })
  end
end)
C.On("PLAYER_CONTROL_LOST", function()
  C_Timer.After(1, function()
    if UnitOnTaxi("player") and once("flight") then C.Emit("flight_first", format("%s took to the skies for the first time.", short()), nil, { title = "First flight" }) end
  end)
end)
C.On("HEARTHSTONE_BOUND", function()
  local b = GetBindLocation()
  C.Emit("hearth_bind", format("%s now calls %s home.", short(), b or "?"), { bind = b }, { title = "Home: " .. (b or "?") })
end)

---------------------------------------------------------------- Fun & holidays
C.On("PLAYER_FLAGS_CHANGED", function(unit)
  if unit ~= "player" or not UnitIsAFK("player") then return end
  local sub = GetSubZoneText(); sub = sub ~= "" and sub or GetRealZoneText()
  if once("afk" .. sub) then C.Emit("fun_afk_place", format("%s stepped away from the keyboard in %s.", short(), sub)) end
end)
local sessionStart
function L.SessionStart()
  sessionStart = time(); C.sessionStart = sessionStart
  local c = date("*t", C.cdb.created); local n = date("*t")
  if c.month == n.month and c.day == n.day and n.year > c.year and once("bday" .. n.year) then
    C.Emit("birthday", format("%s celebrates %d year(s) of adventure today.", short(), n.year - c.year), nil, { title = "Happy birthday!", force = true })
  end
end
C.Init(function()
  C_Timer.NewTicker(60, function()
    local h = tonumber(date("%H")); local m = tonumber(date("%M"))
    if h == 0 and m == 0 then C.Emit("fun_midnight", format("%s is adventuring at the stroke of midnight in %s.", short(), GetRealZoneText()), nil, { title = "Midnight" }) end
    if sessionStart and time() - sessionStart >= 4 * 3600 and not L.longDone then
      L.longDone = true
      C.Emit("fun_long_session", format("%s has been adventuring for four hours straight.", short()), nil, { title = "Stretch your legs" })
    end
  end)
end)
