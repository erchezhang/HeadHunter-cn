-- HH-161: the website's buckles in game (Sync/Buckles.lua, UI/BuckleDialog.lua): our
-- characters' finds and the world's worn buckles from the download, the login reveal once
-- per find, quiet finds never shown, closing early keeping the rest, waiting out combat
-- and instances, the case per character and the tooltip line. Made-up players only.

return function(T, H)
    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
    end

    local function Find(uid, buckle, overrides)
        local find = {
            uid = uid, buckle = buckle, name = "English " .. buckle, quality = "epic", source = "hunter_kill",
            found_at = H.serverTime - 3600 + uid, event_at = 1794700000, map_id = 1434, quiet = false,
            other = { name = "Moomello", realm = "Firemaw", class = "warrior", race = "orc" }, tournament = nil,
        }
        for k, v in pairs(overrides or {}) do find[k] = v end
        return find
    end

    local function Character(name, finds, worn, world)
        return { world = world or "era|eu|Firemaw", name = name, deaths = {}, duels = {}, catches = {},
            bounty = { total = 0, events = {} }, buckles = finds, worn_buckle = worn }
    end

    local function Data(characters, wornList)
        return {
            format_version = 1,
            generated_at = H.serverTime - 600,
            worlds = {
                ["era|eu|Firemaw"] = {
                    generated_at = H.serverTime - 600, wanted = {}, duels = { alliance = {}, horde = {} },
                    buckles = wornList or {},
                },
            },
            characters = characters,
        }
    end

    local function Boot(data, savedDB)
        local ns = H.Boot({ client = "era", siteData = data, savedDB = savedDB, tooltip = "script" })
        Settle()
        return ns
    end

    local function Reveal(ns)
        H.Advance(ns.Buckles.REVEAL_DELAY + 1)
        for _ = 1, 5 do H.Advance(0) end
    end

    local function InCombat(fn)
        _G.InCombatLockdown = function() return true end
        local ok, err = pcall(fn)
        _G.InCombatLockdown = nil
        if not ok then error(err, 0) end
    end

    T.case("reads our characters' finds in this world, newest first, and the worn buckles", function()
        local ns = Boot(Data({
            Character("Vati", { Find(2, "hunters_bane") }, "hunters_bane"),
            Character("Grulalt", { Find(3, "tin_star", { quality = "uncommon" }) }),
            Character("Elsewhere", { Find(9, "dead_mans_hand") }, nil, "era|eu|Gehennas"),
        }, { { name = "Grulironhide", realm = "Firemaw", buckle = "gold_spur", buckle_name = "Gold Spur", quality = "legendary" } }))
        local finds = ns.SiteData:BuckleFinds()
        T.eq(#finds, 2, "both our characters here, not the other realm's")
        T.eq(finds[1].uid, 3, "newest first")
        T.eq(finds[1].owner, "Grulalt-Firemaw", "whose find")
        T.eq(finds[2].other, "Moomello-Firemaw", "the other player's key")
        T.eq(ns.SiteData:OwnWornBuckle("Vati-Firemaw"), "hunters_bane", "our worn buckle")
        local worn = ns.SiteData:WornBuckle("Grulironhide-Firemaw")
        T.eq(worn.buckle, "gold_spur", "another player's worn buckle")
        T.eq(worn.name, "Gold Spur", "with its English name")
        T.eq(ns.SiteData:WornBuckle("Nobody-Firemaw"), nil, "none for a player without one")
        T.noErrors()
    end)

    T.case("reveals every new find of our characters once, oldest first, saying who found it", function()
        local data = Data({
            Character("Vati", { Find(2, "hunters_bane") }),
            Character("Grulalt", { Find(1, "tin_star", { quality = "uncommon" }) }),
        })
        local ns = Boot(data)
        Reveal(ns)
        T.ok(ns.BuckleDialog:IsRevealShown(), "shown after login")
        T.eq(ns.BuckleDialog.queue[1].uid, 1, "the older find first")
        T.eq(_G.HeadHunterBuckleDialog.who.shownText, "Found by Grulalt", "the alt that found it")
        T.ok(ns.BuckleDialog:Next(), "on to the second")
        T.ok(not ns.BuckleDialog:Next(), "the last one closes it")
        T.ok(ns.Buckles:IsShown(1) and ns.Buckles:IsShown(2), "both marked shown")

        local ns2 = Boot(data, _G.HeadHunter_DB)
        Reveal(ns2)
        T.ok(not ns2.BuckleDialog:IsRevealShown(), "not shown again after a reload")
        T.noErrors()
    end)

    T.case("closing the reveal early keeps the finds not shown yet for the next login", function()
        local data = Data({ Character("Vati", { Find(3, "fastest_gun"), Find(2, "hunters_bane"), Find(1, "tin_star") }) })
        local ns = Boot(data)
        Reveal(ns)
        local f = _G.HeadHunterBuckleDialog
        f:Hide()
        f:GetScript("OnHide")(f)
        T.ok(ns.Buckles:IsShown(1), "the one seen is marked")
        T.ok(not ns.Buckles:IsShown(2) and not ns.Buckles:IsShown(3), "the others are not")

        local ns2 = Boot(data, _G.HeadHunter_DB)
        Reveal(ns2)
        T.ok(ns2.BuckleDialog:IsRevealShown(), "shown at the next login")
        T.eq(#ns2.BuckleDialog.queue, 2, "the two left")
        T.noErrors()
    end)

    T.case("never shows a quiet find, only marks it shown", function()
        local ns = Boot(Data({ Character("Vati", { Find(1, "pioneer", { source = "award", quality = "awarded", quiet = true }) }) }))
        Reveal(ns)
        T.ok(not ns.BuckleDialog:IsRevealShown(), "no reveal")
        T.ok(ns.Buckles:IsShown(1), "marked shown")
        T.noErrors()
    end)

    T.case("waits for the fight to end before the reveal, without polling", function()
        local ns = Boot(Data({ Character("Vati", { Find(1, "hunters_bane") }) }))
        InCombat(function()
            Reveal(ns)
            T.ok(not ns.BuckleDialog:IsRevealShown(), "not in combat")
            T.ok(ns.Buckles:IsWaiting(), "waiting")
            H.Advance(120)
            T.ok(not ns.BuckleDialog:IsRevealShown(), "no timer shows it while the fight lasts")
        end)
        H.Fire("PLAYER_REGEN_ENABLED")
        T.ok(ns.BuckleDialog:IsRevealShown(), "shown once the fight is over")
        T.noErrors()
    end)

    T.case("waits for the instance to end before the reveal", function()
        local ns = Boot(Data({ Character("Vati", { Find(1, "hunters_bane") }) }))
        H.instance = { true, "party" }
        ns.Guards:UpdateInstance()
        Reveal(ns)
        T.ok(not ns.BuckleDialog:IsRevealShown(), "not in a dungeon")
        H.instance = { false, "none" }
        ns.Guards:UpdateInstance()
        T.ok(ns.BuckleDialog:IsRevealShown(), "shown on leaving it")
        T.noErrors()
    end)

    T.case("says who found a buckle, where it came from, where and when", function()
        local ns = Boot(Data({}))
        local B = ns.Buckles
        local kill = { source = "hunter_kill", other = "Moomello-Firemaw", owner = "Vati-Firemaw", mapID = 1434, eventAt = 1794700000 }
        T.eq(B.FromText(kill), "Kill of the HeadHunter Moomello", "a kill")
        T.eq(B.FromText({ source = "punishment", other = "Moomello-Firemaw" }), "Punished Moomello", "a punishment")
        T.eq(B.FromText({ source = "duel_upset", other = "Moomello-Firemaw" }), "Beat Moomello at High Noon", "a duel")
        T.eq(B.FromText({ source = "glass" }), "Glass raised to the bust of someone", "a glass, the outlaw unknown")
        T.eq(B.FromText({ source = "award", buckle = "pioneer" }), ns.L.BUCKLE_FROM_PIONEER, "Pioneer")
        T.eq(B.FromText({ source = "award", buckle = "champion", tournament = "Gate Brawl" }), "Gate Brawl", "the tournament")
        T.eq(B.FromText({ source = "award", buckle = "champion" }), ns.L.BUCKLE_FROM_TOURNAMENT, "a deleted tournament")
        T.eq(B.WhoText(kill), "Found by Vati", "found")
        T.eq(B.WhoText({ source = "award", owner = "Vati-Firemaw" }), "Awarded to Vati", "awarded")
        T.eq(B.WhereText(kill), "Stranglethorn Vale · " .. date("%Y-%m-%d", 1794700000), "zone and date")
        T.noErrors()
    end)

    T.case("shows a buckle this version does not know on its quality's plate, by the download's name", function()
        local ns = Boot(Data({}))
        local B = ns.Buckles
        T.eq(B.Texture("gold_spur", "legendary"), B.TEXTURES .. "plate_legendary", "the plate")
        T.eq(B.Name("gold_spur", "Gold Spur"), "Gold Spur", "the download's name")
        T.eq(B.Name("gold_spur"), "Gold Spur", "the id read as words without one")
        T.eq(B.Quality("gold_spur", "nonsense"), "uncommon", "an unknown quality falls back")
        T.eq(B.Texture("hunters_bane"), B.TEXTURES .. "hunters_bane", "a known buckle's own picture")
        T.noErrors()
    end)

    T.case("the case per character: owned rarest first with counts, the worn one, then the ones to find", function()
        local ns = Boot(Data({
            Character("Vati", {
                Find(4, "gold_spur", { quality = "legendary" }),
                Find(3, "tin_star", { quality = "uncommon" }), Find(2, "tin_star", { quality = "uncommon" }),
                Find(1, "dead_mans_hand", { quality = "legendary" }),
            }, "tin_star"),
            Character("Grulalt", { Find(5, "pioneer", { source = "award", quality = "awarded" }) }),
        }))
        local cases = ns.Buckles:Cases()
        T.eq(#cases, 2, "two characters")
        T.eq(cases[1].key, "Vati-Firemaw", "the one we play first")
        local mine = cases[1].case
        T.eq(mine.owned[1].buckle, "dead_mans_hand", "Legendary first, the known one before the unknown")
        T.eq(mine.owned[3].buckle, "tin_star", "then Uncommon")
        T.eq(#mine.owned[3].finds, 2, "Tin Star twice")
        T.eq(mine.worn, "tin_star", "the worn one")
        for _, id in ipairs(mine.missing) do T.ok(id ~= "pioneer", "Pioneer can no longer be earned") end

        H.Slash("buckles")
        T.ok(ns.BuckleDialog:IsCaseShown(), "/hh buckles opens it")
        local shown = 0
        for _, cell in ipairs(ns.BuckleDialog:CaseCells()) do
            if cell:IsShown() then shown = shown + 1 end
        end
        T.eq(shown, #mine.owned + #mine.missing, "a cell for every slot, an unknown buckle drops nothing")
        T.noErrors()
    end)

    T.case("a player's tooltip shows the buckle they wear, and nothing without one", function()
        local ns = Boot(Data({}, { { name = "Grulironhide", realm = "Firemaw", buckle = "hunters_bane", quality = "epic" } }))
        local function Line(name)
            H.units.mouseover = { name = name, realm = "Firemaw", level = 60, class = "WARRIOR", race = "Orc",
                faction = "Horde", isPlayer = true, guid = "Player-2-000" .. name }
            H.ShowUnitTooltip("mouseover")
            for _, line in ipairs(H.tooltipLines) do
                if line:find("Assets\\Buckles", 1, true) then return line end
            end
            return nil
        end
        local found = Line("Grulironhide")
        T.ok(found and found:find("Hunter's Bane", 1, true) ~= nil, "the buckle line")
        T.ok(found and found:find("|cffa335ee", 1, true) ~= nil, "in the Epic colour")
        T.eq(Line("Plainfolk"), nil, "no line without a buckle")
        T.noErrors()
    end)

    T.case("WoW Forever: names without realms", function()
        local data = {
            format_version = 1,
            worlds = { ["forever|us|pvp"] = { generated_at = H.serverTime - 60, wanted = {}, duels = { alliance = {}, horde = {} },
                buckles = { { name = "Grim Tusk", buckle = "last_call", quality = "uncommon" } } } },
            characters = { Character("Vati Guda", { Find(1, "last_call", { other = { name = "Moo Mello" } }) }, nil, "forever|us|pvp") },
        }
        local ns = H.Boot({ client = "forever", siteData = data })
        Settle()
        local finds = ns.SiteData:BuckleFinds()
        T.eq(#finds, 1, "our find")
        T.eq(finds[1].owner, "Vati Guda", "our key, no realm")
        T.eq(finds[1].other, "Moo Mello", "the other player's key, no realm")
        T.eq(ns.SiteData:WornBuckle("Grim Tusk").buckle, "last_call", "a worn buckle by name")
        T.noErrors()
    end)
end
