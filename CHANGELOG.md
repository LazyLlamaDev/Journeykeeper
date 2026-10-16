# Changelog

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
