-- ============================================================
--  MODULE: comms.lua
--  Rednet message log, connected computer IDs, and
--  broadcast status. Listens on the "shipcomms" protocol.
-- ============================================================

local mod = {
    id        = "comms",
    name      = "Comms",
    shortName = "COMMS",
}

local PROTOCOL   = "shipcomms"
local MAX_LOG    = 12
local modemSide  = nil
local msgLog     = {}   -- { {from, text, time}, ... }
local knownPeers = {}   -- set of computer IDs seen

local function findModemSide()
    for _, side in ipairs({"top","bottom","left","right","front","back"}) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            return side
        end
    end
    return nil
end

function mod.init(cfg)
    modemSide = findModemSide()
    if modemSide then
        pcall(rednet.open, modemSide)
    end
    msgLog     = {}
    knownPeers = {}
end

function mod.onRednet(senderID, message, protocol)
    -- Accept any message or filter by protocol
    if protocol ~= PROTOCOL and protocol ~= nil then return end
    knownPeers[senderID] = true
    local text = type(message) == "string" and message
                 or textutils.serialise(message):sub(1,32)
    table.insert(msgLog, { from=senderID, text=text, time=os.clock() })
    if #msgLog > MAX_LOG then table.remove(msgLog, 1) end
end

function mod.summary(cfg)
    local status = modemSide and "ONLINE" or "NO MODEM"
    local color  = modemSide and colors.lime or colors.red
    local peers  = 0
    for _ in pairs(knownPeers) do peers = peers + 1 end
    return {
        { label="Comms",  value=status,          color=color },
        { label="Peers",  value=tostring(peers) },
        { label="Last msg", value=#msgLog > 0 and msgLog[#msgLog].text:sub(1,14) or "none", color=colors.lightGray },
    }
end

function mod.draw(mon, y0, y1, W, cfg, C)
    mon.setCursorPos(2, y0)
    mon.setTextColor(C.accent)
    mon.setBackgroundColor(C.bg)
    mon.write("── COMMUNICATIONS ───────────────")

    local statusColor = modemSide and C.ok or C.err
    mon.setCursorPos(2, y0+1)
    mon.setTextColor(C.muted)
    mon.write("Modem: ")
    mon.setTextColor(statusColor)
    mon.write(modemSide and ("Online [" .. modemSide .. "]") or "NOT FOUND")

    -- Known peers
    local peerList = {}
    for id in pairs(knownPeers) do peerList[#peerList+1] = id end
    mon.setCursorPos(2, y0+2)
    mon.setTextColor(C.muted)
    mon.write("Peers seen: ")
    mon.setTextColor(C.white)
    mon.write(#peerList == 0 and "none" or table.concat(peerList, ", "):sub(1, W-16))

    -- Message log
    mon.setCursorPos(2, y0+3)
    mon.setTextColor(C.accent)
    mon.write("── Message Log ──────────────────")

    local logStart = y0 + 4
    if #msgLog == 0 then
        mon.setCursorPos(4, logStart)
        mon.setTextColor(C.muted)
        mon.write("No messages received yet.")
    else
        -- Show most recent messages, newest at top
        local display = {}
        for i = #msgLog, 1, -1 do display[#display+1] = msgLog[i] end
        for i, msg in ipairs(display) do
            local row = logStart + (i - 1)
            if row > y1 then break end
            mon.setCursorPos(2, row)
            mon.setTextColor(C.muted)
            mon.write(string.format("[%3d]", msg.from))
            mon.setTextColor(C.white)
            mon.write(" " .. msg.text:sub(1, W-8))
        end
    end
end

function mod.connections(cfg)
    return {
        {
            label  = "Wireless Modem",
            detail = "modem",
            check  = function()
                local side = findModemSide()
                if not side then return false end
                local m = peripheral.wrap(side)
                return m and m.isWireless and m.isWireless()
            end,
        },
    }
end

return mod
