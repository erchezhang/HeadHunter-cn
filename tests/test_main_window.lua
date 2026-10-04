-- HH-060: main window (WANTED, Bullies, My deaths) and the minimap button.

return function(T, H)
    local serial = 0

    -- `killer` kills n victims; the newest kill `ago` seconds ago
    local function Spree(ns, killer, n, opts)
        opts = opts or {}
        for i = 1, n do
            serial = serial + 1
            local victim = "Victim" .. serial .. "-Firemaw"
            local t = H.serverTime - (opts.ago or 0) - (n - i + 1) * 30
            ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = opts.victimLevel or 58 },
                killer = { key = killer, name = killer, level = 60, class = opts.class or "ROGUE", race = opts.race ~= false and (opts.race or "Orc") or nil },
                assists = {}, mapID = opts.mapID or 1436, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
        end
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    local function Names(rows)
        local names = {}
        for i, row in ipairs(rows) do
            -- Icons and colors off, and the realm (other realms keep it in the name)
            names[i] = row.name:gsub("^|T.-|t", ""):gsub("|A.-|a", ""):gsub(" |T.-|t$", ""):gsub("^ ", "")
                :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%-%a+$", "")
        end
        return table.concat(names, ",")
    end

    T.case("WANTED tab: rank, kills, last kill and zone, badges; three sort orders", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Big-Stonespine", 12, { ago = 3600 })          -- Outlaw, an hour ago
        Spree(ns, "Fresh-Stonespine", 5, { mapID = 1417 })        -- Ganker, just now
        Spree(ns, "Mid-Stonespine", 6, { ago = 600, class = "MAGE" })
        Settle()
        local rows = ns.MainWindow.Rows("wanted", "rank")
        T.eq(Names(rows), "Big,Mid,Fresh", "by rank, then kills")
        T.ok(rows[1].rank:find("Outlaw", 1, true) ~= nil, "rank text")
        T.eq(rows[1].kills, "12", "kills")
        T.ok(rows[1].lastKill:find("1 h", 1, true) ~= nil and rows[1].lastKill:find("Westfall", 1, true) ~= nil,
            "last kill: " .. rows[1].lastKill)
        T.ok(rows[1].badges:find("Gunslinger", 1, true) ~= nil, "badges: " .. rows[1].badges)
        T.eq(Names(ns.MainWindow.Rows("wanted", "kills")), "Big,Mid,Fresh", "by kills")
        T.eq(Names(ns.MainWindow.Rows("wanted", "last")), "Fresh,Mid,Big", "by last kill")
        T.ok(rows[2].name:find("|c", 1, true) ~= nil, "class colored name")
    end)

    T.case("Bullies: every coward, WANTED or not, most coward kills first", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Bully-Stonespine", 5, { victimLevel = 20 })       -- WANTED coward
        Spree(ns, "Sneak-Stonespine", 2, { victimLevel = 20 })       -- coward, not WANTED
        Spree(ns, "Fair-Stonespine", 5, { victimLevel = 60 })        -- WANTED, fair fights
        Settle()
        local rows = ns.MainWindow.Rows("bullies")
        T.eq(Names(rows), "Bully,Sneak", "cowards only")
        T.eq(rows[1].coward, "5", "coward kills")
        T.ok(rows[1].status:find("WANTED", 1, true) ~= nil, "WANTED now")
        T.eq(rows[2].status, "|cffaaaaaaNot WANTED|r", "past status: no counts")
        T.ok(rows[2].desc:find("Orc", 1, true) ~= nil, "who")
    end)

    T.case("My deaths: our own deaths, newest first", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim death Older-Stonespine 60 ROGUE Orc")
        H.serverTime = H.serverTime + 120
        H.Slash("sim death Newer-Stonespine skull WARRIOR Troll")
        local rows = ns.MainWindow.Rows("deaths")
        T.eq(Names(rows), "Newer,Older", "newest first")
        T.ok(rows[1].desc:find("UI-TargetingFrame-Skull", 1, true) ~= nil, "skull icon, not ??")
        T.ok(rows[1].kind ~= "", "kill type")
        T.eq(rows[1].zone, "Elwynn Forest", "zone")
    end)

    T.case("My deaths and bounty posting: only the character we play", function()
        local ns = H.Boot({ client = "era" })
        local function Death(victim, killer, t)
            ns.db.deaths[#ns.db.deaths + 1] = { id = victim .. ":" .. t, t = t, victim = { key = victim },
                killer = { key = killer, name = killer, level = 30, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = 1429, confidence = "exact" }
        end
        Death("Vati-Firemaw", "Brute-Stonespine", H.serverTime - 120)
        Death("Tovik-Firemaw", "Sneak-Firemaw", H.serverTime - 60)
        T.eq(Names(ns.MainWindow.Rows("deaths")), "Brute", "our deaths only")
        T.eq(#ns.Bounties:PostableTargets(), 1, "bounty only on our own killers")
        H.units.player.name = "Tovik"
        T.eq(Names(ns.MainWindow.Rows("deaths")), "Sneak", "the other character's deaths")
        T.eq(#ns.Bounties:PostableTargets(), 1, "and its own killers")
        T.noErrors()
    end)

    T.case("search on WANTED, Bullies and My deaths, one search per tab", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Bully-Stonespine", 5, { victimLevel = 20 })
        Spree(ns, "Sneak-Stonespine", 2, { victimLevel = 20 })
        H.Slash("sim death Older-Stonespine 60 ROGUE Orc")
        H.serverTime = H.serverTime + 120
        H.Slash("sim death Newer-Stonespine 60 WARRIOR Troll")
        Settle()
        local M = ns.MainWindow
        T.eq(Names(M.Rows("bullies", nil, nil, nil, "SNE")), "Sneak", "Bullies, any case")
        T.eq(Names(M.Rows("deaths", nil, nil, nil, "old")), "Older", "My deaths: by the killer")
        T.eq(Names(M.Rows("wanted", "rank", nil, nil, "BUL")), "Bully", "WANTED, any case")
        T.eq(#M.Rows("wanted", "rank", nil, nil, "zzz"), 0, "WANTED: nobody by that name")

        M:Toggle()
        M:SelectTab("bullies")
        T.ok(_G.HeadHunterMainFrame.search:IsShown(), "box on Bullies")
        M:SetSearch("bul")
        T.eq(Names(M.shownRows), "Bully", "filtered")
        M:SelectTab("deaths")
        T.ok(_G.HeadHunterMainFrame.search:IsShown(), "box on My deaths")
        T.eq(M:Search(), nil, "My deaths has its own, empty search")
        T.eq(#M.shownRows, 2, "all deaths")
        M:SetSearch("zzz")
        T.eq(_G.HeadHunterMainFrame.empty.shownText, "Nobody called zzz", "nobody")
        M:SelectTab("bullies")
        local box = _G.HeadHunterMainFrame.search
        T.eq(M:Search(), "bul", "Bullies kept its search")
        T.eq(box.shownText, "bul", "and the box shows it")
        T.eq(box.clear.shown, true, "with the x to clear it")
        box.clear.scripts.OnClick(box.clear)
        T.eq(M:Search(), nil, "the x clears the search")
        T.eq(box.shownText, "", "and the box")
        T.eq(box.clear.shown, false, "the x goes")
        T.eq(#M.shownRows, #M.Rows("bullies"), "everyone again")
        M:SelectTab("marks")
        T.ok(not _G.HeadHunterMainFrame.search:IsShown(), "no box on My bounty")
        M:SetSearch("x")
        T.eq(M:Search(), nil, "no search there")
        T.noErrors()
    end)

    T.case("My deaths: a 3 vs 1 shows as Gang, even if saved as fair before", function()
        local ns = H.Boot({ client = "era" })
        table.insert(ns.db.deaths, { id = "Vati-Firemaw:1", t = H.serverTime - 60, classification = "fair",
            victim = { key = "Vati-Firemaw", level = 30 },
            killer = { key = "Gank-Stonespine", level = 30, class = "ROGUE", race = "Orc" },
            assists = { { key = "Pal-Stonespine", level = 30 }, { key = "Buddy-Stonespine", level = 31 } },
            mapID = 1429 })
        local row = ns.MainWindow.Rows("deaths")[1]
        T.eq(row.kind, "|cffcc66ffGang|r (3 vs 1)", "kind")
    end)

    T.case("the window warns on Forever that saved data resets on reload, on every tab", function()
        H.Boot({ client = "forever" })
        H.Slash("")
        local note = _G.HeadHunterMainFrame.forever
        T.ok(note:IsShown(), "shown on Forever")
        T.ok(note.text.shownText:find("saved data resets on reload", 1, true) ~= nil, "text")
        H.Boot({ client = "era" })
        H.Slash("")
        T.ok(not _G.HeadHunterMainFrame.forever:IsShown(), "not on Era")
        T.noErrors()
    end)

    T.case("Busted: the WANTED players caught, newest first, with the mark and who busted them", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 5)
        Spree(ns, "Brute-Stonespine", 5)
        Settle()
        ns.Justice:Record(ns.Wanted:ByKey("Gank-Stonespine"), "test")
        H.Advance(120)
        H.serverTime = H.serverTime + 120
        ns.Justice:Record(ns.Wanted:ByKey("Brute-Stonespine"), "test", "Hunter-Firemaw")
        Settle()

        local rows = ns.MainWindow.Rows("busted")
        local plain = {}
        for i, row in ipairs(rows) do plain[i] = row.plain end
        T.eq(table.concat(plain, ","), "Brute-Stonespine,Gank-Stonespine", "newest first")
        T.ok(rows[1].name:find(ns.MainWindow.MARK_ICON, 1, true) == 1, "the HeadHunter mark first")
        T.eq(rows[1].byPlain, "Hunter", "who landed the blow")
        T.ok(rows[2].by:find(ns.Utils.ClassIcon(ns.Utils.UnitClass("player")), 1, true) ~= nil,
            "our own catch: our race and class icons")
        T.ok(rows[1].tooltip[2]:find("Busted", 1, true) ~= nil, "tooltip: " .. rows[1].tooltip[2])
        T.eq(#ns.MainWindow.Rows("busted", nil, nil, nil, "gan"), 1, "search by name")
        T.noErrors()
    end)

    T.case("five sections with their own sub-tabs; a section opens on its last view", function()
        local ns = H.Boot({ client = "era" })
        local M = ns.MainWindow
        H.Slash("")
        local f = _G.HeadHunterMainFrame
        local ids = {}
        for i, tab in ipairs(f.tabs.buttons) do ids[i] = tab.id end
        T.eq(table.concat(ids, ","), "board,busted,duels,events,me", "the top tabs")
        T.ok(f.subtabs.board:IsShown(), "WANTED and Bullies under the board")
        T.ok(not f.subtabs.events:IsShown(), "only the section's own sub-tabs")
        M:SelectSection("me")
        T.eq(select(1, M:Current()), "deaths", "Me opens on My deaths")
        M:SelectTab("marks")
        M:SelectSection("events")
        T.eq(select(1, M:Current()), "ongoing", "Events opens on Ongoing")
        T.ok(f.subtabs.events:IsShown(), "Ongoing and Upcoming")
        M:SelectSection("me")
        T.eq(select(1, M:Current()), "marks", "back on the view last shown")
        M:SelectTab("tours")
        T.eq(select(1, M:Current()), "ongoing", "the old Tournaments tab is the Events tab")
        T.noErrors()
    end)

    T.case("the window: /hh opens it, tabs, sorting, live refresh, row click", function()
        local ns = H.Boot({ client = "era" })
        local M = ns.MainWindow
        H.Slash("")
        T.ok(M:IsShown(), "open")
        T.eq(#M.shownRows, 0, "empty")
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        H.Advance(0.2)
        T.eq(#M.shownRows, 1, "refreshed when the WANTED list changed")

        M:SelectTab("deaths")
        T.eq(select(1, M:Current()), "deaths", "tab")
        local tabs = _G.HeadHunterMainFrame.tabs.buttons
        T.eq(#tabs, 5, "five sections")
        T.ok(tabs[5].selected and not tabs[1].selected, "My deaths: the Me section drawn selected")
        T.eq(tabs[1].point[2], _G.HeadHunterMainFrame.header, "in the header, like the website's menu")
        T.eq(#M.shownRows, 0, "no deaths of ours")
        M:SelectTab("wanted")
        M:SetSort("kills")
        T.eq(select(2, M:Current()), "kills", "sort")

        M:OnRowClick(M.shownRows[1])
        T.eq(ns.Poster:ShownId(), "Gank-Stonespine", "the row opened the poster")
        local at = _G.HeadHunterPosterFrame.point
        T.ok(at[1] == "CENTER" and at[2] == _G.HeadHunterMainFrame and at[3] == "CENTER",
            "in the middle of the main window")
        H.Slash("")
        T.ok(not M:IsShown(), "closed")
        T.noErrors()
    end)

    T.case("WANTED tab: one list per faction, no race counts as the enemy", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Grubnak-Stonespine", 5)
        Spree(ns, "Brenna-Stonespine", 5, { race = "Dwarf" })
        Spree(ns, "Nameless-Stonespine", 5, { race = false })
        Settle()
        local M = ns.MainWindow
        T.eq(Names(M.Rows("wanted", "rank", nil, "Horde")), "Nameless,Grubnak", "Horde list, newest kill first")
        T.eq(Names(M.Rows("wanted", "rank", nil, "Alliance")), "Brenna", "Alliance list")
        T.eq(#M.Rows("wanted", "rank"), 3, "no faction: everyone")
    end)

    T.case("WANTED tab: WANTED first, then outlaws at large until the list has 25 rows", function()
        local ns = H.Boot({ client = "era" })
        local DAY = 86400
        Spree(ns, "Fresh-Stonespine", 5)
        Spree(ns, "Older-Stonespine", 5, { ago = 9 * DAY })
        Spree(ns, "Oldest-Stonespine", 5, { ago = 12 * DAY })
        Settle()
        local M = ns.MainWindow
        local rows = M.Rows("wanted", "rank", nil, "Horde")
        T.eq(Names(rows), "Fresh,Older,Oldest", "WANTED first, then at large newest first")
        T.ok(rows[2].rank:find("At large", 1, true) ~= nil, "marked at large")
        T.eq(rows[2].atLarge, true, "row flag")
        T.ok(rows[2].tooltip[3]:find("never busted", 1, true) ~= nil, "tooltip: " .. rows[2].tooltip[3])

        M.BOARD_MIN = 2
        T.eq(Names(M.Rows("wanted", "rank", nil, "Horde")), "Fresh,Older", "filled up to the minimum only")
        M.BOARD_MIN = 1
        Spree(ns, "Second-Stonespine", 5)
        Settle()
        T.eq(#M.Rows("wanted", "rank", nil, "Horde"), 2, "more WANTED than the minimum: all of them, no at large")
    end)

    T.case("Bounty board and Duels open on All; WANTED and Bullies share a choice, Duels has its own", function()
        local ns = H.Boot({ client = "era" })
        local M = ns.MainWindow
        M:Toggle()
        local board = _G.HeadHunterMainFrame.faction
        T.eq(#board.buttons, 3, "All, Alliance and Horde")
        T.eq(board.value, M.ALL, "All lit")
        T.eq(M:ListFaction(), nil, "All: both factions")
        M:SwitchFaction()
        T.eq(M:BoardFaction(), "Alliance", "switched to Alliance")
        M:SelectTab("bullies")
        T.eq(board.shown, true, "the switch stays on Bullies")
        T.eq(_G.HeadHunterMainFrame.search.point[2], board, "the search left of it")
        T.eq(M:ListFaction(), "Alliance", "Bullies keeps the board's faction")
        M:SwitchFaction()
        T.eq(M:BoardFaction(), "Horde", "then Horde")
        M:SwitchFaction()
        T.eq(M:BoardFaction(), M.ALL, "then All again")
        M:SwitchFaction()
        M:SelectTab("duels")
        T.eq(board.value, M.ALL, "Duels has its own choice")
        T.eq(M:ListFaction(), nil, "Duels: All")
        M:SwitchFaction()
        T.eq(M:DuelFaction(), "Alliance", "Duels switched")
        T.eq(M:BoardFaction(), "Alliance", "the board unchanged")
        M:SelectTab("deaths")
        T.eq(M:ListFaction(), nil, "no list on other tabs")
        M:SelectTab("shame")
        T.eq((M:Current()), "bullies", "the old Hall of Shame tab opens Bullies")
        T.noErrors()
    end)

    T.case("Bounty board sub-tabs: what each one lists, on hover", function()
        local ns = H.Boot({ client = "era", tooltip = "script" })
        local M = ns.MainWindow
        M:Toggle()
        local buttons = _G.HeadHunterMainFrame.subtabs.board.buttons
        T.eq(#buttons, 3, "WANTED, Bullies and Deadbeats")
        for i, view in ipairs({ "wanted", "bullies", "deadbeats" }) do
            H.tooltipLines = {}
            buttons[i].scripts.OnEnter(buttons[i])
            T.eq(H.tooltipLines[1], ns.L[M.TAB_TIPS[view]], view .. " explained")
        end
        T.ok(ns.L.TIP_TAB_WANTED:find("small on purpose", 1, true) ~= nil, "WANTED: why a gold bounty is small")
        T.noErrors()
    end)

    T.case("Bullies: one faction's bullies, or both", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Grubnak-Stonespine", 5)
        Spree(ns, "Brenna-Stonespine", 5, { race = "Dwarf" })
        Settle()
        for _, id in ipairs({ "Grubnak-Stonespine", "Brenna-Stonespine" }) do
            local entry = ns.Wanted:Get(id)
            entry.badges = entry.badges or {}
            entry.badges.coward = true
        end
        local M = ns.MainWindow
        T.eq(#M.Rows("bullies"), 2, "both factions")
        T.eq(#M.Rows("bullies", nil, nil, "Alliance"), 1, "Alliance only")
        T.ok(M.Rows("bullies", nil, nil, "Horde")[1].plain:find("Grubnak", 1, true) ~= nil, "Horde only")
    end)

    T.case("a name in the lists: faction crest, race icon, the name, then the class icon", function()
        local M = H.Boot({ client = "era" }).MainWindow
        local named = M.Named("Sneak", { race = "Orc", sex = 2, class = "ROGUE" })
        T.ok(named:find("^|TInterface\\TargetingFrame\\UI%-PVP%-Horde:14:14:0:0:64:64:2:40:1:40|t|A:raceicon%-orc%-male") ~= nil,
            "Horde crest, then the race: " .. named)
        T.ok(named:find("|a |c%x+Sneak|r |TInterface\\WorldStateFrame\\ICONS%-CLASSES") ~= nil,
            "then the name in class color and the class icon: " .. named)
        T.ok(M.Named("Knight", { race = "Human", faction = "Horde" }):find("UI%-PVP%-Horde") ~= nil, "its own faction first")
        T.ok(M.Named("Nameless", {}):find("UI%-PVP%-Horde") ~= nil, "no race: the enemy's crest")
    end)

    T.case("race icons: atlas per client, gender, Undead's atlas name, unknown race", function()
        local U = H.Boot({ client = "era" }).Utils
        T.eq(U.RaceIcon("Orc", 3), "|A:raceicon-orc-female:14:14|a", "era, female")
        T.eq(U.RaceIcon("Scourge", 2), "|A:raceicon-undead-male:14:14|a", "Scourge is undead")
        T.eq(U.RaceIcon("NightElf"), "|A:raceicon-nightelf-male:14:14|a", "unknown gender: male")
        T.eq(U.RaceIcon(nil, 2), "", "unknown race: nothing")
        T.eq(U.RaceName("NightElf"), "Night Elf", "race names as players know them")
        T.eq(U.RaceName("Scourge"), "Undead", "Scourge is shown as Undead")
        T.eq(U.RaceName("Orc"), "Orc", "others unchanged")
        U = H.Boot({ client = "forever" }).Utils
        T.eq(U.RaceIcon("Orc", 2), "|A:raceicon128-orc-male:14:14|a", "forever: larger art")
    end)

    T.case("rows start with the faction and race icons; hovering shows the outlaw's details", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        local row = ns.MainWindow.Rows("wanted", "rank")[1]
        T.ok(row.name:find("|TInterface\\TargetingFrame\\UI-PVP-Horde", 1, true) == 1, "faction crest first: " .. row.name)
        T.ok(row.name:find("|t|A:raceicon-orc-male", 1, true) ~= nil, "then the race: " .. row.name)
        local tip = table.concat(row.tooltip, "\n")
        T.ok(row.tooltip[1]:find("raceicon", 1, true) ~= nil, "title with icon")
        T.ok(tip:find("60 Orc Rogue", 1, true) ~= nil, "who")
        T.ok(tip:find("WANTED|r · ", 1, true) ~= nil and tip:find("5 kills", 1, true) ~= nil, "status")
        T.ok(tip:find("Last kill just now in Westfall", 1, true) ~= nil, "last kill")
        T.ok(tip:find("Kills known: 5|r", 1, true) ~= nil, "history: " .. tip)

        H.Slash("sim death Gank-Stonespine 60 ROGUE Orc 3")
        local death = ns.MainWindow.Rows("deaths")[1]
        T.ok(death.name:find("raceicon-orc-female", 1, true) ~= nil, "the killer's gender from the death")
        T.ok(death.tooltip[2]:find("^Killed you") ~= nil, "this death first")
        T.ok(table.concat(death.tooltip, "\n"):find("Kills known", 1, true) ~= nil, "then the outlaw's record")
    end)

    T.case("minimap button: shown by default, /hh minimap hides it (remembered)", function()
        local ns = H.Boot({ client = "era", minimap = true })
        T.ok(ns.MinimapButton:IsShown(), "shown")
        H.Slash("minimap")
        T.ok(not ns.MinimapButton:IsShown(), "hidden")
        T.eq(ns.db.settings.minimap.hidden, true, "remembered")
        local x, y = ns.MinimapButton.Offset(90, 80)
        T.ok(math.abs(x) < 1e-9 and math.abs(y - 80) < 1e-9, "90 degrees: straight up")
        T.noErrors()
    end)

    T.case("no minimap frame: no button, no error", function()
        local ns = H.Boot({ client = "forever" })
        T.ok(not ns.MinimapButton:IsShown(), "none")
        T.noErrors()
    end)

    T.case("every list tab has a text for when it is empty", function()
        local ns = H.Boot({ client = "forever" })
        for _, tab in ipairs(ns.MainWindow.TABS) do
            local key = "EMPTY_" .. tab:upper()
            T.ok(rawget(ns.L, key) ~= nil, key)
        end
    end)
end
