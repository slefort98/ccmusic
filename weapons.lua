-- ============================================================
--  MODULE: weapons.lua
--  Cannon charge, ammo inventory, and fire control.
--  Reads an inventory peripheral for ammo count and uses
--  RedRouter channels for fire triggers.
--
--  SETUP: Wire a RedRouter output channel to your cannon's
--  firing mechanism. Set FIRE_CHANNEL below.
--  Place an inventory (chest) with ammo next to the computer
--  via wired modem for ammo counting.
-- ============================================================

local mod = {
    id        = "weapons",
    name      = "Weapons",
    shortName = "WEAP",
}

-- ── Config ────────────────────────────────────────────────────
local FIRE_CHANNEL  = 8     -- RedRouter channel for fire trigger
local AMMO_NAMES    = {     -- item names to count as ammo
    "minecraft:iron_ball",
    "create:iron_sheet",
}
-- ─────────────────────────────────────────────────────────────

local rr     = nil
local ammoInv = nil
local armed  = false

local function countAmmo()
    if not ammoInv then return nil end
    local ok, items = pcall(function() return ammoInv.list() end)
    if not ok then return nil end
    local count = 0
    local ammoSet = {}
    for _, name in ipairs(AMMO_NAMES) do ammoSet[name] = true end
    for _, item in pairs(items) do
        if ammoSet[item.name] then count = count + item.count end
    end
    return count
end

function mod.init(cfg)
    rr      = peripheral.find("redrouter")
    ammoInv = peripheral.find("inventory")
    armed   = false
end

function mod.summary(cfg)
    local ammo = countAmmo()
    local ammoStr = ammo and tostring(ammo) or "?"
    local ammoColor = (not ammo or ammo == 0) and colors.red
                     or (ammo < 10 and colors.yellow or colors.lime)
    return {
        { label="Armed",  value=armed and "YES" or "NO", color=armed and colors.red or colors.gray },
        { label="Ammo",   value=ammoStr, color=ammoColor },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    local ammo = countAmmo()

    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── WEAPONS ──────────────────────")

    local function row(y, label, value, col)
        mon.setCursorPos(2, y)
        mon.setTextColor(C.muted)
        mon.setBackgroundColor(C.bg)
        mon.write(string.format("%-14s", label))
        mon.setTextColor(col or C.white)
        mon.write(tostring(value))
    end

    local armedColor = armed and C.err or C.muted
    row(y0+1, "Status:", armed and "ARMED" or "SAFE",    armedColor)
    row(y0+2, "Ammo:",   ammo and tostring(ammo) or "N/A",
        (not ammo or ammo == 0) and C.err or (ammo < 10 and C.warn or C.ok))

    -- Arm / Safe toggle button
    local armBtnY  = y0 + 4
    if armBtnY <= y1 then
        local btnBg  = armed and colors.gray or C.err
        local btnTxt = armed and "  SAFE  " or "  ARM  "
        mon.setCursorPos(2, armBtnY)
        mon.setTextColor(C.white)
        mon.setBackgroundColor(btnBg)
        mon.write(btnTxt)
    end

    -- Fire button (only shown when armed)
    if armed then
        local fireBtnY = y0 + 5
        if fireBtnY <= y1 then
            mon.setCursorPos(2, fireBtnY)
            mon.setTextColor(C.black)
            mon.setBackgroundColor(C.err)
            mon.write("  !! FIRE !!  ")
        end
    end

    if not rr then
        row(y0 + (armed and 7 or 6), "Warning:", "No RedRouter found", C.err)
    end
end

function mod.onClick(x, y, cfg)
    -- ARM/SAFE toggle — approximate position
    if x >= 2 and x <= 12 then
        armed = not armed
    end
    -- FIRE — only when armed, approximate next row
    if armed and x >= 2 and x <= 16 then
        if rr then
            -- Pulse fire channel
            pcall(function()
                rr.setOutput(FIRE_CHANNEL, 15)
                os.sleep(0.1)
                rr.setOutput(FIRE_CHANNEL, 0)
            end)
        end
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "RedRouter (fire control)",
            detail = "redrouter",
            check  = function() return peripheral.find("redrouter") ~= nil end,
        },
        {
            label  = "Ammo Inventory (chest)",
            detail = "inventory",
            check  = function() return peripheral.find("inventory") ~= nil end,
        },
    }
end

return mod
