-- HH-128: the sheriff's star on tournament hosts and co-organizers
-- (Tournament/Organizers.lua), from the website data. Made-up players only.

return function(T, H)
    local function Data(startsIn)
        return {
            format_version = 1,
            generated_at = H.serverTime - 60,
            worlds = {
                ["era|eu|Firemaw"] = {
                    generated_at = H.serverTime - 60,
                    tournaments = { {
                        id = "gatebrawl", name = "Gate Brawl", starts_at = H.serverTime + startsIn,
                        host = { name = "Tovik", realm = "Firemaw" },
                        organizers = { { name = "Marla", realm = "Firemaw" } },
                    } },
                },
            },
        }
    end

    local function Boot(startsIn, opts)
        opts = opts or {}
        opts.client, opts.siteData = "era", Data(startsIn)
        return H.Boot(opts)
    end

    T.case("the host gets the gold star and a co-organizer the silver one, from 1 hour before the start", function()
        local ns = Boot(1800)
        local O = ns.Organizers
        local role, tournament = O:RoleOf("Tovik-Firemaw")
        T.eq(role, "host", "host")
        T.eq(tournament and tournament.name, "Gate Brawl", "tournament")
        T.eq((O:RoleOf("Marla-Firemaw")), "organizer", "co-organizer")
        T.eq((O:RoleOf("Stranger-Firemaw")), nil, "anyone else")
        T.ok(O.Star("host"):find("230:180:34", 1, true) ~= nil, "gold")
        T.ok(O.Star("organizer"):find("192:192:192", 1, true) ~= nil, "silver")
        T.noErrors()
    end)

    T.case("no star before the hour before the start, nor 4 hours after it", function()
        local ns = Boot(2 * 3600)
        T.eq((ns.Organizers:RoleOf("Tovik-Firemaw")), nil, "2 hours before")
        T.eq((ns.Organizers:RoleOf("Tovik-Firemaw", H.serverTime + 2 * 3600 + 3600)), "host", "during")
        T.eq((ns.Organizers:RoleOf("Tovik-Firemaw", H.serverTime + 2 * 3600 + 4 * 3600 + 60)), nil, "after")
        T.noErrors()
    end)

    T.case("a tournament of several days has the star on each day, not between them", function()
        local data = Data(-2 * 86400)
        data.worlds["era|eu|Firemaw"].tournaments[1].days = { H.serverTime - 86400, H.serverTime + 1800 }
        local ns = H.Boot({ client = "era", siteData = data })
        local O = ns.Organizers
        T.eq((O:RoleOf("Tovik-Firemaw")), "host", "30 min before day 3")
        local _, tournament = O:RoleOf("Tovik-Firemaw")
        T.eq(O.Status(tournament, H.serverTime), "starts in 30 min", "counts to that day")
        T.eq((O:RoleOf("Tovik-Firemaw", H.serverTime - 86400 + 3600)), "host", "during day 2")
        T.eq((O:RoleOf("Tovik-Firemaw", H.serverTime - 12 * 3600)), nil, "between the days")
        T.noErrors()
    end)

    T.case("the tooltip of an organizer says so, friend or foe", function()
        local ns = Boot(1800, { tooltip = "script" })
        H.units.mouseover = { name = "Tovik", level = 30, class = "WARRIOR", race = "Human", faction = "Alliance",
            isPlayer = true }
        H.ShowUnitTooltip("mouseover")
        local text = table.concat(H.tooltipLines, "\n")
        T.ok(text:find("Tournament host: Gate Brawl · starts in 30 min", 1, true) ~= nil, "host line")
        T.ok(text:find("star", 1, true) ~= nil, "with the star")
        ns.db.settings.organizerMarks = false
        H.ShowUnitTooltip("mouseover")
        T.ok(not table.concat(H.tooltipLines, "\n"):find("Tournament host", 1, true), "option off")
        T.noErrors()
    end)

    T.case("an organizer's chat lines get the star; nobody else's", function()
        local ns = Boot(-600)
        local filter = ns.Organizers.ChatFilter
        local blocked, message, author = filter(nil, "CHAT_MSG_SAY", "Round 2 at the gate", "Marla")
        T.eq(blocked, false, "never hides a line")
        T.ok(message:find("^|T.-star.-|t Round 2 at the gate$") ~= nil, "star before the message")
        T.eq(author, "Marla", "author kept, so a click still whispers")
        local _, other = filter(nil, "CHAT_MSG_SAY", "hello", "Stranger")
        T.eq(other, nil, "nothing changed for others")
        T.noErrors()
    end)

    -- Nameplates: a frame per unit token, as C_NamePlate gives them
    local function Plates()
        local plates = {}
        _G.C_NamePlate = {
            GetNamePlateForUnit = function(unit) return plates[unit] end,
            GetNamePlates = function()
                local list = {}
                for _, plate in pairs(plates) do list[#list + 1] = plate end
                return list
            end,
        }
        return function(unit, player)
            H.units[unit] = player
            local plate = _G.CreateFrame("Frame")
            plate.namePlateUnitToken = unit
            plates[unit] = plate
            return plate
        end
    end

    T.case("a star above the head of the host (gold) and a co-organizer (silver), nobody else", function()
        local ns = Boot(1800)
        local AddPlate = Plates()
        local host = AddPlate("nameplate1", { name = "Tovik", class = "WARRIOR", faction = "Alliance", isPlayer = true })
        local organizer = AddPlate("nameplate2", { name = "Marla", class = "MAGE", faction = "Alliance", isPlayer = true })
        local stranger = AddPlate("nameplate3", { name = "Stranger", class = "MAGE", faction = "Alliance", isPlayer = true })
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        T.ok(host.hhBadges.organizer and host.hhBadges.organizer:IsShown(), "host star")
        T.eq(host.hhBadges.organizer.texture, ns.Organizers.STAR, "the star texture")
        T.eq(math.floor(host.hhBadges.organizer.color[1] * 255 + 0.5), 230, "gold")
        T.ok(organizer.hhBadges.organizer and organizer.hhBadges.organizer:IsShown(), "co-organizer star")
        T.eq(math.floor(organizer.hhBadges.organizer.color[1] * 255 + 0.5), 192, "silver")
        T.eq(rawget(stranger, "hhBadges"), nil, "no star for others")

        H.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        T.ok(not host.hhBadges.organizer:IsShown(), "hidden when the nameplate goes")
        ns.db.settings.organizerMarks = false
        ns.Nameplates:Refresh()
        T.ok(not organizer.hhBadges.organizer:IsShown(), "option off")
        _G.C_NamePlate = nil
        T.noErrors()
    end)

    T.case("the star leaves the head when the time window closes", function()
        local ns = Boot(-4 * 3600 + 30)
        local AddPlate = Plates()
        local host = AddPlate("nameplate1", { name = "Tovik", class = "WARRIOR", faction = "Alliance", isPlayer = true })
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        T.ok(host.hhBadges.organizer:IsShown(), "still in the window")
        H.serverTime = H.serverTime + 120
        H.Advance(ns.Nameplates.REFRESH)
        T.ok(not host.hhBadges.organizer:IsShown(), "gone after the window")
        _G.C_NamePlate = nil
        T.noErrors()
    end)
end
