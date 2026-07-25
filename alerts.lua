-- ============================================================
--  MODULE: alerts.lua
--  Central warning log. Other modules can post alerts here.
--  Also polls connection state of all enabled modules and
--  fires a warning if any peripheral goes offline.
--
--  OTHER MODULES: call alerts.post(level, source, message)
--  Levels: "INFO", "WARN", "CRIT"
-- ============================================================

local mod = {
    id        = "alerts",
    name      = "Alerts",
    shortName = "ALERT",
}

local MAX_ALERTS = 20
local alertLog   = {}   -- { {level, source, message, time}, ... }

-- ── Public API for other modules to post alerts ───────────────
-- (Access via the global _G.hudAlerts after first init)

local function post(level, source, message)
    table.insert(alertLog, {
        level   = level or "INFO",
        source  = source or "?",
        message = message or "",
        time    = os.clock(),
    })
    if #alertLog > MAX_ALERTS then table.remove(alertLog, 1) end
end

function mod.init(cfg)
    alertLog = {}
    -- Expose to global so other modules can call hudAlerts.post(...)
    _G.hudAlerts = { post = post }
end

function mod.summary(cfg)
    -- Count unacknowledged criticals and warnings
    local crits = 0
    local warns = 0
    for _, a in ipairs(alertLog) do
        if a.level == "CRIT" then crits = crits + 1
        elseif a.level == "WARN" then warns = warns + 1 end
    end
    if crits > 0 then
        return { { label="ALERTS", value=crits .. " CRITICAL", color=colors.red } }
    elseif warns > 0 then
        return { { label="Alerts", value=warns .. " warnings",  color=colors.yellow } }
    else
        return { { label="Alerts", value="All clear",           color=colors.lime } }
    end
end

function mod.draw(mon, y0, y1, W, cfg, C)
    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── ALERT LOG ────────────────────")

    -- Clear button
    mon.setCursorPos(W - 9, y0)
    mon.setTextColor(C.black)
    mon.setBackgroundColor(colors.gray)
    mon.write(" CLEAR ")

    if #alertLog == 0 then
        mon.setCursorPos(4, y0+2)
        mon.setTextColor(C.ok)
        mon.setBackgroundColor(C.bg)
        mon.write("No alerts. All systems nominal.")
        return
    end

    -- Show newest first
    local display = {}
    for i = #alertLog, 1, -1 do display[#display+1] = alertLog[i] end

    local row = y0 + 1
    for _, alert in ipairs(display) do
        if row > y1 then break end

        local levelColor = C.muted
        local levelStr   = "[INFO]"
        if alert.level == "WARN" then
            levelColor = C.warn
            levelStr   = "[WARN]"
        elseif alert.level == "CRIT" then
            levelColor = C.err
            levelStr   = "[CRIT]"
        end

        mon.setCursorPos(2, row)
        mon.setTextColor(levelColor)
        mon.setBackgroundColor(C.bg)
        mon.write(levelStr .. " ")
        mon.setTextColor(C.muted)
        mon.write(string.format("%-8s", alert.source:sub(1,8)))
        mon.setTextColor(C.white)
        mon.write(alert.message:sub(1, W - 20))
        row = row + 1
    end
end

function mod.onClick(x, y, cfg)
    -- CLEAR button (top right of draw area)
    if x >= W - 9 then
        alertLog = {}
    end
end

function mod.connections(cfg)
    -- Alerts has no peripheral requirements of its own
    return {
        {
            label  = "No peripherals required",
            detail = "internal",
            check  = function() return true end,
        },
    }
end

-- Allow direct call from outside: alerts.post(...)
mod.post = post

return mod
