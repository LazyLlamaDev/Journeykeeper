-- Warband overview: a table-of-contents spread, one line per character: level, time played, gold, zones explored,
-- memories, deaths, last played. Gold is stored at login/logout; time played only when you ask
-- (button in the chapter or /jkp played -> RequestTimePlayed once; the normal chat lines are printed, we never filter chat).
local _, C = ...
local WT = {}; C.WarbandTOC = WT
local S = C.S
local requested = 0

local function snapshot()
  if not C.set.warbandTOC then return end
  local ci = C.db.chars[C.charKey()]; if not ci then return end
  local m = S(GetMoney()); if m then ci.money = m end
  ci.seen = time()
  local n = 0; for _ in pairs(C.cdb.zones or {}) do n = n + 1 end; ci.zones = n
end
C.On("PLAYER_ENTERING_WORLD", snapshot)
C.On("PLAYER_LOGOUT", snapshot)
C.On("PLAYER_MONEY", function() local ci = C.db.chars[C.charKey()]; local m = S(GetMoney()); if ci and m and C.set.warbandTOC then ci.money = m end end)
C.On("TIME_PLAYED_MSG", function(total, level)
  if not C.set.warbandTOC then return end
  local ci = C.db.chars[C.charKey()]; total = S(total)
  if ci and total then ci.played = total; ci.playedAt = time() end
  if C.Journal and C.Journal.Refresh then C.Journal.Refresh() end
end)
function WT.RequestPlayed()
  if time() - requested < 10 then return false end -- one request per press, never automatic
  requested = time(); C.API("RequestTimePlayed"); return true
end

function WT.Money(c)
  if not c then return "?" end
  return format("%dg %02ds %02dc", floor(c / 10000), floor(c / 100) % 100, c % 100)
end
function WT.Played(s)
  if not s then return "ask" end
  local d, h = floor(s / 86400), floor(s / 3600) % 24
  return d > 0 and format("%dd %dh", d, h) or format("%dh %dm", h, floor(s / 60) % 60)
end

function WT.Rows()
  local rows, mem, deaths = {}, {}, {}
  for _, e in ipairs(C.db.entries) do if e.char then mem[e.char] = (mem[e.char] or 0) + 1; if e.id == "death" then deaths[e.char] = (deaths[e.char] or 0) + 1 end end end
  for ck, ci in pairs(C.db.chars) do
    rows[#rows + 1] = { ck = ck, level = ci.level, class = ci.class, played = ci.played, money = ci.money, zones = ci.zones, mem = mem[ck] or 0, deaths = deaths[ck] or 0, seen = ci.seen }
  end
  table.sort(rows, function(a, b) return (a.seen or 0) > (b.seen or 0) end)
  return rows
end

function WT.Build(blocks, search, H)
  tinsert(blocks, { kind = "chapterhead", text = "The Warband" })
  local rows, gold, played = WT.Rows(), 0, 0
  for _, r in ipairs(rows) do gold = gold + (r.money or 0); played = played + (r.played or 0) end
  tinsert(blocks, { kind = "dash", stats = { { "Characters", #rows }, { "Gold", WT.Money(gold) }, { "Played", WT.Played(played > 0 and played or nil) } },
    note = "Click a character to open its chapter. Time played is asked from the server when you click the refresh row below." })
  tinsert(blocks, H.row({ cat = "warband", title = "Refresh time played", text = "Ask the server for /played of this character.", onClick = function() if WT.RequestPlayed() then C.Print("asked the server for time played") end end }))
  for i, r in ipairs(rows) do
    if search == "" or r.ck:lower():find(search:lower(), 1, true) then
      tinsert(blocks, H.row({ cat = "level", t = r.seen, title = format("%d. Level %s %s", i, r.level or "?", r.class or ""), char = r.ck,
        text = format("Played %s  ·  %s  ·  %s zones  ·  %d memories  ·  %d deaths", WT.Played(r.played), WT.Money(r.money), r.zones or "?", r.mem, r.deaths),
        onClick = function() C.Journal.OpenChapter(r.ck) end }))
    end
  end
end

C.Init(function()
  C.Journal.PROVIDERS.Warband = { enabled = function() return C.set.warbandTOC end, build = WT.Build }
end)
