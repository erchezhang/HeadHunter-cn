-- The toolbox: the website's macro command table as buttons, and the layer (phase)
-- ID card on top (UI/Toolbox.lua).

return function(T, H)
    local function NPC(layer)
        return { name = "Defias Thug", faction = "Horde", isPlayer = false,
            guid = "Creature-0-4613-0-" .. layer .. "-116-0000ABCD" }
    end

    -- The harness stores SetText on the font string itself
    local function Shown(fontString)
        return fontString and fontString.shownText
    end

    T.case("the command table is the website's, with labels where arguments differ", function()
        local ns = H.Boot({ client = "era" })
        T.eq(table.concat(ns.Toolbox.COMMANDS, ","),
            "show,help,options,wanted,outlaw,deaths,posse,bounty,hotspots,duels," ..
            "duelspots,map,tooltip,minimap,claim,catchup,online,layer", "commands")
        T.eq(ns.Toolbox.Label("show"), "/hh", "the plain slash")
        T.eq(ns.Toolbox.Label("outlaw"), "/hh outlaw <name>", "an argument")
        T.eq(ns.Toolbox.Label("layer"), "/hh layer", "a plain command")
        T.noErrors()
    end)

    T.case("layer card: unknown at first, then the ID with zone and age", function()
        local ns = H.Boot({ client = "era" })
        local value, info = ns.Toolbox.LayerLines()
        T.eq(value, "?", "no NPC seen yet")
        T.eq(info, ns.L.LAYER_UNKNOWN, "hint shown")
        H.units.nameplate1 = NPC(777)
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        local zone
        value, info, zone = ns.Toolbox.LayerLines()
        T.eq(value, "777", "the ID")
        T.ok(info:find("777", 1, true) ~= nil, "age line: " .. info)
        T.eq(zone, "Elwynn Forest", "the zone it belongs to")
        T.noErrors()
    end)

    T.case("/hh toolbox opens the window and its buttons run the command", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("toolbox")
        local f = ns.Toolbox:Frame()
        T.ok(f and f:IsShown(), "window shown")
        T.eq(Shown(f.layerValue), "?", "card painted")
        T.eq(f.buttons.status, nil, "the table keeps only the website's commands")
        T.eq(ns.Toolbox.COMMANDS[#ns.Toolbox.COMMANDS], "layer", "ends with the layer lookup")
        -- The layer button runs /hh layer, the same as typing it
        f.buttons.layer:GetScript("OnClick")(f.buttons.layer)
        T.ok(H.Printed("Layer unknown"), "layer from its button")
        T.noErrors()
    end)

    T.case("the window opens and closes; HH_LAYER_CHANGED repaints it", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("toolbox")
        local f = ns.Toolbox:Frame()
        T.eq(Shown(f.layerValue), "?", "unknown first")
        H.units.target = NPC(4321)
        H.Fire("PLAYER_TARGET_CHANGED")
        T.eq(Shown(f.layerValue), "4321", "repainted on HH_LAYER_CHANGED")
        H.Slash("toolbox")
        T.eq(ns.Toolbox:IsShown(), false, "second /hh toolbox closes it")
        T.noErrors()
    end)

    T.case("the Refresh button scans NPCs again", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("toolbox")
        local f = ns.Toolbox:Frame()
        H.units.target = NPC(99)
        f.refresh:GetScript("OnClick")(f.refresh)
        T.eq(Shown(f.layerValue), "99", "rescanned and repainted")
        T.noErrors()
    end)

    T.case("help lists /hh toolbox", function()
        H.Boot({ client = "era" })
        H.Slash("help")
        T.ok(H.Printed("/hh toolbox"), "in the help")
        T.ok(H.Printed("/hh t"), "the short alias too")
        T.noErrors()
    end)

    T.case("/hh t opens and closes the same window", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("t")
        T.ok(ns.Toolbox:IsShown(), "opened by the alias")
        T.ok(ns.Toolbox:Frame() ~= nil, "the same frame")
        H.Slash("t")
        T.eq(ns.Toolbox:IsShown(), false, "closed by the alias again")
        H.Slash("toolbox")
        T.ok(ns.Toolbox:IsShown(), "both commands stay")
        T.noErrors()
    end)

    T.case("the minimap gear button opens the toolbox", function()
        local ns = H.Boot({ client = "era", minimap = true })
        T.ok(ns.MinimapButton:IsShown(), "head shown")
        T.ok(ns.MinimapButton:IsToolboxShown(), "gear shown")
        local gear = _G.HeadHunterToolboxMinimapButton
        T.ok(gear ~= nil, "the gear frame exists")
        gear:GetScript("OnClick")(gear)
        T.ok(ns.Toolbox:IsShown(), "click opens the toolbox")
        gear:GetScript("OnClick")(gear)
        T.eq(ns.Toolbox:IsShown(), false, "click closes it again")
        T.noErrors()
    end)

    T.case("the gear follows /hh minimap and comes back", function()
        local ns = H.Boot({ client = "era", minimap = true })
        H.Slash("minimap")
        T.ok(not ns.MinimapButton:IsShown(), "head hidden")
        T.ok(not ns.MinimapButton:IsToolboxShown(), "gear hidden with it")
        H.Slash("minimap")
        T.ok(ns.MinimapButton:IsShown(), "head back")
        T.ok(ns.MinimapButton:IsToolboxShown(), "gear back")
        T.noErrors()
    end)
end
