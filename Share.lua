-- Friend sharing (opt-in). Addon messages via C_ChatInfo; own throttled queue (ChatThrottleLib-like);
-- nothing is sent in combat, nothing is sent unless the user enabled it and the recipient is trusted.
-- Policy: we send only small, user-selected milestone records to trusted friends; no chat-channel spam,
-- no location unless "share location" is enabled. Protocol: "JKPR" prefix, pipe-separated, chunked.
local _, C = ...
local SH = {}; C.Share = SH
local PREFIX, VERSION = "JKPR", 1
local MAXLEN = 240
local queue, partial, bytesBudget, lastSend = {}, {}, 2000, 0
local BUDGET_MAX, BUDGET_RATE = 2000, 800 -- bytes, bytes/sec
local msgId = 0

local function sdb()
  C.db.share = C.db.share or { trusted = {}, blocked = {}, peers = {}, inbox = {} }
  return C.db.share
end
local function norm(name)
  if not name then return nil end
  if not name:find("-", 1, true) then name = name .. "-" .. (GetNormalizedRealmName() or "") end
  return name
end
local function esc(s) return (tostring(s or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", " ")) end
local function unesc(s) return (s:gsub("%%7C", "|"):gsub("%%25", "%%")) end

function SH.IsTrusted(sender)
  local d = sdb(); sender = norm(sender)
  if d.blocked[sender] then return false end
  if d.trusted[sender] then return true end
  local short = sender:match("^[^-]+")
  if C.set.shareAllowFriends and C_FriendList and C_FriendList.IsFriend then
    local ok, f = pcall(C_FriendList.IsFriend, sender); if ok and f then return true end
  end
  if C.set.shareAllowGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.MemberExistsByName then
    local ok, g = pcall(C_GuildInfo.MemberExistsByName, short); if ok and g then return true end
  end
  return false
end

---------------------------------------------------------------- queue
local pumpTicker
local function ensurePump()
  if pumpTicker or not C_Timer.NewTicker then return end
  pumpTicker = C_Timer.NewTicker(0.2, function()
    SH.Pump(0.2)
    if #queue == 0 and pumpTicker then if pumpTicker.Cancel then pumpTicker:Cancel() end; pumpTicker = nil end
  end)
end
local function enqueue(channel, target, payload)
  ensurePump()
  msgId = (msgId % 999) + 1
  local n = math.max(1, math.ceil(#payload / MAXLEN))
  for i = 1, n do
    tinsert(queue, { channel = channel, target = target, text = format("%d:%d:%d:%s", msgId, i, n, payload:sub((i - 1) * MAXLEN + 1, i * MAXLEN)) })
  end
end
function SH.Pump(elapsed)
  bytesBudget = math.min(BUDGET_MAX, bytesBudget + BUDGET_RATE * (elapsed or 0.2))
  if #queue == 0 or InCombatLockdown() or UnitAffectingCombat("player") then return end
  local m = queue[1]
  if bytesBudget < #m.text + 40 then return end
  tremove(queue, 1)
  bytesBudget = bytesBudget - #m.text - 40
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  pcall(send, PREFIX, m.text, m.channel, m.target)
end
SH.queue = queue

function SH.Send(kind, fields, toWhom)
  if not C.set.shareEnabled then return end
  local parts = { tostring(VERSION), kind }
  for _, f in ipairs(fields) do parts[#parts + 1] = esc(f) end
  local payload = table.concat(parts, "|")
  if toWhom then enqueue("WHISPER", toWhom, payload) return end
  local d = sdb()
  for name in pairs(d.trusted) do
    if not d.blocked[name] and d.peers[name] then enqueue("WHISPER", name, payload) end
  end
  if C.set.shareGuild and IsInGuild() then enqueue("GUILD", nil, payload) end
  if C.set.shareParty and IsInGroup() and not IsInRaid() then enqueue("PARTY", nil, payload) end
end

---------------------------------------------------------------- outgoing: milestones
local SHARE_KIND = {
  level_milestone = "milestones", achievement = "milestones", guild_join = "milestones", mount_first = "milestones",
  boss_first_kill = "firsts", dungeon_enter_first = "firsts", rare_kill = "firsts", family_first_rare = "firsts", family_first_boss = "firsts",
  family_first_clear = "firsts", loot_first_epic = "firsts",
}
function SH.OnEmit(id, e)
  if not C.set.shareEnabled or not e then return end
  local group = SHARE_KIND[id]
  if not group then return end
  if group == "milestones" and not C.set.shareMilestones then return end
  if group == "firsts" and not C.set.shareFirsts then return end
  local who = C.charKey():match("^[^-]+")
  SH.Send("MS", { id, who, e.level or "", e.boss or e.target or e.instance or e.newLevel or "", e.instance or "", date("%Y-%m-%d", e.t),
    C.set.shareLocation and (e.zone or "") or "" })
end

---------------------------------------------------------------- incoming
local function displayName(sender) return (sender or "?"):match("^[^-]+") end
local SHARED_TEXT = {
  level_milestone = "%s reached level %s.", achievement = "%s earned an achievement.", guild_join = "%s found a guild.",
  mount_first = "%s earned a first mount.", boss_first_kill = "%s defeated %s for the first time.", dungeon_enter_first = "%s entered %s for the first time.",
  rare_kill = "%s brought down the rare %s.", family_first_rare = "%s brought down the rare %s.", family_first_boss = "%s defeated %s.",
  family_first_clear = "%s completed %s.", loot_first_epic = "%s found a first epic treasure.",
}
local function sharedMemory(id, subject, inst, day)
  if not C.set.shareShared or subject == "" then return nil end
  for i = #C.db.entries, 1, -1 do
    local e = C.db.entries[i]
    if date("%Y-%m-%d", e.t) == day then
      local same = (e.boss and e.boss == subject) or (e.target and e.target == subject) or (e.instance and e.instance == subject and id == "dungeon_enter_first")
      if same then return i, e end
    end
  end
end
local handlers = {}
-- peer directory: everyone detected running Journeykeeper (handshakes + messages)
local function touchPeer(sender, channel, ver, class)
  local p = sdb().peers[sender] or { shared = 0, first = time() }
  sdb().peers[sender] = p
  p.seen = time(); p.src = (channel or "WHISPER"):lower()
  if ver then p.ver = ver end
  if class and class ~= "" then p.class = class end
  return p
end
SH.touchPeer = touchPeer
function handlers.HELLO(sender, f, channel)
  touchPeer(sender, channel, tonumber(f[1]) or 0, f[3])
  if f[2] ~= "ack" and SH.IsTrusted(sender) then SH.Send("HELLO", { VERSION, "ack", select(2, UnitClass("player")) or "" }, sender) end
  if SH.OnPeersChanged then SH.OnPeersChanged() end
end
function handlers.MS(sender, f, channel)
  if not SH.IsTrusted(sender) then return end
  touchPeer(sender, channel)
  local id, who, level, subject, inst, day, zone = f[1], f[2], f[3], f[4], f[5], f[6], f[7]
  -- the same milestone can arrive via WHISPER and PARTY/GUILD: handle it once
  local dk = sender .. "|" .. tostring(id) .. "|" .. tostring(subject) .. "|" .. tostring(level) .. "|" .. tostring(day)
  SH.seenMsg = SH.seenMsg or {}
  if SH.seenMsg[dk] then return end
  SH.seenMsg[dk] = true
  local fmt = SHARED_TEXT[id]; if not fmt then return end
  local text = format(fmt, who, subject ~= "" and subject or level)
  if zone and zone ~= "" then text = text .. " (" .. zone .. ")" end
  tinsert(sdb().inbox, { t = time(), from = sender, id = id, text = text })
  while #sdb().inbox > 200 do tremove(sdb().inbox, 1) end
  local idx, mine = sharedMemory(id, subject, inst, day)
  if idx then
    local p = sdb().peers[sender]; p.shared = (p.shared or 0) + 1
    if SH.OnPeersChanged then SH.OnPeersChanged() end
    C.Emit("shared_echo", format("You and %s share a memory: %s, on the same day.", displayName(sender), subject), { guidFriend = sender, entryRef = idx },
      C.set.shareSharedToasts and { title = "A shared memory", key = "shared" .. sender .. subject .. day, force = true, meta = { entry = idx, first = true },
        text = format("You and %s both faced %s on %s. Two journals, one memory.", displayName(sender), subject, C.dateStr(mine.t)) } or nil)
  else
    C.Emit("friend_milestone", format("From %s's journal: %s", displayName(sender), text), { friend = sender },
      C.set.shareToasts and { title = "A friend's journal", key = "fm" .. sender .. id .. subject, text = text } or nil)
  end
end

C.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
  if prefix ~= PREFIX or not C.set.shareEnabled then return end
  msg, sender = C.S(msg), C.S(sender)
  if not msg or not sender then return end
  sender = norm(sender)
  if sender == C.charKey() or sdb().blocked[sender] then return end
  local id, i, n, body = msg:match("^(%d+):(%d+):(%d+):(.*)$")
  if not id then return end
  i, n = tonumber(i), tonumber(n)
  local key = sender .. id
  partial[key] = partial[key] or {}
  partial[key][i] = body
  for k = 1, n do if not partial[key][k] then return end end
  local payload = table.concat(partial[key]); partial[key] = nil
  local fields = {}
  for part in (payload .. "|"):gmatch("(.-)|") do fields[#fields + 1] = unesc(part) end
  local ver, kind = tonumber(fields[1]), fields[2]
  if not ver or not handlers[kind] then return end
  local rest = {}
  for k = 3, #fields do rest[#rest + 1] = fields[k] end
  if kind ~= "HELLO" and not SH.IsTrusted(sender) then return end
  handlers[kind](sender, rest, channel)
end)

---------------------------------------------------------------- setup + commands
C.Init(function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  -- no per-frame OnUpdate: a 0.2 s ticker runs only while messages are queued
end)
C.On("PLAYER_ENTERING_WORLD", function(isLogin)
  if isLogin and C.set.shareEnabled then C_Timer.After(10, function() for name in pairs(sdb().trusted) do SH.Hello(name) end end) end
end)
local function hello(name) SH.Send("HELLO", { VERSION, "hi", select(2, UnitClass("player")) or "" }, name) end
SH.Hello = hello
function SH.Ping(name)
  if not C.set.shareEnabled then C.Print("enable friend sharing first"); return false end
  hello(norm(name)); return true
end
function SH.Trust(name) local d = sdb(); name = norm(name); d.trusted[name] = true; d.blocked[name] = nil; if C.set.shareEnabled then hello(name) end; if SH.OnPeersChanged then SH.OnPeersChanged() end end
function SH.Untrust(name) sdb().trusted[norm(name)] = nil; if SH.OnPeersChanged then SH.OnPeersChanged() end end
function SH.Block(name) local d = sdb(); name = norm(name); d.blocked[name] = true; d.trusted[name] = nil; if SH.OnPeersChanged then SH.OnPeersChanged() end end
function SH.Unblock(name) sdb().blocked[norm(name)] = nil; if SH.OnPeersChanged then SH.OnPeersChanged() end end
function SH.Remove(name) local d = sdb(); name = norm(name); d.trusted[name] = nil; d.peers[name] = nil; if SH.OnPeersChanged then SH.OnPeersChanged() end end
function SH.Status(name) local d = sdb(); if d.blocked[name] then return "Blocked" elseif d.trusted[name] then return "Trusted" end; return "Known" end
-- rows for the Friends page: union of peers, trusted and blocked
function SH.Rows()
  local d, seen, out = sdb(), {}, {}
  local function add(n) if not seen[n] then seen[n] = true; local p = d.peers[n] or {}
    out[#out + 1] = { name = n, ver = p.ver, seen = p.seen, src = p.src, class = p.class, shared = p.shared or 0, status = SH.Status(n) } end end
  for n in pairs(d.peers) do add(n) end; for n in pairs(d.trusted) do add(n) end; for n in pairs(d.blocked) do add(n) end
  return out
end
SH.norm = norm
local lastGroupHello = 0
C.On("GROUP_ROSTER_UPDATE", function()
  if C.set.shareEnabled and C.set.shareParty and IsInGroup() and time() - lastGroupHello > 60 then
    lastGroupHello = time(); SH.Send("HELLO", { VERSION, "hi", select(2, UnitClass("player")) or "" }, nil)
  end
end)
function SH.Command(rest)
  local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  local d = sdb(); local name = arg ~= "" and norm(arg) or nil
  if sub == "add" and name then SH.Trust(name); C.Print("trusted: " .. name)
  elseif sub == "remove" and name then SH.Untrust(name); C.Print("removed: " .. name)
  elseif sub == "block" and name then SH.Block(name); C.Print("blocked: " .. name)
  elseif sub == "unblock" and name then SH.Unblock(name); C.Print("unblocked: " .. name)
  elseif sub == "ping" and name then if SH.Ping(name) then C.Print("hello sent to " .. name) end
  elseif sub == "page" then if C.FriendsPage then C.FriendsPage.Open() end
  else
    C.Print("/jkp friend add|remove|block|unblock|ping <Name-Realm>, /jkp friend page  -  sharing is " .. (C.set.shareEnabled and "ON" or "OFF (enable in settings)"))
    for n in pairs(d.trusted) do C.Print("  trusted: " .. n .. (d.peers[n] and d.peers[n].ver and format(" (Journeykeeper v%d)", d.peers[n].ver) or " (no handshake yet)")) end
    for n in pairs(d.blocked) do C.Print("  blocked: " .. n) end
  end
end
