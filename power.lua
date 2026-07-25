-- ============================================================
--  MODULE: power.lua
--  Reads Create: Power Grid gauges via redstone analog input
--  or via a CC:C RedRouter if the gauge is not adjacent.
--
--  SETUP: Place a Voltmeter Gauge on the edge of a Circuit
--  Board. It emits redstone 0-15 proportional to voltage.
--  Wire that redstone output to a side of this computer
--  (or through a RedRouter).
--
--  Edit VOLT_SIDE, VOLT_MAX, AMP_SIDE, AMP_MAX below to
--  match your wiring.
-- ============================================================

local mod = {
    id        = "power",
    name      = "Power",
    shortName = "POWER",
}

-- ── Configuration (edit to match your ship) ──────────────────
local VOLT_SIDE = "left"    -- side the voltmeter redstone signal comes in on
local VOLT_MAX  = 230       -- max voltage your gauge is set to (e.g. 230V)
local AMP_SIDE  = "right"   -- side the ammeter signal comes in on (or nil)
local AMP_MAX   = 20        -- max amps your ammeter is set to
-- ─────────────────────────────────────────────────────────────

local rr          = nil
local useRouter   = false

local function readVoltage()
    local sig
    if useRouter and rr then
        local ok, v = pcall(function() return rr.getAnalogInput(VOLT_SIDE) end)
        sig = ok and v or 0
    else
        sig = redstone.getAnalogInput(VOLT_SIDE)
    end
    return math.floor((sig / 15) * VOLT_MAX * 10) / 10
end

local function readAmps()
    if not AMP_SIDE then return nil end
    local sig
    if useRouter and rr then
        local ok, v = pcall(function() return rr.getAnalogInput(AMP_SIDE) end)
        sig = ok and v or 0
    else
        sig = redstone.getAnalogInput(AMP_SIDE)
    end
    return math.floor((sig / 15) * AMP_MAX * 10) / 10
end

function mod.init(cfg)
    rr = peripheral.find("redrouter")
    -- Prefer RedRouter if present, otherwise direct redstone
    useRouter = (rr ~= nil)
end

function mod.summary(cfg)
    local v = readVoltage()
    local a = readAmps()
    local vColor = v > VOLT_MAX * 0.8 and colors.lime or (v > VOLT_MAX * 0.4 and colors.yellow or colors.red)
    local result = {
        { label="Voltage", value=string.format("%.1fV", v), color=vColor },
    }
    if a then
        result[#result+1] = { label="Current", value=string.format("%.1fA", a) }
    end
    return result
end

function mod.draw(mon, y0, y1, W, cfg, C)
    local v = readVoltage()
    local a = readAmps()
    local w = a and (v * a) or nil

    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── POWER GRID ───────────────────")

    local function row(y, label, value, col)
        mon.setCursorPos(2, y)
        mon.setTextColor(C.muted)
        mon.setBackgroundColor(C.bg)
        mon.write(string.format("%-14s", label))
        mon.setTextColor(col or C.white)
        mon.write(tostring(value))
    end

    local vPct   = math.min(100, math.floor((v / VOLT_MAX) * 100))
    local vColor = vPct > 70 and C.ok or (vPct > 30 and C.warn or C.err)

    row(y0+1, "Voltage:",  string.format("%.1f V", v),  vColor)
    if a then
        local aColor = a < AMP_MAX * 0.8 and C.ok or C.err
        row(y0+2, "Current:", string.format("%.1f A", a), aColor)
    end
    if w then
        row(y0+3, "Power:", string.format("%.1f W", w), C.white)
    end

    -- Voltage bar
    local barLen = W - 6
    local filled = math.floor((vPct / 100) * barLen)
    mon.setCursorPos(3, y0 + (a and 4 or 3))
    mon.setBackgroundColor(C.bg)
    mon.setTextColor(vColor)
    mon.write("[" .. string.rep("█", filled) .. string.rep("░", barLen - filled) .. "]")

    -- Warning if voltage dangerously low
    if v < VOLT_MAX * 0.2 then
        mon.setCursorPos(2, y0 + (a and 5 or 4))
        mon.setTextColor(C.err)
        mon.write("!! LOW VOLTAGE WARNING !!")
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "Voltmeter (redstone on '" .. VOLT_SIDE .. "')",
            detail = "analog redstone",
            check  = function()
                return redstone.getAnalogInput(VOLT_SIDE) ~= nil
            end,
        },
        {
            label  = "RedRouter (optional, for remote gauges)",
            detail = "redrouter",
            check  = function() return peripheral.find("redrouter") ~= nil end,
        },
    }
end

return mod
