local addonName, ns = ...

-- Missing keys fall back to the key itself, so an untranslated string is visible
-- rather than an error.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- enUS (default). Other locales are added in HH-064.
L.LOADED = "v%s loaded. |cffffff00/hh help|r for commands."
L.FOREVER_SAVED_VARS = "|cffff8800WoW Forever is in testing mode:|r this client does not load saved data back (a known client issue), so your lists and settings reset on every reload. Catch-up refills them from other HeadHunters when you log in."
L.FOREVER_SAVED_VARS_SHORT = "Forever testing mode: saved data resets on reload (client issue)"
L.UNSUPPORTED_CLIENT = "This client (interface %s) is not supported. HeadHunter runs on Classic Era and WoW Forever only."

L.HELP_HEADER = "|cffc41e3a========== HeadHunter ==========|r"
L.HELP_STATUS = "|cffffff00/hh status|r: Client, flags and database summary"
L.HELP_DEBUG = "|cffffff00/hh debug [on|off]|r: Toggle debug mode (echo debug lines to chat). |cffffff00/hh debug tours on|off|r: Tournaments tab (under development)"
L.HELP_LOG = "|cffffff00/hh log [clear]|r: Show the debug log window"
L.HELP_PROBE = "|cffffff00/hh probe [watch|witness]|r: Report which WoW APIs this client offers; 'watch' logs live combat/death signals, 'witness' logs other players dying near you"
L.HELP_SIM = "|cffffff00/hh sim death|sighting|send|demo ...|r: Inject simulated data; 'send' shares it with other characters (debug); 'demo' fills every tab for screenshots"

L.UNKNOWN_COMMAND = "Unknown command '%s'. Type /hh help."
L.DEBUG_ON = "Debug mode on."
L.DEBUG_OFF = "Debug mode off."
L.LOG_CLEARED = "Debug log cleared."

L.STATUS_CLIENT = "Client: %s (interface %d)"
L.STATUS_FEATURES = "CLEU: %s · SavedVariables reliable: %s · Secret values: %s"
L.STATUS_DB = "Database: schema %d · loaded from disk: %s · loads: %d · deaths: %d · enemies: %d"
L.STATUS_SUSPENDED = "Suspended (instance: %s)"
L.STATUS_ACTIVE = "Active (open world)"

L.PROBE_DONE = "Probe written to the debug log (/hh log)."
L.PROBE_WATCH_ON = "Probe watch on: combat and death signals are logged."
L.PROBE_WATCH_OFF = "Probe watch off."
L.PROBE_WITNESS_ON = "Probe witness on: deaths of other players near you are logged (/hh log)."
L.PROBE_WITNESS_OFF = "Probe witness off."

L.HELP_ENEMIES = "|cffffff00/hh enemies|r: Enemy players seen recently"
L.HELP_DEATHS = "|cffffff00/hh deaths [n]|r: Your recent PvP deaths"
L.ENEMIES_HEADER = "Enemies seen: %d (newest first)"
L.DEATHS_HEADER = "PvP deaths recorded: %d (newest first)"
L.DEATH_RECORDED = "Killed by |cffff4040%s|r (%s) · %s"
L.KILL_COWARD = "|cffff8000Bully kill|r"
L.KILL_FAIR = "|cff40ff40Fair fight|r"
L.KILL_GIANT = "|cff40c0ffUnderdog win|r"
L.KILL_NORMAL = "Outleveled"
L.KILL_UNKNOWN = "level unknown"
L.KILL_DUO = "|cffcc66ffDuo|r (%d vs 1)"
L.KILL_GANG = "|cffcc66ffGang|r (%d vs 1)"
L.KILL_GROUP = "|cffcc66ffGroup fight|r (%d vs %d)"

L.SYNC_PING_QUEUED = "Sync ping queued (sent within ~3 s). Other HeadHunter users will print it."
L.SYNC_PING_RECEIVED = "Sync ping from %s [%s] (%s) via %s"
L.SYNC_WHISPER_QUEUED = "Addon whisper ping queued for %s. If it arrives, they print \"Sync ping from ...\"."
L.SYNC_WHISPER_USAGE = "Usage: /hh sync whisper \"<name>\""
L.SYNC_PROBE_LINE = "Addon messages via %s: %s · result %s"
L.SYNC_CHAT_SENT = "Channel text test sent. Other HeadHunter users in the channel should print it."
L.SYNC_CHAT_FAILED = "Channel text test failed: %s"
L.SYNC_CHAT_NO_CHANNEL = "Not in the HeadHunter channel yet."
L.SYNC_CHAT_RECEIVED = "Channel text from %s: %s"
L.HELP_SYNC = "|cffffff00/hh sync [ping|probe|chat|whisper <name>]|r: Sync counters; 'ping' test message; 'probe' test every chat type; 'chat' test channel text; 'whisper' test an addon whisper"
L.SYNC_STATUS = "Sync: channel %s · queued %d · sent %d msg / %d records · received %d · dropped %d · failed %d"
L.SYNC_DIAG = "Sync diag: faction %s · auto routes %s · flush blocked: %s · last send: %s · last sender: %s · last ignored: %s"
L.HELP_REPORT = "|cffffff00/hh report|r: Send your waiting death reports to all HeadHunters (Classic Era)"
L.REPORT_PROMPT = "HeadHunter\n\nReport |cffff4040%s|r (%s) to all HeadHunters?"
L.REPORT_MORE = "(+%d more waiting)"
L.REPORT_BUTTON = "Report"
L.REPORT_SKIP = "Skip"
L.REPORT_SENT = "Reported %d death(s) to all HeadHunters."
L.REPORT_FAILED = "Could not reach the HeadHunter channel. Try /hh report again."
L.REPORT_NOTHING = "No death reports waiting."
L.SYNC_REJECTED = "Last rejected report: %s"
L.HELP_REPORTS = "|cffffff00/hh reports|r: Shared death reports (yours and other players')"
L.REPORTS_HEADER = "Shared reports: %d (%d yours, %d from other players)"

-- Rules (M3)
L.RANK_GANKER = "|cffffd100Ganker|r"
L.RANK_OUTLAW = "|cffff9933Outlaw|r"
L.RANK_DESPERADO = "|cffff6600Desperado|r"
L.RANK_MOSTWANTED = "|cffff3333Most Wanted|r"
L.RANK_DEADORALIVE = "|cffcc0000Dead or Alive|r"
L.RANK_NONE = "-"
L.NOT_WANTED = "not wanted"
L.BADGE_COWARD = "|cffff8000Bully|r"
L.BADGE_GANG = "|cffcc66ffGang|r"
L.BADGE_DUO = "|cffcc66ffDuo|r"
L.BADGE_SERIALKILLER = "|cffff3333Serial Killer|r"
L.BADGE_GUNSLINGER = "|cff40ff40Gunslinger|r"
L.BADGE_GIANTSLAYER = "|cff40c0ffUnderdog|r"
L.HELP_WANTED = "|cffffff00/hh wanted|r: Current WANTED list"
L.WANTED_HEADER = "WANTED: %d"
L.WANTED_LINE = "  %s  |cffff4040%s|r  %d kills  last kill %s%s"
L.WANTED_TEST_THRESHOLD = "|cffff8000(test threshold: WANTED from %d kills; /hh debug wanted off to restore 4)|r"
L.DEBUG_WANTED_ON = "Test threshold: WANTED from %d kills in 20 min."
L.DEBUG_WANTED_OFF = "Test threshold off: WANTED from 4 kills in 20 min."
L.DEBUG_WANTED_USAGE = "/hh debug wanted <1-10|off>"
L.HELP_OUTLAW = "|cffffff00/hh outlaw <name>|r: Poster details of one enemy"
L.OUTLAW_USAGE = "/hh outlaw <name>   (Forever names: /hh outlaw Grim Reaper)"
L.OUTLAW_UNKNOWN = "No kills known for %s."
L.OUTLAW_LINE1 = "|cffff4040%s|r · %s · until caught (ends after %s more without a kill)"
L.OUTLAW_LINE2 = "Kills known: %d (exact %d, guessed %d = half weight) · times WANTED: %d · caught: %d · peak rank: %s · %s"
L.OUTLAW_LINE3 = "Last kill: %s, %s in %s"
L.HELP_SPREE = "|cffffff00/hh spree \"<name>\" <kills> [secondsApart] [killerLevel] [victimLevel]|r: Simulate a killing spree (local only)"
L.SPREE_USAGE = "/hh spree \"<name>\" <kills 1-60> [secondsApart=120] [killerLevel=60] [victimLevel=40]"
L.SPREE_DONE = "Simulated %d kills by %s (local only, never sent)."

-- Alerts (M4)
L.HELP_ALERTS = "|cffffff00/hh alerts [on|off|sound on|off|range adjacent|continent|whisper on|off|test]|r: Alert settings"
L.ALERTS_STATUS = "Alerts: %s · sound: %s · range: %s · invite whisper: %s"
L.ALERT_TEST_TEXT = "|cffc41e3aHeadHunter|r alert test"
L.ALERT_QUEUED = "In combat: the alert will show when combat ends."
L.SIGHTING_TEXT = "|cffff2020WANTED|r · %s |cffff4040%s|r is here!"
L.SIGHTING_AT_LARGE = "|cffff2020WANTED|r · At large: |cffff4040%s|r is here!"
L.SIGHTING_CHAT = "|cffff2020WANTED|r %s |cffff4040%s|r spotted (%s) · %d kills"
L.SIGHTING_CHAT_AT_LARGE = "|cffff2020WANTED|r |cffff8040At large|r |cffff4040%s|r spotted (%s) · was %s · %d kills known"
L.AT_LARGE = "|cffff8040At large|r"
L.ACTIVITY_HEADLINE = "|cffff2020WANTED|r · %s |cffff4040%s|r (%s) killed %s in %s, %s"
L.ACTIVITY_DETAILS = "%d kills · WANTED until caught"
L.ACTIVITY_CENTER = "|cffff2020WANTED|r · %s |cffff4040%s|r is killing in %s"
L.JUST_NOW = "just now"
L.MINUTES_AGO = "%d min ago"
L.HOURS_AGO = "%d h %d min ago"
L.DAYS_AGO = "%d d %d h ago"
L.UNKNOWN_ZONE = "an unknown zone"
L.POSSE_JOIN = "Join the posse"
L.POSSE_DECLINE = "Decline"
L.POSSE_JOINED_PIN = "You joined the posse against %s. Waypoint set in %s."
L.POSSE_JOINED_COORDS = "You joined the posse against %s. Last seen in %s at %.1f, %.1f."
L.POSSE_JOINED = "You joined the posse against %s. Last seen in %s."
L.LAYER_SAME = "|cff40ff40Same layer as you|r"
L.LAYER_DIFFERENT = "|cffff8000Different layer|r (you %d, kill on %d): ask for a group invite"
L.LAYER_TAG = "layer %d"
L.LAYER_CURRENT = "Your layer: %d (read %d s ago)"
L.LAYER_UNKNOWN = "Layer unknown: target or mouse over an NPC."
L.HELP_LAYER = "|cffffff00/hh layer|r: Your current layer (from nearby NPCs)"
L.POSSE_WHISPER = "HeadHunter: joining the posse against %s. Please invite me so I can switch to your layer."
L.POSSE_WHISPERED = "Asked %s for a group invite to switch layers."
L.HOTSPOT_LEVEL_1 = "Skirmish"
L.HOTSPOT_LEVEL_2 = "Battle"
L.HOTSPOT_LEVEL_3 = "Warzone"
L.HOTSPOT_LINE = "%s |cffff3300PvP|r |cffff9933%s|r in %s: %s"
L.HOTSPOT_BOTH = "≈%d %s fighting %d %s"
L.HOTSPOT_ENEMIES = "≈%d %s seen fighting"
L.HOTSPOT_OURS = "%d %s fighting"
L.HOTSPOT_DEATHS = "%d death(s) in 5 min"
L.HOTSPOT_CENTER = "%s |cffff3300PvP %s|r in %s!"
L.HOTSPOT_HELP = "Help"
L.HOTSPOT_IGNORE = "Ignore"
L.HOTSPOT_WAYPOINT = "Waypoint set to the fight in %s."
L.HOTSPOT_NAMES = " · Enemies: %s"
L.HOTSPOT_FIGHTING = " · Fighting: %s"
L.HOTSPOT_HELP_COMING = "|cff00ff00Help on the way:|r %s is coming to the fight in %s."
L.HOTSPOT_WHISPER = "HeadHunter: coming to help in the fight in %s. Please invite me so I can switch to your layer."
L.HOTSPOT_STATUS = "%s %s: heat %d (HeadHunters %d, enemies %d, deaths %d)"
L.HOTSPOT_NONE = "No PvP activity known in the last 5 minutes."
L.HELP_HOTSPOTS = "|cffffff00/hh hotspots|r: PvP activity per zone (last 5 min)"
L.ENEMIES = "enemies"
L.HEADHUNTERS = "HeadHunters"
L.POSSE_UPDATE_CENTER = "Posse: |cffff4040%s|r struck again in %s"
L.POSSE_SUMMARY = "Posse: %s"
L.POSSE_YOU = "you"
L.POSSE_MEMBER_JOINED = "%s joined the posse against |cffff4040%s|r."
L.POSSE_NONE = "No active posses."
L.HELP_POSSE = "|cffffff00/hh posse|r: Who is hunting which outlaw"

L.SIM_USAGE_DEATH = "/hh sim death \"<name>\" <level|skull> <CLASS> <RACE> [sex 2|3]"
L.SIM_USAGE_SIGHTING = "/hh sim sighting \"<name>\" <level|skull> <CLASS> <RACE> [sex 2|3]"
L.SIM_SEND_USAGE = "/hh sim send \"<killer>\" [kills 1-10] [level|skull] [CLASS] [RACE] [\"Zone\"] (WoW Forever names have two words, e.g. \"Grim Reaper\")"
L.SIM_SEND_NEEDS_DEBUG = "/hh sim send is a debug tool: turn on /hh debug on first."
L.SIM_SENT = "Sent %d simulated death(s) by %s in %s to other HeadHunters (test)."
L.SIM_BAD_NAME = "Invalid name for this client: %s"
L.SIM_DEATH = "Simulated death by %s (%s)."
L.SIM_SIGHTING = "Simulated sighting of %s (%s)."
L.SIM_USAGE_DEMO = "/hh sim demo [clear]: fill every tab with made-up data for screenshots, or take it out again"
L.SIM_USAGE_CLEAR = "/hh sim clear: remove every simulated death (sim send, spree, sim death) and test catch from this character"
L.SIM_CLEARED = "Test data removed: %d simulated report(s), %d of your simulated death(s), %d test catch(es). Clear the other test characters too."
L.DEMO_DONE = "Demo data added: %d kills, %d duels, %d bounty events. Nothing was sent. |cffffff00/hh sim demo clear|r takes it out."
L.DEMO_CLEARED = "Demo data removed (%d records). Your bounty is back as it was."
L.DEMO_ERA_ONLY = "The demo uses Classic Era names (Name-Realm), so it only runs on Classic Era."

-- Map markers (HH-046)
L.MAP_HOTSPOT_TITLE = "|cffff3300PvP zone|r · |cffff9933%s|r in %s"
L.MAP_PVP = "PVP"
L.MAP_WANTED_TITLE = "|cffff2020WANTED|r · |cffff4040%s|r"
L.MAP_WANTED_STATUS = "%s · %d kills · until caught"
L.MAP_WANTED_LAST_KILL = "Last kill %s in %s"
L.MAP_STATUS = "Map pins: %s · %d pin(s) for your zone"
L.HELP_MAP = "|cffffff00/hh map [on|off]|r: Hotspot and WANTED pins on the world map"
L.ON = "on"
L.OFF = "off"

-- Guiding to a place: the game's waypoint, or the coordinates where the client has none (Era)
L.GUIDE_COORDS = "%s at %.1f, %.1f."
L.GUIDE_UNKNOWN = "%s: position unknown."
L.GUIDE_HOTSPOT = "PvP %s in %s"
L.GUIDE_WANTED = "%s's last kill"

-- Justice served (HH-048)
L.JUSTICE_LINE = "|cff40ff40Justice served!|r %s |cffff4040%s|r (%d kills) was brought down by %s in %s."
L.JUSTICE_CENTER = "|cff40ff40Justice served!|r You brought down |cffff4040%s|r"
L.JUSTICE_CENTER_POSSE = "|cff40ff40Justice served!|r |cffff4040%s|r brought down by %s"
L.JUSTICE_ANNOUNCE_QUESTION = "Announce it to all HeadHunters?"
L.JUSTICE_ANNOUNCE = "Announce"
L.JUSTICE_ANNOUNCED = "Announced to all HeadHunters."
L.JUSTICE_NOTHING = "No catch waiting to be announced."
L.HELP_JUSTICE = "|cffffff00/hh justice|r: Announce your catch of a WANTED outlaw to all HeadHunters (Classic Era)"
L.CATCH_NOT_WANTED = "%s is not WANTED right now (or was caught less than a minute ago)."
L.CATCH_NEEDS_DEBUG = "/hh catch is a debug tool: turn on /hh debug on first."

-- Login catch-up (HH-023)
L.CATCHUP_STARTED = "Asking other HeadHunters for what you missed."
L.CATCHUP_BUSY = "Catch-up already running."
L.CATCHUP_NO_ROUTE = "No HeadHunters reachable right now (Classic Era: join a guild or group)."
L.HELP_CATCHUP = "|cffffff00/hh catchup|r: Ask other HeadHunters for reports and catches you missed"
L.CATCHUP_PROMPT = "HeadHunter\n\nYou were last online %s.\nAsk all HeadHunters what you missed?"
L.CATCHUP_PROMPT_NEW = "HeadHunter\n\nAsk all HeadHunters for the current WANTED list?"
L.CATCHUP_BUTTON = "Catch up"

-- Main window (HH-060)
L.WINDOW_TITLE = "HeadHunter"
L.WINDOW_COUNT = "%d shown"
L.WINDOW_SITE_DATA = " · with the website list from %s"
L.SELF_WANTED_CENTER = "You are WANTED!"
L.SELF_WANTED = "|cffff4040You are WANTED|r by the %s: %s, %d kills (website list from %s). HeadHunters of the other faction will hunt you."
L.WINDOW_ROW_HINT = "|cff00ff00Click: open the poster|r"
L.WINDOW_ROW_WHISPER = "|cff00ff00Click: whisper|r"
L.TIP_WANTED = "|cffff2020WANTED|r · %s · %d kills"
L.TIP_NOT_WANTED = "|cffaaaaaaNot WANTED|r"
L.TIP_BOUNTY_ONLY = "|cffffd100BOUNTY|r · %s from players (not WANTED)"
L.TIP_AT_LARGE = "|cffff8040At large|r: was %s, never caught"
L.TIP_LAST_KILL = "Last kill %s in %s"
L.TIP_HISTORY = "|cffaaaaaaKills known: %d · WANTED %dx · caught %dx|r"
L.TIP_KILLED_YOU = "Killed you %s in %s (%s)"
L.TAB_WANTED = "WANTED"
L.TAB_SHAME = "Hall of Shame"
L.TAB_DEATHS = "My deaths"
L.COL_RANK = "Rank"
L.COL_NAME = "Name"
L.COL_KILLS = "Kills"
L.COL_LAST_KILL = "Last kill"
L.COL_BADGES = "Badges"
L.COL_WHO = "Level, race, class"
L.COL_COWARD_KILLS = "Bully kills"
L.COL_STATUS = "Status"
L.COL_WHEN = "When"
L.COL_KILLER = "Killer"
L.COL_KIND = "Kill"
L.COL_ZONE = "Zone"
L.SHAME_WANTED = "|cffff2020WANTED|r · %s"
L.SHAME_PAST = "WANTED %dx · caught %dx"
L.EMPTY_WANTED = "Nobody is WANTED right now."
L.EMPTY_SHAME = "No bullies known yet."
L.SHAME_UNPAID_WHO = "|cffff4040Deadbeat|r · did not pay a bounty"
L.SHAME_UNPAID = "%d unpaid · no bounties for %d day(s)"
L.SHAME_UNPAID_TIP = "|cffff4040Deadbeat|r: hunters brought down their bounty targets and never got the gold. They cannot post bounties while blocked."
L.EMPTY_DEATHS = "No PvP deaths recorded."
L.HELP_SHOW = "|cffffff00/hh|r: Open the HeadHunter window (/hh help: all commands)"
L.MINIMAP_HINT = "Left-click: open · Drag: move"
L.MINIMAP_HIDDEN = "Minimap button hidden (/hh minimap to show it again)."
L.MINIMAP_SHOWN = "Minimap button shown."
L.HELP_MINIMAP = "|cffffff00/hh minimap|r: Show or hide the minimap button"

-- Tooltip line (HH-062)
L.TOOLTIP_WANTED = "|cffff2020WANTED|r · %s · %d kills"
L.TOOLTIP_KNOWN = "HeadHunter: %d kills known"
L.TOOLTIP_AT_LARGE = "|cffff8040At large|r · was %s · %d kills known"
L.TOOLTIP_CAUGHT = " · caught %dx"
L.TOOLTIP_ON = "WANTED line on enemy tooltips: on."
L.TOOLTIP_OFF = "WANTED line on enemy tooltips: off."
L.HELP_TOOLTIP = "|cffffff00/hh tooltip [on|off]|r: WANTED line on enemy player tooltips"

-- Poster (HH-061)
L.POSTER_HEADER = "Poster"
L.POSTER_HISTORY = "Kills known: %d (exact %d, guessed %d) · WANTED %dx · caught %dx · peak rank %s"
L.POSTER_RECENT = "Recent kills"
L.POSTER_KILL = "%s · %s · %s · %s"
L.POSTER_NO_KILLS = "No kills known."

-- Settings page (HH-063)
L.OPTIONS_BUTTON = "Options"
L.HELP_OPTIONS = "|cffffff00/hh options|r: Open the HeadHunter options page"
L.SET_UNAVAILABLE = "The options page is not available on this client; use /hh help for the commands."
L.SET_HINT = "Changes apply at once. The same settings are also /hh commands (/hh help)."
L.SET_SECTION_ALERTS = "Alerts"
L.SET_SECTION_DISPLAY = "Display"
L.SET_SECTION_RULES = "Rules"
L.SET_ALERTS = "Alerts"
L.SET_ALERTS_TIP = "WANTED sightings, WANTED activity, hotspots and Justice served messages."
L.SET_SOUND = "Alert sound"
L.SET_SOUND_TIP = "Play a sound with alerts."
L.SET_POPUPS = "Popups"
L.SET_POPUPS_TIP = "Join the posse / Help popups. Off: chat lines and center text only."
L.SET_RANGE = "Alert range"
L.SET_RANGE_TIP = "Neighbouring zones: your zone and the zones bordering it. Whole continent: farther alerts too."
L.SET_CHOICE_ADJACENT = "Neighbouring zones"
L.SET_CHOICE_CONTINENT = "Whole continent"
L.SET_WHISPER = "Ask for an invite on another layer"
L.SET_WHISPER_TIP = "When you join a posse and the kill was on another layer, whisper the victim for a group invite."
L.SET_MAP = "PvP areas and WANTED skulls on the map"
L.SET_MAP_TIP = "Red PvP areas for hotspots, skulls for WANTED outlaws (10 min after their last kill)."
L.SET_TOOLTIP = "WANTED line on enemy tooltips"
L.SET_TOOLTIP_TIP = "Adds the WANTED status (or what is known) to enemy player tooltips."
L.SET_MINIMAP = "Minimap button"
L.SET_MINIMAP_TIP = "Click it to open the HeadHunter window; drag it to move it."
L.SET_SERIAL = "Serial Killer window"
L.SET_SERIAL_TIP = "The Serial Killer badge needs 5 different victims in separate fights within this time."
L.SET_MINUTES = "%d min"

-- Bounty, "Marks" in the code (HH-050)
L.HUNTER_RANK_TRACKER = "Tracker"
L.HUNTER_RANK_BOUNTYHUNTER = "Bounty Hunter"
L.HUNTER_RANK_MANHUNTER = "Manhunter"
L.HUNTER_RANK_HEADHUNTER = "Headhunter"
L.HUNTER_RANK_REAPER = "Reaper"
L.MARKS_LINE = "%s|r bounty: %s (total %d)"
L.MARKS_REASON_JOIN = "joined the posse against %s"
L.MARKS_REASON_CATCH = "brought down %s"
L.MARKS_REASON_DECLINE = "declined the posse against %s"
L.MARKS_REASON_SKIP = "No bounty: %s is 10+ levels below you (hunting down is ganking too)"
L.MARKS_RANK_UP = "|cffffd100You are now a %s!|r"
L.MARKS_STATUS = "HeadHunter rank: |cffffd100%s|r · bounty %d"
L.MARKS_NEXT = "%d more for %s"
L.HELP_MARKS = "|cffffff00/hh bounty|r: Your HeadHunter rank and recent bounty"
L.TAB_MARKS = "My bounty"
L.COL_CHANGE = "Bounty"
L.COL_REASON = "Why"
L.COL_TOTAL = "Total"
L.EMPTY_MARKS = "No bounty yet: join posses and bring WANTED outlaws down."

-- Level window (HH-047)
L.ACTIVITY_NOT_YOUR_LEVEL = "|cffaaaaaanot your level range: no popup|r"
L.DEBUG_LEVELS_OFF = "Test mode: level window OFF (every level gets WANTED popups). /hh debug levels on to restore it."
L.DEBUG_DUELS = "Duels: Greenhorn below %d duel(s). /hh debug duels off to restore 5."
L.DEBUG_DUELS_USAGE = "Usage: /hh debug duels <1-5|off>"
L.DEBUG_LEVELS_ON = "Level window on: WANTED popups only from the outlaw's level -5 to +9."
L.DEBUG_TOURS_ON = "Tournaments tab shown (under development). /hh debug tours off to hide it."
L.DEBUG_TOURS_OFF = "Tournaments tab hidden (under development). /hh debug tours on to show it."

-- Duels, "High Noon" in the code (HH-090..093)
L.DUEL_RANK_GREENHORN = "Greenhorn"
L.DUEL_RANK_QUICKDRAW = "Quickdraw"
L.DUEL_RANK_SHARPSHOOTER = "Sharpshooter"
L.DUEL_RANK_DEADEYE = "Deadeye"
L.DUEL_RANK_LEGEND = "Legend"
L.DUEL_RANK_TOPGUN = "Top Gun"
L.FACTION_BUTTON = "%s list"
L.DUEL_TITLE = "%s #%d (%s)"
L.DUEL_TITLE_TOPGUN = "|cffff8000Top Gun|r (%s)"
L.DUEL_TITLE_GREENHORN = "%s (%d duels)"
L.DUEL_TOOLTIP = "|cffffd100Duels:|r %s"
L.DUELS_HEADER = "Duels, %s: %d duelists"
L.DUELS_YOU = "You: %s · %d wins, %d losses"
L.HELP_DUELS = "|cffffff00/hh duels|r: Duels, the best duelists of your faction"
L.HELP_ONLINE = "|cffffff00/hh online|r: HeadHunters online now, per faction, and their addon versions"
L.ONLINE_REGION = "HeadHunters online: %d (Alliance %d, Horde %d), you included"
L.ONLINE_GROUP = "HeadHunters online in your guild and group: %d, you included (Classic Era cannot count further)"
L.ONLINE_VERSIONS = "Addon versions: %s"
L.ONLINE_SHORT = "%d online"
L.ONLINE_SHORT_GROUP = "%d online in guild/group"
L.ONLINE_SHORT_CAPPED = "%d+ online"
L.ONLINE_CAPPED = "More than %d HeadHunters online. The count is off on such a busy region, to save traffic."

-- Gurubashi Tournament (M9)
L.HELP_ARENA = "|cffffff00/hh arena|r: Are you at a tournament venue (Gurubashi Arena, the capital gates)? Shows your position"
L.ARENA_WHERE = "%s at %s: %s"
L.ARENA_IN_PIT = "|cff40ff40in the arena pit|r"
L.ARENA_IN_ARENA = "|cff40ff40in Gurubashi Arena|r (stands)"
L.ARENA_OUTSIDE = "|cffff8000not at a tournament venue|r"
L.VENUE_AT = "|cff40ff40at %s|r"
L.VENUE_GURUBASHI = "Gurubashi Arena (Stranglethorn Vale)"
L.VENUE_ORGRIMMAR = "the Orgrimmar gate (Durotar)"
L.VENUE_UNDERCITY = "the Undercity ruins (Tirisfal Glades)"
L.VENUE_IRONFORGE = "the Ironforge gate (Dun Morogh)"
L.VENUE_STORMWIND = "the Stormwind gate (Elwynn Forest)"
L.HELP_TOUR = "|cffffff00/hh tour [list|create|join <n>|leave <n>|here|cancel]|r: Gurubashi Tournaments"
L.TOUR_CREATE_USAGE = "Usage: /hh tour create \"Name\" <1v1|2v2|3v3|5v5> <single|robin> <bo1|bo3|bo5> <minutes to start> [min level] [max teams]"
L.TOUR_HEADER = "Gurubashi Tournaments: %d"
L.TOUR_LINE = "  #%d  |cffffd100%s|r · %dv%d · %s · Best of %d · %s · level %d+ · %d/%d teams · by %s · %s%s"
L.TOUR_STARTS_IN = "starts in %d min"
L.TOUR_STARTED = "started %s"
L.TOUR_JOINED_MARK = " · |cff40ff40joined|r"
L.TOUR_BRACKET_SINGLE = "single elimination"
L.TOUR_BRACKET_ROBIN = "round robin"
L.TOUR_STATE_SCHEDULED = "scheduled"
L.TOUR_STATE_CHECKIN = "|cff40ff40check-in|r"
L.TOUR_STATE_RUNNING = "|cffff8000running|r"
L.TOUR_STATE_FINISHED = "finished"
L.TOUR_STATE_CANCELLED = "|cffff4040cancelled|r"
L.TOUR_CREATED = "Tournament |cffffd100%s|r created. Players join with /hh tour."
L.TOUR_CANCELLED = "Tournament %s cancelled."
L.TOUR_NONE_OWN = "You are not running a tournament."
L.TOUR_PICK = "Which one? The number from /hh tour."
L.TOUR_REQUEST_SENT = "Request sent to the organizer of %s."
L.TOUR_ORGANIZER_GONE = "Tournament %s is cancelled: the organizer is gone."
L.TOUR_REPLY_OK = "You are in: %s."
L.TOUR_REPLY_LEFT = "You left %s."
L.TOUR_REPLY_FULL = "%s is full."
L.TOUR_REPLY_LEVEL = "%s: a team member is below the minimum level."
L.TOUR_REPLY_FORMAT = "%s: your team has the wrong number of players."
L.TOUR_REPLY_DUPE = "%s: a team member is already in another team."
L.TOUR_REPLY_CLOSED = "%s no longer takes changes."
L.TOUR_REPLY_LEADER = "%s: only the party leader can register the team."
L.TOUR_ERR_NOT_READY = "Not ready yet, try again in a moment."
L.TOUR_ERR_NAME = "The tournament needs a name."
L.TOUR_ERR_FORMAT = "Format: 1v1, 2v2, 3v3 or 5v5."
L.TOUR_ERR_BRACKET = "Bracket: single or robin."
L.TOUR_ERR_BEST_OF = "Series: bo1, bo3 or bo5."
L.TOUR_ERR_START = "The start must be at least 1 minute and at most 7 days away."
-- Reminders and check-in (HH-104)
L.TOUR_REMIND_CENTER = "|cffffd100Gurubashi Tournament|r %s in %d min!"
L.TOUR_REMIND_CHAT = "|cffffd100%s|r starts in %d min at %s. Be there for the check-in."
L.TOUR_REMIND_OPEN = "Gurubashi Tournament |cffffd100%s|r starts in %d min and you can still join: /hh tour."
L.TOUR_CHECKIN_CENTER = "|cffffd100%s|r: check-in! Click I'm here at %s."
L.TOUR_CHECKIN_CHAT = "|cffffd100%s|r: check-in is open. Go to %s and click I'm here (Tournaments tab or /hh tour here) within %d min."
L.TOUR_CHECKIN_POPUP = "Tournament\n\n|cffffd100%s|r: check-in is open.\nAre you at %s?"
L.TOUR_CHECKIN_SENT = "Check-in sent for %s."
L.TOUR_CHECKIN_DONE = "Check-in for %s is over: %d teams are in. The bracket is ready."
L.TOUR_CHECKIN_TOO_FEW = "Check-in for %s is over with fewer than 2 teams: cancelled."
L.TOUR_RUNNING_NOTICE = "Check-in for |cffffd100%s|r is over: the matches begin."
L.TOUR_CANCELLED_NOTICE = "Tournament %s is cancelled."
L.TOUR_BUTTON_HERE = "I'm here"
L.TOUR_BUTTON_LATER = "Later"
L.TOUR_REPLY_HERE = "Checked in for %s. Stay in the arena."
L.TOUR_REPLY_NOTIN = "You are not registered in %s."
L.TOUR_ERR_NOT_CHECKIN = "No check-in is open for you right now."
L.TOUR_ERR_NOT_REGISTERED = "You are not registered in this tournament."
L.TOUR_ERR_NOT_AT_VENUE = "You must be at the tournament's venue to check in (/hh arena shows where you are)."
L.TOUR_ERR_VENUE = "That venue is for the other faction."
L.TOUR_STATUS_HERE = "|cff40ff40Checked in|r"
L.TOUR_STATUS_CHECKIN_ME = "|cffff8000Check in now!|r"
L.TIP_TOUR_HERE = " |cff40ff40(here)|r"

-- Tournaments tab and Create dialog (HH-103)
L.TAB_TOURS = "Tournaments"
L.COL_TOUR = "Tournament"
L.COL_FORMAT = "Format"
L.COL_SERIES = "Series"
L.COL_START = "Start"
L.COL_LEVEL = "Level"
L.COL_TEAMS = "Teams"
L.COL_ORGANIZER = "Organizer"
L.EMPTY_TOURS = "No tournaments yet. From level 19, click Create to host one."
L.TOUR_IN_MIN = "in %d min"
L.TOUR_IN_HOURS = "in %d h %d min"
L.TOUR_IN_DAYS = "in %d d %d h"
L.TOUR_SERIES = "Best of %d%s"
L.TOUR_ROBIN_SHORT = ", robin"
L.TOUR_BEST_OF = "Best of %d"
L.TOUR_STATUS_OPEN = "|cff40ff40Open|r"
L.TOUR_STATUS_JOINED = "|cff40ff40Joined|r"
L.TOUR_STATUS_FULL = "|cffff8000Full|r"
L.TOUR_STATUS_LEVEL = "|cffff4040Level too low|r"
L.TOUR_STATUS_PARTY = "|cffff8000Needs a party|r"
L.TOUR_STATUS_LEADER = "|cffff8000Leader joins|r"
L.TOUR_STATUS_CHECKIN = "|cff40ff40Check-in|r"
L.TOUR_STATUS_RUNNING = "|cffff8000Running|r"
L.TOUR_STATUS_FINISHED = "Finished"
L.TOUR_STATUS_CANCELLED = "|cffff4040Cancelled|r"
L.TIP_TOUR_FORMAT = "%dv%d · %s · Best of %d"
L.TIP_TOUR_START = "Start: %s (realm time %s)"
L.TIP_TOUR_TEAMS = "Teams: %d of %d · minimum level %d"
L.TIP_TOUR_ORGANIZER = "Organizer: %s"
L.TIP_TOUR_VENUE = "Where: %s"
L.TOUR_DLG_VENUE = "Venue"
L.TOUR_BUTTON_CREATE = "Create"
L.TOUR_BUTTON_JOIN = "Join"
L.TOUR_BUTTON_LEAVE = "Leave"
L.TOUR_BUTTON_CANCEL = "Cancel it"
L.TOUR_DLG_TITLE = "New Gurubashi Tournament"
L.TOUR_DLG_NAME = "Name"
L.TOUR_DLG_FORMAT = "Format"
L.TOUR_DLG_BRACKET = "Bracket"
L.TOUR_DLG_SERIES = "Series"
L.TOUR_DLG_MINUTES = "Starts in (minutes)"
L.TOUR_DLG_LEVEL = "Minimum level"
L.TOUR_DLG_TEAMS = "Max teams"
L.TOUR_DLG_STARTS = "|cff40ff40Starts at %s realm time.|r"
L.TOUR_DLG_CHEST = "|cffff4040%s realm time clashes with the arena chest event.|r Start 15 min to 2 h after a chest (00:15-02:00, 03:15-05:00 ...)."
L.TOUR_DLG_NEED_MINUTES = "Enter the minutes until the start."
L.TOUR_ERR_CHEST = "That start clashes with the arena chest event (every 3 hours from midnight, realm time). Start 15 min to 2 h after a chest: 00:15-02:00, 03:15-05:00, 06:15-08:00 and so on."
L.TOUR_NEXT_CHEST = "Next arena chest in %d min (realm time %s)."
L.TOUR_ERR_LEVEL = "Minimum level: 19 to 60."
L.TOUR_ERR_ORGANIZER_LEVEL = "You can host tournaments from level 19."
L.TOUR_ERR_TEAMS = "Teams: 2 to 32 (round robin: up to 8)."
L.TOUR_ERR_ALREADY = "You already run a tournament. Cancel it first (/hh tour cancel)."
L.TOUR_ERR_UNKNOWN = "Unknown tournament."
L.TOUR_ERR_CLOSED = "This tournament no longer takes changes."
L.TOUR_ERR_NOT_LEADER = "Only the party leader can register the team."
L.TOUR_ERR_PARTY_SIZE = "Your party must have exactly as many players as the format."
L.TOUR_ERR_LEVEL_LOW = "You or a party member is below the minimum level."
L.TAB_DUELS = "Duels"
L.COL_POSITION = "#"
L.COL_DUEL_RANK = "Rank"
L.COL_NET = "Net"
L.COL_RECORD = "Won-Lost"
L.COL_LAST_DUEL = "Last duel"
L.EMPTY_DUELS = "No duelists yet. Duels between players of level 10 or higher show up here."
L.TIP_DUEL = "%d wins, %d losses · last duel %s"

-- HH-118 Player bounties
L.BOUNTY_REASON_CAMPED = "Camped me"
L.BOUNTY_REASON_MOBS = "Ganked me while I fought mobs"
L.BOUNTY_REASON_LOWLEVEL = "Killed me at low level"
L.BOUNTY_REASON_GROUP = "Killed me in a group"
L.BOUNTY_POST_BUTTON = "Post a bounty"
L.BOUNTY_DLG_TITLE = "Post a bounty"
L.BOUNTY_DLG_TARGET = "Put a bounty on |cffff4040%s|r"
L.BOUNTY_DLG_REASON = "Reason"
L.BOUNTY_DLG_GOLD = "Gold"
L.BOUNTY_DLG_RANGE = "%s to %s"
L.BOUNTY_DLG_DAYS = "Runs for"
L.BOUNTY_DLG_POST = "Post"
L.BOUNTY_DAYS = "%d day(s)"
L.BOUNTY_ERR_NOTKILLER = "You can only post a bounty on a player who killed you in the last 24 hours."
L.BOUNTY_ERR_LEVEL = "Bounties are from level 15: you were under 15 when this player killed you."
L.BOUNTY_ERR_TARGETLEVEL = "Bounties are on players from level 15: this player was under 15 when they killed you."
L.BOUNTY_ERR_ACTIVE = "You already have a bounty running. One at a time."
L.BOUNTY_ERR_COOLDOWN = "You posted a bounty less than 30 minutes ago."
L.BOUNTY_ERR_BLOCKED = "A hunter was not paid your bounty: you cannot post bounties for 30 days."
L.BOUNTY_ERR_GOLD = "A bounty is at least 2g."
L.BOUNTY_ERR_TOOMUCH = "A bounty is at most 15g."
L.BOUNTY_ERR_DAYS = "Pick how many days the bounty runs."
L.BOUNTY_ERR_REASON = "Pick a reason."
L.BOUNTY_ERR_UNKNOWN = "Cannot post a bounty right now."
L.BOUNTY_POSTED = "Bounty posted: %s on |cffff4040%s|r for %d day(s). Whoever brings them down gets it; you pay by mail."
L.BOUNTY_LINE = "|cffffd100Bounty:|r %s by %s · %s"
L.BOUNTY_LINE_MANY = "|cffffd100Bounty:|r %d posters · %s"
L.BOUNTY_PAYS_UP = " · |cff40ff40pays up|r"
L.BOUNTY_UNPAID_WARNING = " · |cffff4040%d unpaid|r"
L.BOUNTY_RANK = "|cffffd100Bounty|r %s"
L.BOUNTY_POSTERS = "%d posters"
L.BOUNTY_DETAIL = "%s · by %s"
L.BOUNTY_LEFT = "%s left"
L.BOUNTY_ROW_HINT = "|cffffd100Open the poster to post a bounty on this killer|r"
L.BOUNTY_CLAIMED = "|cffffd100Bounty claimed:|r %s from %s, it comes by mail."
L.BOUNTY_CLAIMED_CENTER = "|cffffd100Bounty claimed!|r %s for |cffff4040%s|r"
L.BOUNTY_ANNOUNCE_QUESTION = "Announce your claim to all HeadHunters, so the poster's owner hears about it?"
L.BOUNTY_ANNOUNCED = "Claim announced to all HeadHunters."
L.BOUNTY_ANNOUNCE_NOTHING = "No bounty claim waiting to be announced."
L.HELP_CLAIM = "|cffffff00/hh claim|r: Announce your bounty claim to all HeadHunters (Classic Era)"
L.BOUNTY_OWNER_CENTER = "|cffffd100Your bounty is claimed:|r %s brought down |cffff4040%s|r"
L.BOUNTY_OWNER_CHAT = "|cffffd100Your bounty is claimed:|r %s brought down |cffff4040%s|r (%s, %s). Pay at the next mailbox."
L.BOUNTY_NO_CLAIM_LEVEL = "No bounty: %s is 10+ levels below you (hunting down is ganking too)"
L.BOUNTY_NO_CLAIM_REPEAT = "No bounty: you claimed one on %s less than 7 days ago."
L.BOUNTY_PAID = "|cffffd100%s paid the %s bounty.|r"
L.BOUNTY_MAIL_SUBJECT = "HeadHunter bounty: %s"
L.BOUNTY_MAIL_BODY = "You brought down %s. Reason for the bounty: %s. Thanks, hunter!"
L.BOUNTY_PAY_PROMPT = "%s brought down %s (your bounty: %s).\nSend %s?"
L.BOUNTY_PAY_FIRST = "\n\n|cffaaaaaaThe first bounty claim by %s.|r"
L.BOUNTY_PAY_ALT = "\n\n|cffff8000%s claimed a bounty on %s before: maybe an alt. If you do not pay, you are not a Deadbeat.|r"
L.BOUNTY_PAY_SEND = "Send"
L.BOUNTY_PAY_LATER = "Later"
L.BOUNTY_PAY_SENT = "Sent %s to %s. Thanks for paying up!"
L.BOUNTY_PAY_NO_GOLD = "Not enough gold to pay the %s bounty. It asks again at the next mailbox."
L.BOUNTY_PAY_NO_MAIL = "HeadHunter could not write the mail. Please send the gold yourself."
L.SIGHTING_BULLY = "|cffff8040BULLY|r · |cffff4040%s|r is here!"
L.SIGHTING_CHAT_BULLY = "|cffff8040BULLY|r |cffff4040%s|r spotted (%s) · %d kills of lowbies · Hall of Shame"
L.SIGHTING_DEADBEAT = "|cffff4040DEADBEAT|r · %s is here!"
L.SIGHTING_CHAT_DEADBEAT = "|cffff4040DEADBEAT|r %s is near · did not pay %d bounties · Hall of Shame"
L.SIGHTING_CHAT_DEADBEAT_ENEMY = "|cffff4040DEADBEAT|r |cffff4040%s|r spotted · did not pay %d bounties of their own side · bring them down for bounty points"
L.SET_SHAME = "Hall of Shame alerts"
L.SET_SHAME_TIP = "Tell me when a bully or a Deadbeat from the Hall of Shame is near, even when they are not WANTED (at most once every 10 minutes each)."
L.SIGHTING_BOUNTY = "|cffffd100BOUNTY|r · |cffff4040%s|r is here!"
L.SIGHTING_CHAT_BOUNTY = "|cffffd100BOUNTY|r |cffff4040%s|r spotted (%s)"
L.MARKS_REASON_BULLY = "brought down the bully %s (Hall of Shame)"
L.MARKS_REASON_DEADBEAT = "brought down the Deadbeat %s (Hall of Shame)"
L.MARKS_REASON_CLAIM = "brought down %s (a player's bounty)"

-------------------------------------------------
-- zhCN: the browsed interface only (main window, tabs, columns, hover tips,
-- tooltips, poster, settings page, map pins, the bounty and tournament dialogs,
-- and the confirmation dialogs they open). enUS above stays the fallback; only
-- the keys listed here are replaced, so chat lines, /hh help, debug and sync
-- diagnostics keep their English text. Missing keys still print as the key.
-- Race/class words in the "Level, race, class" column go through the display
-- tables below (Core/Utils.lua reads them when set).
-------------------------------------------------
local locale = type(GetLocale) == "function" and GetLocale() or "enUS"

if locale == "zhCN" then
    local CN = {
        -- Main window chrome
        WINDOW_COUNT = "%d 个",
        WINDOW_SITE_DATA = " · 含 %s 的官网榜单",
        WINDOW_ROW_HINT = "|cff00ff00点击：打开通缉令|r",
        WINDOW_ROW_WHISPER = "|cff00ff00点击：密语|r",
        FOREVER_SAVED_VARS = "|cffff8800WoW Forever 处于测试模式：|r此客户端不会回读存档（已知客户端问题），每次重载后列表与设置都会重置。登录时会从其他 HeadHunter 补齐。",
        FOREVER_SAVED_VARS_SHORT = "Forever 测试模式：重载后存档重置（客户端问题）",
        FACTION_BUTTON = "%s 名单",
        OPTIONS_BUTTON = "选项",
        MINIMAP_HINT = "左键点击：打开 · 拖动：移动",

        -- Tabs
        TAB_WANTED = "通缉",
        TAB_SHAME = "耻辱柱",
        TAB_DUELS = "决斗",
        TAB_DEATHS = "我的死亡",
        TAB_MARKS = "我的赏金",
        TAB_TOURS = "赛事",

        -- Column headers
        COL_RANK = "通缉等级",
        COL_NAME = "名字",
        COL_KILLS = "击杀",
        COL_LAST_KILL = "最近击杀",
        COL_BADGES = "徽章",
        COL_WHO = "等级、种族、职业",
        COL_COWARD_KILLS = "欺凌击杀",
        COL_STATUS = "状态",
        COL_WHEN = "时间",
        COL_KILLER = "击杀者",
        COL_KIND = "击杀方式",
        COL_ZONE = "区域",
        COL_CHANGE = "赏金",
        COL_REASON = "原因",
        COL_TOTAL = "总计",
        COL_POSITION = "#",
        COL_DUEL_RANK = "段位",
        COL_NET = "净胜",
        COL_RECORD = "胜负",
        COL_LAST_DUEL = "最近决斗",
        COL_TOUR = "赛事",
        COL_FORMAT = "模式",
        COL_SERIES = "局制",
        COL_START = "开始",
        COL_LEVEL = "等级",
        COL_TEAMS = "队伍",
        COL_ORGANIZER = "组织者",

        -- Empty tabs
        EMPTY_WANTED = "当前没有人被通缉。",
        EMPTY_SHAME = "还没有已知的欺凌者。",
        EMPTY_DEATHS = "还没有记录到 PvP 死亡。",
        EMPTY_DUELS = "还没有决斗记录。10 级及以上玩家之间的决斗会显示在这里。",
        EMPTY_MARKS = "还没有赏金：加入追捕队，击倒被通缉的亡命徒。",
        EMPTY_TOURS = "还没有赛事。19 级起可以点击“创建”举办一场。",

        -- Row hover tips
        TIP_WANTED = "|cffff2020通缉|r · %s · 击杀 %d",
        TIP_NOT_WANTED = "|cffaaaaaa未被通缉|r",
        TIP_BOUNTY_ONLY = "|cffffd100赏金|r · 玩家悬赏 %s（非通缉）",
        TIP_AT_LARGE = "|cffff8040在逃|r：曾为 %s，从未落网",
        TIP_LAST_KILL = "最近击杀 %s，位于 %s",
        TIP_HISTORY = "|cffaaaaaa已知击杀：%d · 通缉 %d 次 · 落网 %d 次|r",
        TIP_KILLED_YOU = "%s 在 %s 击杀了你（%s）",
        TIP_DUEL = "%d 胜 %d 负 · 最近决斗 %s",
        TIP_TOUR_FORMAT = "%dv%d · %s · BO%d",
        TIP_TOUR_START = "开始：%s（服务器时间 %s）",
        TIP_TOUR_TEAMS = "队伍：%d/%d · 最低等级 %d",
        TIP_TOUR_ORGANIZER = "组织者：%s",
        TIP_TOUR_VENUE = "地点：%s",
        TIP_TOUR_HERE = " |cff40ff40（已到场）|r",

        -- Enemy player tooltips
        TOOLTIP_WANTED = "|cffff2020通缉|r · %s · 击杀 %d",
        TOOLTIP_KNOWN = "HeadHunter：已知击杀 %d",
        TOOLTIP_AT_LARGE = "|cffff8040在逃|r · 曾为 %s · 已知击杀 %d",
        TOOLTIP_CAUGHT = " · 落网 %d 次",

        -- Poster (UI/Poster.lua)
        POSTER_HEADER = "通缉令",
        POSTER_HISTORY = "已知击杀：%d（确切 %d，推算 %d） · 通缉 %d 次 · 落网 %d 次 · 最高头衔 %s",
        POSTER_RECENT = "近期击杀",
        POSTER_NO_KILLS = "没有已知击杀。",
        POSSE_JOIN = "加入追捕队",
        POSSE_DECLINE = "拒绝",
        POSSE_SUMMARY = "追捕队：%s",
        POSSE_YOU = "你",

        -- Gold bounties: rows, poster and the post dialog
        BOUNTY_POST_BUTTON = "发布悬赏",
        BOUNTY_ROW_HINT = "|cffffd100打开通缉令，对这名击杀者发布悬赏|r",
        BOUNTY_LINE = "|cffffd100悬赏：|r %s，由 %s 发布 · %s",
        BOUNTY_LINE_MANY = "|cffffd100悬赏：|r %d 人发布 · %s",
        BOUNTY_PAYS_UP = " · |cff40ff40已付清|r",
        BOUNTY_UNPAID_WARNING = " · |cffff4040未付 %d 笔|r",
        BOUNTY_RANK = "|cffffd100悬赏|r %s",
        BOUNTY_POSTERS = "%d 人发布",
        BOUNTY_DETAIL = "%s · 由 %s 发布",
        BOUNTY_LEFT = "剩 %s",
        BOUNTY_DAYS = "%d 天",
        BOUNTY_DLG_TITLE = "发布悬赏",
        BOUNTY_DLG_TARGET = "对 |cffff4040%s|r 发布悬赏",
        BOUNTY_DLG_REASON = "原因",
        BOUNTY_DLG_GOLD = "金币",
        BOUNTY_DLG_RANGE = "%s 至 %s",
        BOUNTY_DLG_DAYS = "持续时间",
        BOUNTY_DLG_POST = "发布",
        BOUNTY_REASON_CAMPED = "蹲守杀我",
        BOUNTY_REASON_MOBS = "我打怪时偷袭我",
        BOUNTY_REASON_LOWLEVEL = "我低等级时杀我",
        BOUNTY_REASON_GROUP = "组队杀我",
        BOUNTY_ERR_NOTKILLER = "只能对最近 24 小时内击杀过你的玩家发布悬赏。",
        BOUNTY_ERR_LEVEL = "悬赏需要 15 级：这名玩家击杀你时你未满 15 级。",
        BOUNTY_ERR_TARGETLEVEL = "悬赏对象需 15 级及以上：该玩家击杀你时未满 15 级。",
        BOUNTY_ERR_ACTIVE = "你已有一个进行中的悬赏，同一时间只能有一个。",
        BOUNTY_ERR_COOLDOWN = "你在 30 分钟内刚发布过悬赏。",
        BOUNTY_ERR_BLOCKED = "有猎人没收到你的悬赏金：30 天内你不能发布悬赏。",
        BOUNTY_ERR_GOLD = "悬赏至少 2 金。",
        BOUNTY_ERR_TOOMUCH = "悬赏至多 15 金。",
        BOUNTY_ERR_DAYS = "请选择悬赏持续的天数。",
        BOUNTY_ERR_REASON = "请选择原因。",
        BOUNTY_ERR_UNKNOWN = "当前无法发布悬赏。",
        BOUNTY_PAY_PROMPT = "%s 击倒了 %s（你的悬赏：%s）。\n发送 %s 吗？",
        BOUNTY_PAY_FIRST = "\n\n|cffaaaaaa这是 %s 第一次领取悬赏。|r",
        BOUNTY_PAY_ALT = "\n\n|cffff8000%s 之前就对 %s 领取过悬赏：可能是小号。不支付也不会算你老赖。|r",
        BOUNTY_PAY_SEND = "发送",
        BOUNTY_PAY_LATER = "稍后",
        BOUNTY_MAIL_SUBJECT = "HeadHunter 悬赏：%s",
        BOUNTY_MAIL_BODY = "你击倒了 %s。悬赏原因：%s。谢了，猎人！",

        -- Hall of Shame rows
        SHAME_WANTED = "|cffff2020通缉|r · %s",
        SHAME_PAST = "通缉 %d 次 · 落网 %d 次",
        SHAME_UNPAID_WHO = "|cffff4040老赖|r · 未支付悬赏",
        SHAME_UNPAID = "未付 %d 笔 · %d 天内不能发布悬赏",
        SHAME_UNPAID_TIP = "|cffff4040老赖|r：猎人为他们击倒了目标却没拿到钱。封禁期间他们无法发布悬赏。",

        -- Ranks, badges and kill kinds (shown in lists, tips and the poster)
        RANK_GANKER = "|cffffd100偷袭者|r",
        RANK_OUTLAW = "|cffff9933亡命徒|r",
        RANK_DESPERADO = "|cffff6600悍匪|r",
        RANK_MOSTWANTED = "|cffff3333头号通缉|r",
        RANK_DEADORALIVE = "|cffcc0000生死不论|r",
        NOT_WANTED = "未被通缉",
        AT_LARGE = "|cffff8040在逃|r",
        BADGE_COWARD = "|cffff8000欺凌者|r",
        BADGE_GANG = "|cffcc66ff群殴|r",
        BADGE_DUO = "|cffcc66ff二打一|r",
        BADGE_SERIALKILLER = "|cffff3333连环杀手|r",
        BADGE_GUNSLINGER = "|cff40ff40快枪手|r",
        BADGE_GIANTSLAYER = "|cff40c0ff以弱胜强|r",
        KILL_COWARD = "|cffff8000欺凌击杀|r",
        KILL_FAIR = "|cff40ff40公平对决|r",
        KILL_GIANT = "|cff40c0ff以弱胜强|r",
        KILL_NORMAL = "等级压制",
        KILL_UNKNOWN = "等级未知",
        KILL_DUO = "|cffcc66ff二打一|r（%d vs 1）",
        KILL_GANG = "|cffcc66ff群殴|r（%d vs 1）",
        KILL_GROUP = "|cffcc66ff团战|r（%d vs %d）",
        HUNTER_RANK_TRACKER = "追踪者",
        HUNTER_RANK_BOUNTYHUNTER = "赏金猎人",
        HUNTER_RANK_MANHUNTER = "追猎者",
        HUNTER_RANK_HEADHUNTER = "猎头者",
        HUNTER_RANK_REAPER = "死神",
        DUEL_RANK_GREENHORN = "新手",
        DUEL_RANK_QUICKDRAW = "快拔",
        DUEL_RANK_SHARPSHOOTER = "神射手",
        DUEL_RANK_DEADEYE = "鹰眼",
        DUEL_RANK_LEGEND = "传奇",
        DUEL_RANK_TOPGUN = "王牌",
        DUEL_TITLE = "%s 第 %d 名（%s）",
        DUEL_TITLE_TOPGUN = "|cffff8000王牌|r（%s）",
        DUEL_TITLE_GREENHORN = "%s（%d 场决斗）",
        DUEL_TOOLTIP = "|cffffd100决斗：|r %s",

        -- My bounty tab (Rules/Marks.lua text)
        MARKS_STATUS = "猎头等级：|cffffd100%s|r · 赏金 %d",
        MARKS_REASON_JOIN = "加入了追捕 %s 的队伍",
        MARKS_REASON_CATCH = "击倒了 %s",
        MARKS_REASON_DECLINE = "拒绝了追捕 %s",
        MARKS_REASON_SKIP = "无赏金：%s 比你低 10 级以上（追杀低级也是偷袭）",
        MARKS_REASON_BULLY = "击倒了欺凌者 %s（耻辱柱）",
        MARKS_REASON_DEADBEAT = "击倒了老赖 %s（耻辱柱）",
        MARKS_REASON_CLAIM = "击倒了 %s（玩家悬赏）",

        -- Time and places in the lists
        JUST_NOW = "刚刚",
        MINUTES_AGO = "%d 分钟前",
        HOURS_AGO = "%d 小时 %d 分钟前",
        DAYS_AGO = "%d 天 %d 小时前",
        UNKNOWN_ZONE = "未知区域",

        -- World map pins (UI/MapMarkers.lua)
        MAP_PVP = "PVP",
        MAP_HOTSPOT_TITLE = "|cffff3300PvP 区域|r · |cffff9933%s|r，位于 %s",
        MAP_WANTED_TITLE = "|cffff2020通缉|r · |cffff4040%s|r",
        MAP_WANTED_STATUS = "%s · 击杀 %d · 直至落网",
        MAP_WANTED_LAST_KILL = "最近击杀 %s，位于 %s",
        MAP_STATUS = "地图标记：%s · 你的区域有 %d 个",
        ON = "开",
        OFF = "关",
        GUIDE_COORDS = "%s，坐标 %.1f, %.1f。",
        GUIDE_UNKNOWN = "%s：位置未知。",
        GUIDE_HOTSPOT = "PvP %s，位于 %s",
        GUIDE_WANTED = "%s 的最近击杀",
        HOTSPOT_LEVEL_1 = "遭遇战",
        HOTSPOT_LEVEL_2 = "战斗",
        HOTSPOT_LEVEL_3 = "战区",

        -- Tournaments: tab, create dialog and the selected tournament's buttons
        TOUR_IN_MIN = "%d 分钟后",
        TOUR_IN_HOURS = "%d 小时 %d 分钟后",
        TOUR_IN_DAYS = "%d 天 %d 小时后",
        TOUR_SERIES = "BO%d%s",
        TOUR_ROBIN_SHORT = "，循环赛",
        TOUR_BEST_OF = "BO%d",
        TOUR_BRACKET_SINGLE = "单败淘汰",
        TOUR_BRACKET_ROBIN = "循环赛",
        TOUR_STATUS_OPEN = "|cff40ff40可报名|r",
        TOUR_STATUS_JOINED = "|cff40ff40已报名|r",
        TOUR_STATUS_FULL = "|cffff8000已满员|r",
        TOUR_STATUS_LEVEL = "|cffff4040等级不足|r",
        TOUR_STATUS_PARTY = "|cffff8000需要队伍|r",
        TOUR_STATUS_LEADER = "|cffff8000由队长报名|r",
        TOUR_STATUS_CHECKIN = "|cff40ff40签到中|r",
        TOUR_STATUS_RUNNING = "|cffff8000进行中|r",
        TOUR_STATUS_FINISHED = "已结束",
        TOUR_STATUS_CANCELLED = "|cffff4040已取消|r",
        TOUR_BUTTON_CREATE = "创建",
        TOUR_BUTTON_JOIN = "报名",
        TOUR_BUTTON_LEAVE = "退出",
        TOUR_BUTTON_CANCEL = "取消赛事",
        TOUR_BUTTON_HERE = "我到了",
        TOUR_BUTTON_LATER = "稍后",
        TOUR_CREATED = "赛事 |cffffd100%s|r 已创建。玩家用 /hh tour 报名。",
        TOUR_CHECKIN_POPUP = "赛事\n\n|cffffd100%s|r：签到已开放。\n你在 %s 吗？",
        TOUR_REQUEST_SENT = "已向 %s 的组织者发送请求。",
        TOUR_REPLY_OK = "你已加入：%s。",
        TOUR_REPLY_LEFT = "你已退出 %s。",
        TOUR_REPLY_FULL = "%s 已满员。",
        TOUR_REPLY_LEVEL = "%s：有队员低于最低等级。",
        TOUR_REPLY_FORMAT = "%s：队伍人数不符。",
        TOUR_REPLY_DUPE = "%s：有队员已在其他队伍中。",
        TOUR_REPLY_CLOSED = "%s 已不再接受变更。",
        TOUR_REPLY_LEADER = "%s：只有队长可以报名队伍。",
        TOUR_ERR_NOT_READY = "尚未就绪，请稍后再试。",
        TOUR_ERR_NAME = "赛事需要一个名称。",
        TOUR_ERR_FORMAT = "赛制：1v1、2v2、3v3 或 5v5。",
        TOUR_ERR_BRACKET = "赛制：单败淘汰或循环赛。",
        TOUR_ERR_BEST_OF = "局制：bo1、bo3 或 bo5。",
        TOUR_ERR_START = "开始时间至少 1 分钟、至多 7 天。",
        TOUR_ERR_CHEST = "该开始时间与竞技场宝箱事件冲突（服务器时间午夜起每 3 小时一次）。请在宝箱后 15 分钟至 2 小时开始：00:15-02:00、03:15-05:00、06:15-08:00，依此类推。",
        TOUR_ERR_LEVEL = "最低等级：19 至 60。",
        TOUR_ERR_ORGANIZER_LEVEL = "19 级起可以举办赛事。",
        TOUR_ERR_TEAMS = "队伍数：2 至 32（循环赛至多 8）。",
        TOUR_ERR_ALREADY = "你已有一场进行中的赛事。请先取消（/hh tour cancel）。",
        TOUR_ERR_UNKNOWN = "未知赛事。",
        TOUR_ERR_CLOSED = "该赛事已不再接受变更。",
        TOUR_ERR_NOT_LEADER = "只有队长可以报名队伍。",
        TOUR_ERR_PARTY_SIZE = "队伍人数必须与赛制要求一致。",
        TOUR_ERR_LEVEL_LOW = "你或有队员低于最低等级。",
        TOUR_DLG_TITLE = "新建古拉巴什赛事",
        TOUR_DLG_NAME = "名称",
        TOUR_DLG_VENUE = "场地",
        TOUR_DLG_FORMAT = "模式",
        TOUR_DLG_BRACKET = "赛制",
        TOUR_DLG_SERIES = "局制",
        TOUR_DLG_MINUTES = "开始倒计时（分钟）",
        TOUR_DLG_LEVEL = "最低等级",
        TOUR_DLG_TEAMS = "队伍上限",
        TOUR_DLG_STARTS = "|cff40ff40将于服务器时间 %s 开始。|r",
        TOUR_DLG_CHEST = "|cffff4040服务器时间 %s 与竞技场宝箱事件冲突。|r请在宝箱事件后 15 分钟至 2 小时开始（00:15-02:00、03:15-05:00 …）。",
        TOUR_DLG_NEED_MINUTES = "请输入距离开始的分钟数。",
        VENUE_GURUBASHI = "古拉巴什竞技场（荆棘谷）",
        VENUE_ORGRIMMAR = "奥格瑞玛城门（杜隆塔尔）",
        VENUE_UNDERCITY = "幽暗城废墟（提瑞斯法林地）",
        VENUE_IRONFORGE = "铁炉堡城门（丹莫罗）",
        VENUE_STORMWIND = "暴风城城门（艾尔文森林）",

        -- Settings page (Esc > Options > AddOns > HeadHunter)
        SET_HINT = "改动立即生效。同样的设置也可以用 /hh 命令（/hh help）。",
        SET_UNAVAILABLE = "此客户端不支持选项页；请用 /hh help 查看命令。",
        SET_SECTION_ALERTS = "提醒",
        SET_SECTION_DISPLAY = "显示",
        SET_SECTION_RULES = "规则",
        SET_ALERTS = "提醒",
        SET_ALERTS_TIP = "通缉目击、通缉活动、交战热点与“正法”消息。",
        SET_SOUND = "提示音",
        SET_SOUND_TIP = "提醒时播放音效。",
        SET_POPUPS = "弹窗",
        SET_POPUPS_TIP = "“加入追捕队”/“支援”弹窗。关闭后只在聊天与屏幕中央显示。",
        SET_RANGE = "提醒范围",
        SET_RANGE_TIP = "相邻区域：你所在区域及与之接壤的区域。整个大陆：更远的区域也会提醒。",
        SET_CHOICE_ADJACENT = "相邻区域",
        SET_CHOICE_CONTINENT = "整个大陆",
        SET_WHISPER = "跨层时请求组队邀请",
        SET_WHISPER_TIP = "加入追捕队而击杀发生在其他分层时，密语受害者请求组队邀请。",
        SET_MAP = "地图上的 PvP 区域与通缉骷髅",
        SET_MAP_TIP = "红色 PvP 区域表示交战热点，骷髅表示通缉亡命徒的最近击杀点（10 分钟）。",
        SET_TOOLTIP = "敌人鼠标提示上的通缉信息",
        SET_TOOLTIP_TIP = "在玩家鼠标提示上附加通缉状态（或已知信息）。",
        SET_MINIMAP = "小地图按钮",
        SET_MINIMAP_TIP = "点击打开 HeadHunter 窗口；拖动可移动位置。",
        SET_SERIAL = "连环杀手时间窗",
        SET_SERIAL_TIP = "“连环杀手”徽章要求在此时间内、在互相独立的战斗中击杀 5 名不同受害者。",
        SET_SHAME = "耻辱柱提醒",
        SET_SHAME_TIP = "耻辱柱里的欺凌者或老赖靠近时提醒我，即使他们没有被通缉（每人每 10 分钟至多一次）。",
        SET_MINUTES = "%d 分钟",

        -- Confirmation dialogs opened from the window / after a catch
        REPORT_PROMPT = "HeadHunter\n\n向所有 HeadHunter 报告 |cffff4040%s|r（%s）吗？",
        REPORT_MORE = "（还有 %d 条待报告）",
        REPORT_BUTTON = "报告",
        REPORT_SKIP = "跳过",
        CATCHUP_PROMPT = "HeadHunter\n\n你上次在线是 %s。\n向所有 HeadHunter 询问你错过的内容吗？",
        CATCHUP_PROMPT_NEW = "HeadHunter\n\n向所有 HeadHunter 索取当前的通缉名单吗？",
        CATCHUP_BUTTON = "补齐",
        JUSTICE_ANNOUNCE_QUESTION = "向所有 HeadHunter 宣告这件事吗？",
        JUSTICE_ANNOUNCE = "宣告",

        -- Chat lines: /hh help and every command's output, alerts, sim/debug tools.
        -- Command syntax after the |cffffff00…|r stays as typed; colour codes and the
        -- argument order of every format string are identical to the English above.
        LOADED = "v%s 已加载。输入 |cffffff00/hh help|r 查看命令。",
        UNSUPPORTED_CLIENT = "不支持此客户端（界面版本 %s）。HeadHunter 仅支持 Classic Era 与 WoW Forever。",
        HELP_HEADER = "|cffc41e3a========== HeadHunter ==========|r",
        HELP_STATUS = "|cffffff00/hh status|r：客户端、特性开关与数据库摘要",
        HELP_DEBUG = "|cffffff00/hh debug [on|off]|r：开关调试模式（调试信息回显到聊天）。|cffffff00/hh debug tours on|off|r：赛事页签（开发中）",
        HELP_LOG = "|cffffff00/hh log [clear]|r：显示调试日志窗口",
        HELP_PROBE = "|cffffff00/hh probe [watch|witness]|r：报告此客户端提供了哪些 WoW API；'watch' 记录实时战斗与死亡信号，'witness' 记录附近其他玩家的死亡",
        HELP_SIM = "|cffffff00/hh sim death|sighting|send|demo ...|r：注入模拟数据；'send' 与其他角色共享（调试），'demo' 用虚构数据填满每个页签供截图",
        UNKNOWN_COMMAND = "未知命令 '%s'。输入 /hh help。",
        DEBUG_ON = "调试模式已开启。",
        DEBUG_OFF = "调试模式已关闭。",
        LOG_CLEARED = "调试日志已清空。",
        STATUS_CLIENT = "客户端：%s（界面版本 %d）",
        STATUS_FEATURES = "CLEU：%s · 存档可靠：%s · 密值：%s",
        STATUS_DB = "数据库：架构 %d · 磁盘载入：%s · 载入次数：%d · 死亡：%d · 敌人：%d",
        STATUS_SUSPENDED = "已挂起（副本：%s）",
        STATUS_ACTIVE = "运行中（野外）",
        PROBE_DONE = "探针已写入调试日志（/hh log）。",
        PROBE_WATCH_ON = "watch 探针已开启：战斗与死亡信号会被记录。",
        PROBE_WATCH_OFF = "watch 探针已关闭。",
        PROBE_WITNESS_ON = "witness 探针已开启：附近其他玩家的死亡会被记录（/hh log）。",
        PROBE_WITNESS_OFF = "witness 探针已关闭。",
        HELP_ENEMIES = "|cffffff00/hh enemies|r：最近见过的敌方玩家",
        HELP_DEATHS = "|cffffff00/hh deaths [n]|r：你最近的 PvP 死亡",
        ENEMIES_HEADER = "见过的敌人：%d（最新在前）",
        DEATHS_HEADER = "记录到的 PvP 死亡：%d（最新在前）",
        DEATH_RECORDED = "被 |cffff4040%s|r 击杀（%s） · %s",
        SYNC_PING_QUEUED = "同步 ping 已排队（约 3 秒内发出）。其他 HeadHunter 会把它打印出来。",
        SYNC_PING_RECEIVED = "收到来自 %s [%s]（%s）经 %s 的同步 ping",
        SYNC_WHISPER_QUEUED = "已为 %s 排队插件密语 ping。若对方收到，会打印 \"Sync ping from ...\"。",
        SYNC_WHISPER_USAGE = "用法：/hh sync whisper \"<name>\"",
        SYNC_PROBE_LINE = "经 %s 的插件消息：%s · 结果 %s",
        SYNC_CHAT_SENT = "频道文本测试已发送。频道内其他 HeadHunter 应会打印它。",
        SYNC_CHAT_FAILED = "频道文本测试失败：%s",
        SYNC_CHAT_NO_CHANNEL = "尚未加入 HeadHunter 频道。",
        SYNC_CHAT_RECEIVED = "来自 %s 的频道文本：%s",
        HELP_SYNC = "|cffffff00/hh sync [ping|probe|chat|whisper <name>]|r：同步计数；'ping' 测试消息；'probe' 测试所有聊天类型；'chat' 测试频道文本；'whisper' 测试插件密语",
        SYNC_STATUS = "同步：频道 %s · 排队 %d · 已发 %d 条消息 / %d 条记录 · 收到 %d · 丢弃 %d · 失败 %d",
        SYNC_DIAG = "同步诊断：阵营 %s · 自动路由 %s · 冲刷被阻：%s · 最近发送：%s · 最近发送者：%s · 最近忽略：%s",
        HELP_REPORT = "|cffffff00/hh report|r：把等待中的死亡报告发送给所有 HeadHunter（Classic Era）",
        REPORT_SENT = "已向所有 HeadHunter 报告 %d 条死亡。",
        REPORT_FAILED = "未能接通 HeadHunter 频道。请再试一次 /hh report。",
        REPORT_NOTHING = "没有等待报告的死亡。",
        SYNC_REJECTED = "最近一次被拒的报告：%s",
        HELP_REPORTS = "|cffffff00/hh reports|r：共享的死亡报告（你的与他人的）",
        REPORTS_HEADER = "共享报告：%d（你 %d 条，其他玩家 %d 条）",
        RANK_NONE = "-",
        HELP_WANTED = "|cffffff00/hh wanted|r：当前通缉名单",
        WANTED_HEADER = "通缉：%d",
        WANTED_LINE = "  %s  |cffff4040%s|r  击杀 %d  最近击杀 %s%s",
        WANTED_TEST_THRESHOLD = "|cffff8000（测试阈值：%d 次击杀即通缉；/hh debug wanted off 恢复 4）|r",
        DEBUG_WANTED_ON = "测试阈值：20 分钟内 %d 次击杀即通缉。",
        DEBUG_WANTED_OFF = "测试阈值已关闭：20 分钟内 4 次击杀即通缉。",
        DEBUG_WANTED_USAGE = "/hh debug wanted <1-10|off>",
        HELP_OUTLAW = "|cffffff00/hh outlaw <name>|r：某个敌人的通缉令详情",
        OUTLAW_USAGE = "/hh outlaw <name>   （Forever 名字：/hh outlaw Grim Reaper）",
        OUTLAW_UNKNOWN = "没有 %s 的已知击杀。",
        OUTLAW_LINE1 = "|cffff4040%s|r · %s · 直至落网（再 %s 无击杀即结束）",
        OUTLAW_LINE2 = "已知击杀：%d（确切 %d，推算 %d = 半权重） · 通缉 %d 次 · 落网 %d 次 · 最高头衔 %s · %s",
        OUTLAW_LINE3 = "最近击杀：%s，%s 在 %s",
        HELP_SPREE = "|cffffff00/hh spree \"<name>\" <kills> [secondsApart] [killerLevel] [victimLevel]|r：模拟连杀（仅本地）",
        SPREE_USAGE = "/hh spree \"<name>\" <kills 1-60> [secondsApart=120] [killerLevel=60] [victimLevel=40]",
        SPREE_DONE = "已模拟 %d 次击杀（%s，仅本地，绝不发送）。",
        HELP_ALERTS = "|cffffff00/hh alerts [on|off|sound on|off|range adjacent|continent|whisper on|off|test]|r：提醒设置",
        ALERTS_STATUS = "提醒：%s · 提示音：%s · 范围：%s · 邀请密语：%s",
        ALERT_TEST_TEXT = "|cffc41e3aHeadHunter|r 提醒测试",
        ALERT_QUEUED = "战斗中：提醒会在脱战后显示。",
        SIGHTING_TEXT = "|cffff2020通缉|r · %s |cffff4040%s|r 出现了！",
        SIGHTING_AT_LARGE = "|cffff2020通缉|r · 在逃：|cffff4040%s|r 出现了！",
        SIGHTING_CHAT = "|cffff2020通缉|r %s |cffff4040%s|r 被目击（%s） · 击杀 %d",
        SIGHTING_CHAT_AT_LARGE = "|cffff2020通缉|r |cffff8040在逃|r |cffff4040%s|r 被目击（%s） · 曾为 %s · 已知击杀 %d",
        ACTIVITY_HEADLINE = "|cffff2020通缉|r · %s |cffff4040%s|r（%s）击杀了 %s，在 %s，%s",
        ACTIVITY_DETAILS = "击杀 %d · 通缉直至落网",
        ACTIVITY_CENTER = "|cffff2020通缉|r · %s |cffff4040%s|r 正在 %s 杀人",
        POSSE_JOINED_PIN = "你已加入追捕 %s 的队伍。已在 %s 设置路径点。",
        POSSE_JOINED_COORDS = "你已加入追捕 %s 的队伍。最后出现于 %s，坐标 %.1f, %.1f。",
        POSSE_JOINED = "你已加入追捕 %s 的队伍。最后出现于 %s。",
        LAYER_SAME = "|cff40ff40与你在同一分层|r",
        LAYER_DIFFERENT = "|cffff8000不同分层|r（你在 %d，击杀发生在 %d）：请求组队邀请",
        LAYER_TAG = "分层 %d",
        LAYER_CURRENT = "你的分层：%d（%d 秒前读取）",
        LAYER_UNKNOWN = "分层未知：选中或指向一个 NPC。",
        HELP_LAYER = "|cffffff00/hh layer|r：你当前的分层（读取自附近 NPC）",
        POSSE_WHISPER = "HeadHunter：我要加入追捕 %s 的队伍。请邀请我，我好切到你的分层。",
        POSSE_WHISPERED = "已请求 %s 组队邀请以切换分层。",
        HOTSPOT_LINE = "%s |cffff3300PvP|r |cffff9933%s|r，位于 %s：%s",
        HOTSPOT_BOTH = "≈%d %s 对阵 %d %s",
        HOTSPOT_ENEMIES = "≈%d %s 被目击在交战",
        HOTSPOT_OURS = "%d %s 在交战",
        HOTSPOT_DEATHS = "5 分钟内 %d 次死亡",
        HOTSPOT_CENTER = "%s |cffff3300PvP %s|r 在 %s！",
        HOTSPOT_HELP = "支援",
        HOTSPOT_IGNORE = "忽略",
        HOTSPOT_WAYPOINT = "已设置路径点到 %s 的战斗。",
        HOTSPOT_NAMES = " · 敌人：%s",
        HOTSPOT_FIGHTING = " · 交战中：%s",
        HOTSPOT_HELP_COMING = "|cff00ff00支援已在路上：|r%s 正赶往 %s 的战斗。",
        HOTSPOT_WHISPER = "HeadHunter：我来支援 %s 的战斗。请邀请我，我好切到你的分层。",
        HOTSPOT_STATUS = "%s %s：热度 %d（HeadHunter %d，敌人 %d，死亡 %d）",
        HOTSPOT_NONE = "过去 5 分钟内没有已知的 PvP 活动。",
        HELP_HOTSPOTS = "|cffffff00/hh hotspots|r：各区域的 PvP 活动（最近 5 分钟）",
        ENEMIES = "敌人",
        HEADHUNTERS = "HeadHunter",
        POSSE_UPDATE_CENTER = "追捕队：|cffff4040%s|r 在 %s 再次出手",
        POSSE_MEMBER_JOINED = "%s 加入了追捕 |cffff4040%s|r 的队伍。",
        POSSE_NONE = "没有进行中的追捕队。",
        HELP_POSSE = "|cffffff00/hh posse|r：谁在追捕哪个亡命徒",
        SIM_USAGE_DEATH = "/hh sim death \"<name>\" <level|skull> <CLASS> <RACE> [sex 2|3]",
        SIM_USAGE_SIGHTING = "/hh sim sighting \"<name>\" <level|skull> <CLASS> <RACE> [sex 2|3]",
        SIM_SEND_USAGE = "/hh sim send \"<killer>\" [kills 1-10] [level|skull] [CLASS] [RACE] [\"Zone\"]（WoW Forever 的名字有两个词，例如 \"Grim Reaper\"）",
        SIM_SEND_NEEDS_DEBUG = "/hh sim send 是调试工具：先打开 /hh debug on。",
        SIM_SENT = "已发送 %d 条模拟死亡：%s 位于 %s（测试）。",
        SIM_BAD_NAME = "此客户端不支持的名字：%s",
        SIM_DEATH = "%s 的模拟死亡（%s）。",
        SIM_SIGHTING = "%s 的模拟目击（%s）。",
        SIM_USAGE_DEMO = "/hh sim demo [clear]：用虚构数据填满每个页签供截图，或再清除",
        SIM_USAGE_CLEAR = "/hh sim clear：移除本角色的全部模拟死亡（sim send、spree、sim death）与测试击倒",
        SIM_CLEARED = "已移除测试数据：%d 条模拟报告、%d 条你的模拟死亡、%d 次测试击倒。请一并清理其他测试角色。",
        DEMO_DONE = "已加入演示数据：%d 次击杀、%d 场决斗、%d 条赏金事件。没有发送任何内容。|cffffff00/hh sim demo clear|r 可移除。",
        DEMO_CLEARED = "已移除演示数据（%d 条记录）。你的赏金已恢复原状。",
        DEMO_ERA_ONLY = "演示使用 Classic Era 的名字格式（名字-服务器），因此只能在 Classic Era 上运行。",
        HELP_MAP = "|cffffff00/hh map [on|off]|r：世界地图上的热点与通缉标记",
        JUSTICE_LINE = "|cff40ff40正法！|r %s |cffff4040%s|r（击杀 %d）被 %s 在 %s 击倒。",
        JUSTICE_CENTER = "|cff40ff40正法！|r 你击倒了 |cffff4040%s|r",
        JUSTICE_CENTER_POSSE = "|cff40ff40正法！|r |cffff4040%s|r 被 %s 击倒",
        JUSTICE_ANNOUNCED = "已向所有 HeadHunter 宣告。",
        JUSTICE_NOTHING = "没有等待宣告的击倒。",
        HELP_JUSTICE = "|cffffff00/hh justice|r：向所有 HeadHunter 宣告你击倒了通缉犯（Classic Era）",
        CATCH_NOT_WANTED = "%s 目前没有被通缉（或在一分钟内刚被抓）。",
        CATCH_NEEDS_DEBUG = "/hh catch 是调试工具：先打开 /hh debug on。",
        CATCHUP_STARTED = "正在向其他 HeadHunter 询问你错过的消息。",
        CATCHUP_BUSY = "追赶已在进行中。",
        CATCHUP_NO_ROUTE = "当前联系不到任何 HeadHunter（Classic Era：加入一个公会或队伍）。",
        HELP_CATCHUP = "|cffffff00/hh catchup|r：向其他 HeadHunter 索取你错过的报告与击倒",
        WINDOW_TITLE = "HeadHunter",
        SELF_WANTED_CENTER = "你被通缉了！",
        SELF_WANTED = "|cffff4040你被通缉了|r（%s）：%s，击杀 %d（官网榜单更新于 %s）。对方阵营的 HeadHunter 会来猎杀你。",
        HELP_SHOW = "|cffffff00/hh|r：打开 HeadHunter 窗口（/hh help：全部命令）",
        MINIMAP_HIDDEN = "小地图按钮已隐藏（/hh minimap 可再次显示）。",
        MINIMAP_SHOWN = "小地图按钮已显示。",
        HELP_MINIMAP = "|cffffff00/hh minimap|r：显示或隐藏小地图按钮",
        TOOLTIP_ON = "敌人鼠标提示的通缉行：开。",
        TOOLTIP_OFF = "敌人鼠标提示的通缉行：关。",
        HELP_TOOLTIP = "|cffffff00/hh tooltip [on|off]|r：敌人玩家鼠标提示上的通缉行",
        POSTER_KILL = "%s · %s · %s · %s",
        HELP_OPTIONS = "|cffffff00/hh options|r：打开 HeadHunter 选项页",
        MARKS_LINE = "%s|r 赏金：%s（总计 %d）",
        MARKS_RANK_UP = "|cffffd100你现在是 %s 了！|r",
        MARKS_NEXT = "再得 %d 即可成为 %s",
        HELP_MARKS = "|cffffff00/hh bounty|r：你的猎头等级与最近赏金",
        ACTIVITY_NOT_YOUR_LEVEL = "|cffaaaaaa不在你的等级段：不弹窗|r",
        DEBUG_LEVELS_OFF = "测试模式：等级窗口已关闭（所有等级都会弹通缉窗）。/hh debug levels on 恢复。",
        DEBUG_DUELS = "决斗：%d 场以下为新手。/hh debug duels off 恢复 5。",
        DEBUG_DUELS_USAGE = "用法：/hh debug duels <1-5|off>",
        DEBUG_LEVELS_ON = "等级窗口已开启：只有亡命徒等级 -5 至 +9 才弹通缉窗。",
        DEBUG_TOURS_ON = "赛事页签已显示（开发中）。/hh debug tours off 隐藏。",
        DEBUG_TOURS_OFF = "赛事页签已隐藏（开发中）。/hh debug tours on 显示。",
        DUELS_HEADER = "决斗，%s：%d 名决斗者",
        DUELS_YOU = "你：%s · %d 胜 %d 负",
        HELP_DUELS = "|cffffff00/hh duels|r：决斗，你阵营最强的决斗者",
        HELP_ONLINE = "|cffffff00/hh online|r：当前在线的 HeadHunter（按阵营）及其插件版本",
        ONLINE_REGION = "在线 HeadHunter：%d（联盟 %d，部落 %d），含你在内",
        ONLINE_GROUP = "你的公会与队伍中在线的 HeadHunter：%d，含你在内（Classic Era 无法统计更多）",
        ONLINE_VERSIONS = "插件版本：%s",
        ONLINE_SHORT = "%d 在线",
        ONLINE_SHORT_GROUP = "公会/队伍 %d 在线",
        ONLINE_SHORT_CAPPED = "%d+ 在线",
        ONLINE_CAPPED = "在线 HeadHunter 超过 %d。为节省流量，如此繁忙的区域不再计数。",
        HELP_ARENA = "|cffffff00/hh arena|r：你是否在赛事场地（古拉巴什竞技场、主城门口）？显示你的位置",
        ARENA_WHERE = "%s 位于 %s：%s",
        ARENA_IN_PIT = "|cff40ff40在竞技场场内|r",
        ARENA_IN_ARENA = "|cff40ff40在古拉巴什竞技场|r（看台）",
        ARENA_OUTSIDE = "|cffff8000不在赛事场地|r",
        VENUE_AT = "|cff40ff40在 %s|r",
        HELP_TOUR = "|cffffff00/hh tour [list|create|join <n>|leave <n>|here|cancel]|r：古拉巴什赛事",
        TOUR_CREATE_USAGE = "用法：/hh tour create \"Name\" <1v1|2v2|3v3|5v5> <single|robin> <bo1|bo3|bo5> <开赛倒计时分钟> [最低等级] [队伍上限]",
        TOUR_HEADER = "古拉巴什赛事：%d",
        TOUR_LINE = "  #%d  |cffffd100%s|r · %dv%d · %s · BO%d · %s · %d 级以上 · %d/%d 队 · 由 %s · %s%s",
        TOUR_STARTS_IN = "%d 分钟后开始",
        TOUR_STARTED = "已开始 %s",
        TOUR_JOINED_MARK = " · |cff40ff40已报名|r",
        TOUR_STATE_SCHEDULED = "已排期",
        TOUR_STATE_CHECKIN = "|cff40ff40签到|r",
        TOUR_STATE_RUNNING = "|cffff8000进行中|r",
        TOUR_STATE_FINISHED = "已结束",
        TOUR_STATE_CANCELLED = "|cffff4040已取消|r",
        TOUR_CANCELLED = "赛事 %s 已取消。",
        TOUR_NONE_OWN = "你没有正在举办的赛事。",
        TOUR_PICK = "哪一个？输入 /hh tour 里的编号。",
        TOUR_ORGANIZER_GONE = "赛事 %s 已取消：组织者已离开。",
        TOUR_REMIND_CENTER = "|cffffd100古拉巴什赛事|r %s 将在 %d 分钟后开始！",
        TOUR_REMIND_CHAT = "|cffffd100%s|r 将在 %d 分钟后于 %s 开始。去现场签到。",
        TOUR_REMIND_OPEN = "古拉巴什赛事 |cffffd100%s|r 将在 %d 分钟后开始，你仍可报名：/hh tour。",
        TOUR_CHECKIN_CENTER = "|cffffd100%s|r：签到！在 %s 点击“我到了”。",
        TOUR_CHECKIN_CHAT = "|cffffd100%s|r：签到已开放。前往 %s，%d 分钟内在赛事页签或 /hh tour here 点击“我到了”。",
        TOUR_CHECKIN_SENT = "已为 %s 提交签到。",
        TOUR_CHECKIN_DONE = "%s 的签到结束：%d 支队伍到场。对阵表已就绪。",
        TOUR_CHECKIN_TOO_FEW = "%s 的签到结束，不足 2 支队伍：已取消。",
        TOUR_RUNNING_NOTICE = "|cffffd100%s|r 的签到结束：比赛开始。",
        TOUR_CANCELLED_NOTICE = "赛事 %s 已取消。",
        TOUR_REPLY_HERE = "已为 %s 签到。留在竞技场。",
        TOUR_REPLY_NOTIN = "你没有报名参加 %s。",
        TOUR_ERR_NOT_CHECKIN = "当前没有开放给你的签到。",
        TOUR_ERR_NOT_REGISTERED = "你没有报名这场赛事。",
        TOUR_ERR_NOT_AT_VENUE = "签到需要亲临赛事场地（/hh arena 可显示你的位置）。",
        TOUR_ERR_VENUE = "那是对方阵营的场地。",
        TOUR_STATUS_HERE = "|cff40ff40已签到|r",
        TOUR_STATUS_CHECKIN_ME = "|cffff8000立即签到！|r",
        TOUR_NEXT_CHEST = "下一个竞技场宝箱在 %d 分钟后（服务器时间 %s）。",
        BOUNTY_POSTED = "悬赏已发布：%s 挂在 |cffff4040%s|r 身上，为期 %d 天。谁击倒他谁领赏；你用邮件支付。",
        BOUNTY_CLAIMED = "|cffffd100悬赏已被领取：|r %s，来自 %s，会邮寄过来。",
        BOUNTY_CLAIMED_CENTER = "|cffffd100悬赏已被领取！|r %s，目标 |cffff4040%s|r",
        BOUNTY_ANNOUNCE_QUESTION = "把你的领取宣告给所有 HeadHunter，好让海报主人知道吗？",
        BOUNTY_ANNOUNCED = "已向所有 HeadHunter 宣告你的领取。",
        BOUNTY_ANNOUNCE_NOTHING = "没有等待宣告的悬赏领取。",
        HELP_CLAIM = "|cffffff00/hh claim|r：向所有 HeadHunter 宣告你领取了悬赏（Classic Era）",
        BOUNTY_OWNER_CENTER = "|cffffd100你的悬赏被领取了：|r%s 击倒了 |cffff4040%s|r",
        BOUNTY_OWNER_CHAT = "|cffffd100你的悬赏被领取了：|r%s 击倒了 |cffff4040%s|r（%s，%s）。请到下一个邮箱付款。",
        BOUNTY_NO_CLAIM_LEVEL = "无赏金：%s 比你低 10 级以上（追杀低级也是偷袭）",
        BOUNTY_NO_CLAIM_REPEAT = "无赏金：你在 7 天内已对 %s 领取过悬赏。",
        BOUNTY_PAID = "|cffffd100%s 支付了 %s 的悬赏。|r",
        BOUNTY_PAY_SENT = "已把 %s 寄给 %s。谢谢付清！",
        BOUNTY_PAY_NO_GOLD = "金币不足，无法支付 %s 的悬赏。下一个邮箱会再次询问。",
        BOUNTY_PAY_NO_MAIL = "HeadHunter 未能写好邮件。请自行寄出金币。",
        SIGHTING_BULLY = "|cffff8040欺凌者|r · |cffff4040%s|r 出现了！",
        SIGHTING_CHAT_BULLY = "|cffff8040欺凌者|r |cffff4040%s|r 被目击（%s） · 击杀低级玩家 %d 次 · 耻辱柱",
        SIGHTING_DEADBEAT = "|cffff4040老赖|r · %s 出现了！",
        SIGHTING_CHAT_DEADBEAT = "|cffff4040老赖|r %s 在附近 · 未支付 %d 笔悬赏 · 耻辱柱",
        SIGHTING_CHAT_DEADBEAT_ENEMY = "|cffff4040老赖|r |cffff4040%s|r 被目击 · 欠自己阵营 %d 笔悬赏未付 · 击倒可拿赏金",
        SIGHTING_BOUNTY = "|cffffd100赏金|r · |cffff4040%s|r 出现了！",
        SIGHTING_CHAT_BOUNTY = "|cffffd100赏金|r |cffff4040%s|r 被目击（%s）",
    }

    for key, text in pairs(CN) do L[key] = text end

    -- Race and class words in the "Level, race, class" column and the poster
    ns.RaceDisplay = {
        Human = "人类", Dwarf = "矮人", NightElf = "暗夜精灵", Gnome = "侏儒",
        Draenei = "德莱尼", Orc = "兽人", Scourge = "亡灵", Tauren = "牛头人",
        Troll = "巨魔", BloodElf = "血精灵", HighmountainTauren = "高岭牛头人",
        VoidElf = "虚空精灵", LightforgedDraenei = "光铸德莱尼", DarkIronDwarf = "黑铁矮人",
        MagharOrc = "马格汉兽人", ZandalariTroll = "赞达拉巨魔",
        KulTiran = "库尔提拉斯人", Mechagnome = "机械侏儒",
        Dracthyr = "龙希尔", Worgen = "狼人", Goblin = "地精",
        Pandaren = "熊猫人", Nightborne = "夜之子", Highmountain = "高岭",
        SandTroll = "沙怒巨魔", ForestTroll = "森林巨魔", IceTroll = "冰巨魔",
        MountainTroll = "山地巨魔",
    }
    ns.ClassDisplay = {
        WARRIOR = "战士", PALADIN = "圣骑士", HUNTER = "猎人", ROGUE = "盗贼",
        PRIEST = "牧师", SHAMAN = "萨满祭司", MAGE = "法师", WARLOCK = "术士",
        DRUID = "德鲁伊", DEATHKNIGHT = "死亡骑士", MONK = "武僧",
        DEMONHUNTER = "恶魔猎手", EVOKER = "唤魔师",
    }
end
