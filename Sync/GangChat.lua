-- HH-155: gang chat, like guild chat. The website gives each gang a hidden game chat
-- channel with a password and sends both only to its members (the download's
-- characters[...].gang_chat). We join it, keep it out of the chat windows' own channel
-- list, and show its lines ourselves as "[Gang] Name: text" in the gang chat colour.
-- /gang <text> and /gc <text> send to it (typing and Enter is the key press the game asks
-- for). A gang's channel changes when a member is kicked; any other HHG channel we are
-- in is left. WoW Forever only, and only once the website confirmed the gang.

local addonName, ns = ...
local L = ns.L

local GangChat = ns:RegisterModule("GangChat", {})

local OWNER = "GangChat"

GangChat.PREFIX = "HHG"
-- seconds after login before joining, so the game's own channels take the first slots
GangChat.JOIN_DELAY = 12
GangChat.DEFAULT_COLOR = "ff9f40"

local current

-- The channel and password the website sent for our character, or nil
function GangChat.Credentials()
    if not ns.Gangs.Enabled() then return nil end
    return ns.SiteData:GangChat(ns.Utils.UnitKey("player"))
end

local function ChannelId(name)
    local id = name and tonumber((ns.Utils.SafeCall(GetChannelName, name)))
    return id and id > 0 and id or nil
end

local function IsGangChannel(name)
    return type(name) == "string" and name:sub(1, #GangChat.PREFIX) == GangChat.PREFIX
end

-- The chat windows do not list our channel; its lines come from us
local function KeepOutOfChatWindows(name)
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local window = _G["ChatFrame" .. i]
        if window then
            if window.RemoveChannel then
                pcall(window.RemoveChannel, window, name)
            elseif ChatFrame_RemoveChannel then
                pcall(ChatFrame_RemoveChannel, window, name)
            end
        end
    end
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
    KeepOutOfChatWindows(chat.channel)
    return true
end

function GangChat:Leave()
    if current then pcall(LeaveChannelByName, current) end
    current = nil
end

function GangChat:Channel()
    return current
end

-- "ff9f40" -> r, g, b (0..1)
function GangChat.Color()
    local hex = ns.db and ns.db.settings.gangChatColor or GangChat.DEFAULT_COLOR
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then hex = GangChat.DEFAULT_COLOR end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function GangChat.SetColor(hex)
    hex = type(hex) == "string" and hex:gsub("^#", ""):lower() or ""
    if not hex:match("^%x%x%x%x%x%x$") then return false end
    ns.Database:SetSetting("gangChatColor", hex)
    return true
end

-- "[Gang] [Andy Gue]: text", the name a link like in guild chat
function GangChat.Line(sender, text)
    local key = ns.Utils.PlayerKey(sender) or sender
    local shown = ns.Utils.DisplayName(key) or key
    return string.format("%s |Hplayer:%s|h[%s]|h: %s", L.GANG_CHAT_TAG, sender, shown, text)
end

function GangChat:OnChannelText(text, sender, channelBaseName, channelName)
    local name = channelBaseName ~= "" and channelBaseName or (type(channelName) == "string" and channelName:match("^%d+%. (.+)$"))
    if not current or name ~= current or type(text) ~= "string" then return end
    local window = DEFAULT_CHAT_FRAME
    if window and window.AddMessage then window:AddMessage(self.Line(sender, text), self.Color()) end
end

function GangChat:Send(text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text == "" then ns:Print(L.GANG_CHAT_USAGE) return false end
    local id = ChannelId(current)
    if not id then ns:Print(L.GANG_CHAT_NONE) return false end
    SendChatMessage(text, "CHANNEL", nil, id)
    return true
end

_G.SLASH_HEADHUNTERGANGCHAT1 = "/gang"
_G.SLASH_HEADHUNTERGANGCHAT2 = "/gc"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList.HEADHUNTERGANGCHAT = function(text) GangChat:Send(text) end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("CHAT_MSG_CHANNEL", function(_, text, sender, _, channelName, _, _, _, _, channelBaseName)
        GangChat:OnChannelText(text, sender, channelBaseName, channelName)
    end, OWNER)
    ns.Events:Register("HH_GANG_CHANGED", function(_, action)
        if action and action.kind == "leave" then GangChat:Leave() end
    end, OWNER)
    C_Timer.After(GangChat.JOIN_DELAY, function() GangChat:Join() end)
end, OWNER)
