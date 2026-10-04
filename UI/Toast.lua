-- A HeadHunter notice under the minimap (author, 2026-10-04): a small parchment poster
-- like the WANTED poster (UI/Poster.lua) with a red stamp over it, and a gold button
-- with an icon below. One at a time: a new one replaces the one on show. It closes
-- itself after `seconds` (30 by default), on the button, or with its x.
--
--   Toast:Show({ heading, title, titleInfo, stamp, text, textInfo, icon, accept, decline,
--                onAccept, onDecline, seconds })
--     heading: "WANTED" at the top; title and titleInfo: the name and a line of icons
--     and level; stamp: red text in a box ("BUSTED"); text and textInfo: two lines under
--     it; icon and accept, decline: the buttons under the paper (see-through, gold edge)
--   Toast:Hide(), Toast:IsShown(), Toast:Accept(), Toast:Decline() (the button and x, also for tests)

local addonName, ns = ...

local Toast = ns:RegisterModule("Toast", {})

Toast.WIDTH = 220
Toast.PAPER_HEIGHT = 262
Toast.BUTTON_HEIGHT = 30
Toast.SECONDS = 30
Toast.GAP = 12 -- below the minimap

local frame, current, closesAt

local function Anchor(f)
    f:ClearAllPoints()
    local minimap = _G.MinimapCluster or _G.Minimap
    if minimap then
        f:SetPoint("TOPRIGHT", minimap, "BOTTOMRIGHT", -8, -Toast.GAP)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -220)
    end
end

-- A frame of `size` px lines in `color` around `f`
local function Outline(f, color, alpha, size)
    local sides = {
        { "TOPLEFT", "TOPRIGHT", nil, size }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, size },
        { "TOPLEFT", "BOTTOMLEFT", size, nil }, { "TOPRIGHT", "BOTTOMRIGHT", size, nil },
    }
    for _, side in ipairs(sides) do
        local line = f:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(color[1], color[2], color[3], alpha)
        line:SetPoint(side[1])
        line:SetPoint(side[2])
        if side[3] then line:SetWidth(side[3]) else line:SetHeight(side[4]) end
    end
end

local function PaperText(paper, role, size, color, relative, y)
    local fs = ns.Theme.Text(paper, role, size, color)
    fs:SetPoint("TOP", relative or paper, relative and "BOTTOM" or "TOP", 0, y)
    fs:SetWidth(Toast.WIDTH - 30)
    fs:SetJustifyH("CENTER")
    return fs
end

local function Create()
    local Theme, C = ns.Theme, ns.Theme.COLORS
    local f = CreateFrame("Frame", "HeadHunterToast", UIParent)
    f:SetSize(Toast.WIDTH, Toast.PAPER_HEIGHT + 8 + Toast.BUTTON_HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)

    -- The parchment, with a dark edge so it stands out from the game world
    local paper = CreateFrame("Frame", nil, f)
    paper:SetPoint("TOPLEFT")
    paper:SetPoint("TOPRIGHT")
    paper:SetHeight(Toast.PAPER_HEIGHT)
    local bg = paper:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(Theme.TEXTURES.poster)
    bg:SetAllPoints(paper)
    Outline(paper, { 0, 0, 0 }, 0.8, 2)
    local pin = paper:CreateTexture(nil, "ARTWORK")
    pin:SetTexture(Theme.TEXTURES.pin)
    pin:SetSize(14, 14)
    pin:SetPoint("TOP", 0, -6)

    f.heading = PaperText(paper, "western", 30, "wanted", nil, -22)
    local rule = paper:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.parchmentText[1], C.parchmentText[2], C.parchmentText[3], 0.3)
    rule:SetSize(Toast.WIDTH - 50, 1)
    rule:SetPoint("TOP", f.heading, "BOTTOM", 0, -6)
    f.title = PaperText(paper, "western", 20, "parchmentText", rule, -10)
    f.titleInfo = PaperText(paper, "bold", 13, "parchmentText", f.title, -4)

    -- The red stamp between the two players
    local stamp = CreateFrame("Frame", nil, paper)
    f.stampBox = stamp
    stamp:SetSize(Toast.WIDTH - 50, 44)
    stamp:SetPoint("TOP", f.titleInfo, "BOTTOM", 0, -12)
    stamp:SetFrameLevel(paper:GetFrameLevel() + 2)
    Outline(stamp, C.wanted, 0.9, 3)
    f.stamp = Theme.Text(stamp, "western", 32, "wanted")
    f.stamp:SetPoint("CENTER", 0, 0)
    f.stamp:SetAlpha(0.95)
    f.text = PaperText(paper, "bold", 13, "parchmentText", stamp, -12)
    f.textInfo = PaperText(paper, "bold", 13, "parchmentText", f.text, -4)

    local close = CreateFrame("Button", nil, paper)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -4, -4)
    local x = Theme.Text(close, "bold", 15, "parchmentText")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
    close:SetScript("OnClick", function() Toast:Decline() end)

    -- See-through buttons with a gold edge: the one with the icon, and the other on its right
    f.decline = Theme.Button(f, "", "outline", 80, Toast.BUTTON_HEIGHT)
    f.decline:SetPoint("TOPRIGHT", paper, "BOTTOMRIGHT", 0, -8)
    f.decline:SetScript("OnClick", function() Toast:Decline() end)
    f.accept = Theme.Button(f, "", "outline", Toast.WIDTH - 88, Toast.BUTTON_HEIGHT)
    f.accept:SetPoint("TOPLEFT", paper, "BOTTOMLEFT", 0, -8)
    f.accept:SetScript("OnClick", function() Toast:Accept() end)
    -- The label moves right to make room for the icon on its left
    local label = f.accept:GetFontString()
    f.icon = f.accept:CreateTexture(nil, "OVERLAY")
    f.icon:SetSize(22, 22)
    if label then
        label:SetPoint("CENTER", 12, 0)
        f.icon:SetPoint("RIGHT", label, "LEFT", -6, 0)
    end

    f:SetScript("OnUpdate", function()
        if closesAt and ns.Utils.Now() >= closesAt then Toast:Decline() end
    end)
    Theme.ApplyScale(f)
    f:Hide()
    return f
end

function Toast:Show(notice)
    local Theme = ns.Theme
    frame = frame or Create()
    current = notice
    local width = self.WIDTH - 30
    Theme.FitText(frame.heading, notice.heading or "", "western", 30, width, 16)
    Theme.FitText(frame.title, notice.title or "", "western", 20, width, 12)
    frame.titleInfo:SetText(notice.titleInfo or "")
    frame.text:SetText(notice.text or "")
    frame.textInfo:SetText(notice.textInfo or "")
    Theme.FitText(frame.stamp, notice.stamp or "", "western", 32, self.WIDTH - 70, 16)
    frame.stampBox:SetShown(notice.stamp ~= nil)
    frame.accept:SetText(notice.accept or "")
    frame.accept:SetShown(notice.accept ~= nil)
    frame.decline:SetText(notice.decline or "")
    frame.decline:SetShown(notice.decline ~= nil)
    frame.icon:SetTexture(notice.icon)
    frame.icon:SetShown(notice.icon ~= nil)
    closesAt = ns.Utils.Now() + (notice.seconds or self.SECONDS)
    Anchor(frame)
    frame:Show()
    return frame
end

local function Close(handler)
    local notice = current
    current, closesAt = nil, nil
    if frame then frame:Hide() end
    if notice and notice[handler] then notice[handler]() end
end

function Toast:Accept() Close("onAccept") end
function Toast:Decline() Close("onDecline") end
function Toast:Hide() Close(nil) end

function Toast:IsShown()
    return frame ~= nil and frame:IsShown() and current ~= nil
end

-- What is on show (tests): { title, text, ... } or nil
function Toast:Current()
    return current
end

-- Leaving the world for an instance closes it, as the alerts' queue is dropped there
ns.Events:Register("HH_SUSPEND_CHANGED", function(_, suspended)
    if suspended then Toast:Hide() end
end, "Toast")
