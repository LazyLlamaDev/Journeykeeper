-- Flavor layer: adapts echo wording to holidays (C_Calendar), real-world season, game time of day,
-- zone mood and a configurable era label. Pure text; reads no restricted data.
local _, C = ...
local F = {}; C.Flavor = F
F.holiday = nil

local HOLIDAYS = {
  { match = "hallow", name = "Hallow's End", lines = { "Somewhere a pumpkin grins in the dark.", "The Headless Horseman would approve.", "Candles flicker in carved gourds." } },
  { match = "winter veil", name = "Feast of Winter Veil", lines = { "Greatfather Winter is surely watching.", "Snow would suit this moment.", "Bells ring faintly from Orgrimmar." } },
  { match = "brewfest", name = "Brewfest", lines = { "Somewhere a keg is being tapped in your honour.", "The dwarves would raise a mug to this." } },
  { match = "lunar", name = "Lunar Festival", lines = { "The elders would remember this.", "Lanterns drift over Moonglade tonight." } },
  { match = "midsummer", name = "Midsummer Fire Festival", lines = { "Bonfires burn across Azeroth tonight.", "The flames of Midsummer dance in your memory." } },
  { match = "love is in the air", name = "Love is in the Air", lines = { "Something sweet hangs in the air." } },
  { match = "noblegarden", name = "Noblegarden", lines = { "Somewhere an egg lies hidden." } },
  { match = "children", name = "Children's Week", lines = { "An orphan would like to hear this story." } },
  { match = "harvest", name = "Harvest Festival", lines = { "A good season to remember the fallen." } },
  { match = "pilgrim", name = "Pilgrim's Bounty", lines = { "There is always room for one more at the table." } },
  { match = "dead", name = "Day of the Dead", lines = { "The dead are close today; they would remember too." } },
  { match = "fishing", name = "Fishing Extravaganza", lines = { "The fish are biting somewhere." } },
}
local SEASONS = {
  winter = { "The cold makes old memories sharper.", "A winter memory, then." },
  spring = { "Spring air carries old echoes.", "Something new grows out of something old." },
  summer = { "The long summer light lingers on it.", "A warm memory for a warm season." },
  autumn = { "An autumn memory, falling like leaves.", "The year turns, and so do you." },
}
local TIMES = {
  dawn = { "Dawn, as it was then.", "First light finds you again." },
  day = { "In plain daylight, it still feels close." },
  dusk = { "Dusk settles, as it did then.", "The light is going amber." },
  night = { "The night keeps old memories close.", "Under these same stars." },
}
local ZONES = {
  ["Durotar"] = { "The red dust has not changed.", "Dry wind over Durotar." },
  ["Tirisfal Glades"] = { "Fog clings to the memory.", "The dead trees remember." },
  ["The Barrens"] = { "The grass hisses in the wind, as it did then." },
  ["Mulgore"] = { "The plains are wide enough to hold any memory." },
  ["Elwynn Forest"] = { "Birdsong, the same as ever." },
  ["Dun Morogh"] = { "Snow creaks underfoot, as before." },
  ["Teldrassil"] = { "The great tree whispers." },
  ["Stranglethorn Vale"] = { "The jungle hums and forgets nothing." },
  ["Duskwood"] = { "Something howls in the distance." },
  ["Tanaris"] = { "The sand keeps its own counsel." },
}

local function pick(list, seed) if not list or #list == 0 then return nil end; return list[(seed % #list) + 1] end

function F.Season()
  local m = tonumber(date("%m"))
  if m == 12 or m <= 2 then return "winter" elseif m <= 5 then return "spring" elseif m <= 8 then return "summer" end
  return "autumn"
end
function F.TimeOfDay()
  local h = GetGameTime and select(1, GetGameTime()) or tonumber(date("%H"))
  if h >= 5 and h < 8 then return "dawn" elseif h < 18 then return "day" elseif h < 21 then return "dusk" end
  return "night"
end

-- Holiday detection through the calendar (needs calendar data: we call OpenCalendar once, a normal UI request).
function F.ScanHoliday()
  local now = C.API("C_DateAndTime.GetCurrentCalendarTime")
  local n = now and C.API("C_Calendar.GetNumDayEvents", 0, now.monthDay)
  if not n then return end
  F.holiday = nil
  for i = 1, n do
    local ev = C.API("C_Calendar.GetDayEvent", 0, now.monthDay, i)
    if ev and ev.calendarType == "HOLIDAY" and ev.title then
      local t = ev.title:lower()
      for _, h in ipairs(HOLIDAYS) do if t:find(h.match, 1, true) then F.holiday = h; return end end
    end
  end
end
C.On("PLAYER_ENTERING_WORLD", function(isLogin)
  if isLogin and C_Calendar and C_Calendar.OpenCalendar then C.API("C_Calendar.OpenCalendar") end
  C_Timer.After(3, F.ScanHoliday)
end)
C.On("CALENDAR_UPDATE_EVENT_LIST", F.ScanHoliday)

-- Append one understated flavor line (holiday > zone > time > season), respecting toggles and chance.
local counter = 0
function F.Apply(text, cat)
  if not C.set.flavor then return text end
  counter = counter + 1
  if (counter * 37) % 100 >= C.set.flavorChance then return text end
  local seed = counter + (time() % 7)
  local line
  if C.set.flavorHoliday and F.holiday then line = pick(F.holiday.lines, seed) end
  if not line and C.set.flavorZone then line = pick(ZONES[GetRealZoneText() or ""], seed) end
  if not line and C.set.flavorTime and seed % 2 == 0 then line = pick(TIMES[F.TimeOfDay()], seed) end
  if not line and C.set.flavorSeason then line = pick(SEASONS[F.Season()], seed) end
  if not line then return text end
  return text .. " " .. line
end

-- Era label is used in journal title pages / export headers
function F.Era() return C.set.eraLabel ~= "" and C.set.eraLabel or nil end
