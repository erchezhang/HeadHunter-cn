-- HH-157: Blizzard's shared tables are only added to, never assigned. Writing the global
-- itself (even `SlashCmdList = SlashCmdList or {}`) taints the variable, so every slash
-- command Blizzard looks up in it runs tainted and its protected calls are blocked
-- (seen: `/tm` in a macro, SetRaidTarget blocked, "HeadHunter has been blocked").

return function(T, H)
    local SHARED = {
        "SlashCmdList", "hash_SlashCmdList", "SecureCmdList", "StaticPopupDialogs",
        "UISpecialFrames", "UnitPopupMenus", "ChatTypeInfo", "ChatTypeGroup",
    }

    -- the addon's Lua files, from the TOC
    local function Files()
        local files = {}
        local toc = assert(io.open(H.ROOT .. "/HeadHunter.toc", "r"))
        for line in toc:lines() do
            line = line:gsub("\r", "")
            if line:match("%.lua$") and not line:match("^#") then
                files[#files + 1] = line:gsub("\\", "/")
            end
        end
        toc:close()
        return files
    end

    T.case("no file assigns a whole Blizzard table", function()
        local found = {}
        for _, path in ipairs(Files()) do
            local file = assert(io.open(H.ROOT .. "/" .. path, "r"))
            local number = 0
            for line in file:lines() do
                number = number + 1
                local code = line:gsub("%-%-.*$", "")
                for _, name in ipairs(SHARED) do
                    if code:match("^%s*" .. name .. "%s*=[^=]") or code:match("^%s*_G%." .. name .. "%s*=[^=]")
                        or code:match("^%s*_G%[\"" .. name .. "\"%]%s*=[^=]") then
                        found[#found + 1] = path .. ":" .. number .. ": " .. line
                    end
                end
            end
            file:close()
        end
        T.eq(#found, 0, "whole-table assignments:\n      " .. table.concat(found, "\n      "))
    end)
end
