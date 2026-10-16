-- Data-driven option definitions. Settings.lua renders these; tools/settings_doc.py turns them into docs/SETTINGS.md.
-- type: toggle | slider | cycle | button
local _, C = ...
C.OPTIONS = {
  { section = "Detail Preset", items = {
    { key = "preset", type = "cycle", label = "Detail preset", values = { "essentials", "storyteller", "chronicler", "custom" },
      help = "essentials = only the big moments, few popups. storyteller = the balanced default. chronicler = record nearly everything, more echoes. Changing any setting yourself switches to 'custom'. Choosing a preset never deletes memories.",
      apply = function() if C.Presets then C.Presets.Apply(C.set.preset) end end },
    { key = "presetPicker", type = "button", label = "Show the preset picker", run = function() if C.Presets then C.Presets.ShowPicker(true) end end },
  } },
  { section = "General", items = {
    { key = "intensity", type = "cycle", label = "Echo intensity", values = { "silent", "soft", "present", "storyteller" }, default = "present", help = "How often and how readily echoes appear." },
    { key = "quietMode", type = "toggle", label = "Quiet Mode", default = false, help = "Only the highest-weight memories are shown." },
    { key = "quietMin", type = "slider", label = "Quiet Mode minimum score", min = 4, max = 14, step = 1, default = 8 },
    { key = "toastStyle", type = "cycle", label = "Toast style", values = { "parchment", "dark" }, default = "parchment" },
    { key = "toastAnchor", type = "cycle", label = "Popup position", values = { "top", "center", "bottom", "custom" }, default = "top",
      help = "top = top-center (default), center = middle of the screen, bottom = bottom-center. 'custom' is set automatically when you Shift-drag a popup.",
      apply = function() if C.set.toastAnchor ~= "custom" then C.Toast.SetPreset(C.set.toastAnchor) end end },
    { key = "toastReset", type = "button", label = "Reset popup position (Shift-drag a popup to move it)", run = function() C.Toast.ResetPosition() end },
    { key = "bookSize", type = "slider", label = "Book size (%)", min = 50, max = 160, step = 5, default = 100,
      help = "100 = automatic size for your screen (1080p, 1440p and 4K). The book always stays fully on screen.",
      apply = function() if C.Journal and C.Journal.ApplyScale then C.Journal.ApplyScale() end end },
    { key = "bookReset", type = "button", label = "Reset book position", run = function() if C.set then C.set.bookPos = nil end; local w = _G.JourneykeeperJournal; if w then w:ClearAllPoints(); w:SetPoint("CENTER", 0, -20) end end },
    { key = "quietInstances", type = "toggle", label = "Hold echoes while in instances", default = true },
    { key = "mapPins", type = "toggle", label = "World map pins for memorable spots", default = false, help = "Off by default: pinning frames onto the world map can trigger Blizzard's addon blocker. Turn on only if you need the pins." },
  } },
  { section = "Emotional Weighting", items = {
    { key = "rarityWeight", type = "slider", label = "Rarity weight", min = 0, max = 3, step = 0.5, default = 1, help = "Bonus for memories that are rare across the whole account." },
    { key = "contextWeight", type = "slider", label = "Context weight", min = 0, max = 4, step = 0.5, default = 2, help = "e.g. returning at high level to where you died at low level." },
    { key = "anchorBoost", type = "slider", label = "Pinned moment boost", min = 0, max = 10, step = 1, default = 6 },
    { key = "decayDays", type = "slider", label = "Ordinary memories fade over (days)", min = 7, max = 365, step = 7, default = 90 },
    { key = "reinforceStep", type = "slider", label = "Reinforcement per revisit/echo", min = 0, max = 1, step = 0.25, default = 0.5 },
    { key = "resetBoosts", type = "button", label = "Reset 'remind me more' boosts", run = function() wipe(C.set.catBoost); C.Print("category boosts reset") end },
  } },
  { section = "Warband Resonance", items = {
    { key = "warbandEcho", type = "toggle", label = "Echoes that name your other characters", default = true },
    { key = "familyFirsts", type = "toggle", label = "Warband 'family firsts'", default = true },
    { key = "ghostTrail", type = "toggle", label = "Ghost trail of other characters on the world map", default = false },
    { key = "ghostDensity", type = "cycle", label = "Ghost trail density", values = { "low", "medium", "high" }, default = "low", help = "Sampling: 120 s / 60 s / 30 s, max 400 dots per map." },
    { key = "ghostSelf", type = "toggle", label = "Include the current character's trail", default = false },
  } },
  { section = "Soft Social", items = {
    { key = "socialTooltip", type = "toggle", label = "Known-player lines in unit tooltips", default = true },
    { key = "ratingPrompt", type = "toggle", label = "Ask for a private rating after a group ends", default = true },
    { key = "ratingMinMinutes", type = "slider", label = "Only ask after grouping for (minutes)", min = 5, max = 60, step = 5, default = 10 },
    { key = "ratingWeight", type = "slider", label = "How much ratings affect ally echoes", min = 0, max = 5, step = 1, default = 3 },
  } },
  { section = "Atmosphere", items = {
    { key = "sound", type = "toggle", label = "Toast sound", default = true },
    { key = "ambient", type = "cycle", label = "Ambient sound for strong echoes", values = { "off", "chime", "parchment", "horn" }, default = "chime" },
    { key = "vignette", type = "toggle", label = "Subtle screen vignette for strong echoes", default = false },
    { key = "vignetteMin", type = "slider", label = "Vignette minimum score", min = 4, max = 14, step = 1, default = 9 },
    { key = "minimapIcon", type = "toggle", label = "Minimap icon (glows on new echoes)", default = true },
    { key = "mmAngle", type = "slider", label = "Minimap icon angle (degrees)", min = 0, max = 359, step = 1, default = 225,
      help = "Position on the rim. 225 = southwest, away from the Issue Reporter. Shift-drag the icon to set this live.",
      apply = function()
        C.db.mmAngle = C.set.mmAngle
        if C.Atmos and C.Atmos.PlaceMinimap then C.Atmos.PlaceMinimap() end
      end },
  } },
  { section = "Threads & Arcs", items = {
    { key = "threads", type = "toggle", label = "Detect chains (returning to where you first fell, ...)", default = true },
    { key = "digest", type = "toggle", label = "'Since you were last here' digest at login", default = true },
    { key = "digestHours", type = "slider", label = "Digest after an absence of (hours)", min = 1, max = 72, step = 1, default = 8 },
  } },
  { section = "Agency", items = {
    { key = "autoCurve", type = "toggle", label = "Adapt intensity: lower in long sessions, instances and raids, higher while resting", default = true },
    { key = "unmuteAll", type = "button", label = "Unmute all memories", run = function() wipe(C.db.muted); C.Print("all memories unmuted") end },
  } },
  { section = "Combat Metrics", items = {
    { key = "combatMetrics", type = "toggle", label = "Track fight records via the built-in damage meter", default = true, help = "Reads C_DamageMeter only after combat ends and only non-secret values. No single biggest hit: the API exposes per-spell totals per fight." },
    { key = "minFightSeconds", type = "slider", label = "Ignore fights shorter than (seconds)", min = 5, max = 120, step = 5, default = 15 },
    { key = "recordEchoes", type = "toggle", label = "Echo toasts for new personal records", default = true },
    { key = "combatLog", type = "toggle", label = "Use the combat log (killer names, rare kills)", default = false, apply = function() C.Logger.UpdateCombatLog() end,
      help = "Off by default: the combat log is WoW's busiest event and Midnight-era clients restrict it for addons. Without it, killer names come from your last hostile target." },
  } },
  { section = "Flavor & Seasons", items = {
    { key = "flavor", type = "toggle", label = "Seasonal / atmospheric wording in echoes", default = true },
    { key = "flavorChance", type = "slider", label = "How often to add a flavor line (%)", min = 0, max = 100, step = 10, default = 40 },
    { key = "flavorHoliday", type = "toggle", label = "Holiday flavor (from the in-game calendar)", default = true },
    { key = "flavorSeason", type = "toggle", label = "Real-world season flavor", default = true },
    { key = "flavorTime", type = "toggle", label = "Game time of day flavor", default = true },
    { key = "flavorZone", type = "toggle", label = "Zone mood flavor", default = true },
    { key = "eraLabel", type = "input", label = "Era / phase label (journal title)", default = "", help = "e.g. 'Forever Phase 1'. Shown on the journal title page and in exports." },
  } },
  { section = "Photo Mode", items = {
    { key = "photoMode", type = "toggle", label = "Photo mode (master switch)", default = true, help = "/jkp photo, keybind, or the camera button on toasts and the journal. Out of combat only." },
    { key = "photoHideUI", type = "toggle", label = "Hide the interface while shooting", default = true },
    { key = "photoVignette", type = "toggle", label = "Vignette", default = true },
    { key = "photoFrame", type = "toggle", label = "Ornate frame", default = true },
    { key = "photoCaption", type = "toggle", label = "Caption (memory, zone, character, date)", default = true },
    { key = "photoPreset", type = "cycle", label = "Camera preset", values = { "none", "close", "medium", "wide" }, default = "none" },
  } },
  { section = "Journey Map", items = {
    { key = "journey", type = "toggle", label = "Journey chapter (master switch)", default = true },
    { key = "journeySketch", type = "toggle", label = "Continent sketch pages", default = true },
    { key = "journeyRealMap", type = "toggle", label = "Use the real in-game continent map behind the journey path", default = true, help = "Reads Blizzard map tiles via C_Map onto the journal page. Falls back to the drawn parchment map." },
    { key = "journeyOverlay", type = "toggle", label = "Draw my path on the world map", default = true, help = "Uses the ghost-trail samples you already record." },
  } },
  { section = "Death Reports", items = {
    { key = "deathReports", type = "toggle", label = "Last-moments report per death (master switch)", default = true },
    { key = "deathAnnounce", type = "cycle", label = "Announce my deaths (one line)", values = { "off", "party", "guild" }, default = "off", help = "Off by default. At most once per 5 minutes, never in combat or during a boss encounter." },
  } },
  { section = "Person Profiles", items = {
    { key = "profiles", type = "toggle", label = "Private profiles for people you meet (master switch)", default = true, help = "Never sent to anyone. /jkp who <name>, /jkp tag, /jkp rate." },
    { key = "profileTooltip", type = "toggle", label = "Show rating and tags in unit tooltips", default = true },
  } },
  { section = "Warband Overview", items = {
    { key = "warbandTOC", type = "toggle", label = "Warband table of contents (master switch)", default = true, help = "Time played is only requested when you click it or type /jkp played." },
  } },
  { section = "Book-style Dialogue", items = {
    { key = "dialogue", type = "toggle", label = "Book-style dialogue (master switch)", default = false, help = "Adds a 'Read in Journeykeeper' button beside the quest window. Blizzard's quest window is never changed." },
    { key = "dialogueCapture", type = "toggle", label = "Save story quest texts to the journal", default = true },
    { key = "dialogueAll", type = "toggle", label = "Save all quest texts, not only story quests", default = false },
    { key = "dialogueOverlay", type = "toggle", label = "Open the parchment automatically", default = false },
  } },
  { section = "Sharing", page = "friends", items = {
    { key = "shareEnabled", type = "toggle", label = "Enable friend sharing (master switch, opt-in)", default = false, help = "Sends small addon messages only to trusted friends. Never in combat. Nothing is sent while this is off." },
  } },
  { section = "What to share", page = "friends", items = {
    { key = "shareMilestones", type = "toggle", label = "Milestones (levels, achievements, mounts, guild)", default = true },
    { key = "shareFirsts", type = "toggle", label = "Firsts (boss kills, rares, dungeons, epics)", default = true },
    { key = "shareShared", type = "toggle", label = "Detect shared memories with friends", default = true },
    { key = "shareLocation", type = "toggle", label = "Include zone name", default = false, help = "Off: messages never contain a location." },
  } },
  { section = "Channels", page = "friends", items = {
    { key = "shareGuild", type = "toggle", label = "Also send to GUILD channel", default = false },
    { key = "shareParty", type = "toggle", label = "Also send to PARTY channel", default = false },
  } },
  { section = "Accept from", page = "friends", items = {
    { key = "shareAllowFriends", type = "toggle", label = "Players on my friends list", default = false },
    { key = "shareAllowGuild", type = "toggle", label = "Members of my guild", default = false },
  } },
  { section = "Incoming", page = "friends", items = {
    { key = "shareToasts", type = "toggle", label = "Show toasts for incoming friend milestones", default = true, help = "Off: they are only logged in the journal." },
    { key = "shareSharedToasts", type = "toggle", label = "Show toasts for shared memories", default = true },
  } },
  { section = "Quick Notes", items = {
    { key = "quickNotes", type = "toggle", label = "Quick notes (master switch)", default = true, help = "/jkp note <text>, the key binding, the journal's Note button and Shift-click on the minimap icon. Notes are journal entries with zone, time and character; right-click one in the journal to edit or archive it." },
    { key = "noteSlash", type = "toggle", label = "Also register /note (only if no other addon uses it)", default = true, help = "Checked at login. If another addon already owns /note, only /jkp note is used. Takes effect after /reload." },
    { key = "minimapNoteClick", type = "toggle", label = "Shift-click the minimap icon for a quick note", default = true },
  } },
  { section = "Fellowship", items = {
    { key = "fellowship", type = "toggle", label = "Remember the people I group with (master switch)", default = true, help = "Stores only name, realm and class, plus when and where you met, time together, shared dungeon runs and boss kills. Never sent anywhere." },
    { key = "fellowGuild", type = "toggle", label = "Leave out members of my guild", default = false },
    { key = "fellowEchoes", type = "toggle", label = "Echo when I group again with someone I ran a dungeon or killed a boss with", default = true },
    { key = "fellowRetention", type = "slider", label = "Forget fellows not seen for (days, 0 = never)", min = 0, max = 730, step = 30, default = 0, help = "0 keeps everyone. A snapshot is taken before anyone is removed." },
    { key = "fellowExclude", type = "input", label = "Never record these names (comma separated)", default = "", maxLetters = 250, help = "e.g. 'Bob, Alice-Realm'. A name without realm matches every realm." },
  } },
  { section = "Addon Compartment", items = {
    { key = "compartment", type = "toggle", label = "Use the Addon Compartment entry (left: journal, right: settings)", default = true, help = "Blizzard always lists the entry; when this is off, clicking it only prints a hint." },
  } },
  { section = "Export", items = {
    { key = "htmlTop", type = "slider", label = "Memories in the HTML book", min = 10, max = 200, step = 10, default = 50 },
  } },
}
for _, sec in ipairs(C.OPTIONS) do
  for _, o in ipairs(sec.items) do if o.default ~= nil then C.defaults[o.key] = o.default end end
end
