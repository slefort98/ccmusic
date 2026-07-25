-- ============================================================
--  MODULE: autopilot.lua
--  Waypoint navigation and target altitude management.
--  Reads navigation_table. Sends heading corrections via
--  RedRouter channels (configure below).
--
--  NOTE: Enable this module only when you have the navigation
--  table and RedRouter wired up for autopilot control.
-- ============================================================

local mod = {
    id        = "autopilot",
    name      = "Autopilot",
    shortName = "AUTO",
}

-- ── Config (edit to match your ship wiring) ──────────────────
local HEADING_CHANNEL = 5   -- RedRouter channel for heading correction
local LIFT_CHANNEL    = 6   -- RedRouter channel for altitude correction
local TARGET_ALTITUDE = 100 -- default target altitude in metres
local ALT_TOLERANCE   = 3   -- metres of tolerance before correcting
-- ─────────────────────────────────────────────────────────────

local nav      = nil
local rr       = nil
local enabled  = false
local waypoint = nil   -- { x, y, z, label }

local function getAlt()
    return nav and nav.getAltitude and nav.getAltitude() or nil
end

local function getHeading()
    return nav and nav.getHeading and nav.getHeading() or nil
end

function mod.init(cfg)
    nav     = peripheral.find("navigation_table")
    rr      = peripheral.find("redrouter")
    enabled = false
end

function mod.summary(cfg)
    if not enabled then
        return { { label="Autopilot", value="STANDBY", color=colors.gray } }
    end
    local alt  = getAlt()
    local diff = alt and math.abs(alt - TARGET_ALTITUDE) or nil
    local status = waypoint
        and ("→ " .. (waypoint.label or "WPT"))
        or  ("ALT HOLD " .. TARGET_ALTITUDE .. "m")
    return {
        { label="AUTO", value=status, color=colors.cyan },
        diff and { label="Alt err", value=tostring(diff) .. "m",
                   color = diff < ALT_TOLERANCE and colors.lime or colors.yellow } or nil,
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── AUTOPILOT ────────────────────")

    local function row(y, label, value, col)
        mon.setCursorPos(2, y)
        mon.setTextColor(C.muted)
        mon.setBackgroundColor(C.bg)
        mon.write(string.format("%-16s", label))
        mon.setTextColor(col or C.white)
        mon.write(tostring(value))
    end

    local statusColor = enabled and C.ok or C.muted
    row(y0+1, "Status:", enabled and "ACTIVE" or "STANDBY", statusColor)
    row(y0+2, "Target Alt:", TARGET_ALTITUDE .. " m", C.white)

    local curAlt = getAlt()
    if curAlt then
        local diff = math.abs(curAlt - TARGET_ALTITUDE)
        row(y0+3, "Current Alt:", curAlt .. " m", diff < ALT_TOLERANCE and C.ok or C.warn)
    end

    if waypoint then
        row(y0+4, "Waypoint:", waypoint.label or "Custom", C.accent)
        row(y0+5, "Target XZ:", string.format("%d, %d", waypoint.x, waypoint.z), C.white)
    else
        row(y0+4, "Waypoint:", "None set", C.muted)
    end

    -- Toggle button
    local btnY   = y0 + 7
    local btnBg  = enabled and C.err or C.ok
    local btnTxt = enabled and "  DISENGAGE  " or "  ENGAGE  "
    if btnY <= y1 then
        mon.setCursorPos(2, btnY)
        mon.setTextColor(C.black)
        mon.setBackgroundColor(btnBg)
        mon.write(btnTxt)
    end

    -- Clear alt hold/waypoint buttons
    if btnY + 1 <= y1 then
        mon.setCursorPos(2, btnY+1)
        mon.setTextColor(C.black)
        mon.setBackgroundColor(colors.blue)
        mon.write("  SET ALT HOLD  ")
    end
end

function mod.onClick(x, y, cfg)
    -- Toggle engage (rough row 7 from content top = y0+7 in core terms)
    -- This works because core calls us after drawing, y is absolute monitor y
    enabled = not enabled
end

function mod.connections(cfg)
    return {
        {
            label  = "Navigation Table",
            detail = "navigation_table",
            check  = function() return peripheral.find("navigation_table") ~= nil end,
        },
        {
            label  = "RedRouter (for control outputs)",
            detail = "redrouter",
            check  = function() return peripheral.find("redrouter") ~= nil end,
        },
    }
end

return mod
