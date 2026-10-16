# Journeykeeper — Echoes of Your Journey

**Your journey remembers you.** Journeykeeper is a free memory journal for WoW Forever. It quietly records your firsts, your fights and the places that mattered, keeps them in a book you can read in-game, and gently **echoes** them back when you return. All data stays on your PC; nothing is sent to anyone unless you turn on friend sharing.

![Journeykeeper — Echoes of Your Journey](docs/images/00_hero.jpg)

## Features

### 📖 Journal book
A leather-bound journal for each character, with chapters, a diary, your own story arcs, a warband overview and "last moments" cards for every death.

### ✨ Living Echoes
Short memory reminders when you come back somewhere that mattered: "You first walked these woods as a level 12 Hunter…". They are rare, never shown in combat, and you can move them, mute them or turn them up or down.

### 🥇 Firsts & timeline
Your first zone, dungeon, boss kill, rare, mount, epic and level milestones, plus your whole journey as a clean, filterable timeline. Fights & Records (best DPS, longest fight, boss kills) come from Blizzard's built-in damage meter.

### 🗺️ Journey map
A real, zoomable Kalimdor and Eastern Kingdoms map with your road through the world and your memories on it. Echoes can also show on the world map.

### 📷 Photo mode
Hide the UI, frame the moment with a parchment border and caption, and take a screenshot linked to the memory. Works only out of combat.

### 🤝 Friends & Sharing (opt-in, off by default)
- Share your milestones and firsts (levels, first boss kills, rares, dungeons, epics) with friends you trust, and nobody else.
- Get a "Two journals, one memory" echo when you and a friend faced the same boss or dungeon on the same day.
- You decide what to share, whether your zone is included, and who you accept from: trusted friends only, or your friends list or guild too.
- A Friends & Sharing page lists other Journeykeeper players with Trust, Block and Ping buttons, and anyone you block is ignored.
- It's quiet and safe: nothing is sent in combat, it never posts in public chat, and nothing is sent at all while it's off.

### 🛡️ Data safety
Updates never delete your data. Every logout keeps a backup, a second backup lives in the companion addon **Journeykeeper_Vault**, and a damaged save switches the addon to read-only instead of overwriting it. See [docs/DATA_SAFETY.md](docs/DATA_SAFETY.md).

### ⚙️ Settings
Everything can be switched off or tuned: what gets tracked, how often echoes appear and where they show up. See [docs/SETTINGS.md](docs/SETTINGS.md).

## Screenshots

| | |
|---|---|
| <img src="docs/images/01_journal_book.jpg" alt="The journal book"><br><sub>The journal book</sub> | <img src="docs/images/02_echoes_page.jpg" alt="Echoes page with filters"><br><sub>Echoes page with filters</sub> |
| <img src="docs/images/03_timeline_firsts.jpg" alt="Timeline of your firsts"><br><sub>Timeline of your firsts</sub> | <img src="docs/images/04_echo_toast_durotar.jpg" alt="Echo toast in Durotar"><br><sub>Echo toast in Durotar</sub> |
| <img src="docs/images/05_echo_toast_brill.jpg" alt="Echo toast in Brill"><br><sub>Echo toast in Brill</sub> | <img src="docs/images/06_world_map_echo.jpg" alt="Echoes on the world map"><br><sub>Echoes on the world map</sub> |
| <img src="docs/images/07_settings_categories.jpg" alt="Settings categories"><br><sub>Settings categories</sub> | <img src="docs/images/08_data_backups.jpg" alt="Data & Backups"><br><sub>Data & Backups</sub> |

## Install
- **Wago App:** search for Journeykeeper and choose your WoW Forever install.
- **CurseForge:** install from the CurseForge app or website (see the FAQ if the app doesn't find your Forever client).
- **Manual:** unzip the download so that **both** the `Journeykeeper` and `Journeykeeper_Vault` folders land in `World of Warcraft\_classic_beta_\Interface\AddOns`.

Then log in and type `/jkp`.

## Commands
| Command | What it does |
|---|---|
| `/jkp` or `/journeykeeper` | Open the journal |
| `/jkp config` | Settings |
| `/jkp journey` | Journey map |
| `/jkp warband` | Warband overview |
| `/jkp records` | Fights & records |
| `/jkp photo` | Photo mode |
| `/jkp friend page` | Friends & Sharing |
| `/jkp data` | Data & backups |
| `/jkp backup` | Take a backup now |
| `/jkp test` | Show a test echo |

## Community & feedback
- Discord: [discord.gg/EYEuYJxY4U](https://discord.gg/EYEuYJxY4U)
- Bugs & ideas: [GitHub Issues](https://github.com/LazyLlamaDev/Journeykeeper/issues). Please include your addon version and any Lua error (BugSack/BugGrabber help).

## FAQ
**Journeykeeper not showing in the CurseForge app?**
The CurseForge app doesn't reliably detect the WoW Forever beta client yet. Two easy options:
- Use the **Wago App** and choose your WoW Forever install.
- Or install it manually: unzip the download so that **both** the `Journeykeeper` and `Journeykeeper_Vault` folders land in `World of Warcraft\_classic_beta_\Interface\AddOns`.

**Was AI used?** Yes. Journeykeeper is my idea and design: a journal that keeps memories across your characters and years in WoW Forever. I used AI tools to help write code, text and some artwork. I test every feature in-game myself and decide what ships.

## Version history
See [CHANGELOG.md](CHANGELOG.md).

## License
All Rights Reserved (see `LICENSE`). Source is published for transparency and personal inspection. Copying, modifying, redistributing, or reuploading without written permission is not allowed. Contact: [github.com/LazyLlamaDev](https://github.com/LazyLlamaDev).
World of Warcraft® and Blizzard Entertainment® are trademarks of Blizzard Entertainment, Inc. This is an independent community addon.
