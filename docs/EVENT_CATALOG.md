# Journeykeeper event catalog

Generated from the addon's event list. Feasibility is judged against the WoW Forever beta (interface 16001, Midnight-era Mainline API): secret values (health, many combat-log fields during restricted content), protected input and missing transport APIs are treated as blocked. **Impl** = implemented in v1 registry.

**127 events**: 77 OK, 44 partial, 6 blocked; 85 implemented.

## Exploration

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `zone_first_char` | First visit to a zone by this character | ZONE_CHANGED_NEW_AREA + GetRealZoneText | OK | on | journal | yes |
| `zone_first_account` | First visit to a zone by any character (account-wide first) | ZONE_CHANGED_NEW_AREA | OK | on | toast | yes |
| `sub_first_char` | First visit to a subzone by this character | ZONE_CHANGED / ZONE_CHANGED_INDOORS + GetSubZoneText | OK | on | journal | yes |
| `sub_first_account` | First visit to a subzone on the account | ZONE_CHANGED | OK | on | toast | yes |
| `echo_revisit` | Echo when entering a place visited before by any character | zone events vs JourneykeeperDB.firstSub | OK | on | toast | yes |
| `zone_explored_pct` | Zone exploration % milestone (25/50/75/100) | C_MapExplorationInfo.GetExploredMapTextures vs map art | partial | off | chat |  |
| `explore_achievement` | Exploration achievement earned | ACHIEVEMENT_EARNED + category check | OK | on | toast |  |
| `capital_first` | First visit to a capital city | ZONE_CHANGED_NEW_AREA + map type | OK | on | toast |  |
| `highest_point` | Reached a notable vantage point (manual landmark list) | position polling vs landmark table | partial | off | chat |  |
| `sea_swim` | Swam into open sea / far from shore | IsSwimming() + subzone 'The Great Sea' | partial | off | chat |  |
| `rest_area_first` | First time resting in an inn of a town | PLAYER_UPDATE_RESTING + IsResting() | OK | off | journal | yes |

## Combat & Deaths

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `death` | Player death with zone, subzone, level, coords | PLAYER_DEAD | OK | on | journal | yes |
| `death_killer` | Killer name for a death | last hostile target / CLEU source name (secret-checked) | partial | on | journal | yes |
| `death_spot_echo` | Echo when returning to a past death spot | 5s position ticker vs deathSpots | OK | on | toast | yes |
| `death_drowning` | Death while out of breath (drowning) | MIRROR_TIMER_START 'BREATH' active at PLAYER_DEAD | OK | on | toast | yes |
| `death_falling` | Death right after falling | IsFalling() sampled in last 3 s before PLAYER_DEAD | partial | on | toast | yes |
| `death_fatigue` | Death in fatigue / deep water | MIRROR_TIMER_START 'EXHAUSTION' | OK | on | chat | yes |
| `death_streak` | Several deaths in one subzone in 10 minutes | PLAYER_DEAD timestamps | OK | on | chat | yes |
| `spirit_res` | Accepted spirit healer resurrection (res sickness) | PLAYER_UNGHOST + debuff check | partial | off | journal |  |
| `first_kill_type` | First kill of a creature type (beast, undead...) | CLEU PARTY_KILL | blocked | off | journal |  |
| `close_call` | Survived a fight at low health | needs UnitHealth -> secret value | blocked | off | off |  |
| `crit_record` | Biggest single hit dealt | No per-hit max in C_DamageMeter; CLEU amounts secret. Replaced by combat_top_spell (per-spell fight total) | blocked | off | off |  |
| `combat_record_dps` | New personal DPS record (fight) | C_DamageMeter Current session, Dps, read after PLAYER_REGEN_ENABLED if non-secret | partial | on | toast | yes |
| `combat_record_damage` | Most damage dealt in one fight | C_DamageMeter DamageDone totalAmount after combat | partial | on | journal | yes |
| `combat_longest_fight` | Longest fight | C_DamageMeter.GetSessionDurationSeconds after combat | partial | on | journal | yes |
| `combat_record_heal` | New personal HPS record | C_DamageMeter Hps after combat | partial | on | journal | yes |
| `combat_top_spell` | Strongest ability in one fight (per-spell total) | GetCombatSessionSourceFromType combatSpells after combat | partial | on | journal | yes |
| `combat_boss_stats` | Boss fight stats (damage, DPS, duration) | ENCOUNTER_END success + C_DamageMeter after combat | partial | on | journal | yes |
| `elite_kill` | Killed an elite while solo | PLAYER_TARGET_CHANGED classification + UnitIsDead | partial | off | chat |  |
| `rare_kill` | Killed a rare (rare/rareelite classification) | target classification + UnitIsDead / CLEU UNIT_DIED | partial | on | toast | yes |
| `rare_seen` | Spotted a rare creature | NAME_PLATE_UNIT_ADDED + UnitClassification | OK | off | chat | yes |

## Dungeons & Raids

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `dungeon_enter_first` | First entry into a dungeon/raid (char + account) | PLAYER_ENTERING_WORLD + GetInstanceInfo | OK | on | toast | yes |
| `boss_first_kill` | First kill of a boss encounter | ENCOUNTER_END success==1 | OK | on | toast | yes |
| `boss_wipe` | Wipe on an encounter | ENCOUNTER_END success==0 | OK | off | journal | yes |
| `instance_complete` | Instance completion | LFG_COMPLETION_REWARD / SCENARIO_COMPLETED | partial | on | toast | yes |
| `dungeon_party` | Who you ran a dungeon with | GROUP_ROSTER_UPDATE inside instance | OK | on | journal | yes |
| `dungeon_time` | Time spent in an instance | enter/leave timestamps | OK | on | journal | yes |
| `raid_first` | First raid entry | GetInstanceInfo instanceType=='raid' | OK | on | toast | yes |
| `lockout_saved` | Saved to a lockout | UPDATE_INSTANCE_INFO + GetSavedInstanceInfo | OK | off | journal |  |

## Quests & Story

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `quest_story` | Story quest text captured into the journal (Book-style dialogue) | QUEST_DETAIL/PROGRESS/COMPLETE + GetQuestText etc.; campaign/important only | OK | on | journal | yes |
| `quest_turnin` | Quest turned in | QUEST_TURNED_IN | OK | on | journal | yes |
| `quest_story` | Story / questline turn-in flagged | C_QuestLog.IsQuestCampaign / C_QuestLine.GetQuestLineInfo | partial | on | chat | yes |
| `quest_accept` | Quest accepted | QUEST_ACCEPTED | OK | off | journal | yes |
| `quest_abandon` | Quest abandoned | QUEST_REMOVED without turn-in | OK | off | journal | yes |
| `quest_count` | Quest-count milestones (10/50/100/250/500) | QUEST_TURNED_IN counter | OK | on | toast | yes |
| `quest_elite` | Group/elite quest completed | C_QuestLog.GetQuestTagInfo | partial | off | chat |  |
| `quest_chain_end` | Final quest of a chain | C_QuestLine data | partial | off | toast |  |
| `quest_dungeon` | Dungeon quest completed | GetQuestTagInfo tagID | partial | off | journal |  |

## Items & Loot

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `loot_first_green` | First uncommon item | CHAT_MSG_LOOT + item quality | OK | on | chat | yes |
| `loot_first_blue` | First rare item | CHAT_MSG_LOOT | OK | on | toast | yes |
| `loot_first_epic` | First epic item | CHAT_MSG_LOOT | OK | on | toast | yes |
| `loot_first_legendary` | First legendary item | CHAT_MSG_LOOT | OK | on | toast | yes |
| `loot_slot_quality` | First green/blue/epic per equip slot | CHAT_MSG_LOOT + equipLoc | OK | on | journal | yes |
| `loot_boe_bop` | Bind type of notable loot (BoE vs BoP) | C_Item.GetItemInfo bindType | OK | on | journal | yes |
| `loot_named` | Named / unique items (quality>=3 and unique) | GetItemInfo | partial | off | journal |  |
| `equip_upgrade` | Equipped a higher quality item in a slot | PLAYER_EQUIPMENT_CHANGED | OK | off | journal | yes |
| `bag_first` | First bag of each size | BAG_UPDATE + C_Container.GetContainerNumSlots | OK | off | chat |  |

## Mounts, Pets & Toys

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `mount_first` | First mount learned | NEW_MOUNT_ADDED | OK | on | toast | yes |
| `mount_item` | Mount item looted | CHAT_MSG_LOOT classID 15/5 | OK | on | toast | yes |
| `pet_new` | New companion pet | NEW_PET_ADDED | OK | on | chat | yes |
| `toy_new` | New toy | NEW_TOY_ADDED | OK | on | chat | yes |
| `mount_count` | Mount count milestones | C_MountJournal.GetNumMounts | OK | off | toast |  |
| `riding_skill` | Riding skill learned | LEARNED_SPELL_IN_SKILL_LINE (riding spells) | OK | on | toast |  |

## Professions

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `prof_learn` | Learned a profession | SKILL_LINES_CHANGED + GetProfessions | OK | on | chat | yes |
| `prof_milestone` | Profession skill milestones (75/150/225/300) | CHAT_MSG_SKILL | partial | on | chat | yes |
| `craft_first` | First item crafted | TRADE_SKILL / CHAT_MSG_LOOT 'You create' | partial | off | journal |  |
| `fish_first` | First fish caught | CHAT_MSG_LOOT while fishing | partial | off | chat |  |
| `recipe_learn` | Recipe learned | NEW_RECIPE_LEARNED | OK | off | journal | yes |
| `camp_first` | First camp made (Forever camping) | unknown Forever API | blocked | off | off |  |

## Economy & Gold

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `gold_threshold` | Purse thresholds 1/10/100/500/1000/5000/10000 g | PLAYER_MONEY + GetMoney | OK | on | chat | yes |
| `vendor_first` | First item sold to a vendor | MERCHANT_SHOW + PLAYER_MONEY delta | partial | off | journal |  |
| `ah_first_sale` | First auction sold | CHAT_MSG_SYSTEM ERR_AUCTION_SOLD_S | OK | off | chat | yes |
| `repair_bill` | Biggest repair bill | MERCHANT + money delta | partial | off | off |  |
| `mail_gold` | Gold received by mail | MAIL_INBOX_UPDATE | partial | off | off |  |

## Social & Allies

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `friend_milestone` | A trusted friend shared a milestone (opt-in addon messages) | CHAT_MSG_ADDON prefix JKPR from trusted sender | OK | on | toast | yes |
| `shared_echo` | You and a friend share the same memory (same boss/rare/dungeon, same day) | incoming milestone matched to own entries | OK | on | toast | yes |
| `group_join` | Grouped with a player (name-realm, GUID, class, where, duration) | GROUP_ROSTER_UPDATE | OK | on | tooltip | yes |
| `group_echo` | Echo when grouping with / hovering a known player | GROUP_ROSTER_UPDATE / UPDATE_MOUSEOVER_UNIT | OK | on | tooltip | yes |
| `ally_note` | Personal note on an ally | /jkp allynote | OK | on | journal | yes |
| `quick_note` | Quick note written into the journal (zone, time, character) | /jkp note, /note, minimap Shift-click, key binding | OK | on | journal | yes |
| `fellow_first` | Fellowship: met a new fellow traveller in a group | GROUP_ROSTER_UPDATE (name, realm, class only) | OK | on | journal | yes |
| `fellow_echo` | Fellowship: grouped again with someone you ran a dungeon or killed a boss with | GROUP_ROSTER_UPDATE vs fellowship runs/kills | OK | on | toast | yes |
| `fellow_reunion` | Fellowship: reunion after days apart, with what happened since (and a trusted friend's shared milestones) | GROUP_ROSTER_UPDATE + gap >= reunionDays; optional JKPR RS/RR exchange with trusted friends | OK | on | toast | yes |
| `guild_join` | Joined a guild | PLAYER_GUILD_UPDATE + GetGuildInfo | OK | on | toast | yes |
| `friend_add` | Added a friend | FRIENDLIST_UPDATE diff | partial | off | journal |  |
| `trade_first` | First trade with a player | TRADE_CLOSED + name | partial | off | journal |  |
| `whisper_first` | First whisper exchange | CHAT_MSG_WHISPER (may be secret) | partial | off | off |  |
| `duel` | Duel fought | DUEL_REQUESTED / DUEL_FINISHED (no winner info) | partial | off | journal | yes |

## Travel

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `flight_learn` | New flight path discovered | UI_INFO_MESSAGE ERR_NEWTAXIPATH | OK | on | toast | yes |
| `flight_first` | First flight taken | PLAYER_CONTROL_LOST + UnitOnTaxi | OK | on | chat | yes |
| `hearth_bind` | Hearthstone bound to a new inn | HEARTHSTONE_BOUND + GetBindLocation | OK | on | chat | yes |
| `boat_zeppelin` | First boat/zeppelin ride | transport detection (UnitInVehicle false; no API) | blocked | off | off |  |
| `portal_use` | Used a portal / mage teleport | zone change while not on taxi in <2s | partial | off | off |  |
| `distance` | Distance travelled per session | position ticker deltas | partial | off | journal |  |

## Character Progression

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `level_up` | Level up | PLAYER_LEVEL_UP | OK | on | journal | yes |
| `level_milestone` | Level milestones (5,10,20..60) with account comparison | PLAYER_LEVEL_UP | OK | on | toast | yes |
| `spell_learn` | New spell learned | LEARNED_SPELL_IN_SKILL_LINE / LEARNED_SPELL_IN_TAB | OK | off | journal | yes |
| `talent_first` | First talent point / spec choice | PLAYER_TALENT_UPDATE / TRAIT_CONFIG_UPDATED | partial | on | chat | yes |
| `rep_tier` | Reputation tier reached (Friendly..Exalted) | CHAT_MSG_COMBAT_FACTION_CHANGE / UPDATE_FACTION | partial | on | toast | yes |
| `played_time` | Played-time milestones | TIME_PLAYED_MSG (needs /played) | partial | off | off |  |
| `title_earned` | New title | KNOWN_TITLES_UPDATE | OK | off | chat |  |

## Achievements

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `achievement` | Achievement earned | ACHIEVEMENT_EARNED | OK | on | chat | yes |
| `achieve_points` | Achievement point milestones | GetTotalAchievementPoints | OK | off | chat |  |
| `feat` | Feat of Strength | ACHIEVEMENT_EARNED + flags | OK | on | toast |  |

## PvP & World Events

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `pvp_kill` | Honorable kill | PLAYER_PVP_KILLS_CHANGED | partial | off | journal | yes |
| `bg_first` | First battleground entered | PLAYER_ENTERING_WORLD instanceType=='pvp' | OK | on | toast | yes |
| `bg_result` | Battleground win/loss | UPDATE_BATTLEFIELD_STATUS / GetBattlefieldWinner | partial | off | journal |  |
| `world_event` | World event participation | scenario / area POI events | partial | off | off |  |
| `warmode` | War mode toggled | PLAYER_FLAGS_CHANGED | OK | off | off |  |

## Holidays

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `holiday_login` | Logged in during a holiday | C_Calendar.GetHolidayInfo / GetDayEvent | partial | on | chat |  |
| `holiday_boss` | Holiday boss killed | ENCOUNTER_END in holiday dungeon | partial | off | journal |  |
| `birthday` | Character birthday (anniversary of first login) | PLAYER_LOGIN vs created date | OK | on | toast | yes |

## Weird & Fun Moments

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `photo_taken` | Photo mode screenshot linked to a memory | Screenshot() + SCREENSHOT_SUCCEEDED, out of combat | OK | on | journal | yes |
| `auto_screenshot` | Automatic screenshot taken at a big moment (file name linked to the memory) | Screenshot() a moment after boss/dungeon firsts, level milestones, reunions (achievements optional) + SCREENSHOT_SUCCEEDED/FAILED | OK | on | journal | yes |
| `fun_fall` | Survived a long fall | IsFalling duration >3 s, then not dead | OK | on | chat | yes |
| `fun_afk_place` | Went AFK in a notable place | PLAYER_FLAGS_CHANGED UnitIsAFK + subzone | OK | on | journal | yes |
| `fun_drown_close` | Ran out of breath but survived | MIRROR_TIMER_STOP BREATH without death | partial | off | chat |  |
| `fun_dance` | Danced (emote /dance) | CHAT_MSG_TEXT_EMOTE from self | partial | off | off |  |
| `fun_midnight` | Playing at midnight local time | clock check | OK | on | chat | yes |
| `fun_long_session` | Very long session (4h+) | session timer | OK | on | chat | yes |
| `fun_jump` | Jump counter | no jump event (JumpOrAscendStart is protected input) | blocked | off | off |  |

## Warband Resonance

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `warband_echo` | Cross-character echo naming the other character, class and level | zone events vs account firsts by another character | OK | on | toast | yes |
| `family_first_rare` | Warband first: first time any character killed a given rare | rare_kill + JourneykeeperDB.family | partial | on | toast | yes |
| `family_first_boss` | Warband first: first kill of a boss by any character | ENCOUNTER_END success + family table | OK | on | toast | yes |
| `family_first_clear` | Warband first: first completion of an instance by any character | LFG_COMPLETION_REWARD / SCENARIO_COMPLETED + family table | partial | on | toast | yes |
| `ghost_trail` | Footprints of your other characters sampled onto the world map | C_Map position sampling ticker (outside instances) | OK | off | journal | yes |

## Threads & Arcs

| id | Description | Trigger | Feasibility | Default | Channel | Impl |
|---|---|---|---|---|---|---|
| `thread_return` | Chain: you came back again to where you first fell (2nd, 3rd... return) | death-spot proximity ticker + return counter | OK | on | toast | yes |
| `thread_zone_return` | Chain: you came back to your character's first zone after leveling 10+ | ZONE_CHANGED_NEW_AREA + level delta | OK | on | toast | yes |
| `arc_add` | Moment added to a player-created arc | /jkp arc, toast menu, journal menu | OK | on | journal | yes |
| `digest_login` | 'Since you were last here' digest at login | PLAYER_ENTERING_WORLD(isLogin) + last logout time | OK | on | journal | yes |
| `ally_rating` | Your private rating of a group (Great run / Forgettable / Avoid) | group disband prompt | OK | on | journal | yes |
| `moment_pinned` | You pinned a moment as an anchor | /jkp pin, toast menu, journal menu | OK | on | journal | yes |
