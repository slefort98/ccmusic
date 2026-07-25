-- ============================================================
--  MODULE: environment.lua
--  Reads world environment data: time of day, weather,
--  and biome (if a Create: Aeronautics nav table is present).
-- ============================================================

local mod = {
    id        = "environment",
    name      = "Environment",
    shortName = "ENV",
}

local nav = nil

local function getTimeStr()
    -- Minecraft day time: 0=dawn, 6000=noon, 13000=dusk, 18000=midnight
    local t = os.time()  -- returns 0-24 float in CC
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    return string.format("%02d:%02d", h % 24, m)
end

local function getDayPhase()
    local t = os.time()
    if t >= 6 and t < 12 then return "Morning", colors.yellow
    elseif t >= 12 and t < 18 then return "Afternoon", colors.orange
    elseif t >= 18 and t < 20 then return "Dusk", colors.orange
    else return "Night", colors.blue end
end

local function getWeather()
    -- CC: Tweaked exposes weather through the "weather" attribute in some builds.
    -- This is a best-effort read.
    local ok, weather = pcall(function() return os.weather and os.weather() or "clear" end)
    if ok then return weather else return "unknown" end
end

function mod.init(cfg)
    nav = peripheral.find("navigation_table")
end

function mod.summary(cfg)
    local timeStr      = getTimeStr()
    local phase, color = getDayPhase()
    return {
        { label="Time",    value=timeStr .. "  " .. phase, color=color },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── ENVIRONMENT ──────────────────")

    local function row(y, label, value, col)
        mon.setCursorPos(2, y)
        mon.setTextColor(C.muted)
        mon.setBackgroundColor(C.bg)
        mon.write(string.format("%-14s", label))
        mon.setTextColor(col or C.white)
        mon.write(tostring(value))
    end

    local timeStr       = getTimeStr()
    local phase, pColor = getDayPhase()
    local weather       = getWeather()

    row(y0+1, "Time:",    timeStr,  C.white)
    row(y0+2, "Phase:",   phase,    pColor)
    row(y0+3, "Weather:", weather,  weather == "clear" and C.ok or C.warn)

    -- Altitude context from nav if available
    if nav then
        local alt    = nav.getAltitude and nav.getAltitude()
        local biome  = nav.getBiome    and nav.getBiome()
        if alt  then row(y0+4, "Altitude:", tostring(alt) .. " m", C.white) end
        if biome then row(y0+5, "Biome:",   biome,                  C.accent) end
    end

    -- Day/night visual bar
    local barY = y0 + 7
    if barY <= y1 then
        local t       = os.time()
        local barLen  = W - 6
        local pos     = math.floor((t / 24) * barLen)
        local bar     = string.rep("─", pos) .. "☀" .. string.rep("─", barLen - pos - 1)
        mon.setCursorPos(3, barY)
        mon.setTextColor(pColor)
        mon.setBackgroundColor(C.bg)
        mon.write("[" .. bar:sub(1, barLen) .. "]")
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "Navigation Table (for biome/alt)",
            detail = "navigation_table",
            check  = function() return peripheral.find("navigation_table") ~= nil end,
        },
        -- Time and weather use CC built-ins, always available
    }
end

return mod
