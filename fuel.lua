-- ============================================================
--  MODULE: fuel.lua
--  Reads a fluid_storage peripheral (fuel tank) for level
--  and estimates range from recent burn rate.
-- ============================================================

local mod = {
    id        = "fuel",
    name      = "Fuel",
    shortName = "FUEL",
}

local tank    = nil
local history = {}   -- ring buffer of {time, amount} for burn rate
local MAX_HIST = 10

local function getFuelData()
    if not tank then return nil, nil, nil end
    local ok, tanks = pcall(function() return tank.tanks() end)
    if not ok or not tanks or #tanks == 0 then return nil, nil, nil end
    local t   = tanks[1]
    local pct = math.floor((t.amount / t.capacity) * 100)
    return t.amount, t.capacity, pct
end

local function getBurnRate()
    if #history < 2 then return nil end
    local oldest = history[1]
    local newest = history[#history]
    local dt     = newest.time - oldest.time
    local da     = oldest.amount - newest.amount
    if dt <= 0 or da <= 0 then return nil end
    return da / dt  -- mB per second
end

function mod.init(cfg)
    tank    = peripheral.find("fluid_storage")
    history = {}
end

-- Called every tick by the rotation draw; we record history here too
local function recordHistory(amount)
    if not amount then return end
    history[#history+1] = { time=os.clock(), amount=amount }
    if #history > MAX_HIST then table.remove(history, 1) end
end

function mod.summary(cfg)
    local amount, capacity, pct = getFuelData()
    if not pct then
        return { { label="Fuel", value="No tank", color=colors.red } }
    end
    recordHistory(amount)
    local fuelColor = pct > 50 and colors.lime or (pct > 20 and colors.yellow or colors.red)
    local bar = string.rep("█", math.floor(pct / 10)) .. string.rep("░", 10 - math.floor(pct / 10))
    return {
        { label="Fuel",  value=pct .. "%  " .. bar, color=fuelColor },
        { label="Level", value=tostring(amount) .. "/" .. tostring(capacity) .. " mB" },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    local amount, capacity, pct = getFuelData()
    recordHistory(amount)
    local burnRate = getBurnRate()

    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── FUEL SYSTEM ──────────────────")

    local function row(y, label, value, col)
        mon.setCursorPos(2, y)
        mon.setTextColor(C.muted)
        mon.setBackgroundColor(C.bg)
        mon.write(string.format("%-14s", label))
        mon.setTextColor(col or C.white)
        mon.write(tostring(value))
    end

    if not pct then
        row(y0+1, "Status:", "No fluid_storage found", C.err)
        return
    end

    local fuelColor = pct > 50 and C.ok or (pct > 20 and C.warn or C.err)
    local barLen    = W - 6
    local filled    = math.floor((pct / 100) * barLen)
    local bar       = string.rep("█", filled) .. string.rep("░", barLen - filled)

    row(y0+1, "Level:", tostring(amount) .. " / " .. tostring(capacity) .. " mB", C.white)
    row(y0+2, "Percent:", pct .. "%", fuelColor)

    -- Draw fuel bar
    mon.setCursorPos(3, y0+3)
    mon.setBackgroundColor(C.bg)
    mon.setTextColor(fuelColor)
    mon.write("[" .. bar .. "]")

    if burnRate then
        local rateStr = string.format("%.1f mB/s", burnRate)
        local secsLeft = amount / burnRate
        local minStr  = secsLeft > 0 and string.format("%.0fm remaining", secsLeft/60) or "∞"
        row(y0+4, "Burn rate:", rateStr, C.white)
        row(y0+5, "Est. range:", minStr, pct > 20 and C.ok or C.warn)
    else
        row(y0+4, "Burn rate:", "Calculating...", C.muted)
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "Fuel Tank (fluid_storage)",
            detail = "fluid_storage",
            check  = function() return peripheral.find("fluid_storage") ~= nil end,
        },
    }
end

return mod
