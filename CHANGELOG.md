# Changelog

## v0.8.0
- **Runs on every WoW version.** One download now works on WoW Forever, Retail (Midnight), Mists of Pandaria Classic, Classic Anniversary (Burning Crusade) and Classic Era (including Hardcore and Season of Discovery). Each game picks its own toc file; WoW Forever is unchanged (Interface 16001).
- **Journey map beyond the old world.** Kalimdor and the Eastern Kingdoms use the right map for your game version, and a new **Other lands** tab steps through every other continent your characters have reached (Outland, Northrend, Pandaria, the Dragon Isles, Khaz Algar ...), drawn with the game's own map art.
- **Quiet fallbacks instead of errors.** Where a game version lacks something, that feature switches itself off: fight records need the built-in damage meter (Retail and Forever), achievements, mount, pet and toy echoes and story-quest tags appear only where the game has them. On Classic clients professions come from the skill list, quest names from the quest log and player tooltips use the classic tooltip hook; Settings open in the classic Interface Options where the new Settings panel is missing.
- `/jkp perf` now also shows your game version and interface number (handy for bug reports).
- Data: no schema change. Every game version keeps its own saved data in its own folder, so your Forever journal is untouched.
- New files (Compat.lua and the per-version toc files): needs a full client restart once.

## v0.7.2
- **Fellowship tooltips.** Hovering a player from your Fellowship adds two quiet lines: runs together and the last one ("3 runs together · last: Deadmines, Oct 2026") and where you first met. Excluded and archived people never show. Bosses you have defeated before get a memory hint ("You first defeated Hogger on 12 Oct 2026"). Both can be switched off (Settings > Fellowship).
- **Auto screenshots at big moments.** A normal game screenshot a moment after a first boss kill, a first dungeon completion, a level milestone or a reunion (achievements optional). The memory remembers the file name (WoWScrnShot_MMDDYY_HHMMSS) and the journal shows "Screenshot taken 21:04 (Screenshots\\...)"; the Journey chapter lists them under Snapshots. Settings: master switch, each moment, delay, at most one every 60 s, and an option to keep the Journeykeeper popup out of the picture. Never during photo mode.
- **Your journey so far.** The Journey chapter opens with a replay of your road on the map: Play / Pause, speed 1x/2x/4x, this character or the whole warband, Restart. Pins appear one by one with a short caption, and the map switches continent when your road does. It pauses when the journal is closed.
- **Reunions.** Grouping again with a fellow after a few days apart (3 by default) brings a reunion echo instead of the normal fellowship echo: how long it has been and what happened on your side since (levels, new places, dungeons, bosses). With a trusted friend who also uses Journeykeeper and friend sharing, it adds up to 5 of their shared milestones since your last time together. Only for trusted friends, only the milestone kinds they already share, opt-in.
- Data: schema 9 (additive: `shots` list, screenshot links on memories). A pre-migration snapshot is taken automatically; nothing is removed or overwritten.
- New files (AutoShot.lua, Replay.lua): needs a full client restart once.

## v0.7.1
- **Detail presets.** A one-time picker (and Settings > Detail preset, `/jkp preset`) with Essentials, Storyteller and Chronicler. A preset only sets existing settings: echo frequency, which events pop up as toasts and what is recorded. Changing any setting afterwards shows "custom". Existing journals keep every setting and get the picker once as an optional offer.
- **Key bindings.** New: Open the journey map, Quick note, Open the Fellowship page (under Key Bindings > AddOns > Journeykeeper, next to journal, photo mode and profile).
- **Addon Compartment.** Journeykeeper appears in the Addon Compartment: click opens the journal, right-click opens Settings, Shift-click writes a quick note; the tooltip shows new echoes.
- **Quick notes.** `/jkp note <text>`, `/note <text>` (only when no other addon uses /note), the Quick note key binding, the journal's Note button or Shift-click on the minimap icon. Notes are journal entries with zone, time and character. Right-click a note in the journal to edit or archive it; `/jkp note list`, `/jkp note restore`. Archiving never deletes. The old note-on-a-player command is now `/jkp allynote <text>`.
- **Fellowship.** Remembers the people you group with: name, realm and class only, plus when and where you first met, time together, shared dungeon runs and boss kills. New journal chapter "Fellowship" with search and sorting. Grouping again with someone you ran a dungeon with brings back an echo ("You ran Deadmines with X on ..."). Settings: on/off, leave out guild members, echoes, retention (default: keep forever, snapshot before anything is removed) and a never-record list. Never sent anywhere.
- Journeykeeper_Forever.toc and Journeykeeper_Camelot.toc are shipped next to the main toc, so a renamed Forever client still finds the addon.
- Data: schema 8 (additive: `fellowship` table). A pre-migration snapshot is taken automatically; nothing is removed or overwritten.
- Needs a full client restart once (new key bindings and toc files); later changes only need /reload.

## v0.7.0 — first public beta
- First public beta for WoW Forever (Interface 16001): Echoes journal book with Timeline, Echoes, Arcs and Chapters; echo toasts; Journey map with echo pins (Kalimdor + Eastern Kingdoms); fights & death reports; photo mode; Friends & Sharing; Data & Backups with optional Vault companion. All data stays local.
- Echo popup hint no longer clipped: short text ("Click: open · Right-click: options"), wraps within the popup and leaves room for the camera button; "Shift-drag to move" shows while hovering.
- Wording: "chronicle" replaced by "journal" in all visible text (search box "Search the journal...", Data & Backups, friend echoes, map pin tooltip, restore prompts). Saved data keys are unchanged.

## v0.6.9
- Friends & Sharing: settings are one column; "What to share" and "Accept from" now sit below "Incoming".
- Friends & Sharing / Data & Backups: content scales to the panel width (down to 80%), with a horizontal scrollbar (also Shift + wheel) when still wider; list action buttons fit inside their lists.
- Echoes filter: our own parchment dropdown and list (brown border, serif ink text, accent hover) instead of the black Blizzard dropdown.
- Arcs are editable: click an arc's title page (or /jkp arc edit <n>) to rename, write notes, set an optional from/to date range, take moments out or back in, make active, or delete. Delete archives (never erased); restore from "Archived arcs" on the Arcs page or /jkp arc restore. New optional arc fields only; no schema change.

## v0.6.8
- Book stays put: the page-flip animation no longer translates the whole book; wheel/clicks on pages never drag it (drag by the leather border). Position is remembered.
- Ribbon bookmarks moved to the right edge of the cover as side tabs (same silk texture, rotated).
- Book scales to the screen (1080p/1440p/4K) plus a "Book size (%)" slider and "Reset book position" in Settings > General; always clamped on screen.
- Echoes filter is a real dropdown (WowStyle1DropdownTemplate), with a list-menu fallback.
- Every Echoes row is clickable: left-click opens a detail card (Show in Timeline / Options), right-click the memory menu.
- Settings: Friends & Sharing and Data & Backups show their content on the first click.
- Photo mode: entering no longer snaps and exits. Move freely, click "Take photo" (or the new "Photo mode: take photo" key binding, /jkp photo snap), take several, exit with Exit / Esc / /jkp photo exit. Combat still exits immediately.
- Sounds: Journeykeeper plays only short UI sound effects (toast chime, page turn, optional ambient chime); no voice lines or music.
