-- M9 Gurubashi Tournament: HH-100 spike tools, HH-102 arena and venues, HH-105
-- brackets, and the website's tournaments in game (WEB-080: made and joined only on the
-- website, read only here). Made-up players only.

return function(T, H)
    local function Ids(list, field)
        local out = {}
        for i, item in ipairs(list) do out[i] = tostring(field and item[field] or item) end
        return table.concat(out, ",")
    end

    -------------------------------------------------
    -- HH-100 spike tools
    -------------------------------------------------

    T.case("a ping from the other faction is printed; their other records stay dropped", function()
        local ns = H.Boot({ client = "forever" })
        H.Slash("debug on")
        H.Deliver(ns.Protocol.Pack("H", "T", { "12:00:00" }), "Hordie")
        T.ok(H.Printed("Sync ping from Hordie %[Horde%]"), "cross-faction ping shown with the faction")
        T.ok(H.Printed("Other faction %(Horde%) message from Hordie"), "debug line")
        T.eq(ns.Transport.stats.crossFaction, 1, "counted")
        T.noErrors()
    end)

    T.case("/hh sync whisper sends an addon whisper ping", function()
        H.Boot({ client = "era" })
        H.Slash('sync whisper "Hordie"')
        for _ = 1, 5 do H.Advance(1) end
        local whisper
        for _, m in ipairs(H.sent) do
            if m.chatType == "WHISPER" and m.message:find("^1AT:whisper") then whisper = m end
        end
        T.ok(whisper ~= nil, "whisper ping sent")
        T.eq(whisper and whisper.target, "Hordie", "to the name given")
        H.Slash("sync whisper")
        T.ok(H.Printed("Usage: /hh sync whisper"), "usage")
        T.noErrors()
    end)

    -------------------------------------------------
    -- HH-102 arena presence
    -------------------------------------------------

    T.case("arena: pit, stands, outside, other zone", function()
        local ns = H.Boot({ client = "era" })
        local A = ns.Arena
        T.eq(A.Where(1434, 0.3055, 0.4785), "pit", "center")
        T.eq(A.Where(1434, 0.312, 0.479), "pit", "east edge 31.2, 47.9")
        T.eq(A.Where(1434, 0.306, 0.489), "pit", "south edge 30.6, 48.9")
        T.eq(A.Where(1434, 0.299, 0.476), "pit", "west edge 29.9, 47.6")
        T.eq(A.Where(1434, 0.305, 0.468), "pit", "north edge 30.5, 46.8")
        T.eq(A.Where(1434, 0.316, 0.4785), "arena", "stands east of the pit")
        T.eq(A.Where(1434, 0.305, 0.492), "arena", "south seats start 30.5, 49.2")
        T.eq(A.Where(1434, 0.297, 0.476), "arena", "west seats start 29.7, 47.6")
        T.eq(A.Where(1434, 0.306, 0.465), "arena", "north seats start 30.6, 46.5")
        T.eq(A.Where(1434, 0.396, 0.480), nil, "outside")
        T.eq(A.Where(1429, 0.3055, 0.4785), nil, "another zone")
        T.eq(A.Where(1434, nil, nil), nil, "no position")

        H.playerMap, H.playerX, H.playerY = 1434, 0.306, 0.480
        T.eq(A:PlayerWhere(), "pit", "player in the pit")
        H.Slash("arena")
        T.ok(H.Printed("Stranglethorn Vale at 30%.6, 48%.0: .*in the arena pit"), "/hh arena")
        H.playerX = 0.5
        T.ok(not A:InArena(), "left")
        T.noErrors()
    end)

    -------------------------------------------------
    -- WEB-080 the website's tournaments, read only
    -------------------------------------------------

    local function Data(tournaments)
        return {
            format_version = 1,
            generated_at = H.serverTime - 60,
            worlds = { ["era|eu|Firemaw"] = { generated_at = H.serverTime - 60, tournaments = tournaments } },
        }
    end

    local function Tournament(overrides)
        local t = {
            id = "gatebrawl", name = "Gate Brawl", venue = "orgrimmar", format = "1v1", best_of = 3,
            faction = "horde", min_level = 50, max_level = 59, places = 16,
            starts_at = H.serverTime + 5400, locks_at = H.serverTime + 1800, signups_closed = false,
            host = { name = "Tovik", realm = "Firemaw" }, organizers = {},
            players = { { entrant = "p1", name = "Grimtusk" }, { entrant = "p2", name = "Marla" } }, teams = {},
        }
        for k, v in pairs(overrides or {}) do t[k] = v end
        return t
    end

    T.case("the website's tournaments: details, soonest first, over ones left out", function()
        local ns = H.Boot({ client = "era", siteData = Data({
            Tournament({ id = "later", name = "Later", starts_at = H.serverTime + 90000, locks_at = H.serverTime + 86400 }),
            Tournament(),
            Tournament({ id = "over", name = "Over", starts_at = H.serverTime - 8 * 3600, locks_at = H.serverTime - 9 * 3600 }),
            Tournament({ id = "teams", name = "Pit Fight", venue = "gurubashi", format = "2v2", best_of = 1,
                final_best_of = 3, faction = false, min_level = 60, max_level = 60, places = false,
                teams = { { entrant = "t1" }, { entrant = "t2" }, { entrant = "t3" } }, players = {},
                starts_at = H.serverTime + 7200, locks_at = H.serverTime + 3600 }),
        }) })
        local TN = ns.Tournaments
        T.eq(Ids(TN:List(), "id"), "gatebrawl,teams,later", "soonest first, the one that is over left out")
        local gate, pit = TN:List()[1], TN:List()[2]
        T.eq(gate.teamSize, 1, "1v1")
        T.eq(TN.Series(gate), "Best of 3", "series")
        T.eq(TN.Series(pit), "Best of 1, final Best of 3", "a longer final")
        T.eq(TN.Levels(gate), "50-59", "level band")
        T.eq(TN.Levels(pit), "60", "one level")
        T.eq(TN.Entrants(gate), "2/16", "players of the places")
        T.eq(TN.Entrants(pit), "3", "teams, no limit")
        T.eq(TN.Where(pit), "Gurubashi Arena (Stranglethorn Vale)", "venue name")
        T.eq(TN.Start(gate, H.serverTime), "in 1 h 30 min", "starts in")
        T.noErrors()
    end)

    T.case("Join event until we sign up or sign-up closes, then Event link; Events counts the upcoming ones", function()
        H.Install({ client = "era" })
        local me = H.units.player.name
        local ns = H.Boot({ client = "era", siteData = Data({
            Tournament(),
            Tournament({ id = "mine", players = { { entrant = "p1", name = me, realm = "Firemaw" } } }),
            Tournament({ id = "teams", format = "2v2", players = {},
                teams = { { entrant = "t1", members = { { entrant = "p2", name = me, realm = "Firemaw" } } } } }),
            Tournament({ id = "shut", signups_closed = true }),
            Tournament({ id = "live", starts_at = H.serverTime - 600, locks_at = H.serverTime - 4200 }),
        }) })
        local TN, MW = ns.Tournaments, ns.MainWindow
        T.eq(MW.EventLinkJoins(TN:Get("gatebrawl")), true, "open and not in it: Join event")
        T.eq(TN.Joined(TN:Get("mine")), true, "signed up alone")
        T.eq(TN.Joined(TN:Get("teams")), true, "signed up in a team")
        T.eq(MW.EventLinkJoins(TN:Get("mine")), false, "in it: Event link")
        T.eq(MW.EventLinkJoins(TN:Get("shut")), false, "sign-up closed: Event link")
        T.eq(TN:UpcomingCount(), 4, "the running one does not count")
        T.noErrors()
    end)

    T.case("/hh sim event adds a test event being played now or later, only with HeadHunter_Dev", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim event ongoing")
        T.ok(H.Printed("need the HeadHunter_Dev addon"), "refused without the dev addon")
        T.eq(#ns.Tournaments:List(), 0, "nothing added")

        ns = H.Boot({ client = "era", dev = { trust = {} } })
        H.Slash("sim event ongoing")
        H.Slash("sim event upcoming")
        T.eq(ns.Tournaments:OngoingCount(), 1, "one being played")
        T.eq(ns.Tournaments:UpcomingCount(), 1, "one to come")
        T.ok(H.Printed("Test Event 1"), "told what was added")
        H.Slash("sim event clear")
        T.ok(H.Printed("Removed 2 test event"), "both gone")
        T.eq(#ns.Tournaments:List(), 0, "the list is empty again")
        T.noErrors()
    end)

    T.case("state: open, sign-ups closed, locked, running until the last day is over", function()
        local ns = H.Boot({ client = "era" })
        local TN = ns.Tournaments
        local t = { startsAt = 1000, locksAt = 400, signupsClosed = false, days = { 1000, 90000 } }
        T.eq(TN.State(t, 100), "open", "open")
        t.signupsClosed = true
        T.eq(TN.State(t, 100), "closed", "closed")
        T.eq(TN.State(t, 500), "locked", "locked")
        T.eq(TN.State(t, 1000), "running", "running")
        T.eq(TN.LastStart(t), 90000, "the last day")
        T.noErrors()
    end)

    T.case("Events lists them, ongoing apart from upcoming; /hh tour prints them", function()
        local ns = H.Boot({ client = "era", siteData = Data({ Tournament(),
            Tournament({ id = "live", name = "Live Brawl", starts_at = H.serverTime - 600, locks_at = H.serverTime - 4200 }) }) })
        local rows = ns.MainWindow.Rows("upcoming")
        T.eq(#rows, 1, "one to come")
        local row = rows[1]
        T.eq(row.name .. "|" .. row.format .. "|" .. row.series .. "|" .. row.level .. "|" .. row.teams,
            "Gate Brawl|1v1|Best of 3|50-59|2/16", "columns")
        T.ok(row.status:find("Open") ~= nil, "status")
        T.eq(row.event, "gatebrawl", "a click opens the event")
        T.eq(row.id, nil, "no poster")
        local ongoing = ns.MainWindow.Rows("ongoing")
        T.eq(#ongoing, 1, "one being played")
        T.eq(ongoing[1].name, "Live Brawl", "the running one")
        H.Slash("tour")
        T.ok(H.Printed("Tournaments from the website: 2"), "header")
        T.ok(H.Printed("Gate Brawl.*1v1.*Best of 3.*2/16.*by Tovik"), "the line")
        T.noErrors()
    end)

    T.case("the bracket is the website's: the same draw, winners on, final series, 3rd place", function()
        local ns = H.Boot({ client = "era" })
        local B = ns.Brackets
        -- The website's own test (TournamentTest "draws round 1 exactly as the addon does")
        local seeds = B.Seed({ "Tovik-Firemaw", "Marla-Firemaw", "Grimtusk-Firemaw", "Ashfang-Firemaw", "Moonsong-Firemaw" }, nil, 123456789)
        T.eq(Ids(seeds), "Ashfang-Firemaw,Tovik-Firemaw,Marla-Firemaw,Moonsong-Firemaw,Grimtusk-Firemaw", "same seeds")
        local rounds = B.Build(seeds, {}, { bestOf = 3, finalBestOf = 5 })
        T.eq(#rounds, 3, "8 places: 3 rounds")
        local r1 = rounds[1].matches
        T.eq(r1[1].a .. "/" .. tostring(r1[1].b), "Ashfang-Firemaw/nil", "a bye")
        T.eq(r1[2].a .. "/" .. r1[2].b, "Moonsong-Firemaw/Grimtusk-Firemaw", "the one real match")
        T.eq(rounds[2].matches[1].a, "Ashfang-Firemaw", "the bye went on")
        T.eq(rounds[3].bestOf, 5, "the final's series")

        rounds = B.Build(seeds, { { round = 1, match = 2, a = "Moonsong-Firemaw", b = "Grimtusk-Firemaw", winsA = 1, winsB = 2 } },
            { bestOf = 3 })
        T.eq(rounds[2].matches[1].b, "Grimtusk-Firemaw", "the winner went on")
        local stale = B.Build(seeds, { { round = 1, match = 2, a = "Someone-Else", b = "Grimtusk-Firemaw", winsA = 2, winsB = 0 } }, {})
        T.eq(stale[1].matches[2].winner, nil, "a result for other entrants does not count")

        local four = B.Build({ "A", "B", "C", "D" }, {
            { round = 1, match = 1, a = "A", b = "D", winsA = 1, winsB = 0 },
            { round = 1, match = 2, a = "B", b = "C", winsA = 0, winsB = 0, forfeit = "a" },
        }, { thirdPlace = true })
        local third = four[2].matches[2]
        T.ok(third.thirdPlace, "match 2 of the final round")
        T.eq(third.a .. "/" .. third.b, "D/B", "the semifinal losers")
        T.ok(not B.NextIsPlayed(four, 1, 1), "nothing played after the semifinals")
        four = B.Build({ "A", "B", "C", "D" }, {
            { round = 1, match = 1, a = "A", b = "D", winsA = 1, winsB = 0 },
            { round = 1, match = 2, a = "B", b = "C", winsA = 1, winsB = 0 },
            { round = 2, match = 2, a = "D", b = "C", winsA = 1, winsB = 0 },
        }, { thirdPlace = true })
        T.ok(B.NextIsPlayed(four, 1, 1), "a semifinal is locked once the 3rd place match has a result")
        T.noErrors()
    end)

    T.case("an event opens on the round being played, with who meets who and the link to copy", function()
        local ns = H.Boot({ client = "era", siteData = Data({ Tournament({
            starts_at = H.serverTime - 600, locks_at = H.serverTime - 4200, best_of = 1,
            url = "https://headhunterwow.com/tournaments/gatebrawl?tab=bracket",
            players = { { entrant = "p1", name = "Grimtusk", realm = "Firemaw" }, { entrant = "p2", name = "Marla", realm = "Firemaw" },
                { entrant = "p3", name = "Tovik", realm = "Firemaw" }, { entrant = "p4", name = "Ashfang", realm = "Firemaw" } },
        }) }) })
        local M, TN = ns.MainWindow, ns.Tournaments
        local t = TN:Get("gatebrawl")
        local first = TN.Bracket(t)[1].matches[1]
        t.results = { { round = 1, match = 1, a = first.a, b = first.b, winsA = 1, winsB = 0 } }
        T.eq(TN.CurrentRound(TN.Bracket(t)), 1, "round 1 still has a match to play")
        local rows = M.MatchRows(t, 1)
        T.eq(#rows, 2, "two matches")
        T.eq(rows[1].score, "1 - 0", "the score")
        T.ok(rows[1].a:find("ReadyCheck-Ready", 1, true) ~= nil, "the winner has a check")
        T.eq(rows[1].status, "Played", "played")
        T.eq(rows[2].score, "vs", "to play")
        local final = M.MatchRows(t, 2)
        T.eq(final[1].status, "Not decided yet", "the final waits")

        H.Slash("")
        M:SelectSection("events")
        M:OnRowClick(M.Rows("ongoing")[1])
        local f = _G.HeadHunterMainFrame
        T.ok(f.eventBack:IsShown() and f.eventLink:IsShown(), "the event's toolbar")
        T.ok(f.eventRound.shownText:find("Round 1", 1, true) ~= nil, "on the round being played")
        M:CopyEventLink()
        local dialog = _G.StaticPopupDialogs.HEADHUNTER_LINK
        T.ok(dialog ~= nil and dialog.hasEditBox, "a box to copy from")
        T.eq(H.popups[#H.popups].which, "HEADHUNTER_LINK", "shown")
        local box = { SetText = function(self, v) self.text = v end, HighlightText = function() end, SetFocus = function() end }
        dialog.OnShow({ editBox = box }, t.url)
        T.eq(box.text, "https://headhunterwow.com/tournaments/gatebrawl?tab=bracket", "the link, selected")
        M:ShowRound(1)
        T.ok(f.eventRound.shownText:find("Final", 1, true) ~= nil, "the next round")
        M:CloseEvent()
        T.ok(not f.eventBack:IsShown() and f.subtabs.events:IsShown(), "back to the list")
        T.noErrors()
    end)

    T.case("a player in an event: faction crest, race icon, the name in class color, class icon", function()
        local ns = H.Boot({ client = "era", siteData = Data({ Tournament({
            faction = false,
            players = { { entrant = "p1", name = "Grimtusk", faction = "horde", race = "orc", class = "rogue", sex = 2 },
                { entrant = "p2", name = "Marla" } },
        }) }) })
        local TN = ns.Tournaments
        local t = TN:Get("gatebrawl")
        local label = TN.SideLabel(t, "p1")
        T.ok(label:find("^|TInterface\\TargetingFrame\\UI%-PVP%-Horde") ~= nil, "Horde crest first: " .. label)
        T.ok(label:find("|t|A:raceicon%-orc%-male") ~= nil, "then the race: " .. label)
        T.ok(label:find("|a |c%x+Grimtusk|r |TInterface\\WorldStateFrame\\ICONS%-CLASSES") ~= nil,
            "then the name in class color and the class icon: " .. label)
        T.eq(TN.SideLabel(t, "p2"), "Marla", "nothing known: the name alone")
        T.noErrors()
    end)

    local function Four(overrides)
        local base = {
            starts_at = H.serverTime - 600, locks_at = H.serverTime - 4200, best_of = 1,
            players = { { entrant = "p1", name = "Grimtusk", realm = "Firemaw" }, { entrant = "p2", name = "Marla", realm = "Firemaw" },
                { entrant = "p3", name = "Tovik", realm = "Firemaw" }, { entrant = "p4", name = "Ashfang", realm = "Firemaw" } },
        }
        for k, v in pairs(overrides or {}) do base[k] = v end
        return Tournament(base)
    end

    -- Plays every match of the bracket with side a winning, up to and with the round given
    local function PlayUpTo(TN, t, lastRound)
        t.results = {}
        for round = 1, lastRound do
            for _, m in ipairs(TN.Bracket(t)[round].matches) do
                if not m.bye and m.a and m.b then
                    t.results[#t.results + 1] = { round = round, match = m.match, a = m.a, b = m.b, winsA = 1, winsB = 0 }
                end
            end
        end
    end

    T.case("a tournament is finished once its final has a result: Finished tab, places, Change still there", function()
        local ns = H.Boot({ client = "era", siteData = Data({ Four({ host = { name = "Vati", realm = "Firemaw" } }) }) })
        local M, TN = ns.MainWindow, ns.Tournaments
        local t = TN:Get("gatebrawl")
        PlayUpTo(TN, t, 1)
        T.eq(TN.State(t, H.serverTime), "running", "semifinals played: still running")
        T.eq(TN.Places(t), nil, "no places yet")

        PlayUpTo(TN, t, 2)
        T.eq(TN.State(t, H.serverTime), "finished", "the final decides")
        T.eq(#M.Rows("ongoing"), 0, "not ongoing any more")
        T.eq(M.Rows("finished")[1].event, "gatebrawl", "in the Finished tab")
        T.ok(M.Rows("finished")[1].status:find("Finished", 1, true) ~= nil, "says so")
        local final = TN.Bracket(t)[2].matches[1]
        local places = TN.Places(t)
        T.eq(places.first, final.a, "1st: the final's winner")
        T.eq(places.second, final.b, "2nd: its loser")
        T.eq(#places.third, 2, "the semifinal losers share 3rd")
        local line = M.PlacesLine(t)
        T.ok(line:find("1st", 1, true) ~= nil and line:find("3rd", 1, true) ~= nil, "the places line: " .. line)
        local change
        for _, action in ipairs(M.MatchRows(t, 2)[1].actions or {}) do
            if action.kind == "set" then change = action end
        end
        T.ok(change ~= nil, "the organizer can still correct the final")

        H.Slash("")
        M:SelectSection("events")
        M:SelectTab("finished")
        M:OnRowClick(M.Rows("finished")[1])
        T.ok(_G.HeadHunterMainFrame.eventPlaces:IsShown(), "the places over the matches")
        T.noErrors()
    end)

    T.case("with a match for 3rd place it waits for that one too, whose winner is 3rd alone", function()
        local ns = H.Boot({ client = "era", siteData = Data({ Four({ third_place_match = true }) }) })
        local TN = ns.Tournaments
        local t = TN:Get("gatebrawl")
        PlayUpTo(TN, t, 1)
        local final = TN.Bracket(t)[2].matches[1]
        t.results[#t.results + 1] = { round = 2, match = 1, a = final.a, b = final.b, winsA = 1, winsB = 0 }
        T.eq(TN.State(t, H.serverTime), "running", "the match for 3rd place is still to play")
        PlayUpTo(TN, t, 2)
        T.eq(TN.State(t, H.serverTime), "finished", "both played")
        T.eq(#TN.Places(t).third, 1, "one 3rd")
    end)

    T.case("the website's word: finished, or ended by the host with no winner", function()
        local ns = H.Boot({ client = "era", siteData = Data({
            Four({ id = "done", finished = true }),
            Four({ id = "stopped", finished = true, ended = true }),
        }) })
        local M, TN = ns.MainWindow, ns.Tournaments
        T.eq(TN.State(TN:Get("done"), H.serverTime), "finished", "finished on the website")
        local stopped = TN:Get("stopped")
        T.eq(TN.State(stopped, H.serverTime), "ended", "ended by the host")
        T.eq(#M.Rows("finished"), 2, "both in the Finished tab")
        T.ok(M.PlacesLine(stopped):find("no winner", 1, true) ~= nil, "no places, says why")
        local organizer = false
        for _, row in ipairs(M.MatchRows(stopped, 1)) do
            if row.actions and #row.actions > 0 then organizer = true end
        end
        T.ok(not organizer, "no buttons once the host ended it")
    end)

    T.case("the Events list shows the host in class color, with icons in the tooltip", function()
        local ns = H.Boot({ client = "era", siteData = Data({ Tournament({
            host = { name = "Tovik", realm = "Firemaw", class = "rogue", race = "orc", sex = 2, faction = "horde" },
        }) }) })
        local row = ns.MainWindow.Rows("upcoming")[1]
        T.ok(row.organizer:find("^|c%x+Tovik|r$") ~= nil, "Host column in class color: " .. row.organizer)
        local tip = table.concat(row.tooltip, "\n")
        T.ok(tip:find("UI-PVP-Horde", 1, true) ~= nil and tip:find("raceicon-orc", 1, true) ~= nil
            and tip:find("ICONS-CLASSES", 1, true) ~= nil, "the tooltip with faction, race and class icons")
    end)

    T.case("a team in an event: its faction crest before its name", function()
        local ns = H.Boot({ client = "era", siteData = Data({ Tournament({
            venue = "gurubashi", format = "2v2", faction = false, players = {},
            teams = {
                { entrant = "t1", name = "Blood Pact", faction = "horde", members = {} },
                { entrant = "t2", name = "Lion Guard", faction = "alliance", members = {} },
            },
        }) }) })
        local TN = ns.Tournaments
        local t = TN:Get("gatebrawl")
        T.ok(TN.SideLabel(t, "t1"):find("^|TInterface\\TargetingFrame\\UI%-PVP%-Horde.-|t Blood Pact$") ~= nil, "Horde crest: " .. TN.SideLabel(t, "t1"))
        T.ok(TN.SideLabel(t, "t2"):find("UI%-PVP%-Alliance.-|t Lion Guard$") ~= nil, "Alliance crest: " .. TN.SideLabel(t, "t2"))
        T.ok(TN.SideLabel(t, "t2", true):find("UI%-PVP%-Alliance.-|t |cff808080Lion Guard|r$") ~= nil,
            "a team that did not come: grey, the crest kept: " .. TN.SideLabel(t, "t2", true))
        T.noErrors()
    end)

    T.case("the Events list: events are made on the website, Create an event copies its link", function()
        local ns = H.Boot({ client = "era" })
        local M = ns.MainWindow
        H.Slash("")
        M:SelectSection("events")
        local f = _G.HeadHunterMainFrame
        T.ok(f.eventsInfo:IsShown() and f.eventsCreate:IsShown(), "the info and the button")
        T.eq(M:CopyCreateLink(), false, "no website data yet")
        T.ok(H.Printed("comes with HeadHunter Sync"), "told where the link comes from")

        _G.HeadHunter_SiteData = { format_version = 1, generated_at = H.serverTime, worlds = {},
            links = { create_tournament = "https://headhunterwow.com/tournaments/create" } }
        T.ok(M:CopyCreateLink(), "the link")
        local dialog = _G.StaticPopupDialogs.HEADHUNTER_LINK
        T.ok(dialog.text:find("made and joined on the HeadHunter website", 1, true) ~= nil, "what to do")
        local box = { SetText = function(self, v) self.text = v end, HighlightText = function() end, SetFocus = function() end }
        dialog.OnShow({ editBox = box }, H.popups[#H.popups].data)
        T.eq(box.text, "https://headhunterwow.com/tournaments/create", "selected to copy")

        M:SelectSection("board")
        T.ok(not f.eventsCreate:IsShown(), "only on the Events list")
        T.noErrors()
    end)

    T.case("nothing is created or joined in game any more", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.TournamentDialog, nil, "no create dialog")
        T.eq(ns.Tournaments.Create, nil, "no create")
        T.eq(ns.Protocol.TYPES.TOURNAMENT, nil, "no tournament messages")
        H.Slash("tour")
        T.ok(H.Printed("No tournaments on your realm"), "empty list says where they come from")
        T.noErrors()
    end)

    T.case("venues: Gurubashi and the capital gates, and where we are", function()
        local ns = H.Boot({ client = "forever" })
        local A = ns.Arena
        local sw = A.VENUE.stormwind
        T.eq(A.VenueWhere("stormwind", sw.mapID, sw.center.x, sw.center.y), "fight", "at the Stormwind gate")
        T.eq(A.VenueWhere("stormwind", sw.mapID, sw.center.x + 0.1, sw.center.y), nil, "away from it")
        T.eq(A.VenueWhere("stormwind", 1434, sw.center.x, sw.center.y), nil, "other zone")
        T.eq(A.VenueWhere("gurubashi", 1434, 0.3055, 0.4785), "fight", "Gurubashi pit")

        H.playerMap, H.playerX, H.playerY = sw.mapID, sw.center.x, sw.center.y
        H.Slash("arena")
        T.ok(H.Printed("at the Stormwind gate"), "/hh arena names the venue")
        H.playerX = 0.9
        H.Slash("arena")
        T.ok(H.Printed("not at a tournament venue"), "and says when we are at none")
        T.noErrors()
    end)

    T.case("select: the modern dropdown where the client has it", function()
        local ns = H.Boot({ client = "forever" })
        local radio
        _G.DoesTemplateExist = function(name) return name == "WowStyle1DropdownTemplate" end
        _G.MenuUtil = { CreateRadioMenu = function(_, isSelected, onSelect, ...)
            radio = { isSelected = isSelected, onSelect = onSelect, entries = { ... } }
        end }
        local value = "b"
        local select = ns.Select.Create(UIParent, { options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
            get = function() return value end, set = function(v) value = v end })
        T.eq(#radio.entries, 2, "radio menu entries")
        T.eq(radio.entries[1][1] .. radio.entries[1][2], "Aa", "label, value")
        T.ok(radio.isSelected("b") and not radio.isSelected("a"), "current value selected")
        radio.onSelect("a")
        T.eq(value, "a", "picked")
        select:Choose("b")
        T.eq(value, "b", "Choose")
        -- Choices filled after the dropdown was made (the result dialog): Refresh has them
        local later = {}
        local filled = ns.Select.Create(UIParent, { options = later, get = function() return value end, set = function() end })
        T.eq(#radio.entries, 0, "empty at first")
        later[1], later[2], later[3] = { value = "x", label = "X" }, { value = "y", label = "Y" }, { value = "z", label = "Z" }
        filled:Refresh()
        T.eq(#radio.entries, 3, "the choices after Refresh")
        _G.DoesTemplateExist, _G.MenuUtil = nil, nil
        T.noErrors()
    end)

    -------------------------------------------------
    -- HH-105 brackets
    -------------------------------------------------

    T.case("seeding: rated best first, unrated shuffled the same way on every client", function()
        local B = H.Boot({ client = "era" }).Brackets
        local ratings = { A = 10, B = 30, C = 20 }
        local entrants = { "A", "B", "C", "X", "Y", "Z" }
        local seeds = B.Seed(entrants, function(id) return ratings[id] end, 42)
        T.eq(Ids({ seeds[1], seeds[2], seeds[3] }), "B,C,A", "rated first, best first")
        T.eq(Ids(B.Seed({ "Z", "Y", "X", "C", "B", "A" }, function(id) return ratings[id] end, 42)), Ids(seeds),
            "same seed, same order whatever the join order")
        T.eq(B.WinsNeeded(1), 1, "Best of 1")
        T.eq(B.WinsNeeded(3), 2, "Best of 3")
        T.eq(B.WinsNeeded(5), 3, "Best of 5")
        T.eq(Ids(B.SeedOrder(8)), "1,8,4,5,2,7,3,6", "seed order")
    end)

    T.case("single elimination with byes, Best of 3, standings and points", function()
        local B = H.Boot({ client = "era" }).Brackets
        local br = B.SingleElimination({ "S1", "S2", "S3", "S4", "S5" }, 3)
        T.eq(#br.rounds, 3, "8 slots: 3 rounds")
        local r1 = br.rounds[1]
        T.eq(r1[1].winner, "S1", "S1 bye")
        T.eq(r1[1].bye, true, "marked as a bye")
        T.eq(r1[2].a .. "v" .. r1[2].b, "S4vS5", "the only first-round game")
        T.eq(br.rounds[2][2].a .. "v" .. br.rounds[2][2].b, "S2vS3", "byes meet in round 2")
        T.eq(Ids(B.Ready(br), "id"), "r1m2,r2m2", "ready now")

        T.eq(B.RecordGame(br, "r1m2", "Nobody"), nil, "not in this match")
        B.RecordGame(br, "r1m2", "S5")
        T.eq(r1[2].winner, nil, "one game is not enough in Best of 3")
        B.RecordGame(br, "r1m2", "S4")
        B.RecordGame(br, "r1m2", "S5")
        T.eq(r1[2].winner, "S5", "2 wins")
        T.eq(br.rounds[2][1].b, "S5", "advanced")
        T.eq(B.RecordGame(br, "r1m2", "S5"), nil, "decided matches take no more games")

        for _ = 1, 2 do B.RecordGame(br, "r2m1", "S1") end
        for _ = 1, 2 do B.RecordGame(br, "r2m2", "S3") end
        T.eq(br.rounds[3][1].a .. "v" .. br.rounds[3][1].b, "S1vS3", "final")
        for _ = 1, 2 do B.RecordGame(br, "r3m1", "S3") end
        T.ok(B.Finished(br), "finished")
        T.eq(br.champion, "S3", "champion")

        local standings = B.Standings(br)
        T.eq(Ids(standings, "id"), "S3,S1,S5,S2,S4", "order")
        T.eq(Ids(standings, "place"), "1,2,3,3,5", "places")
        T.eq(Ids(standings, "points"), "10,6,3,3,1", "points")
    end)

    T.case("round robin: everyone meets everyone once, one round at a time", function()
        local B = H.Boot({ client = "era" }).Brackets
        local br = B.RoundRobin({ "A", "B", "C" }, 1)
        T.eq(#br.rounds, 3, "3 rounds for 3 (one sits out)")
        local pairs = {}
        for _, round in ipairs(br.rounds) do
            T.eq(#round, 1, "one match per round")
            for _, m in ipairs(round) do
                local key = m.a < m.b and m.a .. m.b or m.b .. m.a
                T.eq(pairs[key], nil, "no pair twice")
                pairs[key] = true
            end
        end
        T.eq(Ids(B.Ready(br), "id"), "r1m1", "only the first round is ready")

        -- A beats everyone, B beats C
        for _, round in ipairs(br.rounds) do
            local m = round[1]
            local winner = (m.a == "A" or m.b == "A") and "A" or "B"
            B.RecordGame(br, m.id, winner)
        end
        T.ok(B.Finished(br), "finished")
        T.eq(Ids(B.Standings(br), "id"), "A,B,C", "by match wins")

        local four = B.RoundRobin({ "A", "B", "C", "D" }, 1)
        T.eq(#four.rounds, 3, "3 rounds for 4")
        T.eq(#four.rounds[1], 2, "2 matches per round")
        T.eq(B.SingleElimination({ "A" }), nil, "one entrant: no bracket")
    end)
end