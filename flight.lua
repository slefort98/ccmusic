-- ============================================================
--  MODULE: flight.lua
--  Reads navigation_table peripheral for altitude, speed,
--  heading, and GPS coordinates.
-- ============================================================

local mod = {
    id        = "flight",
    name      = "Flight",
    shortName = "FLIGHT",
}

local nav = nil
local gpsX, gpsY, gpsZ = nil, nil, nil

function mod.init(cfg)
    nav = peripheral.find("navigation_table")
end

function mod.summary(cfg)
    local alt     = nav and nav.getAltitude  and nav.getAltitude()  or "N/A"
    local speed   = nav and nav.getSpeed     and nav.getSpeed()     or "N/A"
    local heading = nav and nav.getHeading   and nav.getHeading()   or "N/A"
    local altColor  = colors.white
    if type(alt) == "number" then
        altColor = alt < 20 and colors.red or (alt < 50 and colors.yellow or colors.lime)
    end
    return {
        { label="ALT",     value=tostring(alt) .. "m",  color=altColor },
        { label="SPEED",   value=tostring(speed) .. " b/t" },
        { label="HEADING", value=tostring(heading) .. "°" },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    local alt     = nav and nav.getAltitude  and nav.getAltitude()  or "N/A"
    local speed   = nav and nav.getSpeed     and nav.getSpeed()     or "N/A"
    local heading = nav and nav.getHeading   and nav.getHeading()   or "N/A"
    local pitch   = nav and nav.getPitch     and nav.getPitch()     or "N/A"
    local roll    = nav and nav.getRoll      and nav.getRoll()      or "N/A"

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

    local altColor = colors.white
    if type(alt) == "number" then
        altColor = alt < 20 and C.err or (alt < 50 and C.warn or C.ok)
    end

    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── FLIGHT DATA ──────────────────")

    row(y0+1, "Altitude:",  tostring(alt)     .. " m",   altColor)
    row(y0+2, "Speed:",     tostring(speed)   .. " b/t", C.white)
    row(y0+3, "Heading:",   tostring(heading) .. "°",    C.white)
    row(y0+4, "Pitch:",     tostring(pitch)   .. "°",    C.white)
    row(y0+5, "Roll:",      tostring(roll)    .. "°",    C.white)

    mon.setCursorPos(2, y0+6)
    mon.setTextColor(C.accent)
    mon.write("── GPS ──────────────────────────")

    if gpsX then
        row(y0+7, "X / Y / Z:", string.format("%d  %d  %d", gpsX, gpsY, gpsZ), C.white)
    else
        row(y0+7, "GPS:", "No fix", C.err)
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "Navigation Table",
            detail = "navigation_table",
            check  = function() return peripheral.find("navigation_table") ~= nil end,
        },
        {
            label  = "GPS Satellites (4 required)",
            detail = "gps.locate",
            check  = function()
                local x = gps.locate(1)
                return x ~= nil
            end,
        },
    }
end

return mod
