# Changelog

## v0.7.0
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
