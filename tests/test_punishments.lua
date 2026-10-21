-- Punished (Sync/Punishments.lua): a bully or the other faction's Deadbeat brought down
-- while not WANTED is kept once per hour, shared with a new message type, listed with the
-- website's in the Punished tab, and takes glasses like a bust. Made-up players only.

return function(T, H)
    local function Bully(name)
        return { id = name, key = name, name = name, badges = { coward = true }, class = "ROGUE", race = "Scourge",
            level = 30 }
    end

    local function Count(ns)
        local n = 0
        for _ in ns.Punishments:All() do n = n + 1 end
        return n
    end

    local function Only(ns)
        for _, record in ns.Punishments:All() do return record end
    end

    local function Sent(code)
        local found = 0
        for _, m in ipairs(H.sent) do
            if m.message:find(code .. ":", 1, true) then found = found + 1 end
        end
        return found
    end

    -- A peer's punishment message, by `by`, from `sender`
    local function Deliver(ns, fields, sender)
        local P = ns.Protocol
        local p = { outlaw = "Grim Reaper", t = H.serverTime - 30, mapID = 1436, kind = "bully", by = "Kestrel Vane",
            killer = "Kestrel Vane" }
        for k, v in pairs(fields or {}) do p[k] = v end
        H.Deliver(P.Pack("A", P.TYPES.PUNISHMENT, { P.EncodePunishment(p) }), sender or p.by)
        return p
    end

    -- Every HeadHunter card shown (UI/Toast.lua)
    local function Cards(ns)
        local shown = {}
        local show = ns.Toast.Show
        ns.Toast.Show = function(toast, notice)
            shown[#shown + 1] = notice
            return show(toast, notice)
        end
        return shown
    end

    T.case("protocol: a punishment reads back; a broken one does not", function()
        local P = H.Boot({ client = "forever" }).Protocol
        local who = { class = "HUNTER", race = "Dwarf", faction = "Alliance", sex = 3, level = 42 }
        local p = P.DecodePunishment(P.EncodePunishment({ outlaw = "Grim Reaper", t = 100, mapID = 1436, kind = "deadbeat",
            by = "Rowan Ash", killer = "Kestrel Vane", killerWho = who }))
        T.eq(p.outlaw, "Grim Reaper", "outlaw")
        T.eq(p.t, 100, "time")
        T.eq(p.mapID, 1436, "map")
        T.eq(p.kind, "deadbeat", "kind")
        T.eq(p.by, "Rowan Ash", "by")
        T.eq(p.killer, "Kestrel Vane", "killer")
        T.eq(p.killerWho.level, 42, "killer level")
        T.eq(P.DecodePunishment("Grim Reaper;2s;;x;Rowan Ash;"), nil, "unknown kind")
        T.eq(P.DecodePunishment("Grim Reaper;2s;;b;;"), nil, "nobody credited")
        T.ok(P.TYPES.PUNISHMENT ~= P.TYPES.JUSTICE, "not the catch message")
    end)

    T.case("our kill of a bully: kept and shared once per hour, not as a catch", function()
        local ns = H.Boot({ client = "forever" })
        H.sent = {}
        ns.Events:Fire("HH_SHAME_KILLED", Bully("Grim Reaper"), "bully")
        local record = Only(ns)
        T.ok(record ~= nil, "kept")
        T.eq(record.kind, "bully", "kind")
        T.eq(record.origin, "local", "our own")
        T.eq(record.by, ns.Utils.UnitKey("player"), "by us")
        T.eq(record.id, "Grim Reaper:" .. record.t .. ":" .. record.by, "id")
        T.eq(record.outlawWho.class, "ROGUE", "who they are")
        H.Advance(10)
        T.eq(Sent("F"), 1, "shared")
        T.eq(Sent("K"), 0, "never as a catch")
        T.eq(next(ns.db.justice), nil, "no catch")

        H.serverTime = H.serverTime + 600
        ns.Events:Fire("HH_SHAME_KILLED", Bully("Grim Reaper"), "bully")
        T.eq(Count(ns), 1, "not again within the hour")
        H.serverTime = H.serverTime + ns.Marks.BULLY_COOLDOWN
        ns.Events:Fire("HH_SHAME_KILLED", Bully("Grim Reaper"), "bully")
        T.eq(Count(ns), 2, "after the hour")
        ns.Events:Fire("HH_SHAME_KILLED", { id = "Payless Pete", key = "Payless Pete" }, "deadbeat")
        T.eq(Count(ns), 3, "a Deadbeat")
        T.noErrors()
    end)

    T.case("none when we hunt 10+ levels down; kept 30 days", function()
        local ns = H.Boot({ client = "forever" })
        local low = Bully("Tiny Gank")
        low.level = 5
        ns.Events:Fire("HH_SHAME_KILLED", low, "bully")
        T.eq(Count(ns), 0, "hunting down")
        ns.Events:Fire("HH_SHAME_KILLED", Bully("Grim Reaper"), "bully")
        ns.Punishments:Prune(H.serverTime + ns.Reports.MAX_AGE + 1)
        T.eq(Count(ns), 0, "pruned")
        T.noErrors()
    end)

    T.case("peers: stored once per kill, only for themselves, under a limit", function()
        local ns = H.Boot({ client = "forever" })
        Deliver(ns)
        local record = Only(ns)
        T.ok(record ~= nil, "a peer's punishment")
        T.eq(record.origin, "peer", "origin")
        T.eq(record.killerClass, nil, "no who sent")
        Deliver(ns, { by = "Rowan Ash", t = H.serverTime - 20 })
        T.eq(Count(ns), 1, "a groupmate's copy of the same kill")
        Deliver(ns, { outlaw = "Dusk Fang", by = "Other Name" }, "Rowan Ash")
        T.eq(Count(ns), 1, "nobody speaks for someone else")
        Deliver(ns, { outlaw = "Dusk Fang", t = H.serverTime - ns.Reports.MAX_AGE - 10 })
        T.eq(Count(ns), 1, "too old")
        for i = 1, ns.Punishments.SENDER_LIMIT + 2 do
            Deliver(ns, { outlaw = "Outlaw" .. i .. " Smith", by = "Moss Walker" })
        end
        T.eq(Count(ns), 1 + ns.Punishments.SENDER_LIMIT, "rate limited")
        T.noErrors()
    end)

    T.case("older addons: the catch handler never reads a punishment", function()
        local ns = H.Boot({ client = "forever" })
        local P = ns.Protocol
        local record = P.EncodePunishment({ outlaw = "Grim Reaper", t = H.serverTime - 30, kind = "bully",
            by = "Kestrel Vane" })
        T.eq(P.DecodeJustice(record), nil, "not a catch")
        ns.CatchUp:OnData("F" .. record, "Kestrel Vane")
        T.eq(Count(ns), 0, "catch-up data only from the peers we pull from")
        T.noErrors()
    end)

    T.case("catch-up: punishments are passed on and taken without the limit", function()
        local ns = H.Boot({ client = "forever" })
        ns.Events:Fire("HH_SHAME_KILLED", Bully("Grim Reaper"), "bully")
        local found
        for _, r in ipairs(ns.CatchUp.Records(H.serverTime - 3600)) do
            if r:sub(1, 1) == "F" then found = r end
        end
        T.ok(found ~= nil, "an F record")
        local other = H.Boot({ client = "forever" })
        local P = other.Protocol
        for i = 1, other.Punishments.SENDER_LIMIT + 2 do
            other.Punishments:AddRelayed(P.EncodePunishment({ outlaw = "Outlaw" .. i .. " Smith", t = H.serverTime - 30,
                kind = "deadbeat", by = "Kestrel Vane" }), "Rowan Ash")
        end
        T.eq(Count(other), other.Punishments.SENDER_LIMIT + 2, "all of them")
        T.eq(Only(other).origin, "relay", "relayed")
        T.noErrors()
    end)

    T.case("glasses: raised like a bust, never to our own, the popup with a PUNISHED stamp", function()
        local ns = H.Boot({ client = "forever" })
        local cards = Cards(ns)
        local p = Deliver(ns)
        local record = Only(ns)
        T.eq(#cards, 1, "the popup for a peer's punishment")
        T.eq(cards[1].stamp, "PUNISHED", "the stamp")
        T.ok(cards[1].text:find("Punished by Kestrel Vane", 1, true) ~= nil, cards[1].text)
        ns.Toast:Accept()
        T.eq(ns.Glasses:Count(record), 1, "raised")
        T.eq(ns.Glasses:CanRaise(record), false, "once")
        local g
        for _, glass in ns.Glasses:All() do g = glass end
        T.eq(g.caughtAt, p.t, "caughtAt is the punishment's time")
        T.eq(g.popup, true, "from the popup")

        local P = ns.Protocol
        H.Deliver(P.Pack("A", P.TYPES.GLASS, { P.EncodeGlass({ outlaw = "Grim Reaper", caughtAt = p.t,
            t = H.serverTime, by = "Kestrel Vane" }) }), "Kestrel Vane")
        T.eq(ns.Glasses:Count(record), 1, "the hunter never to their own punishment")

        ns.Events:Fire("HH_SHAME_KILLED", Bully("Dusk Fang"), "bully")
        local mine
        for _, r in ns.Punishments:All() do
            if r.outlaw == "Dusk Fang" then mine = r end
        end
        T.eq(ns.Glasses:CanRaise(mine), false, "our own")
        T.eq(#cards, 1, "no popup for our own")
        T.noErrors()
    end)

    T.case("the Punished tab: ours and the website's, Bully or Deadbeat, with the mug", function()
        local data = {
            format_version = 1,
            generated_at = H.serverTime - 600,
            worlds = {
                ["era|eu|Firemaw"] = {
                    generated_at = H.serverTime - 600,
                    punished = {
                        { name = "Payless", realm = "Firemaw", class = "rogue", race = "undead", faction = "horde",
                            caught_at = H.serverTime - 300, kind = "deadbeat", map_id = 1429, glasses = 4,
                            hunter = { name = "Brightshield", realm = "Firemaw", class = "paladin", race = "human",
                                faction = "alliance" } },
                        { name = "Known", realm = "Firemaw", caught_at = H.serverTime - 30, kind = "bully", glasses = 9 },
                        { name = "Broken", realm = "Firemaw", caught_at = H.serverTime - 100, kind = "nope" },
                    },
                },
            },
            characters = {},
        }
        local ns = H.Boot({ client = "era", siteData = data })
        H.Advance(1)
        ns.Events:Fire("HH_SHAME_KILLED", { id = "Known-Firemaw", key = "Known-Firemaw",
            badges = { coward = true } }, "bully")
        local rows = ns.MainWindow.Rows("punished")
        T.eq(#rows, 2, "ours and the website's, once each")
        T.eq(rows[1].plain, "Known", "ours first (newest)")
        T.eq(rows[1].kind, "|cffff8000Bully|r", "a bully")
        T.eq(rows[1].actions[1].canRaise, false, "our own")
        T.eq(rows[2].plain, "Payless", "the website's")
        T.eq(rows[2].kind, "|cffff4040Deadbeat|r", "a Deadbeat")
        T.eq(rows[2].byPlain, "Brightshield", "who punished them")
        T.eq(rows[2].glasses, 4, "the website's glasses")
        T.eq(rows[2].actions[1].canRaise, true, "we may raise one")
        T.eq(#ns.MainWindow.Rows("punished", nil, nil, nil, "pay"), 1, "the search")
        T.eq(#ns.MainWindow.Rows("busted"), 0, "not on Busted")
        H.Slash("")
        ns.MainWindow:SelectTab("punished")
        T.noErrors()
    end)
end
