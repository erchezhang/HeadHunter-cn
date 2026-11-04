-- Gangs (Sync/Gangs.lua, HH-155): our actions are kept for HeadHunter Sync, invites go by
-- addon whisper with a popup to accept, and our gang comes from the website's download
-- with our unanswered actions laid over it. Made-up players only.

return function(T, H)
    local PVP = "4619"

    local function Settle()
        for _ = 1, 5 do H.Advance(1) end
    end

    -- The website's download with one gang on our world and our character's results
    local function Data(gangs, results)
        return {
            format_version = 1,
            forever_servers = { [PVP] = "pvp" },
            worlds = { ["forever|us|pvp"] = { generated_at = H.serverTime - 60, wanted = {},
                duels = { alliance = {}, horde = {} }, gangs = gangs or {} } },
            characters = { { world = "forever|us|pvp", name = "Vati Guda", deaths = {}, duels = {}, catches = {},
                gang_results = results or {} } },
        }
    end

    local function Boot(siteData, savedDB)
        local ns = H.Boot({ client = "forever", playerGUID = "Player-" .. PVP .. "-00ABCDEF", siteData = siteData,
            savedDB = savedDB })
        Settle()
        return ns
    end

    local function Whispers(code)
        local found = {}
        for _, m in ipairs(H.sent) do
            if m.chatType == "WHISPER" and m.message:find(code, 1, true) then found[#found + 1] = m end
        end
        return found
    end

    local function Gang(name, leader, members)
        local list = {}
        for _, member in ipairs(members) do list[#list + 1] = { name = member, faction = "alliance", class = "warrior" } end
        return { id = 1, name = name, faction = "alliance", leader = leader, members = list }
    end

    T.case("names: the website's rule", function()
        local ns = Boot()
        local G = ns.Gangs
        T.ok(G.ValidName("Black Hand"), "letters and a space")
        T.ok(G.ValidName("  Dalton's   Riders "), "cleaned first")
        T.ok(not G.ValidName("X!"), "too short and a sign")
        T.ok(not G.ValidName("-Dash"), "starts with a sign")
        T.ok(not G.ValidName(string.rep("a", 25)), "too long")
        T.ok(G.ValidName("Банда Волков"), "any alphabet")
        T.eq(G.CleanName("  Black   Hand "), "Black Hand", "single spaces")
    end)

    T.case("create: kept for Sync and shown as waiting until the website answers", function()
        local ns = Boot()
        H.Slash("gang create Black Hand")
        local actions = ns.Gangs:Actions()
        T.eq(#actions, 1, "one action")
        T.eq(actions[1].kind, "create", "create")
        T.eq(actions[1].name, "Black Hand", "name")
        T.eq(actions[1].by, "Vati Guda", "by our character")
        local gang = ns.Gangs:Mine()
        T.eq(gang.name, "Black Hand", "our gang")
        T.ok(gang.pending, "waiting for Sync")
        T.ok(ns.Gangs:IsLeader(gang), "we lead it")
        H.Slash("gang create Red Fang")
        T.ok(H.Printed("already"), "one gang at a time")
        T.eq(#ns.Gangs:Actions(), 1, "nothing more kept")
    end)

    T.case("the website's gang and our results: confirmed, refused with a reason, said once", function()
        local data = Data()
        local ns = Boot(data)
        H.Slash("gang create Black Hand")
        local uid = ns.Gangs:Actions()[1].uid
        data.worlds["forever|us|pvp"].gangs = { Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) }
        ns.SiteData:Load()
        local gang = ns.Gangs:Mine()
        T.eq(gang.name, "Black Hand", "the website's gang")
        T.eq(#gang.members, 1, "our unanswered create still lays over it")

        data.characters[1].gang_results = { { uid = uid, kind = "create", status = "done", gang = "Black Hand" } }
        ns.SiteData:Load()
        gang = ns.Gangs:Mine()
        T.ok(not gang.pending, "confirmed")
        T.eq(#gang.members, 2, "the website's members")
        T.eq(ns.Gangs:Of("Tobin Ashford"), "Black Hand", "another player's gang")

        H.printed = {}
        ns.Gangs:TellResults()
        T.ok(H.Printed("confirmed"), "said")
        H.printed = {}
        ns.Gangs:TellResults()
        T.ok(not H.Printed("confirmed"), "said once")
    end)

    T.case("a refusal says why and the gang is gone", function()
        local data = Data()
        local ns = Boot(data)
        H.Slash("gang create Black Hand")
        local uid = ns.Gangs:Actions()[1].uid
        data.characters[1].gang_results = { { uid = uid, kind = "create", status = "refused", reason = "name_taken" } }
        ns.SiteData:Load()
        T.eq(ns.Gangs:Mine(), nil, "no gang")
        ns.Gangs:TellResults()
        T.ok(H.Printed("taken"), "the reason")
    end)

    T.case("invite: a whisper and a kept action; the answer is said", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda" }) }))
        H.sent = {}
        H.Slash("gang invite Tobin Ashford")
        Settle()
        local sent = Whispers("i;Black Hand")
        T.eq(#sent, 1, "one invite whisper")
        T.eq(sent[1].target, "Tobin Ashford", "to them")
        local actions = ns.Gangs:Actions()
        T.eq(actions[#actions].kind, "invite", "kept")
        T.eq(actions[#actions].player, "Tobin Ashford", "who")
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "a" }), "Tobin Ashford")
        T.ok(H.Printed("accepted"), "the accept is said")
    end)

    T.case("invite: only the leader, at most 5 a minute", function()
        local ns = Boot(Data({ Gang("Black Hand", "Tobin Ashford", { "Tobin Ashford", "Vati Guda" }) }))
        H.Slash("gang invite Rowan Fairhill")
        T.ok(H.Printed("leader"), "not the leader")

        ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda" }) }))
        for i = 1, 6 do H.Slash("gang invite Player" .. i .. " Test") end
        local invites = 0
        for _, action in ipairs(ns.Gangs:Actions()) do
            if action.kind == "invite" then invites = invites + 1 end
        end
        T.eq(invites, 5, "five, then wait")
    end)

    T.case("an invite to us: the popup, accept kept and answered", function()
        local ns = Boot()
        H.popups, H.sent = {}, {}
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "i;Black Hand" }), "Kira Dawnblade")
        T.eq(#H.popups, 1, "a popup")
        T.ok(H.popups[1].text:find("Black Hand", 1, true), "names the gang")
        StaticPopupDialogs[ns.Gangs.POPUP].OnAccept()
        Settle()
        local action = ns.Gangs:Actions()[1]
        T.eq(action.kind, "accept", "accept kept")
        T.eq(action.leader, "Kira Dawnblade", "the inviter")
        T.eq(#Whispers("a"), 1, "answered")
        T.eq(ns.Gangs:Mine().name, "Black Hand", "waiting to join")
    end)

    T.case("an invite to us is declined quietly when off, when in a gang, or on Classic Era", function()
        local ns = Boot()
        ns.Database:SetSetting("gangInvites", false)
        H.popups, H.sent = {}, {}
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "i;Black Hand" }), "Kira Dawnblade")
        Settle()
        T.eq(#H.popups, 0, "no popup when off")
        T.eq(#Whispers("d"), 1, "declined")

        local era = H.Boot({ client = "era" })
        H.Slash("gang create Black Hand")
        T.ok(H.Printed("WoW Forever"), "Forever only")
        T.eq(#era.Gangs:Actions(), 0, "nothing kept on Classic Era")
    end)

    T.case("leave, kick and lead: the leader's, kept for Sync", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) }))
        H.Slash("gang kick Rowan Fairhill")
        T.ok(H.Printed("not in your gang"), "only members")
        H.Slash("gang lead Tobin Ashford")
        H.Slash("gang leave")
        local kinds = {}
        for _, action in ipairs(ns.Gangs:Actions()) do kinds[#kinds + 1] = action.kind end
        T.eq(table.concat(kinds, ","), "lead,leave", "kept in order")
        T.eq(ns.Gangs:Mine(), nil, "out once we left")
        T.noErrors()
    end)

    T.case("tooltip: a gang member's gang on any player", function()
        local ns = Boot(Data({ Gang("Black Hand", "Tobin Ashford", { "Tobin Ashford" }) }))
        H.units.target = { name = "Tobin Ashford", isPlayer = true, faction = "Alliance", class = "WARRIOR" }
        local line = ns.TooltipLine.GangLine("target")
        T.ok(line and line[1]:find("Black Hand", 1, true), "Gang: Black Hand")
        H.units.target = { name = "Rowan Fairhill", isPlayer = true, faction = "Alliance" }
        T.eq(ns.TooltipLine.GangLine("target"), nil, "nothing for others")
    end)

    T.case("window: the Gang view lists the members, leader first", function()
        local ns = Boot(Data({ Gang("Black Hand", "Tobin Ashford", { "Vati Guda", "Tobin Ashford" }) }))
        local rows = ns.MainWindow.Rows("gang")
        T.eq(#rows, 2, "two members")
        T.eq(rows[1].plain, "Tobin Ashford", "the leader first")
        T.ok(rows[1].role:find("Leader", 1, true), "leader")
        ns.MainWindow:Toggle()
        ns.MainWindow:SelectTab("gang")
        T.noErrors()
    end)

    T.case("Social window tab: off by default; on, our own tab after Raid that hides Blizzard's pages and never writes its tab state", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) }))
        _G.FriendsFrame = CreateFrame("Frame")
        FriendsFrame.hooks = {}
        FriendsFrame.HookScript = function(self, script, fn) self.hooks[script] = fn end
        FriendsFrame.Inset = CreateFrame("Frame")
        for _, i in ipairs({ 1, 3, 4 }) do
            local button = CreateFrame("Button")
            button.shown = i ~= 4
            button.hooks = {}
            button.HookScript = function(self, script, fn) self.hooks[script] = fn end
            _G["FriendsFrameTab" .. i] = button
        end
        _G.FriendsListFrame = CreateFrame("Frame")
        FriendsListFrame:Show()
        _G.RaidFrame = CreateFrame("Frame")
        RaidFrame:Show()
        RaidFrame.GetParent = function() return FriendsFrame end
        local looks = {}
        _G.PanelTemplates_SelectTab = function(button) looks[button] = "selected" end
        _G.PanelTemplates_DeselectTab = function(button) looks[button] = "deselected" end
        local hooked = {}
        _G.FriendsFrame_OnShow, _G.FriendsFrame_Update = function() end, function() end
        local secure = _G.hooksecurefunc
        _G.hooksecurefunc = function(name, fn) hooked[name] = fn end
        T.ok(not ns.SocialTab:Install(), "off by default")

        H.Slash("gang socialtab on")
        T.ok(ns.SocialTab:Install(), "added once on")
        _G.hooksecurefunc = secure
        local tab, panel = ns.SocialTab:Parts()
        T.ok(tab.point[2] == FriendsFrameTab3, "after Raid, the last tab on show; no tab 2, Quick Join hidden")
        T.eq(tab.point[4], 3, "the game's own gap between tabs")

        FriendsFrame.selectedTab = 2
        local title = CreateFrame("Frame")
        title.SetText = function(self, text) self.value = text end
        title.GetText = function(self) return self.value end
        title:SetText("Raid")
        FriendsFrame.GetTitleText = function() return title end
        tab:GetScript("OnClick")()
        T.eq(title.value, "Gang", "the window's title says Gang")
        T.ok(panel:IsShown(), "our page shows")
        T.ok(panel.title.shownText:find("Black Hand", 1, true), "our gang")
        T.eq(looks[tab], "selected", "our tab looks selected")
        T.eq(looks[FriendsFrameTab3], "deselected", "Raid does not, though its id is 2 and its button Tab3")
        T.eq(looks[FriendsFrameTab1], "deselected", "nor Contacts")
        T.ok(not FriendsListFrame:IsShown(), "the friends list hidden")
        T.ok(not RaidFrame:IsShown(), "the Raid page hidden out of combat")
        T.eq(FriendsFrame.selectedTab, 2, "Blizzard's selected tab never written")
        T.eq(rawget(FriendsFrame, "numTabs"), nil, "nor its tab count")

        FriendsListFrame:Show()
        hooked.FriendsFrame_Update()
        T.ok(not FriendsListFrame:IsShown(), "a refresh of the window hides its page again while ours is open")

        FriendsFrameTab3.hooks.OnClick(FriendsFrameTab3)
        T.ok(not panel:IsShown(), "a click on Raid closes ours")
        T.eq(looks[tab], "deselected", "and our tab looks unselected")
        T.ok(FriendsListFrame:IsShown() and RaidFrame:IsShown(), "Raid was Blizzard's tab all along: its page comes back from us")
        T.eq(looks[FriendsFrameTab3], "selected", "and Raid looks selected")
        T.eq(title.value, "Raid", "and its title is back")

        tab:GetScript("OnClick")()
        T.ok(panel:IsShown(), "ours again")
        FriendsFrame.selectedTab = 1
        RaidFrame:Hide()
        FriendsFrameTab1.hooks.OnClick(FriendsFrameTab1)
        T.ok(not panel:IsShown(), "a click on Contacts closes ours")
        T.ok(not RaidFrame:IsShown(), "Blizzard switched pages itself: we show nothing back")

        tab:GetScript("OnClick")()
        hooked.FriendsFrame_OnShow()
        T.ok(not panel:IsShown(), "reopening the window closes ours")
        T.noErrors()
    end)

    T.case("Create gang: a popup asks for the name, then the usual checks; none when in a gang", function()
        local ns = Boot()
        H.popups = {}
        ns.Gangs:PromptCreate()
        T.eq(#H.popups, 1, "the name popup")
        T.eq(H.popups[1].which, ns.Gangs.CREATE_POPUP, "the create popup")
        local popup = { editBox = { GetText = function() return "  Black   Hand " end } }
        StaticPopupDialogs[ns.Gangs.CREATE_POPUP].OnAccept(popup)
        local action = ns.Gangs:Actions()[1]
        T.eq(action.kind, "create", "kept for Sync")
        T.eq(action.name, "Black Hand", "cleaned name")
        H.popups = {}
        ns.Gangs:PromptCreate()
        T.eq(#H.popups, 0, "no popup once in a gang")
        T.ok(H.Printed("already"), "said why")
        local bad = Boot()
        StaticPopupDialogs[bad.Gangs.CREATE_POPUP].OnAccept({ editBox = { GetText = function() return "X!" end } })
        T.eq(#bad.Gangs:Actions(), 0, "a bad name is refused")
    end)

    T.case("invite: the invited addon confirms at once; silence says not online or no HeadHunter", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda" }) }))
        H.printed = {}
        H.Slash("gang invite Rowan Fairhill")
        H.Advance(ns.Gangs.ACK_WAIT + 1)
        T.ok(H.Printed("no HeadHunter"), "told when nobody answers")

        H.printed = {}
        H.Slash("gang invite Tobin Ashford")
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "r" }), "Tobin Ashford")
        H.Advance(ns.Gangs.ACK_WAIT + 1)
        T.ok(not H.Printed("no HeadHunter"), "their addon answered")
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "a" }), "Tobin Ashford")
        local names = {}
        for _, member in ipairs(ns.Gangs:Mine().members) do names[#names + 1] = member.key end
        T.eq(table.concat(names, ","), "Vati Guda,Tobin Ashford", "the accepted player is in our list at once, waiting for Sync")
    end)

    T.case("an invite to us is confirmed to the inviter at once", function()
        local ns = Boot()
        H.sent = {}
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "i;Black Hand" }), "Kira Dawnblade")
        Settle()
        T.eq(#Whispers("r"), 1, "received")
    end)
end
