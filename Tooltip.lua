-- Tooltip lines on player units via TooltipDataProcessor (no frame hooks).
local _, C = ...
local S = C.S
local function ago(t) return t and C.dateStr(t) or "?" end
local RATE = { great = "|cff66dd66Great run|r", forgettable = "|cffaaaaaaForgettable|r", avoid = "|cffff5544Avoid|r" }
C.Init(function()
  if not (TooltipDataProcessor and Enum.TooltipDataType) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
    if tt ~= GameTooltip then return end
    if not C.set.socialTooltip then return end
    local guid = data and S(data.guid)
    if not guid or not guid:find("^Player") then return end
    local p = C.db.players[guid]
    if not p then return end
    tt:AddLine(format("|cff4ce566Journeykeeper:|r grouped %dx%s  ·  last seen %s", p.count or 0, (p.runs or 0) > 0 and format(", %d shared run%s", p.runs, p.runs == 1 and "" or "s") or "", ago(p.last)))
    tt:AddLine(format("|cffbbbbbb  %s, on %s%s|r", p.lastWhere or "?", (p.lastChar or "?"):match("^[^-]+"), p.rating and ("  ·  " .. RATE[p.rating]) or ""))
    for i = math.max(1, #p.notes - 1), #p.notes do
      if p.notes[i] then tt:AddLine("|cffaaaaaa  \"" .. p.notes[i].text .. "\"|r", 1, 1, 1, true) end
    end
  end)
end)

-- Mouseover echo for known players when the group channel is chat/toast.
C.On("UPDATE_MOUSEOVER_UNIT", function()
  if C.set.channel.group_echo == "tooltip" or not S(UnitIsPlayer("mouseover")) then return end
  local guid = S(UnitGUID("mouseover"))
  local p = guid and C.db.players[guid]
  if not p then return end
  C.Echo("group_echo", "m" .. guid, format("You grouped with %s %dx, last in %s on %s.", p.name or "?", p.count or 0, p.lastWhere or "?", ago(p.last)),
    "Echo: a familiar face")
end)
