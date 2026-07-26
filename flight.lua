-- ============================================================
--  MODULE: flight.lua
--  Reads navigation_table for speed, heading, pitch, roll.
--  Reads altitude via RedRouter analog input from sensor.
--
--  ALTITUDE SENSOR WIRING:
--    Sensor output -> redstone dust -> LEFT side of RedRouter
--    RedRouter on wired network as redrouter_0
--    Sensor configured for 0-235m range
-- ============================================================

local mod = {
    id        = "flight",
    name      = "Flight",
    shortName = "FLIGHT",
}

-- Altitude sensor config -- adjust if you rewire
local ALT_REDROUTER = "redrouter_0"  -- name shown by hud_probe
local ALT_SIDE      = "left"         -- side of RedRouter the sensor feeds into
local ALT_MAX       = 235            -- max metres your sensor is set to

local nav = nil
local rr  = nil
local gpsX, gpsY, gpsZ = nil, nil, nil

local function getAltitude()
    -- Try RedRouter analog input first (the physical sensor)
    if rr then
        local ok, sig = pcall(function() return rr.getAnalogInput(ALT_SIDE) end)
        if ok and type(sig) == "number" then
            return math.floor((sig / 15) * ALT_MAX)
        end
    end
    -- Fall back to navigation table if sensor not wired
    if nav and nav.getAltitude then
        return nav.getAltitude()
    end
    return nil
end

function mod.init(cfg)
    nav = peripheral.find("navigation_table")
    rr  = peripheral.wrap(ALT_REDROUTER)
end

function mod.summary(cfg)
    local alt     = getAltitude()
    local speed   = nav and nav.getSpeed   and nav.getSpeed()   or "N/A"
    local heading = nav and nav.getHeading and nav.getHeading() or "N/A"
    local altStr  = alt and (tostring(alt) .. "m") or "N/A"
    local altColor = colors.white
    if type(alt) == "number" then
        altColor = alt < 20 and colors.red or (alt < 50 and colors.yellow or colors.lime)
    end
    return {
        { label="ALT",     value=altStr,                     color=altColor },
        { label="SPEED",   value=tostring(speed) .. " b/t" },
        { label="HEADING", value=tostring(heading) .. " deg" },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    local alt     = getAltitude()
    local speed   = nav and nav.getSpeed   and nav.getSpeed()   or "N/A"
    local heading = nav and nav.getHeading and nav.getHeading() or "N/A"
    local pitch   = nav and nav.getPitch   and nav.getPitch()   or "N/A"
    local roll    = nav and nav.getRoll    and nav.getRoll()    or "N/A"

    -- Work out altitude source label for display
    local altStr, altSrc
    if alt then
        altStr = tostring(alt) .. " m"
        altSrc = rr and "[sensor]" or "[nav]"
    else
        altStr = "N/A"
        altSrc = "[no source]"
    end

    -- GPS (non-blocking, uses last known if available)
    local gx, gy, gz = gps.locate(0.5)
    if gx then gpsX, gpsY, gpsZ = gx, gy, gz end

    local function row(y, label, value, col)
        mon.setCursorPos(2, y)
        mon.setTextColor(C.muted)
        mon.setBackgroundColor(C.bg)
        mon.write(string.format("%-12s", label))
        mon.setTextColor(col or C.white)
        mon.write(tostring(value))
    end

    local altColor = C.white
    if type(alt) == "number" then
        altColor = alt < 20 and C.err or (alt < 50 and C.warn or C.ok)
    end

    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("-- FLIGHT DATA ------------------")

    row(y0+1, "Altitude:", altStr, altColor)
    -- Show source of altitude reading in muted text on the same row
    mon.setCursorPos(W - #altSrc, y0+1)
    mon.setTextColor(C.muted)
    mon.write(altSrc)

    row(y0+2, "Speed:",   tostring(speed)   .. " b/t", C.white)
    row(y0+3, "Heading:", tostring(heading) .. " deg",  C.white)
    row(y0+4, "Pitch:",   tostring(pitch)   .. " deg",  C.white)
    row(y0+5, "Roll:",    tostring(roll)    .. " deg",  C.white)

    mon.setCursorPos(2, y0+6)
    mon.setTextColor(C.accent)
    mon.write("-- GPS --------------------------")

    if gpsX then
        row(y0+7, "X / Y / Z:", string.format("%d  %d  %d", gpsX, gpsY, gpsZ), C.white)
    else
        row(y0+7, "GPS:", "No fix", C.err)
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "Altitude Sensor (via " .. ALT_REDROUTER .. " " .. ALT_SIDE .. ")",
            detail = "redstone signal 0-" .. ALT_MAX .. "m",
            check  = function()
                local r = peripheral.wrap(ALT_REDROUTER)
                if not r then return false end
                local ok, sig = pcall(function() return r.getAnalogInput(ALT_SIDE) end)
                return ok and type(sig) == "number"
            end,
        },
        {
            label  = "Navigation Table (speed/heading/pitch/roll)",
            detail = "navigation_table",
            check  = function() return peripheral.find("navigation_table") ~= nil end,
        },
        {
            label  = "GPS Satellites (4 required for position)",
            detail = "gps.locate",
            check  = function()
                local x = gps.locate(1)
                return x ~= nil
            end,
        },
    }
end

return mod
