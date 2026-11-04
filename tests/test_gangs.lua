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
        for _, member in ipairs(members) do list[#list + 1] = { name = member, faction = "alliance", class = "rogue" } end
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

    T.case("invite: the gang takes up to 20 members", function()
        local members = { "Vati Guda" }
        for i = 1, 19 do members[#members + 1] = "Member" .. i .. " Test" end
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", members) }))
        H.printed = {}
        H.Slash("gang invite One Toomany")
        T.ok(H.Printed("full %(20"), "full at 20")
        local room = { "Vati Guda" }
        for i = 1, 18 do room[#room + 1] = "Member" .. i .. " Test" end
        ns = Boot(Data({ Gang("Black Hand", "Vati Guda", room) }))
        H.printed = {}
        H.Slash("gang invite One More")
        T.ok(not H.Printed("full"), "room for the twentieth")
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
        ns.MainWindow:SelectSection("gang")
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
            local id = ({ [1] = 1, [3] = 2, [4] = 3 })[i]
            button.GetID = function() return id end
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
        T.eq(title.value, "Gang - Black Hand", "the window's title names our gang once the website confirmed it")
        T.ok(panel:IsShown(), "our page shows")
        T.ok(panel.lines[1].shownText:find("Interface\\WorldStateFrame\\ICONS-CLASSES", 1, true), "a class icon")
        T.ok(panel.lines[1].shownText:find("|cff", 1, true), "the name in its class colour")
        T.ok(panel.borders[1].shown and panel.borders[2].shown and not panel.borders[3].shown, "a border under each member")
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

        FriendsFrame.selectedTab = 1
        RaidFrame:Hide()
        FriendsListFrame:Show()
        tab:GetScript("OnClick")()
        T.ok(panel:IsShown(), "ours again, opened from Contacts")
        FriendsFrame.selectedTab = 2
        RaidFrame:Show()
        title:SetText("Raid")
        hooked.FriendsFrame_Update()
        hooked.FriendsFrame_OnShow()
        FriendsFrameTab3.hooks.OnClick(FriendsFrameTab3)
        T.ok(not panel:IsShown(), "a click on Raid closes ours")
        T.ok(RaidFrame:IsShown(), "the Raid page the game showed during the click is back")
        T.ok(not FriendsListFrame:IsShown(), "the Contacts page stays hidden")
        T.eq(title.value, "Raid", "the game's new title is back")
        T.eq(looks[FriendsFrameTab3], "selected", "Raid looks selected")

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
        T.ok(H.popups[1].text:find("headhunterwow.com/gangs", 1, true), "with the link to check taken names")
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

    T.case("invite: only once the gang is on the website", function()
        local ns = Boot()
        H.Slash("gang create Black Hand")
        H.printed = {}
        H.Slash("gang invite Tobin Ashford")
        T.ok(H.Printed("not on the website yet"), "waiting for Sync")
        local invites = 0
        for _, action in ipairs(ns.Gangs:Actions()) do
            if action.kind == "invite" then invites = invites + 1 end
        end
        T.eq(invites, 0, "no invite kept")
    end)

    T.case("Leave from a button asks first; the leader is told the lead passes on", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) }))
        H.popups = {}
        ns.Gangs:PromptLeave()
        T.eq(#H.popups, 1, "asks")
        T.ok(H.popups[1].text:find("longest member", 1, true), "the leader hears who leads next")
        T.eq(#ns.Gangs:Actions(), 0, "nothing kept before yes")
        StaticPopupDialogs[ns.Gangs.LEAVE_POPUP].OnAccept()
        T.eq(ns.Gangs:Actions()[1].kind, "leave", "left after yes")
    end)

    T.case("Social window title: the gang's name, and waiting for Sync until the website confirmed it", function()
        local ns = Boot()
        T.eq(ns.SocialTab.Title(), "Gang", "no gang")
        H.Slash("gang create Western Gods")
        T.eq(ns.SocialTab.Title(), "Gang - Western Gods (waiting for Sync)", "not on the website yet")
        local confirmed = Boot(Data({ Gang("Western Gods", "Vati Guda", { "Vati Guda" }) }))
        T.eq(confirmed.SocialTab.Title(), "Gang - Western Gods", "confirmed")
    end)

    T.case("gang chat: an ordinary channel labelled [Gang], shown in the main window once, /gang sends or opens it", function()
        local data = Data()
        data.characters[1].gang_chat = { channel = "HHGabcdefghijkl", password = "secret" }
        local ns = Boot(data)
        H.joinWorks = true
        local added = {}
        _G.DEFAULT_CHAT_FRAME = { AddChannel = function(_, name) added[#added + 1] = name end }
        ns.db.settings.gangChatShown = false
        T.ok(ns.GangChat:Join(), "joined")
        T.eq(added[1], "HHGabcdefghijkl", "shown in the main chat window")
        ns.GangChat:Join()
        T.eq(#added, 1, "only once: the player's chat settings decide after that")
        H.chatSent = {}
        SlashCmdList.HEADHUNTERGANGCHAT("  hello  ")
        T.eq(H.chatSent[1].chatType, "CHANNEL", "sent to the channel")
        T.eq(H.chatSent[1].text, "hello", "trimmed")
        local opened
        _G.ChatFrame_OpenChat = function(text) opened = text end
        SlashCmdList.HEADHUNTERGANGCHAT("")
        T.eq(opened, "/5 ", "/gang alone opens the chat box on the gang channel")
        T.eq(_G.SLASH_HEADHUNTERGANGCHAT2, nil, "no /gc (GudaChat has it)")
        local hidden = false
        for _, fn in ipairs(H.chatFilterList.CHAT_MSG_CHANNEL or {}) do
            if fn(nil, "CHAT_MSG_CHANNEL", "hi", "Tobin Ashford", "", "5. HHGabcdefghijkl", "", "", 0, 5, "HHGabcdefghijkl") then
                hidden = true
            end
        end
        T.ok(hidden, "the game's own line is hidden")
        local shown = {}
        _G.ChatFrame1 = { AddMessage = function(_, text) shown[#shown + 1] = text end }
        _G.ChatFrame3 = { AddMessage = function(_, text) shown[#shown + 1] = "tab3:" .. text end }
        _G.GetChatWindowChannels = function(i)
            if i == 1 or i == 3 then return "Trade", 2, "HHGabcdefghijkl", 0 end
            return "Trade", 2
        end
        ns.GangChat:OnChannelText("hi all", "Tobin Ashford", "HHGabcdefghijkl", "5. HHGabcdefghijkl")
        T.eq(#shown, 2, "printed into every window that lists the gang channel")
        T.ok(shown[1]:find("[Gang]", 1, true) and shown[1]:find("hi all", 1, true), "as [Gang]")
        T.ok(shown[1]:find("|Hchannel:channel:5|h", 1, true), "[Gang] opens gang chat")
        T.ok(shown[2]:find("^tab3:"), "also in the tab the player gave it")
        T.ok(not ns.GangChat.LabelFilter(nil, "CHAT_MSG_CHANNEL", "x", "y", "", "6. Trade", "", "", 0, 6, "Trade"), "other channels untouched")
        local header = { SetText = function(self, text) self.text = text end, SetTextColor = function() end, GetWidth = function() return 40 end }
        local box = { header = header, GetAttribute = function(_, name) return ({ chatType = "CHANNEL", channelTarget = 5 })[name] end }
        ns.GangChat.OnHeaderUpdate(box)
        T.eq(header.text, "Gang: ", "the chat box says Gang:")
        local hooks = {}
        local updateHeader = function() header:SetText("[5. HHGabcdefghijkl]: ") end
        local tab = { header = header, GetAttribute = box.GetAttribute, UpdateHeader = updateHeader,
            HookScript = function(self, script, fn) hooks[script] = fn end }
        _G.ChatFrame4EditBox = tab
        T.ok(ns.GangChat.HookHeaders() >= 1, "every chat box hooked")
        T.ok(rawequal(tab.UpdateHeader, updateHeader), "the box's own method is left alone")
        header:SetText("[5. HHGabcdefghijkl]: ")
        hooks.OnShow(tab)
        T.eq(header.text, "Gang: ", "a new window's box says Gang: when it shows")
        header:SetText("[5. HHGabcdefghijkl]: ")
        H.Advance(0)
        T.eq(header.text, "Gang: ", "and again right after, over the game's own header")
    end)

    T.case("gang chat: none without the website's channel, and leaving the gang leaves it", function()
        local ns = Boot(Data())
        T.ok(not ns.GangChat:Join(), "no channel before the website confirmed the gang")
        H.chatSent = {}
        SlashCmdList.HEADHUNTERGANGCHAT("hello")
        T.eq(#H.chatSent, 0, "nothing sent")
        T.ok(H.Printed("not in a gang chat"), "said why")
    end)

    T.case("classes travel with the invite and the answer, so every member shows its class at once", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda" }) }))
        H.sent = {}
        H.Slash("gang invite Tobin Ashford")
        Settle()
        T.ok(Whispers("i;Black Hand;ROGUE")[1] ~= nil, "our class goes with the invite")
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "a;MAGE" }), "Tobin Ashford")
        local tobin
        for _, member in ipairs(ns.Gangs:Mine().members) do
            if member.key == "Tobin Ashford" then tobin = member end
        end
        T.eq(ns.Gangs:MemberClass(tobin), "MAGE", "their class from the answer")

        local member = Boot()
        H.sent = {}
        H.Deliver(member.Protocol.Pack("A", member.Protocol.TYPES.GANG, { "i;Black Hand;WARRIOR" }), "Kira Dawnblade")
        StaticPopupDialogs[member.Gangs.POPUP].OnAccept()
        Settle()
        T.ok(Whispers("a;ROGUE")[1] ~= nil, "our class goes with the accept")
        local leader = member.Gangs:Mine().members[1]
        T.eq(member.Gangs:MemberClass(leader), "WARRIOR", "the leader's class from the invite")
    end)

    T.case("Invite target: the target's class is known at once", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda" }) }))
        H.units.target = { name = "Mira Vale", isPlayer = true, faction = "Alliance", class = "PRIEST" }
        ns.Gangs:Command({ "invite" })
        local action = ns.Gangs:Actions()[#ns.Gangs:Actions()]
        T.eq(action.player, "Mira Vale", "the target invited")
        T.eq(action.memberClass, "PRIEST", "with its class")
    end)

    T.case("a member who leaves is off the others' lists at once; a kick too", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford", "Mira Vale" }) }))
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "l" }), "Tobin Ashford")
        local function Names()
            local names = {}
            for _, member in ipairs(ns.Gangs:Mine().members) do names[#names + 1] = member.key end
            return table.concat(names, ",")
        end
        T.eq(Names(), "Vati Guda,Mira Vale", "Tobin off our list")
        T.ok(H.Printed("left the gang"), "said")
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "l" }), "Somebody Else")
        T.eq(Names(), "Vati Guda,Mira Vale", "a stranger's leave changes nothing")
        H.Slash("gang kick Mira Vale")
        T.eq(Names(), "Vati Guda", "the kicked member off our list at once")

        local member = Boot(Data({ Gang("Black Hand", "Tobin Ashford", { "Tobin Ashford", "Vati Guda" }) }))
        H.sent = {}
        H.Slash("gang leave")
        Settle()
        T.ok(Whispers("l")[1] ~= nil and Whispers("l")[1].target == "Tobin Ashford", "we tell the others when we leave")
    end)

    T.case("invite: a member already in the gang is not invited again", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) }))
        H.printed, H.sent = {}, {}
        H.Slash("gang invite Tobin Ashford")
        Settle()
        T.ok(H.Printed("already in your gang"), "said")
        T.eq(#Whispers("i;"), 0, "no invite sent")
    end)

    T.case("gang rules: within 24 hours of leaving, an invite is turned down at once and both are told", function()
        local member = Boot(Data({ Gang("Old Crew", "Kira Dawnblade", { "Kira Dawnblade", "Vati Guda" }) }))
        H.Slash("gang leave")
        H.printed, H.sent, H.popups = {}, {}, {}
        H.Deliver(member.Protocol.Pack("A", member.Protocol.TYPES.GANG, { "i;Black Hand;WARRIOR" }), "Tobin Ashford")
        Settle()
        T.eq(#H.popups, 0, "no popup")
        T.ok(H.Printed("Gang rules: you left a gang less than 24 hours ago"), "we are told")
        T.ok(H.Printed("24 h"), "with the time left")
        T.ok(Whispers("c;")[1] ~= nil, "the inviter is told")

        local leader = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda" }) }))
        H.printed = {}
        H.Slash("gang invite Gang Ster")
        H.Deliver(leader.Protocol.Pack("A", leader.Protocol.TYPES.GANG, { "c;61200" }), "Gang Ster")
        T.ok(H.Printed("Gang rules: Gang Ster left a gang less than 24 hours ago and can join again in 17 h"), "the leader hears why")
    end)

    T.case("gang rules: a member who told us they left is not invited again within 24 hours", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) }))
        H.Deliver(ns.Protocol.Pack("A", ns.Protocol.TYPES.GANG, { "l" }), "Tobin Ashford")
        H.printed, H.sent = {}, {}
        H.Slash("gang invite Tobin Ashford")
        Settle()
        T.ok(H.Printed("Gang rules: Tobin Ashford left a gang"), "said")
        T.eq(#Whispers("i;"), 0, "no invite sent")
    end)

    T.case("testreset (HeadHunter_Dev only) clears the 24-hour rule on this character", function()
        local ns = H.Boot({ client = "forever", playerGUID = "Player-" .. PVP .. "-00ABCDEF", dev = { trust = {} } })
        Settle()
        H.Slash("gang create Black Hand")
        H.Slash("gang leave")
        T.ok(ns.Gangs:CooldownLeft() ~= nil, "waiting after leaving")
        H.Slash("gang testreset")
        T.eq(ns.Gangs:CooldownLeft(), nil, "cleared")
        local player = Boot()
        H.Slash("gang create Black Hand")
        H.Slash("gang leave")
        H.printed = {}
        H.Slash("gang testreset")
        T.ok(player.Gangs:CooldownLeft() ~= nil, "not without HeadHunter_Dev")
    end)

    T.case("create: a name another gang of our world has is refused at once, and the 24-hour rule too", function()
        local ns = Boot(Data({ Gang("Western Gods", "Andy Gue", { "Andy Gue" }) }))
        H.printed = {}
        H.Slash("gang create western   gods")
        T.ok(H.Printed("already taken"), "said")
        T.eq(#ns.Gangs:Actions(), 0, "nothing kept")
        H.Slash("gang create Black Hand")
        H.Slash("gang leave")
        H.printed = {}
        H.Slash("gang create Red Fang")
        T.ok(H.Printed("Gang rules: you left a gang"), "the 24-hour rule")
    end)

    T.case("not in a gang: the Gang page says where to check that a name is free", function()
        local ns = Boot()
        local text = ns.Gangs.EmptyText()
        local link, create = text:find("headhunterwow.com/gangs", 1, true), text:find("/hh gang create", 1, true)
        T.ok(link and create and link < create, "first where to check the name, then how to make one")
    end)

    T.case("an invite to a player already in a gang: both are told why", function()
        local member = Boot(Data({ Gang("Old Crew", "Kira Dawnblade", { "Kira Dawnblade", "Vati Guda" }) }))
        H.printed, H.sent, H.popups = {}, {}, {}
        H.Deliver(member.Protocol.Pack("A", member.Protocol.TYPES.GANG, { "i;Black Hand;WARRIOR" }), "Tobin Ashford")
        Settle()
        T.eq(#H.popups, 0, "no popup")
        T.ok(H.Printed("but you are in a gang"), "we are told")
        T.ok(Whispers("g")[1] ~= nil, "the inviter is told")

        local leader = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda" }) }))
        H.printed = {}
        H.Slash("gang invite Gang Ster")
        H.Deliver(leader.Protocol.Pack("A", leader.Protocol.TYPES.GANG, { "g" }), "Gang Ster")
        T.ok(H.Printed("Gang Ster is already in a gang"), "the leader hears why")
    end)

    T.case("right-click menu: whisper and group invite for anyone, make leader and kick for the leader", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) }))
        local labels = {}
        for _, item in ipairs(ns.GangMenu.Items("Tobin Ashford")) do labels[#labels + 1] = item.label end
        T.eq(table.concat(labels, ","), "Whisper,Invite to group,Make leader,Kick", "the leader's menu")
        T.eq(#ns.GangMenu.Items("Vati Guda"), 0, "none for ourselves")
        local member = Boot(Data({ Gang("Black Hand", "Tobin Ashford", { "Tobin Ashford", "Vati Guda" }) }))
        labels = {}
        for _, item in ipairs(member.GangMenu.Items("Tobin Ashford")) do labels[#labels + 1] = item.label end
        T.eq(table.concat(labels, ","), "Whisper,Invite to group", "a member's menu")
        H.popups = {}
        ns.GangMenu.Items("Tobin Ashford")[4].run()
        T.ok(H.popups[1] and H.popups[1].text:find("Tobin Ashford", 1, true), "kick asks first")
    end)

    T.case("level and online: from the website or the invite, online from the gang channel", function()
        local data = Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) })
        data.worlds["forever|us|pvp"].gangs[1].members[2].level = 27
        data.characters[1].gang_chat = { channel = "HHGabcdefghijkl", password = "secret" }
        local ns = Boot(data)
        H.joinWorks = true
        ns.GangChat:Join()
        local tobin = ns.Gangs:Mine().members[2]
        T.eq(ns.Gangs:MemberLevel(tobin), 27, "the website's level")
        T.ok(not ns.Gangs:IsOnline("Tobin Ashford"), "not seen: offline")
        ns.GangChat:OnJoinLeave(true, "Tobin Ashford", "HHGabcdefghijkl", "6. HHGabcdefghijkl")
        T.ok(ns.Gangs:IsOnline("Tobin Ashford"), "joined the gang channel: online")
        T.ok(ns.SocialTab.MemberDetails(tobin, ns.Gangs:Mine()):find("Level 27", 1, true), "level on the Social page")
        ns.GangChat:OnJoinLeave(false, "Tobin Ashford", "HHGabcdefghijkl", "6. HHGabcdefghijkl")
        T.ok(not ns.Gangs:IsOnline("Tobin Ashford"), "left it: offline")
        H.Advance(5)
        ns.Presence:Heard("Tobin Ashford", "Alliance", "1.0.0")
        T.ok(ns.Gangs:IsOnline("Tobin Ashford"), "heard on the HeadHunter channel after leaving the gang channel: online")
        T.ok(ns.Gangs:IsOnline("Vati Guda"), "we are online")
    end)

    T.case("right-click menu: Blizzard's menu at the cursor with our entries, else our own at the cursor", function()
        local ns = Boot(Data({ Gang("Black Hand", "Vati Guda", { "Vati Guda", "Tobin Ashford" }) }))
        local built = {}
        _G.MenuUtil = { CreateContextMenu = function(owner, generator)
            local root = {
                CreateTitle = function(_, text) built.title = text end,
                CreateButton = function(_, label) built[#built + 1] = label end,
            }
            generator(owner, root)
        end }
        ns.GangMenu:Open("Tobin Ashford")
        T.eq(built.title, "Tobin Ashford", "titled with the member")
        T.eq(table.concat(built, ","), "Whisper,Invite to group,Make leader,Kick", "our entries in Blizzard's menu")
        _G.MenuUtil = nil
        _G.GetCursorPosition = function() return 400, 300 end
        ns.GangMenu:Open("Tobin Ashford")
        local menu = _G.HeadHunterGangMenu
        T.eq(menu.point[1], "TOPLEFT", "our own menu")
        T.eq(menu.point[4], 400, "at the cursor's x")
        T.eq(menu.point[5], 300, "and y, not the screen's centre")
    end)

    T.case("gang chat: /gang right after login joins the channel on the spot", function()
        local data = Data()
        data.characters[1].gang_chat = { channel = "HHGabcdefghijkl", password = "secret" }
        Boot(data)
        H.joinWorks = true
        H.chatSent = {}
        SlashCmdList.HEADHUNTERGANGCHAT("hello")
        T.eq(#H.chatSent, 1, "joined and sent at once")
    end)

    T.case("gang chat test switch: /gang + space switches the chat box only when turned on", function()
        local data = Data()
        data.characters[1].gang_chat = { channel = "HHGabcdefghijkl", password = "secret" }
        local ns = Boot(data)
        H.joinWorks = true
        ns.GangChat:Join()
        local box = { text = "/gang ", GetText = function(self) return self.text end, SetText = function(self, t) self.text = t end,
            SetChatType = function(self, t) self.chatType = t end, SetStickyType = function(self, t) self.sticky = t end,
            SetChannelTarget = function(self, id) self.target = id end, UpdateHeader = function() end }
        T.ok(not ns.GangChat.SwitchOnSlash(box), "off by default")
        H.Slash("gang slashswitch on")
        T.ok(ns.GangChat.SwitchOnSlash(box), "switched")
        T.eq(box.chatType, "CHANNEL", "channel chat")
        T.eq(box.target, 5, "the gang channel")
        T.eq(box.text, "", "the box cleared for typing")
    end)

    T.case("gang chat channels: Gang_HH names, and old HHG ones are left", function()
        local ns = Boot()
        T.ok(ns.GangChat.IsGangChannel("Gang_HHook1esog2mvm"), "a gang channel")
        T.ok(ns.GangChat.IsGangChannel("HHGenahnifl42vu"), "an old one, to leave")
        T.ok(not ns.GangChat.IsGangChannel("Trade"), "not Trade")
    end)
end
