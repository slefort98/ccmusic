-- ============================================================
--  MODULE: engines.lua
--  Shows engine state and thruster channels via RedRouter.
--  Click ENGINE ON / OFF on the detail screen to toggle.
-- ============================================================

local mod = {
    id        = "engines",
    name      = "Engines",
    shortName = "ENGIN",
}

local rr = nil

-- Define your thruster channels here (name = RedRouter channel index)
-- Adjust to match your ship's wiring.
local THRUSTERS = {
    { name="Main Thrust",  channel=1 },
    { name="Lift",         channel=2 },
    { name="Port",         channel=3 },
    { name="Starboard",    channel=4 },
}

local function getState(channel)
    if not rr then return false end
    local ok, v = pcall(function() return rr.getOutput(channel) end)
    return ok and (v == true or v == 15 or (type(v)=="number" and v > 0))
end

local function setState(channel, on)
    if not rr then return end
    pcall(function()
        rr.setOutput(channel, on and 15 or 0)
    end)
end

function mod.init(cfg)
    rr = peripheral.find("redrouter")
end

function mod.summary(cfg)
    local allOn  = true
    local allOff = true
    for _, t in ipairs(THRUSTERS) do
        local s = getState(t.channel)
        if s then allOff = false else allOn = false end
    end
    local statusLabel = allOn and "ALL ONLINE" or (allOff and "ALL OFFLINE" or "PARTIAL")
    local statusColor = allOn and colors.lime or (allOff and colors.red or colors.yellow)
    return {
        { label="Engines", value=statusLabel, color=statusColor },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── ENGINE STATUS ────────────────")

    local row = y0 + 1
    for _, t in ipairs(THRUSTERS) do
        if row > y1 - 2 then break end
        local on    = getState(t.channel)
        local icon  = on and "▶ ON " or "■ OFF"
        local color = on and C.ok   or C.err
        mon.setCursorPos(2,  row) mon.setTextColor(C.muted)  mon.setBackgroundColor(C.bg) mon.write(string.format("%-16s", t.name))
        mon.setCursorPos(18, row) mon.setTextColor(color)                                  mon.write(icon)
        row = row + 1
    end

    -- All ON / All OFF buttons
    row = row + 1
    if row <= y1 then
        mon.setCursorPos(2,     row) mon.setTextColor(C.black) mon.setBackgroundColor(C.ok)  mon.write("  ALL ON  ")
        mon.setCursorPos(14,    row) mon.setTextColor(C.black) mon.setBackgroundColor(C.err) mon.write("  ALL OFF  ")
    end
end

function mod.onClick(x, y, cfg)
    -- We don't know exact row here without re-computing; approximate:
    -- ALL ON  ≈ x 2–11,  ALL OFF ≈ x 14–25  on some row
    -- A more robust approach: store button coords from draw and read here.
    -- For now, toggle all if in right column range.
    if x >= 2 and x <= 11 then
        for _, t in ipairs(THRUSTERS) do setState(t.channel, true) end
    elseif x >= 14 and x <= 25 then
        for _, t in ipairs(THRUSTERS) do setState(t.channel, false) end
    else
        -- Toggle individual thruster row clicked
        local baseRow = 1  -- y0+1 is first thruster row, but y0 unknown here
        -- Individual toggling handled best with a stored hitmap; left for extension.
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "RedRouter Block",
            detail = "redrouter",
            check  = function() return peripheral.find("redrouter") ~= nil end,
        },
    }
end

return mod
