-- ============================================================
--  MODULE: cargo.lua
--  Reads an inventory peripheral (chest, vault, etc.)
--  and displays item counts and slot usage.
-- ============================================================

local mod = {
    id        = "cargo",
    name      = "Cargo",
    shortName = "CARGO",
}

local inv = nil

function mod.init(cfg)
    inv = peripheral.find("inventory")
end

local function getCargoData()
    if not inv then return nil, nil, nil end
    local ok, items = pcall(function() return inv.list() end)
    if not ok then return nil, nil, nil end
    local total     = inv.size()
    local usedSlots = 0
    local itemList  = {}
    for slot, item in pairs(items) do
        usedSlots = usedSlots + 1
        -- Aggregate by item name
        local name = item.name:match(":(.+)$") or item.name  -- strip modid
        itemList[name] = (itemList[name] or 0) + item.count
    end
    return itemList, usedSlots, total
end

function mod.summary(cfg)
    local _, used, total = getCargoData()
    if not used then
        return { { label="Cargo", value="No inventory", color=colors.red } }
    end
    local pct   = math.floor((used / total) * 100)
    local color = pct < 70 and colors.lime or (pct < 90 and colors.yellow or colors.red)
    return {
        { label="Cargo", value=used .. "/" .. total .. " slots (" .. pct .. "%)", color=color },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    local itemList, used, total = getCargoData()

    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── CARGO MANIFEST ───────────────")

    if not itemList then
        mon.setCursorPos(2, y0+2)
        mon.setTextColor(C.err)
        mon.write("No inventory peripheral found.")
        return
    end

    local pct    = math.floor((used / total) * 100)
    local color  = pct < 70 and C.ok or (pct < 90 and C.warn or C.err)
    local barLen = W - 6
    local filled = math.floor((pct/100) * barLen)

    mon.setCursorPos(2, y0+1)
    mon.setTextColor(C.muted)
    mon.write(string.format("Slots: %d/%d  (%d%%)", used, total, pct))
    mon.setCursorPos(3, y0+2)
    mon.setTextColor(color)
    mon.write("[" .. string.rep("█", filled) .. string.rep("░", barLen-filled) .. "]")

    mon.setCursorPos(2, y0+3)
    mon.setTextColor(C.accent)
    mon.write(string.format("%-22s %s", "Item", "Qty"))
    mon.setCursorPos(2, y0+4)
    mon.setTextColor(C.border)
    mon.write(string.rep("-", W-3))

    -- Sort by count descending
    local sorted = {}
    for name, count in pairs(itemList) do
        sorted[#sorted+1] = { name=name, count=count }
    end
    table.sort(sorted, function(a,b) return a.count > b.count end)

    local row = y0 + 5
    for _, item in ipairs(sorted) do
        if row > y1 then break end
        mon.setCursorPos(2, row)
        mon.setTextColor(C.white)
        mon.setBackgroundColor(C.bg)
        -- Truncate name to fit
        local nameW = W - 8
        local name  = item.name:sub(1, nameW)
        mon.write(string.format("%-" .. nameW .. "s %5d", name, item.count))
        row = row + 1
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "Inventory (chest / vault)",
            detail = "inventory",
            check  = function() return peripheral.find("inventory") ~= nil end,
        },
    }
end

return mod
