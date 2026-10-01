-- Tournament matches in game (Tournament/Matches.lua): the organizer calls a match, the
-- players get ready, their duels are the games, the organizer confirms, everyone's
-- bracket moves on. Made-up players only.

return function(T, H)
    local function Data(host, extra)
        local t = {
            id = "gatebrawl", name = "Gate Brawl", venue = "orgrimmar", format = "1v1", best_of = 3,
            faction = "alliance", min_level = 20, max_level = 30, places = 16,
            starts_at = H.serverTime - 600, locks_at = H.serverTime - 4200, bracket_seed = 99,
            host = { name = host, realm = "Firemaw" }, organizers = {},
            players = {
                { entrant = "p1", name = "Grimtusk", realm = "Firemaw" }, { entrant = "p2", name = "Marla", realm = "Firemaw" },
                { entrant = "p3", name = "Vati", realm = "Firemaw" }, { entrant = "p4", name = "Ashfang", realm = "Firemaw" },
            },
            teams = {},
        }
        for k, v in pairs(extra or {}) do t[k] = v end
        return {
            format_version = 1, generated_at = H.serverTime - 60,
            worlds = { ["era|eu|Firemaw"] = { generated_at = H.serverTime - 60, tournaments = { t } } },
        }
    end

    local function Flush()
        for _ = 1, 4 do H.Advance(3) end
    end

    local function Sent(kind, target)
        local found = {}
        for _, m in ipairs(H.sent) do
            if m.message:find("^1AM:" .. kind .. ";") and (not target or m.target == target) then found[#found + 1] = m end
        end
        return found
    end

    -- The match in round 1 without us (the organizer's view) and its two names
    local function OtherMatch(ns)
        local TN = ns.Tournaments
        local t = TN:Get("gatebrawl")
        for _, m in ipairs(TN.Bracket(t)[1].matches) do
            if m.a ~= "p3" and m.b ~= "p3" then return t, m, TN.SideName(t, m.a), TN.SideName(t, m.b) end
        end
    end

    local function Deliver(ns, record, sender)
        H.Deliver(ns.Protocol.Pack("A", "M", { record }), sender)
    end

    T.case("the organizer calls a match: addon whisper and plain whisper to both, 3 minutes", function()
        local ns = H.Boot({ client = "era", siteData = Data("Vati") })
        local t, m, a, b = OtherMatch(ns)
        T.ok(ns.Matches:CallMatch(t, 1, m.match), "called")
        Flush()
        T.eq(#Sent("C"), 2, "both players' addons told")
        local whispers = 0
        for _, w in ipairs(H.chatSent) do
            if w.chatType == "WHISPER" and w.text:find("Gate Brawl", 1, true) and w.text:find("3 min", 1, true) then
                whispers = whispers + 1
            end
        end
        T.eq(whispers, 2, "and a whisper each, for players without the addon")
        local row = ns.MainWindow.MatchRows(t, 1)[m.match]
        T.ok(row.status:find("Called", 1, true) ~= nil and row.status:find("0/2", 1, true) ~= nil, "status: " .. row.status)

        -- Ready: one by the addon, one by a whisper
        Deliver(ns, ns.Protocol.EncodeMatch("R", "gatebrawl", 1, m.match), a)
        H.Fire("CHAT_MSG_WHISPER", "ok ready!", b)
        Flush()
        T.eq(#Sent("D"), 2, "both ready: both told to duel")
        T.ok(ns.MainWindow.MatchRows(t, 1)[m.match].status:find("Both ready", 1, true) ~= nil, "status: both ready")

        -- The duels are the games; a Best of 3 is decided at 2 wins
        H.Fire("CHAT_MSG_SYSTEM", a .. " has defeated " .. b .. " in a duel")
        H.Fire("CHAT_MSG_SYSTEM", a .. " has defeated " .. b .. " in a duel") -- the same game, told twice
        H.clock = H.clock + 30
        H.serverTime = H.serverTime + 30
        H.Fire("CHAT_MSG_SYSTEM", b .. " has defeated " .. a .. " in a duel")
        H.serverTime = H.serverTime + 30
        H.Fire("CHAT_MSG_SYSTEM", a .. " has defeated " .. b .. " in a duel")
        local call = ns.Matches:Call("gatebrawl", 1, m.match)
        T.eq(call.wins.a .. "-" .. call.wins.b, "2-1", "games counted once each")
        local row2 = ns.MainWindow.MatchRows(t, 1)[m.match]
        T.eq(row2.actions[1].kind, "confirm", "Confirm 2 - 1")

        -- Confirm: kept, sent to everyone, the winner goes on
        T.ok(ns.Matches:Confirm(t, 1, m.match, 2, 1), "confirmed")
        Flush()
        T.ok(#Sent("F") >= 1, "the result went out")
        local stored = ns.db.eventResults["gatebrawl:1:" .. m.match]
        T.eq(stored.winsA .. "-" .. stored.winsB .. " " .. stored.origin, "2-1 local", "kept for the website")
        local final = ns.Tournaments.Bracket(t)[2].matches[1]
        T.ok(final.a == m.a or final.b == m.a, "the winner is in the final")
        T.noErrors()
    end)

    T.case("not ready after 3 minutes: the organizer gives the match as a no-show", function()
        local ns = H.Boot({ client = "era", siteData = Data("Vati") })
        local t, m, a, b = OtherMatch(ns)
        ns.Matches:CallMatch(t, 1, m.match)
        Deliver(ns, ns.Protocol.EncodeMatch("R", "gatebrawl", 1, m.match), a)
        H.serverTime = H.serverTime + 181
        local row = ns.MainWindow.MatchRows(t, 1)[m.match]
        T.ok(row.status:find("Not ready: " .. b, 1, true) ~= nil, "who is late: " .. row.status)
        T.eq(row.actions[1].kind .. "/" .. row.actions[1].side, "noshow/b", "No-show button")
        T.eq(row.actions[2].kind, "call", "Call again")
        ns.MainWindow:ShowEvent("gatebrawl")
        ns.MainWindow:OnMatchAction(row, row.actions[1])
        local stored = ns.db.eventResults["gatebrawl:1:" .. m.match]
        T.eq(stored and stored.forfeit, "b", "a no-show")
        local shown = ns.MainWindow.MatchRows(t, 1)[m.match]
        T.eq(shown.status, "No-show", "a short status")
        T.eq(shown.score, "FF", "FF")
        T.ok(shown.b:find("|cff808080" .. b, 1, true) ~= nil, "the absent side in grey")
        T.ok(table.concat(shown.tooltip, "\n"):find(b .. " did not come", 1, true) ~= nil, "the details in the tooltip")
        T.noErrors()
    end)

    T.case("Sync to website: shown once we confirmed a result; yes reloads the interface", function()
        local ns = H.Boot({ client = "era", siteData = Data("Vati") })
        local t, m = OtherMatch(ns)
        H.Slash("")
        local M = ns.MainWindow
        M:ShowEvent("gatebrawl")
        local f = _G.HeadHunterMainFrame
        T.ok(not f.eventSend:IsShown(), "nothing to sync yet")
        T.eq(M:SendToWebsite(), false, "nothing to ask")
        ns.Matches:Confirm(t, 1, m.match, 2, 0)
        T.ok(H.Printed("Sync to website in the event view"), "told how to put it on the website")
        M:Refresh()
        T.ok(f.eventSend:IsShown(), "the button")
        T.eq(f.eventSend.shownText, "Sync to website (1)", "with the count")
        local reloaded = false
        _G.ReloadUI = function() reloaded = true end
        T.ok(M:SendToWebsite(), "asks first")
        T.eq(H.popups[#H.popups].which, "HEADHUNTER_SEND", "a yes / no")
        T.ok(not reloaded, "not before the yes")
        _G.StaticPopupDialogs.HEADHUNTER_SEND.OnAccept()
        T.ok(reloaded, "the yes reloads, the game saves, the app syncs")
        _G.ReloadUI = nil
        T.noErrors()
    end)

    T.case("the match for 3rd place says so in the # column, not in the status", function()
        local ns = H.Boot({ client = "era", siteData = Data("Vati", { third_place_match = true }) })
        local TN = ns.Tournaments
        local t = TN:Get("gatebrawl")
        local semis = TN.Bracket(t)[1].matches
        for i, m in ipairs(semis) do
            t.results[#t.results + 1] = { round = 1, match = i, a = m.a, b = m.b, winsA = 2, winsB = 0 }
        end
        local rows = ns.MainWindow.MatchRows(t, 2)
        T.eq(#rows, 2, "the final and the match for 3rd place")
        T.eq(rows[1].match .. "|" .. rows[2].match, "#1|3rd", "3rd in the # column")
        T.ok(not rows[2].status:find("3rd", 1, true), "not in the status: " .. rows[2].status)
        T.eq(rows[2].tooltip[1], "3rd place", "the tooltip says it")
        T.noErrors()
    end)

    T.case("the organizer sets a result by hand; a wrong score or a locked match is refused", function()
        local ns = H.Boot({ client = "era", siteData = Data("Vati") })
        local t, m = OtherMatch(ns)
        T.eq(select(2, ns.Matches:Confirm(t, 1, m.match, 2, 2)), "score", "2-2 is no Best of 3 result")
        T.ok(ns.ResultDialog:Open(t, 1, m.match, "0-2"), "the dialog")
        T.ok(ns.ResultDialog:Save(), "saved")
        T.eq(ns.db.eventResults["gatebrawl:1:" .. m.match].winsB, 2, "0 - 2")
        local labels = {}
        for _, o in ipairs(ns.ResultDialog.Options("A", "B", 3)) do labels[#labels + 1] = o.label end
        T.eq(table.concat(labels, "|"), "A wins 2 - 0|A wins 2 - 1|B wins 2 - 1|B wins 2 - 0|A did not come|B did not come",
            "the website's choices")
        T.noErrors()
    end)

    T.case("a player: called, Ready, Duel; the result from the organizer; nobody else can call", function()
        local ns = H.Boot({ client = "era", siteData = Data("Tovik") })
        local TN = ns.Tournaments
        local t = TN:Get("gatebrawl")
        local mine
        for _, m in ipairs(TN.Bracket(t)[1].matches) do
            if m.a == "p3" or m.b == "p3" then mine = m end
        end
        local opponent = TN.SideName(t, mine.a == "p3" and mine.b or mine.a)

        Deliver(ns, ns.Protocol.EncodeMatch("C", "gatebrawl", 1, mine.match, H.serverTime + 180), "Marla")
        T.eq(ns.Matches:Mine(), nil, "a player cannot call")
        Deliver(ns, ns.Protocol.EncodeMatch("C", "gatebrawl", 1, mine.match, H.serverTime + 180), "Tovik")
        T.ok(ns.Matches:Mine() ~= nil, "called by the host")
        T.ok(H.Printed("your match vs " .. opponent .. " is called"), "told")
        local row = ns.MainWindow.MatchRows(t, 1)[mine.match]
        T.eq(row.actions[1].kind, "ready", "a Ready button on our row")
        _G.StaticPopupDialogs.HEADHUNTER_TOUR.OnAccept()
        Flush()
        T.eq(#Sent("R", "Tovik"), 1, "ready sent to the host")

        Deliver(ns, ns.Protocol.EncodeMatch("D", "gatebrawl", 1, mine.match), "Tovik")
        _G.StaticPopupDialogs.HEADHUNTER_TOUR.OnAccept()
        T.eq(H.duelsStarted[#H.duelsStarted], opponent, "we challenge our opponent")

        H.Fire("CHAT_MSG_SYSTEM", "Vati has defeated " .. opponent .. " in a duel")
        Flush()
        T.eq(#Sent("G", "Tovik"), 1, "our game reported to the host")

        local fake = ns.Protocol.EncodeMatch("F", "gatebrawl", 1, mine.match, mine.a, mine.b, 2, 0, "", H.serverTime)
        Deliver(ns, fake, "Marla")
        T.eq(ns.db.eventResults["gatebrawl:1:" .. mine.match], nil, "a result from a player is ignored")
        Deliver(ns, fake, "Tovik")
        local stored = ns.db.eventResults["gatebrawl:1:" .. mine.match]
        T.eq(stored and stored.origin, "peer", "the host's result counts")
        T.eq(ns.Matches:Mine(), nil, "our match is over")
        T.noErrors()
    end)
end
