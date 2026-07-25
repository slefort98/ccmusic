-- ============================================================
--  MODULE: crew.lua
--  Turtle crew registry. Turtles broadcast their status via
--  rednet on the "crew" protocol. This module listens and
--  displays a roster of known crew turtles.
--
--  Each turtle should run a small companion script that
--  periodically broadcasts:
--    rednet.broadcast({
--      id=os.computerID(), name="Old Pete",
--      task="Patrolling", x=x, y=y, z=z, health=100
--    }, "crew")
-- ============================================================

local mod = {
    id        = "crew",
    name      = "Crew",
    shortName = "CREW",
}

local PROTOCOL   = "crew"
local TIMEOUT    = 30    -- seconds before a turtle is considered offline
local crewData   = {}    -- { [computerID] = {name, task, x, y, z, lastSeen} }

function mod.init(cfg)
    crewData = {}
end

function mod.onRednet(senderID, message, protocol)
    if protocol ~= PROTOCOL then return end
    if type(message) ~= "table" then return end
    crewData[senderID] = {
        name     = message.name or ("Turtle #" .. senderID),
        task     = message.task or "Idle",
        x        = message.x,
        y        = message.y,
        z        = message.z,
        health   = message.health,
        lastSeen = os.clock(),
    }
end

local function isOnline(entry)
    return (os.clock() - entry.lastSeen) < TIMEOUT
end

function mod.summary(cfg)
    local total   = 0
    local online  = 0
    for _, entry in pairs(crewData) do
        total = total + 1
        if isOnline(entry) then online = online + 1 end
    end
    if total == 0 then
        return { { label="Crew", value="No turtles registered", color=colors.gray } }
    end
    local color = online == total and colors.lime or (online > 0 and colors.yellow or colors.red)
    return {
        { label="Crew", value=online .. "/" .. total .. " online", color=color },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── CREW ROSTER ──────────────────")

    local row = y0 + 1
    -- Header
    mon.setCursorPos(2, row)
    mon.setTextColor(C.accent)
    mon.write(string.format("%-14s %-12s %s", "Name", "Task", "Pos"))
    row = row + 1
    mon.setCursorPos(2, row)
    mon.setTextColor(C.border)
    mon.write(string.rep("-", W-3))
    row = row + 1

    if next(crewData) == nil then
        mon.setCursorPos(4, row)
        mon.setTextColor(C.muted)
        mon.write("No crew turtles reporting in.")
        mon.setCursorPos(4, row+1)
        mon.setTextColor(C.muted)
        mon.write("(Turtles must broadcast on \"crew\" protocol)")
        return
    end

    -- Sort: online first, then by name
    local list = {}
    for id, entry in pairs(crewData) do
        list[#list+1] = { id=id, entry=entry, online=isOnline(entry) }
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.entry.name or "") < (b.entry.name or "")
    end)

    for _, item in ipairs(list) do
        if row > y1 then break end
        local e      = item.entry
        local online = item.online
        local color  = online and C.ok or C.err
        local status = online and "●" or "○"

        local posStr = (e.x and e.z)
            and string.format("%d,%d", math.floor(e.x), math.floor(e.z))
            or  "unknown"

        mon.setCursorPos(2, row)
        mon.setTextColor(color)
        mon.setBackgroundColor(C.bg)
        mon.write(status .. " ")
        mon.setTextColor(online and C.white or C.muted)
        mon.write(string.format("%-13s", (e.name or "?"):sub(1,13)))
        mon.setTextColor(C.muted)
        mon.write(string.format("%-12s", (e.task or "Idle"):sub(1,12)))
        mon.setTextColor(C.muted)
        mon.write(posStr)
        row = row + 1
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "Wireless Modem (for rednet)",
            detail = "modem",
            check  = function()
                for _, side in ipairs({"top","bottom","left","right","front","back"}) do
                    if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
                        local m = peripheral.wrap(side)
                        if m and m.isWireless and m.isWireless() then return true end
                    end
                end
                return false
            end,
        },
        {
            label  = "Turtle crew scripts running",
            detail = "rednet 'crew' protocol",
            check  = function() return next(crewData) ~= nil end,
        },
    }
end

return mod
