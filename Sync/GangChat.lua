-- HH-155: gang chat, like guild chat. The website gives each gang a hidden game chat
-- channel with a password and sends both only to its members (the download's
-- characters[...].gang_chat). We join it and it is an ordinary chat channel: put in the
-- main chat window the first time (the game's chat settings move it to any window or tab),
-- its sticky chat box (/<number> + space) with the header "Gang:". Its lines are printed by
-- us as "[Gang] [Name]: text" into every chat window that lists the channel; the game's own
-- line is hidden, as a shown name shorter than the channel's name makes the chat windows
-- drop the line. The colour and the class-coloured names are the channel's own in the
-- game's chat settings (author, 2026-11-28): we give them our defaults (light green, class
-- colours on) and carry the player's choice to a new gang channel after a kick (gangChatColor,
-- gangChatClassNames keep it). /gang <text> sends; /gang alone opens the
-- chat box on gang chat. The chat box's chat type is never set from our code (that taints
-- protected commands typed in chat). A gang's channel changes when a member is kicked; any
-- other gang channel we are in (GangHH…, or Gang_HH… and HHG… from before) is left. WoW
-- Forever only.
-- The channel works before any sync: the leader's addon makes it and whispers it to each
-- member who accepts (Gangs.lua); what this character saved wins over an older download.

local addonName, ns = ...
local L = ns.L

local GangChat = ns:RegisterModule("GangChat", {})

local OWNER = "GangChat"

-- gang chat channel names (the website's Gang::CHAT_PREFIX); older ones started with
-- Gang_HH or HHG
GangChat.PREFIX = ns.Gangs.CHAT_PREFIX
GangChat.OLD_PREFIXES = { ns.Gangs.OLD_CHAT_PREFIX, "HHG" }
-- 1.0.5: joined this long after our sync channel (Transport: after the game's own
-- channels), so it never takes /1 ahead of General (seen in game 2026-11-06: gang /1,
-- sync /2, General /3); without the sync channel, at JOIN_WAIT_MAX after login
GangChat.JOIN_DELAY = 1
GangChat.JOIN_WAIT_MAX = 45
GangChat.DEFAULT_COLOR = "d4ffb6"
-- the default before the game's chat settings had the colour: kept by everyone who never
-- changed it, so it means "not chosen" and gives way to DEFAULT_COLOR
GangChat.OLD_DEFAULT_COLOR = "ff9f40"

local current
-- true once the first join after login ran (JOIN_DELAY): from then on a gang change joins
-- or leaves at once
local ready = false
-- player key -> { online = true (joined or spoke in the gang channel) or false (left it), t }
local presence = {}

-- Our gang's channel and password while we are in a gang: { channel, password, at (the
-- leader's action that set it) }. The ones this character saved (made as leader, or
-- whispered by the leader) unless the website applied a channel at least as new, else the
-- download's; nil once we left (the download still has it until the next sync), and for a
-- channel name the game refuses
function GangChat.Credentials()
    if not ns.Gangs.Enabled() or ns.Gangs:Sim() then return nil end
    if not ns.Gangs:Mine() then return nil end
    local saved = ns.Gangs:SavedChat()
    local site = ns.SiteData:GangChat(ns.Utils.UnitKey("player"))
    if site and not ns.Gangs.ValidChat(site.channel, site.password) then site = nil end
    if saved and (not site or saved.at > (site.at or 0)) then return saved end
    return site or saved
end

local function OurChannel(channelBaseName, channelName)
    local name = channelBaseName ~= "" and channelBaseName or (type(channelName) == "string" and channelName:match("^%d+%. (.+)$"))
    return current ~= nil and name == current
end

local function ChannelId(name)
    local id = name and tonumber((ns.Utils.SafeCall(GetChannelName, name)))
    return id and id > 0 and id or nil
end

local function IsGangChannel(name)
    if type(name) ~= "string" then return false end
    if name:sub(1, #GangChat.PREFIX) == GangChat.PREFIX then return true end
    for _, prefix in ipairs(GangChat.OLD_PREFIXES) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end
GangChat.IsGangChannel = IsGangChannel

-- The first time we are in a gang channel it goes to the main chat window; after that the
-- player's own chat settings decide where it shows. Only once the game has joined it: a chat
-- window refuses a channel we are not in yet, and the join answers a moment later
local function ShowInMainWindow(name)
    if not name or not ns.db or ns.db.settings.gangChatWindow == name or not ChannelId(name) then return end
    local window = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    if window then
        if window.AddChannel then
            pcall(window.AddChannel, window, name)
        elseif ChatFrame_AddChannel then
            pcall(ChatFrame_AddChannel, window, name)
        end
    end
    ns.Database:SetSetting("gangChatWindow", name)
end


-- Old gang channels we are still in (a kick moved the gang, or we left it)
local function LeaveOthers(keep)
    if not GetChannelList then return end
    local list = { ns.Utils.SafeCall(GetChannelList) }
    for i = 2, #list, 3 do
        local name = list[i]
        if IsGangChannel(name) and name ~= keep then pcall(LeaveChannelByName, name) end
    end
end

function GangChat:Join()
    local chat = self.Credentials()
    LeaveOthers(chat and chat.channel)
    if not chat then
        current = nil
        return false
    end
    current = chat.channel
    if not ChannelId(chat.channel) then
        local join = securecall or function(fn, ...) return fn(...) end
        pcall(join, JoinChannelByName, chat.channel, chat.password, 0, 0)
    end
    ShowInMainWindow(chat.channel)
    GangChat.ApplyChatSettings()
    return true
end

function GangChat:Channel()
    return current
end

-- What the gang channel last told us of a player: { online, t (Utils.Now()) } or nil
function GangChat:Seen(key)
    for name, state in pairs(presence) do
        if ns.Utils.SameCharacter(name, key) then return state end
    end
    return nil
end

function GangChat:OnJoinLeave(joined, sender, channelBaseName, channelName)
    if not OurChannel(channelBaseName, channelName) then return end
    local key = ns.Utils.PlayerKey(sender)
    if not key then return end
    presence[key] = { online = joined, t = ns.Utils.Now() }
    ns.Events:Fire("HH_GANG_CHANGED")
end

-- "ff9f40" -> r, g, b (0..1)
-- The game's chat type of our channel ("CHANNEL5"), or nil while we are not in it
local function ChatType()
    local id = ChannelId(current)
    return id and ("CHANNEL" .. id) or nil
end

local function ChatInfo()
    local chatType = ChatType()
    return chatType and type(ChatTypeInfo) == "table" and ChatTypeInfo[chatType] or nil
end

local function Rgb(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function Hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The colour the player chose for gang chat (hex), DEFAULT_COLOR when none
function GangChat.SavedColor()
    local hex = ns.db and ns.db.settings.gangChatColor
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") or hex == GangChat.OLD_DEFAULT_COLOR then
        return GangChat.DEFAULT_COLOR
    end
    return hex
end

-- Whether gang chat colours names by class, as the player chose (on unless they turned it off)
function GangChat.SavedClassNames()
    return not (ns.db and ns.db.settings.gangChatClassNames == false)
end

-- Gang chat's colour: the channel's in the game's chat settings, else the saved one
function GangChat.Color()
    local info = ChatInfo()
    if info and info.r then return info.r, info.g, info.b end
    return Rgb(GangChat.SavedColor())
end

-- Whether names are class coloured: the channel's "Color names by class", else the saved choice
function GangChat.ClassNames()
    local info = ChatInfo()
    if info and info.colorNameByClass ~= nil then return info.colorNameByClass and true or false end
    return GangChat.SavedClassNames()
end

-- Gives the channel the saved colour and class-name choice in the game's chat settings when
-- it has others: on the first join, and on a new channel after a kick
function GangChat.ApplyChatSettings()
    local chatType = ChatType()
    if not chatType then return end
    local info = ChatInfo()
    local hex = GangChat.SavedColor()
    if ChangeChatColor and not (info and info.r and Hex(info.r, info.g, info.b) == hex) then
        pcall(ChangeChatColor, chatType, Rgb(hex))
    end
    local classNames = GangChat.SavedClassNames()
    if SetChatColorNameByClass and not (info and info.colorNameByClass ~= nil and (info.colorNameByClass and true or false) == classNames) then
        pcall(SetChatColorNameByClass, chatType, classNames)
    end
end

-- The player changed our channel's colour in the game's chat settings: kept for a new channel
function GangChat:OnChatColor(chatType, r, g, b)
    if chatType == nil or chatType ~= ChatType() or type(r) ~= "number" then return end
    ns.Database:SetSetting("gangChatColor", Hex(r, g, b))
end

-- The player turned our channel's class-coloured names on or off: kept for a new channel
function GangChat:OnChatClassNames(chatType, on)
    if chatType == nil or chatType ~= ChatType() then return end
    ns.Database:SetSetting("gangChatClassNames", on and true or false)
end

-- /hh gang color: the colour in six hex digits, set in the game's chat settings too
function GangChat.SetColor(hex)
    hex = type(hex) == "string" and hex:gsub("^#", ""):lower() or ""
    if not hex:match("^%x%x%x%x%x%x$") then return false end
    ns.Database:SetSetting("gangChatColor", hex)
    GangChat.ApplyChatSettings()
    return true
end

-- A gang member's class token for a class-coloured name, or nil: the game's for the GUID,
-- else what HeadHunter knows of the gang member; nil while names are not class coloured
function GangChat.SenderClass(sender, guid)
    if not GangChat.ClassNames() then return nil end
    if guid then
        local _, class = ns.Utils.SafeCall(GetPlayerInfoByGUID, guid)
        if class and class ~= "" then return class end
    end
    local gang = ns.Gangs:Mine()
    local key = ns.Utils.PlayerKey(sender) or sender
    for _, member in ipairs(gang and gang.members or {}) do
        if ns.Utils.SameCharacter(member.key, key) then return ns.Gangs:MemberClass(member) end
    end
    return nil
end

-- A line in our channel: printed as [Gang] into the windows that list it; its sender spoke,
-- so they are online
function GangChat:OnChannelText(text, sender, channelBaseName, channelName, guid)
    if not OurChannel(channelBaseName, channelName) or type(text) ~= "string" then return end
    local key = ns.Utils.PlayerKey(sender)
    if key then presence[key] = { online = true, t = ns.Utils.Now() } end
    local line = self.Line(sender, text, ChannelId(current), self.SenderClass(sender, guid))
    for _, window in ipairs(self.Windows(current)) do
        if window.AddMessage then window:AddMessage(line, self.Color()) end
    end
end

-- Chat filter: the game's own line of our channel is hidden (we print it as [Gang]); its
-- join and leave notices too
function GangChat.LabelFilter(_, _, _, _, _, channelName, _, _, _, _, baseName)
    return OurChannel(baseName or "", channelName)
end

-- "[Gang] [Andy Gue]: text": [Gang] opens the chat box on gang chat, the name a player link,
-- in its class colour when given one
function GangChat.Line(sender, text, id, class)
    local key = ns.Utils.PlayerKey(sender) or sender
    local shown = ns.MainWindow.ClassColored(ns.Utils.DisplayName(key) or key, class)
    local label = id and string.format("|Hchannel:channel:%d|h[%s]|h", id, L.TAB_GANG) or ("[" .. L.TAB_GANG .. "]")
    return string.format("%s |Hplayer:%s|h[%s]|h: %s", label, sender, shown, text)
end

-- The chat windows that list a channel (the game's chat settings)
function GangChat.Windows(name)
    local windows = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local window = _G["ChatFrame" .. i]
        local list = window and GetChatWindowChannels and { ns.Utils.SafeCall(GetChatWindowChannels, i) } or {}
        for j = 1, #list, 2 do
            if list[j] == name then windows[#windows + 1] = window end
        end
    end
    return windows
end

-- The notices of our own joining and leaving it (YOU_CHANGED, YOU_LEFT...)
GangChat.QUIET_NOTICES = { YOU_JOINED = true, YOU_CHANGED = true, YOU_LEFT = true, SUSPENDED = true }

-- Chat filter: others joining or leaving our channel, and our own joins, are hidden; the
-- server's refusals (WRONG_PASSWORD, BANNED...) are shown, so a failed join says why
function GangChat.NoticeFilter(_, event, notice, _, _, channelName, _, _, _, _, baseName)
    if event == "CHAT_MSG_CHANNEL_NOTICE" and not GangChat.QUIET_NOTICES[notice] then return false end
    return OurChannel(baseName or "", channelName)
end

-- The game joined a channel: once it is ours, it goes to the main chat window with our colours
function GangChat:OnChannelsChanged()
    ShowInMainWindow(current)
    GangChat.ApplyChatSettings()
end

-- The sticky chat box on our channel says "Gang:" (a post-hook on Blizzard's header update;
-- only the header's text and the box's insets change, never its chat type)
function GangChat.OnHeaderUpdate(editBox)
    if not (editBox and editBox.GetAttribute and current) then return end
    if editBox:GetAttribute("chatType") ~= "CHANNEL" or tonumber(editBox:GetAttribute("channelTarget")) ~= ChannelId(current) then
        return
    end
    local header = editBox.header or (editBox.GetName and editBox:GetName() and _G[editBox:GetName() .. "Header"])
    if not (header and header.SetText) then return end
    header:SetText(L.GANG_CHAT_HEADER)
    header:SetTextColor(GangChat.Color())
    if editBox.SetTextInsets and header.GetWidth then
        local _, right, top, bottom = editBox:GetTextInsets()
        editBox:SetTextInsets(15 + header:GetWidth(), right or 13, top or 0, bottom or 0)
    end
end

-- "/gang " or "/gg " + space switches the chat box to gang chat as "/guild " does, with the box's own
-- SetChatType, SetStickyType, SetChannelTarget and UpdateHeader (setting gangChatSlash, on;
-- /hh gang slashswitch off turns it off). Checked in game 2026-11-04: /target typed in
-- that chat box afterwards still worked. Returns true when it switched.
GangChat.SWITCH_TEXTS = { ["/gang "] = true, ["/gg "] = true }

function GangChat.SwitchOnSlash(box)
    if not (ns.db and ns.db.settings.gangChatSlash ~= false and box and box.GetText) then return false end
    local text = box:GetText()
    if type(text) ~= "string" or not GangChat.SWITCH_TEXTS[text:lower()] then return false end
    local id = ChannelId(current)
    if not id then return false end
    if box.SetChatType then
        box:SetChatType("CHANNEL")
        if box.SetStickyType then box:SetStickyType("CHANNEL") end
        if box.SetChannelTarget then box:SetChannelTarget(id) end
    else
        box:SetAttribute("chatType", "CHANNEL")
        box:SetAttribute("stickyType", "CHANNEL")
        box:SetAttribute("channelTarget", id)
    end
    box:SetText("")
    if box.UpdateHeader then box:UpdateHeader() elseif ChatEdit_UpdateHeader then ChatEdit_UpdateHeader(box) end
    return true
end

-- "Gang:" once now and once right after, as the game may set its own header after these
-- scripts ran
local function HeaderSoon(box)
    GangChat.SwitchOnSlash(box)
    GangChat.OnHeaderUpdate(box)
    C_Timer.After(0, function() GangChat.OnHeaderUpdate(box) end)
end

-- The chat boxes' header: Blizzard's ChatEdit_UpdateHeader where the client has it, and each
-- box showing or its text changing (a sticky chat type is set then). Script hooks only,
-- never the boxes' own methods; returns how many boxes were hooked.
function GangChat.HookHeaders()
    if hooksecurefunc and _G.ChatEdit_UpdateHeader then hooksecurefunc("ChatEdit_UpdateHeader", GangChat.OnHeaderUpdate) end
    local hooked = 0
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box and box.HookScript then
            box:HookScript("OnShow", HeaderSoon)
            box:HookScript("OnTextChanged", HeaderSoon)
            hooked = hooked + 1
        end
    end
    return hooked
end

-- /gang <text> sends to gang chat; /gang alone opens the chat box on it, as /<number> would
function GangChat:Send(text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local id = ChannelId(current)
    if not id then
        if not self:Join() then ns:Print(L.GANG_CHAT_NONE) return false end
        id = ChannelId(current)
        if not id then ns:Print(L.GANG_CHAT_JOINING) return false end
    end
    if text == "" then
        if ChatFrame_OpenChat then ChatFrame_OpenChat("/" .. id .. " ") else ns:Print(L.GANG_CHAT_USAGE) end
        return false
    end
    SendChatMessage(text, "CHANNEL", nil, id)
    return true
end

_G.SLASH_HEADHUNTERGANGCHAT1 = "/gang"
_G.SLASH_HEADHUNTERGANGCHAT2 = "/gg"
_G.SlashCmdList.HEADHUNTERGANGCHAT = function(text) GangChat:Send(text) end

-- /gg is ours only while no other addon has it (author, 2026-11-28): two addons with one
-- slash command leave only one of them working, and our "/gg " + space switch would cut the
-- other addon's command short. At login, once every addon has loaded, another addon's /gg
-- takes both away; /gang stays. Returns true while /gg is ours.
function GangChat.ClaimShortcut()
    for name, value in pairs(_G) do
        if type(name) == "string" and type(value) == "string" and name:sub(1, 6) == "SLASH_"
            and not name:find("^SLASH_HEADHUNTERGANGCHAT%d+$") and value:lower() == "/gg" then
            _G.SLASH_HEADHUNTERGANGCHAT2 = nil
            GangChat.SWITCH_TEXTS["/gg "] = nil
            return false
        end
    end
    return true
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("CHAT_MSG_CHANNEL", function(_, text, sender, _, channelName, _, _, _, _, channelBaseName, _, _, guid)
        GangChat:OnChannelText(text, sender, channelBaseName, channelName, guid)
    end, OWNER)
    ns.Events:Register("UPDATE_CHAT_COLOR", function(_, chatType, r, g, b) GangChat:OnChatColor(chatType, r, g, b) end, OWNER)
    ns.Events:Register("UPDATE_CHAT_COLOR_NAME_BY_CLASS", function(_, chatType, on) GangChat:OnChatClassNames(chatType, on) end, OWNER)
    ns.Events:Register("CHAT_MSG_CHANNEL_JOIN", function(_, _, sender, _, channelName, _, _, _, _, channelBaseName)
        GangChat:OnJoinLeave(true, sender, channelBaseName, channelName)
    end, OWNER)
    ns.Events:Register("CHAT_MSG_CHANNEL_LEAVE", function(_, _, sender, _, channelName, _, _, _, _, channelBaseName)
        GangChat:OnJoinLeave(false, sender, channelBaseName, channelName)
    end, OWNER)
    ns.Events:Register("HH_GANG_CHANGED", function()
        if ready then GangChat:Join() end
    end, OWNER)
    ns.Events:Register("CHANNEL_UI_UPDATE", function() GangChat:OnChannelsChanged() end, OWNER)
    ns.Events:Register("CHAT_MSG_CHANNEL_NOTICE", function() GangChat:OnChannelsChanged() end, OWNER)
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then
        pcall(add, "CHAT_MSG_CHANNEL", GangChat.LabelFilter)
        for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN",
                "CHAT_MSG_CHANNEL_LEAVE" }) do
            pcall(add, event, GangChat.NoticeFilter)
        end
    end
    GangChat.HookHeaders()
    ns.Events:Register("PLAYER_LOGIN", function() GangChat.ClaimShortcut() end, OWNER)
    local function Start()
        if ready then return end
        ready = true
        GangChat:Join()
    end
    ns.Events:Register("HH_SYNC_CHANNEL_JOINED", function() C_Timer.After(GangChat.JOIN_DELAY, Start) end, OWNER)
    C_Timer.After(GangChat.JOIN_WAIT_MAX, Start)
end, OWNER)
