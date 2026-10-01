-- Marks above players' heads (UI/Nameplates.lua): the HeadHunter crosshair on WANTED
-- players, a white feather on the Hall of Shame, side by side with the organizer star.
-- Made-up players only.

return function(T, H)
    local function Settle()
        H.Advance(1)
        for _ = 1, 20 do H.Advance(0) end
    end

    local function Person(name, faction, overrides)
        local p = { name = name, realm = "Firemaw", faction = faction, class = "rogue", race = "undead", sex = 2, level = 34 }
        for k, v in pairs(overrides or {}) do p[k] = v end
        return p
    end

    local function Outlaw(name, faction)
        return Person(name, faction, {
            rank = "most_wanted", kills = 31, badges = {},
            wanted_since = H.serverTime - 7200, wanted_until = H.serverTime + 86400,
            last_kill_at = H.serverTime - 3600, times_wanted = 1, times_caught = 0, kill_count = 31, coward_kills = 0,
        })
    end

    local function Boot(opts)
        opts = opts or {}
        local world = {
            generated_at = H.serverTime - 60,
            wanted = { Outlaw("Gorvash", "horde"), Outlaw("Brightmane", "alliance") },
            bullies = { Person("Greystomp", "horde", { coward_kills = 4, kill_count = 9, last_kill_at = H.serverTime - 3600 }) },
            deadbeats = { Person("Coinless", "alliance", { unpaid = 2, blocked_until = H.serverTime + 86400 }) },
            tournaments = { {
                id = "gatebrawl", name = "Gate Brawl", starts_at = H.serverTime + 1800,
                host = { name = "Gorvash", realm = "Firemaw" }, organizers = {},
            } },
        }
        opts.client = "era"
        opts.siteData = { format_version = 1, generated_at = H.serverTime - 60, worlds = { ["era|eu|Firemaw"] = world } }
        local ns = H.Boot(opts)
        Settle()
        return ns
    end

    -- A frame per unit token, as C_NamePlate gives them
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
        local count = 0
        return function(name, faction)
            count = count + 1
            local unit = "nameplate" .. count
            H.units[unit] = { name = name, realm = "Firemaw", class = "ROGUE", faction = faction, isPlayer = true }
            local plate = _G.CreateFrame("Frame")
            plate.namePlateUnitToken = unit
            plates[unit] = plate
            H.Fire("NAME_PLATE_UNIT_ADDED", unit)
            return plate
        end
    end

    local function Shown(plate, id)
        local badges = rawget(plate, "hhBadges")
        return badges ~= nil and badges[id] ~= nil and badges[id]:IsShown()
    end

    T.case("the HeadHunter mark on WANTED players of both factions", function()
        Boot()
        local AddPlate = Plates()
        local horde = AddPlate("Gorvash", "Horde")
        local alliance = AddPlate("Brightmane", "Alliance")
        local nobody = AddPlate("Stranger", "Horde")
        T.ok(Shown(horde, "wanted"), "Horde")
        T.ok(Shown(alliance, "wanted"), "Alliance")
        T.ok(horde.hhBadges.wanted.texture:find("mark$") ~= nil, "the HeadHunter logo")
        T.eq(rawget(nobody, "hhBadges"), nil, "nobody else")
        _G.C_NamePlate = nil
        T.noErrors()
    end)

    T.case("a white feather on Hall of Shame bullies and Deadbeats", function()
        Boot()
        local AddPlate = Plates()
        local bully = AddPlate("Greystomp", "Horde")
        local deadbeat = AddPlate("Coinless", "Alliance")
        T.ok(Shown(bully, "shame"), "bully")
        T.ok(Shown(deadbeat, "shame"), "Deadbeat")
        T.ok(bully.hhBadges.shame.texture:find("feather$") ~= nil, "the feather")
        T.ok(not Shown(bully, "wanted"), "a bully is not WANTED")
        _G.C_NamePlate = nil
        T.noErrors()
    end)

    T.case("more than one mark: side by side, centred", function()
        Boot()
        local AddPlate = Plates()
        local plate = AddPlate("Gorvash", "Horde")
        local wanted, organizer = plate.hhBadges.wanted, plate.hhBadges.organizer
        T.ok(wanted:IsShown() and organizer:IsShown(), "both")
        T.ok(wanted.point[4] < 0 and organizer.point[4] > 0, "left and right of the centre")
        T.eq(organizer.point[4] - wanted.point[4], 24, "one mark and the gap apart")
        _G.C_NamePlate = nil
        T.noErrors()
    end)

    T.case("each mark has its own option", function()
        local ns = Boot()
        local AddPlate = Plates()
        local outlaw = AddPlate("Brightmane", "Alliance")
        local bully = AddPlate("Greystomp", "Horde")
        ns.db.settings.wantedMarks = false
        ns.db.settings.shameMarks = false
        ns.Nameplates:Refresh()
        T.ok(not Shown(outlaw, "wanted"), "WANTED mark off")
        T.ok(not Shown(bully, "shame"), "Hall of Shame mark off")
        _G.C_NamePlate = nil
        T.noErrors()
    end)
    T.case("/hh dev puts the target in the WANTED list or the Hall of Shame, only with HeadHunter_Dev", function()
        local ns = Boot({ dev = {} })
        local AddPlate = Plates()
        local plate = AddPlate("Stranger", "Horde")
        H.units.target = H.units.nameplate1
        H.Slash("dev shame")
        Settle()
        local entry = ns.Wanted:ByKey("Stranger-Firemaw")
        T.ok(entry ~= nil and entry.badges.coward, "in the Hall of Shame")
        local names = {}
        for _, row in ipairs(ns.MainWindow.Rows("shame")) do names[#names + 1] = row.name end
        T.ok(table.concat(names, " "):find("Stranger", 1, true) ~= nil, "in the Hall of Shame tab")
        T.ok(Shown(plate, "shame"), "the feather")
        H.Slash("dev wanted")
        Settle()
        T.eq(ns.Wanted:ByKey("Stranger-Firemaw").wanted, true, "WANTED")
        T.ok(Shown(plate, "wanted") and Shown(plate, "shame"), "both marks")
        H.Slash("dev shame")
        Settle()
        T.ok(not Shown(plate, "shame"), "out of the Hall of Shame again")
        H.Slash("dev clear")
        Settle()
        T.eq(ns.Wanted:ByKey("Stranger-Firemaw"), nil, "cleared")
        T.ok(not Shown(plate, "wanted"), "no marks left")
        _G.C_NamePlate = nil

        ns = Boot()
        AddPlate = Plates()
        plate = AddPlate("Stranger", "Horde")
        H.units.target = H.units.nameplate1
        H.Slash("dev shame")
        Settle()
        T.eq(ns.Wanted:ByKey("Stranger-Firemaw"), nil, "nothing without HeadHunter_Dev")
        T.eq(rawget(plate, "hhBadges"), nil, "no mark")
        _G.C_NamePlate = nil
        T.noErrors()
    end)
end
