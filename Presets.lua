-- v0.7.1 detail presets: Essentials / Storyteller / Chronicler / Custom. A preset only sets existing settings
-- (echo frequency, which events pop up as toasts, what gets recorded). It never deletes memories.
-- Any later change in Settings switches the preset label to "custom". Existing users keep their settings:
-- they get "custom" and see the picker once, as an optional offer.
local _, C = ...
local P = {}; C.Presets = P
local applying = false

P.ORDER = { "essentials", "storyteller", "chronicler" }
P.LABEL = { essentials = "Essentials", storyteller = "Storyteller", chronicler = "Chronicler", custom = "Custom" }
P.DESC = {
  essentials = "Only the big moments. Few popups, quiet echoes, no rating prompts.",
  storyteller = "The balanced default: firsts, deaths, allies and echoes as designed.",
  chronicler = "Record nearly everything and echo more often. For people who love details.",
}
-- toasts that stay toasts in Essentials; every other toast is logged quietly to the journal
local MAJOR = {}
for _, id in ipairs({ "zone_first_account", "echo_revisit", "death_spot_echo", "boss_first_kill", "dungeon_enter_first", "raid_first", "loot_first_epic",
  "loot_first_legendary", "mount_first", "friend_milestone", "shared_echo", "fellow_echo", "level_milestone", "birthday", "family_first_boss", "thread_return" }) do MAJOR[id] = true end
local ESS_OFF = { sub_first_char = true, sub_first_account = true, quest_accept = true, quest_abandon = true, rest_area_first = true, rare_seen = true,
  recipe_learn = true, spell_learn = true, duel = true, pvp_kill = true, ah_first_sale = true, equip_upgrade = true, boss_wipe = true }
local CHRON_SKIP = { ghost_trail = true } -- has its own heavier switch (ghostTrail)

local VALUES = {
  essentials = { intensity = "soft", quietMode = true, quietMin = 9, digest = false, flavorChance = 20, ratingPrompt = false, vignette = false, recordEchoes = false, fellowEchoes = true },
  storyteller = { intensity = "present", quietMode = false, quietMin = 8, digest = true, flavorChance = 40, ratingPrompt = true, vignette = false, recordEchoes = true, fellowEchoes = true },
  chronicler = { intensity = "storyteller", quietMode = false, quietMin = 8, digest = true, flavorChance = 60, ratingPrompt = true, vignette = true, recordEchoes = true, fellowEchoes = true, dialogueCapture = true },
}
P.VALUES = VALUES

-- what a preset would set: { settings = {k=v}, ev = {id=bool}, channel = {id=ch} }
function P.Plan(name)
  local v = VALUES[name]; if not v then return nil end
  local plan = { settings = {}, ev = {}, channel = {} }
  for k, x in pairs(v) do plan.settings[k] = x end
  for _, e in ipairs(C.EVENTS) do
    local on, ch = C.defaults.ev[e.id], C.defaults.channel[e.id] -- shipped defaults (last registry row wins)
    if name == "essentials" then
      if ESS_OFF[e.id] then on = false end
      if ch == "toast" and not MAJOR[e.id] then ch = "journal" end
      if ch == "chat" then ch = "journal" end
    elseif name == "chronicler" then
      if not CHRON_SKIP[e.id] and e.feas ~= "blocked" then on = true end
    end
    plan.ev[e.id], plan.channel[e.id] = on, ch
  end
  return plan
end

function P.Apply(name)
  local s = C.set
  if not s then return false end
  if name == "custom" or not VALUES[name] then s.preset = "custom"; return false end
  local plan = P.Plan(name)
  applying = true
  for k, x in pairs(plan.settings) do s[k] = x end
  for id, on in pairs(plan.ev) do s.ev[id] = on end
  for id, ch in pairs(plan.channel) do s.channel[id] = ch end
  s.preset = name; s.presetPicked = time()
  applying = false
  if C.SettingsRefresh then pcall(C.SettingsRefresh) end
  C.Print(format("detail preset: %s. Change anything in Settings to fine-tune (the preset then shows 'custom').", P.LABEL[name]))
  return true
end

-- called by every settings widget after a user change
function C.Touched(key)
  if applying or key == "preset" or not C.set then return end
  if C.set.preset ~= "custom" then C.set.preset = "custom" end
end

-- first load of v0.7.1: decide the starting preset without touching any existing value
function P.Init(isNew)
  local s = C.set
  if s.preset == nil then
    s.preset = isNew and "storyteller" or "custom"
    s.presetOffer = true -- show the picker once (optional for existing users)
  end
end

local picker
local function build()
  picker = CreateFrame("Frame", "JourneykeeperPresetPicker", UIParent, "BasicFrameTemplateWithInset")
  picker:SetSize(420, 250); picker:SetPoint("CENTER", 0, 80); picker:SetFrameStrata("DIALOG"); picker:SetClampedToScreen(true)
  picker:SetMovable(true); picker:EnableMouse(true); picker:RegisterForDrag("LeftButton")
  picker:SetScript("OnDragStart", picker.StartMoving); picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
  if picker.TitleText then picker.TitleText:SetText("Journeykeeper - how much should I remember?") end
  picker.intro = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); picker.intro:SetPoint("TOPLEFT", 16, -32); picker.intro:SetWidth(388); picker.intro:SetJustifyH("LEFT")
  picker.btns = {}
  for i, name in ipairs(P.ORDER) do
    local b = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate"); b:SetSize(120, 24); b:SetPoint("TOPLEFT", 16, -64 - (i - 1) * 46)
    b:SetText(P.LABEL[name])
    b:SetScript("OnClick", function() P.Apply(name); picker:Hide() end)
    local d = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); d:SetPoint("LEFT", b, "RIGHT", 10, 0); d:SetWidth(250); d:SetJustifyH("LEFT"); d:SetText(P.DESC[name])
    picker.btns[i] = b
  end
  local keep = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate"); keep:SetSize(200, 22); keep:SetPoint("BOTTOM", 0, 14)
  keep:SetText("Keep my current settings")
  keep:SetScript("OnClick", function() picker:Hide() end)
  tinsert(UISpecialFrames, "JourneykeeperPresetPicker")
end

function P.ShowPicker(manual)
  if InCombatLockdown and InCombatLockdown() then if manual then C.Print("the preset picker opens after combat") end return false end
  if not picker then build() end
  picker.intro:SetText(C.set.preset == "custom" and "Your own settings stay as they are unless you pick a preset. You can change this any time in Settings > Detail preset."
    or "Pick how detailed your journal should be. You can change this any time in Settings > Detail preset.")
  C.set.presetOffer = nil
  picker:Show()
  return true
end

C.Init(function()
  P.Init(#C.db.entries == 0 and not next(C.db.chars or {}, next(C.db.chars or {})))
  if C.set.presetOffer and C.Data and C.Data.writable then
    C.On("PLAYER_ENTERING_WORLD", function()
      if not C.set.presetOffer then return end
      C_Timer.After(6, function() if C.set.presetOffer then P.ShowPicker(false) end end)
    end)
  end
end)
