-- HH-161: the buckle windows.
--
--   You found a buckle                       Buckles (/hh buckles)    [ Grul Ironhide  v ]
--   [ the plate, then the buckle lights ]    [buckle] Hunter's Bane x2   [buckle] Pioneer
--   Hunter's Bane                            ...
--   Epic                                     dark plates: the ones still to find
--   Found by Grul Ironhide                   Choose the buckle you wear on the website.
--   Kill of the HeadHunter Moo Mello
--   Stranglethorn Vale · 2026-11-14
--   Choose the buckle you wear on the website.
--                            [Next (2 more)] / [OK]
--
-- The reveal shows our characters' new finds one after another: the plate first, grey,
-- then the buckle lights in its colours, then its name. Each find is marked shown
-- (Sync/Buckles.lua) when it is shown, so closing the window early keeps the rest for
-- the next login. Hovering a buckle in the case lists where each of them came from.

local addonName, ns = ...
local L = ns.L

local BuckleDialog = ns:RegisterModule("BuckleDialog", {})

BuckleDialog.WIDTH = 360
BuckleDialog.HEIGHT = 380
BuckleDialog.CASE_COLUMNS = 4
BuckleDialog.CELL_WIDTH = 150
BuckleDialog.CELL_HEIGHT = 96

-- Seconds of the reveal: the buckle lights after the plate, the words after the buckle
BuckleDialog.LIGHT_AFTER = 0.5
BuckleDialog.WORDS_AFTER = 1.2

local reveal, case
BuckleDialog.queue = {}
BuckleDialog.index = 0
BuckleDialog.owner = nil

local function Window(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, name)
    ns.Theme.StyleFrame(f, title)
    return f
end

-- An alpha animation from 0 to 1 on a region after `delay` seconds; a stand-in that does
-- nothing where the client has none
local function FadeAnimation(region, delay, duration)
    local group = region.CreateAnimationGroup and region:CreateAnimationGroup()
    local alpha = type(group) == "table" and group.CreateAnimation and group:CreateAnimation("Alpha")
    if type(alpha) ~= "table" then return { Stop = function() end, Play = function() end } end
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetStartDelay(delay)
    alpha:SetDuration(duration)
    group:SetToFinalAlpha(true)
    return group
end

local function CreateReveal()
    local Theme = ns.Theme
    local f = Window("HeadHunterBuckleDialog", L.BUCKLE_FOUND_TITLE, BuckleDialog.WIDTH, BuckleDialog.HEIGHT)

    f.plate = f:CreateTexture(nil, "ARTWORK")
    f.plate:SetSize(256, 128)
    f.plate:SetPoint("TOP", 0, -56)
    f.plate:SetDesaturated(true)
    f.buckle = f:CreateTexture(nil, "OVERLAY")
    f.buckle:SetAllPoints(f.plate)
    f.lightUp = FadeAnimation(f.buckle, BuckleDialog.LIGHT_AFTER, 0.7)

    f.words = CreateFrame("Frame", nil, f)
    f.words:SetAllPoints(f)
    f.wordsUp = FadeAnimation(f.words, BuckleDialog.WORDS_AFTER, 0.4)
    f.plateName = Theme.Text(f.words, "heading", 12, "background", "OVERLAY")
    f.plateName:SetPoint("CENTER", f.plate, "CENTER", 0, 0)
    f.plateName:SetWidth(120)
    f.name = Theme.Text(f.words, "heading", 18, "foreground")
    f.name:SetPoint("TOP", f.plate, "BOTTOM", 0, -8)
    f.name:SetWidth(BuckleDialog.WIDTH - 36)
    f.quality = Theme.Text(f.words, "bold", 12, "muted")
    f.quality:SetPoint("TOP", f.name, "BOTTOM", 0, -4)
    f.who = Theme.Text(f.words, "bold", 13, "gold")
    f.who:SetPoint("TOP", f.quality, "BOTTOM", 0, -12)
    f.from = Theme.Text(f.words, "text", 13, "foreground")
    f.from:SetPoint("TOP", f.who, "BOTTOM", 0, -4)
    f.from:SetWidth(BuckleDialog.WIDTH - 36)
    f.where = Theme.Text(f.words, "text", 12, "muted")
    f.where:SetPoint("TOP", f.from, "BOTTOM", 0, -4)

    f.hint = Theme.Text(f, "text", 11, "muted")
    f.hint:SetPoint("BOTTOM", 0, 50)
    f.hint:SetWidth(BuckleDialog.WIDTH - 36)
    f.hint:SetText(L.BUCKLE_WEAR_HINT)
    f.next = Theme.Button(f, L.BUCKLE_OK, "gold", 150, 26)
    f.next:SetPoint("BOTTOM", 0, 16)
    f.next:SetScript("OnClick", function() BuckleDialog:Next() end)
    f:SetScript("OnHide", function() BuckleDialog:Reset() end)
    f:Hide()
    return f
end

-- Fills the reveal with one find, marks it shown and plays its reveal
function BuckleDialog:Fill(find)
    local B = ns.Buckles
    local quality = B.Quality(find.buckle, find.quality)
    local texture = B.Texture(find.buckle, find.quality)
    reveal.plate:SetTexture(texture)
    reveal.buckle:SetTexture(texture)
    reveal.plateName:SetText(B.BY_ID[find.buckle] and "" or B.Name(find.buckle, find.name))
    reveal.name:SetText(B.ColoredName(find.buckle, find.quality, find.name))
    reveal.quality:SetText(B.QualityName(quality))
    reveal.who:SetText(B.WhoText(find))
    reveal.from:SetText(B.FromText(find))
    reveal.where:SetText(B.WhereText(find))
    local left = #self.queue - self.index
    reveal.next:SetText(left > 0 and string.format(L.BUCKLE_NEXT, left) or L.BUCKLE_OK)
    for _, group in ipairs({ reveal.lightUp, reveal.wordsUp }) do
        group:Stop()
        group:Play()
    end
    B:MarkShown(find.uid)
end

-- finds: the new finds, oldest first (Buckles:Pending)
function BuckleDialog:ShowFinds(finds)
    if not finds or #finds == 0 then return false end
    reveal = reveal or CreateReveal()
    self.queue = finds
    self.index = 1
    self:Fill(finds[1])
    reveal:Show()
    return true
end

function BuckleDialog:Next()
    if self.index < #self.queue then
        self.index = self.index + 1
        self:Fill(self.queue[self.index])
        return true
    end
    if reveal then reveal:Hide() end
    return false
end

-- The window closed: the finds not shown yet stay for the next login
function BuckleDialog:Reset()
    self.queue, self.index = {}, 0
end

function BuckleDialog:IsRevealShown()
    return reveal ~= nil and reveal:IsShown()
end

local function ShowCellTooltip(cell)
    local slot = cell.slot
    if not (slot and GameTooltip) then return end
    local B = ns.Buckles
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(B.ColoredName(slot.buckle, slot.quality, slot.name))
    GameTooltip:AddLine(B.QualityName(slot.quality), 0.66, 0.59, 0.49)
    for _, find in ipairs(slot.finds or {}) do
        GameTooltip:AddLine(B.FromText(find) .. " · " .. B.WhereText(find), 1, 1, 1, true)
    end
    if slot.missing then GameTooltip:AddLine(L.BUCKLE_NOT_FOUND, 0.5, 0.5, 0.5) end
    GameTooltip:Show()
end

local function Cell(parent)
    local Theme = ns.Theme
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(BuckleDialog.CELL_WIDTH, BuckleDialog.CELL_HEIGHT)
    cell:EnableMouse(true)
    cell:SetScript("OnEnter", ShowCellTooltip)
    cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cell.buckle = cell:CreateTexture(nil, "ARTWORK")
    cell.buckle:SetSize(112, 56)
    cell.buckle:SetPoint("TOP", 0, -4)
    cell.name = Theme.Text(cell, "bold", 12, "foreground")
    cell.name:SetPoint("TOP", cell.buckle, "BOTTOM", 0, -4)
    cell.name:SetWidth(BuckleDialog.CELL_WIDTH - 6)
    cell.count = Theme.Text(cell, "bold", 12, "gold")
    cell.count:SetPoint("TOP", cell.name, "BOTTOM", 0, -2)
    return cell
end

local function CreateCase()
    local Theme = ns.Theme
    local f = Window("HeadHunterBuckleCase", L.BUCKLE_CASE_TITLE, BuckleDialog.CASE_COLUMNS * BuckleDialog.CELL_WIDTH + 36, 200)
    f.options = {}
    f.owner = ns.Select.Create(f, {
        width = 200, options = f.options,
        get = function() return BuckleDialog.owner end,
        set = function(value)
            BuckleDialog.owner = value
            BuckleDialog:FillCase()
        end,
    })
    f.owner:SetPoint("TOPRIGHT", -18, -52)
    f.cells = {}
    f.empty = Theme.Text(f, "text", 13, "muted")
    f.empty:SetPoint("TOP", 0, -92)
    f.empty:SetText(L.BUCKLE_NONE)
    f.hint = Theme.Text(f, "text", 11, "muted")
    f.hint:SetPoint("BOTTOM", 0, 18)
    f.hint:SetText(L.BUCKLE_WEAR_HINT)
    f:Hide()
    return f
end

-- The slots of one character's case: owned (rarest first, with their finds), then the
-- ones still to find
function BuckleDialog.Slots(characterCase)
    local B = ns.Buckles
    local slots = {}
    for _, entry in ipairs(characterCase.owned) do
        slots[#slots + 1] = { buckle = entry.buckle, name = entry.name, quality = entry.quality, finds = entry.finds,
            worn = characterCase.worn == entry.buckle }
    end
    for _, id in ipairs(characterCase.missing) do slots[#slots + 1] = { buckle = id, quality = B.Quality(id), missing = true } end
    return slots
end

local function FillCell(cell, slot)
    local B = ns.Buckles
    cell.slot = slot
    cell.buckle:SetTexture(B.Texture(slot.buckle, slot.quality))
    if slot.missing then
        cell.buckle:SetVertexColor(0.08, 0.06, 0.05, 0.7)
        cell.name:SetText("|cff6f665a" .. B.Name(slot.buckle) .. "|r")
    else
        cell.buckle:SetVertexColor(1, 1, 1, 1)
        cell.name:SetText(B.ColoredName(slot.buckle, slot.quality, slot.name))
    end
    local count = #(slot.finds or {}) > 1 and string.format(L.BUCKLE_COUNT, #slot.finds) or ""
    if slot.worn then count = (count ~= "" and count .. " · " or "") .. L.BUCKLE_WORN end
    cell.count:SetText(count)
    cell:Show()
end

-- Fills the case with the chosen character's buckles; cells are made as many as needed
function BuckleDialog:FillCase()
    local cases = ns.Buckles:Cases()
    for i = #case.options, 1, -1 do case.options[i] = nil end
    local chosen
    for _, c in ipairs(cases) do
        case.options[#case.options + 1] = { value = c.key, label = ns.Utils.DisplayName(c.key) }
        if c.key == self.owner then chosen = c end
    end
    chosen = chosen or cases[1]
    self.owner = chosen and chosen.key
    case.owner:Refresh()
    case.owner:SetShown(#cases > 1)

    local slots = chosen and self.Slots(chosen.case) or {}
    local columns = BuckleDialog.CASE_COLUMNS
    for i, slot in ipairs(slots) do
        if not case.cells[i] then
            case.cells[i] = Cell(case)
            case.cells[i]:SetPoint("TOPLEFT", 18 + ((i - 1) % columns) * BuckleDialog.CELL_WIDTH,
                -88 - math.floor((i - 1) / columns) * BuckleDialog.CELL_HEIGHT)
        end
        FillCell(case.cells[i], slot)
    end
    for i = #slots + 1, #case.cells do case.cells[i]:Hide() end
    case.empty:SetShown(not (chosen and #chosen.case.owned > 0))
    case:SetHeight(math.ceil(math.max(#slots, 1) / columns) * BuckleDialog.CELL_HEIGHT + 140)
end

function BuckleDialog:ShowCase()
    case = case or CreateCase()
    self:FillCase()
    case:Show()
    return true
end

function BuckleDialog:IsCaseShown()
    return case ~= nil and case:IsShown()
end

-- The case window's cells, for the tests
function BuckleDialog:CaseCells()
    return case and case.cells or {}
end
