-- ============================================================
--  AIRSHIP HUD  |  hud/core.lua
--  Central engine: monitor setup, tab routing, draw loop,
--  rotation timer, setup wizard, config persistence.
-- ============================================================

local core = {}

-- ── Constants ───────────────────────────────────────────────
local CONFIG_PATH   = "/hud/config.lua"
local MODULES_DIR   = "/hud/modules"
local ROTATE_SECS   = 5        -- seconds per rotation slot tick
local TEXT_SCALE    = 0.5      -- monitor text scale (0.5 fits most on 3x2)

-- Colour palette (Advanced Monitor colours)
local C = {
    bg         = colors.black,
    header_bg  = colors.gray,
    header_fg  = colors.white,
    tab_bg     = colors.gray,
    tab_fg     = colors.lightGray,
    tab_active = colors.white,
    tab_hl     = colors.blue,
    border     = colors.gray,
    ok         = colors.lime,
    warn       = colors.yellow,
    err        = colors.red,
    muted      = colors.lightGray,
    accent     = colors.cyan,
    white      = colors.white,
    black      = colors.black,
}

-- ── State ────────────────────────────────────────────────────
local mon           = nil   -- monitor peripheral
local W, H          = 0, 0  -- monitor dimensions
local cfg           = {}    -- loaded config table
local modules       = {}    -- all discovered module tables
local enabledMods   = {}    -- ordered list of enabled module tables
local activeTab     = 1     -- index into enabledMods (1 = overview)
local activeSubTab  = "data"-- "data" or "connections" within a module tab
local rotSlots      = {}    -- { {mods={m,m,...}, current=1} , ... }
local rotTimer      = nil   -- os timer handle
local running       = true

-- ── Utility ─────────────────────────────────────────────────

local function writeAt(x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    if fg  then mon.setTextColor(fg)       end
    if bg  then mon.setBackgroundColor(bg) end
    mon.write(text)
end

local function fillLine(y, char, fg, bg)
    if bg  then mon.setBackgroundColor(bg) end
    if fg  then mon.setTextColor(fg)       end
    mon.setCursorPos(1, y)
    mon.write(string.rep(char or " ", W))
end

local function centre(y, text, fg, bg)
    local x = math.floor((W - #text) / 2) + 1
    writeAt(x, y, text, fg, bg)
end

local function padR(s, len)
    s = tostring(s or "")
    return s .. string.rep(" ", math.max(0, len - #s))
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- ── Config persistence ───────────────────────────────────────

local function saveConfig()
    local f = fs.open(CONFIG_PATH, "w")
    if not f then return end
    -- Serialise as a Lua table literal so we can dofile() it back
    f.write("return " .. textutils.serialise(cfg))
    f.close()
end

local function loadConfig()
    if not fs.exists(CONFIG_PATH) then return nil end
    local ok, result = pcall(dofile, CONFIG_PATH)
    if ok and type(result) == "table" then return result end
    return nil
end

-- ── Module loader ────────────────────────────────────────────

local function loadModules()
    modules = {}
    if not fs.isDir(MODULES_DIR) then return end
    local files = fs.list(MODULES_DIR)
    table.sort(files)
    for _, fname in ipairs(files) do
        if fname:match("%.lua$") then
            local path = MODULES_DIR .. "/" .. fname
            local ok, mod = pcall(dofile, path)
            if ok and type(mod) == "table" and mod.id then
                modules[#modules+1] = mod
            end
        end
    end
end

local function buildEnabledList()
    enabledMods = {}
    -- Enabled order follows the order in cfg.moduleOrder
    for _, id in ipairs(cfg.moduleOrder or {}) do
        if cfg.enabled[id] then
            for _, m in ipairs(modules) do
                if m.id == id then
                    enabledMods[#enabledMods+1] = m
                    break
                end
            end
        end
    end
end

local function initModules()
    for _, m in ipairs(enabledMods) do
        if m.init then pcall(m.init, cfg) end
    end
end

-- ── Rotation slot builder ─────────────────────────────────────

local function buildRotationSlots()
    rotSlots = {}
    -- Static modules never rotate
    local staticIds = { flight = true, engines = true }
    -- cfg.rotPairs is a list of lists: { {"fuel","power"}, {"cargo","environment"}, ... }
    local pairs_ = cfg.rotPairs or {}
    -- Build a set of all paired module ids
    local paired = {}
    for _, pair in ipairs(pairs_) do
        for _, id in ipairs(pair) do paired[id] = true end
    end
    -- Add configured pairs as slots
    for _, pair in ipairs(pairs_) do
        local slot = { mods = {}, current = 1 }
        for _, id in ipairs(pair) do
            if cfg.enabled[id] then
                for _, m in ipairs(enabledMods) do
                    if m.id == id then
                        slot.mods[#slot.mods+1] = m
                        break
                    end
                end
            end
        end
        if #slot.mods > 0 then
            rotSlots[#rotSlots+1] = slot
        end
    end
    -- Any enabled non-static, unpaired module gets its own solo slot
    for _, m in ipairs(enabledMods) do
        if not staticIds[m.id] and not paired[m.id] then
            rotSlots[#rotSlots+1] = { mods = {m}, current = 1 }
        end
    end
end

-- ── Draw: Header ─────────────────────────────────────────────

local function drawHeader()
    mon.setBackgroundColor(C.header_bg)
    fillLine(1, " ", C.header_fg, C.header_bg)
    local shipLabel = (cfg.shipName or "UNNAMED") .. "  #" .. (cfg.shipID or "???")
    local timeStr   = os.date and os.date("%H:%M") or ""
    writeAt(2, 1, shipLabel, C.accent, C.header_bg)
    writeAt(W - #timeStr, 1, timeStr, C.muted, C.header_bg)
end

-- ── Draw: Tab bar ────────────────────────────────────────────

local function drawTabBar()
    -- Tabs: OVERVIEW + one per enabled module
    local tabs = { "OVERVIEW" }
    for _, m in ipairs(enabledMods) do
        tabs[#tabs+1] = m.shortName or m.name:sub(1,6):upper()
    end

    fillLine(H, " ", C.tab_fg, C.tab_bg)
    mon.setCursorPos(1, H)

    local colW = math.floor(W / #tabs)
    for i, label in ipairs(tabs) do
        local x    = (i-1)*colW + 1
        local isAct = (i == activeTab)
        local bg   = isAct and C.tab_hl   or C.tab_bg
        local fg   = isAct and C.tab_active or C.tab_fg
        -- Fill the cell
        mon.setCursorPos(x, H)
        mon.setBackgroundColor(bg)
        mon.setTextColor(fg)
        local cell = padR(label, colW)
        mon.write(cell:sub(1, colW))
    end
end

-- ── Draw: Overview ────────────────────────────────────────────

local function drawOverview()
    local contentY1 = 2
    local contentY2 = H - 1
    local rows       = contentY2 - contentY1 + 1

    -- Static modules: flight & engines always fill top half
    local staticMods = {}
    local staticIds  = { flight = true, engines = true }
    for _, m in ipairs(enabledMods) do
        if staticIds[m.id] then staticMods[#staticMods+1] = m end
    end

    -- Layout: split rows evenly between static zone and rotation zone
    local staticRows = math.floor(rows * 0.45)
    local rotRows    = rows - staticRows

    -- Draw static zone
    local sy = contentY1
    mon.setBackgroundColor(C.bg)
    for rowIdx = contentY1, contentY1 + staticRows - 1 do
        fillLine(rowIdx, " ", C.white, C.bg)
    end

    if #staticMods == 0 then
        centre(contentY1 + math.floor(staticRows/2), "No static modules enabled", C.muted, C.bg)
    else
        local slotH = math.floor(staticRows / #staticMods)
        for i, m in ipairs(staticMods) do
            local y0 = contentY1 + (i-1)*slotH
            -- Module label
            writeAt(2, y0, "[ " .. (m.name or m.id):upper() .. " ]", C.accent, C.bg)
            -- Summary lines
            local summary = {}
            if m.summary then
                local ok, s = pcall(m.summary, cfg)
                if ok and type(s) == "table" then summary = s end
            end
            for li, line in ipairs(summary) do
                if y0 + li <= contentY1 + staticRows - 1 then
                    writeAt(4, y0 + li, line.label .. ": " .. tostring(line.value),
                            line.color or C.white, C.bg)
                end
            end
        end
    end

    -- Separator
    local sepY = contentY1 + staticRows
    fillLine(sepY, "-", C.border, C.bg)
    writeAt(2, sepY, " ROTATING ", C.muted, C.bg)

    -- Draw rotation zone
    local ry0 = sepY + 1
    if #rotSlots == 0 then
        centre(ry0 + math.floor(rotRows/2) - 1, "No rotating modules enabled", C.muted, C.bg)
        return
    end

    local slotH2 = math.floor((contentY2 - ry0 + 1) / #rotSlots)
    for si, slot in ipairs(rotSlots) do
        local y0  = ry0 + (si-1)*slotH2
        local m   = slot.mods[slot.current]
        if m then
            for rowIdx = y0, y0 + slotH2 - 1 do
                fillLine(rowIdx, " ", C.white, C.bg)
            end
            -- Dot indicator if multiple in slot
            local dotStr = ""
            if #slot.mods > 1 then
                for di = 1, #slot.mods do
                    dotStr = dotStr .. (di == slot.current and "●" or "○")
                end
            end
            writeAt(2, y0, "[ " .. (m.name or m.id):upper() .. " ] " .. dotStr, C.accent, C.bg)
            local summary = {}
            if m.summary then
                local ok, s = pcall(m.summary, cfg)
                if ok and type(s) == "table" then summary = s end
            end
            for li, line in ipairs(summary) do
                if y0 + li <= y0 + slotH2 - 1 then
                    writeAt(4, y0 + li, line.label .. ": " .. tostring(line.value),
                            line.color or C.white, C.bg)
                end
            end
        end
    end
end

-- ── Draw: Module detail (data view) ──────────────────────────

local function drawModuleData(mod)
    local y0 = 2
    local y1 = H - 2  -- leave room for sub-tab strip
    -- Sub-tab strip
    fillLine(H-1, " ", C.muted, C.header_bg)
    local dtBg = activeSubTab == "data"        and C.tab_hl or C.tab_bg
    local cnBg = activeSubTab == "connections" and C.tab_hl or C.tab_bg
    writeAt(2,       H-1, " DATA ",        activeSubTab=="data"        and C.white or C.tab_fg, dtBg)
    writeAt(10,      H-1, " CONNECTIONS ", activeSubTab=="connections" and C.white or C.tab_fg, cnBg)

    -- Clear content area
    mon.setBackgroundColor(C.bg)
    for row = y0, y1 do fillLine(row, " ", C.white, C.bg) end

    if activeSubTab == "data" then
        if mod.draw then
            local ok, err = pcall(mod.draw, mon, y0, y1, W, cfg, C)
            if not ok then
                writeAt(2, y0+1, "Draw error:", C.err, C.bg)
                writeAt(2, y0+2, tostring(err):sub(1, W-2), C.muted, C.bg)
            end
        else
            centre(y0 + math.floor((y1-y0)/2), "No data view for this module", C.muted, C.bg)
        end
    else
        -- Connections view
        local conns = {}
        if mod.connections then
            local ok, c = pcall(mod.connections, cfg)
            if ok and type(c) == "table" then conns = c end
        end
        writeAt(2, y0, "REQUIRED CONNECTIONS", C.accent, C.bg)
        if #conns == 0 then
            writeAt(2, y0+2, "No connections defined for this module.", C.muted, C.bg)
        else
            for i, conn in ipairs(conns) do
                local row = y0 + i
                if row > y1 then break end
                local found = false
                if conn.check then
                    local ok2, result = pcall(conn.check)
                    found = ok2 and result
                end
                local icon  = found and "[OK]" or "[!!]"
                local color = found and C.ok   or C.err
                writeAt(2,  row, icon,          color,  C.bg)
                writeAt(8,  row, conn.label,    C.white, C.bg)
                if conn.detail then
                    local detail = found and (conn.foundDetail and conn.foundDetail() or "") or conn.detail
                    writeAt(W - #detail, row, detail, C.muted, C.bg)
                end
            end
        end
    end
end

-- ── Full redraw ───────────────────────────────────────────────

local function redraw()
    mon.setBackgroundColor(C.bg)
    mon.clear()
    drawHeader()
    drawTabBar()

    if activeTab == 1 then
        drawOverview()
    else
        local mod = enabledMods[activeTab - 1]
        if mod then drawModuleData(mod) end
    end
end

-- ── Click handling ────────────────────────────────────────────

local function handleClick(x, y)
    -- Tab bar (bottom row)
    if y == H then
        local tabs = { "OVERVIEW" }
        for _, m in ipairs(enabledMods) do tabs[#tabs+1] = m.shortName or m.name:sub(1,6):upper() end
        local colW = math.floor(W / #tabs)
        local idx  = math.ceil(x / colW)
        idx = clamp(idx, 1, #tabs)
        if idx ~= activeTab then
            activeTab    = idx
            activeSubTab = "data"
        end
        redraw()
        return
    end

    -- Sub-tab strip (second to last row, only when in a module tab)
    if y == H-1 and activeTab > 1 then
        if x >= 2 and x <= 7 then
            activeSubTab = "data"
            redraw()
        elseif x >= 10 and x <= 23 then
            activeSubTab = "connections"
            redraw()
        end
        return
    end

    -- Forward click to active module if it wants it
    if activeTab > 1 and activeSubTab == "data" then
        local mod = enabledMods[activeTab - 1]
        if mod and mod.onClick then
            pcall(mod.onClick, x, y, cfg)
            redraw()
        end
    end
end

-- ── Rotation tick ─────────────────────────────────────────────

local function tickRotation()
    for _, slot in ipairs(rotSlots) do
        if #slot.mods > 1 then
            slot.current = (slot.current % #slot.mods) + 1
        end
    end
    if activeTab == 1 then redraw() end
    rotTimer = os.startTimer(ROTATE_SECS)
end

-- ══════════════════════════════════════════════════════════════
--  SETUP WIZARD
-- ══════════════════════════════════════════════════════════════

local wizard = {}

-- Wizard state
local wStep      = 1
local wData      = {}  -- accumulates answers
local wInput     = ""  -- current text field value
local wFocused   = false

local function wClear()
    mon.setBackgroundColor(C.bg)
    mon.clear()
    -- Title bar
    fillLine(1, " ", C.accent, C.header_bg)
    centre(1, "  AIRSHIP HUD  SETUP WIZARD  ", C.accent, C.header_bg)
end

local function wButton(x, y, label, fg, bg)
    local pad = "  " .. label .. "  "
    writeAt(x, y, pad, fg or C.black, bg or C.accent)
    return { x1=x, y1=y, x2=x+#pad-1, y2=y, label=label }
end

local function wHit(btn, x, y)
    return x >= btn.x1 and x <= btn.x2 and y >= btn.y1 and y <= btn.y2
end

-- Step 1: Ship name
local function wDrawStep1()
    wClear()
    centre(3,  "Step 1 of 4", C.muted, C.bg)
    centre(5,  "What is this ship's name?", C.white, C.bg)
    -- Input box
    local boxW = 24
    local boxX = math.floor((W - boxW)/2) + 1
    writeAt(boxX, 7, string.rep(" ", boxW), C.black, colors.lightGray)
    writeAt(boxX, 7, (wData.shipName or ""), C.black, colors.lightGray)
    centre(9, "Click here and type, then press [CONFIRM]", C.muted, C.bg)
    wButton(math.floor(W/2)-6, 11, "CONFIRM", C.black, C.accent)
    wButton(math.floor(W/2)+2, 11, "CLEAR",   C.black, colors.gray)
    wFocused = true
end

-- Step 2: Ship ID
local function wDrawStep2()
    wClear()
    centre(3,  "Step 2 of 4", C.muted, C.bg)
    centre(5,  "Enter a short Ship ID (e.g. ARK-01)", C.white, C.bg)
    local boxW = 16
    local boxX = math.floor((W - boxW)/2) + 1
    writeAt(boxX, 7, string.rep(" ", boxW), C.black, colors.lightGray)
    writeAt(boxX, 7, (wData.shipID or ""), C.black, colors.lightGray)
    wButton(math.floor(W/2)-6, 10, "CONFIRM", C.black, C.accent)
    wButton(math.floor(W/2)+2, 10, "CLEAR",   C.black, colors.gray)
end

-- Step 3: Enable modules
local function wDrawStep3()
    wClear()
    centre(3, "Step 3 of 4", C.muted, C.bg)
    centre(4, "Select modules to enable:", C.white, C.bg)

    wData.enabled = wData.enabled or {}
    local colW = math.floor(W / 2) - 1
    local row  = 5

    for i, m in ipairs(modules) do
        local col   = (i-1) % 2
        local x     = col * (colW + 2) + 2
        local isOn  = wData.enabled[m.id]
        local bg    = isOn and C.ok or colors.gray
        local label = (isOn and "[ON ] " or "[OFF] ") .. (m.name or m.id)
        writeAt(x, row, padR(label, colW), isOn and C.black or C.white, bg)
        if col == 1 then row = row + 1 end
    end
    if #modules % 2 == 1 then row = row + 1 end

    wButton(math.floor(W/2)-6, H-1, "CONTINUE", C.black, C.accent)
end

-- Step 4: Assign rotation pairs
local function wDrawStep4()
    wClear()
    centre(3, "Step 4 of 4", C.muted, C.bg)
    centre(4, "Pair modules for overview rotation:", C.white, C.bg)
    centre(5, "(Flight & Engines are always static)", C.muted, C.bg)

    local staticIds = { flight=true, engines=true }
    local rotatables = {}
    for _, m in ipairs(modules) do
        if wData.enabled[m.id] and not staticIds[m.id] then
            rotatables[#rotatables+1] = m
        end
    end

    wData.rotPairs  = wData.rotPairs  or {}
    wData.rotUnpair = wData.rotUnpair or {}

    -- Show current pairs
    local row = 7
    writeAt(2, 6, "Current pairs:", C.accent, C.bg)
    for pi, pair in ipairs(wData.rotPairs) do
        local line = table.concat(pair, "  +  ")
        writeAt(4, row, line, C.ok, C.bg)
        local btn = wButton(W - 8, row, "UNPAIR", C.black, colors.orange)
        btn.pairIndex = pi
        row = row + 1
    end

    -- Show unpaired modules as clickable buttons to pair
    if #rotatables > 0 then
        writeAt(2, row, "Unpaired (click two to pair):", C.muted, C.bg)
        row = row + 1
        local sel = wData.rotSel
        for _, m in ipairs(rotatables) do
            -- Check if already paired
            local inPair = false
            for _, p in ipairs(wData.rotPairs) do
                for _, pid in ipairs(p) do
                    if pid == m.id then inPair = true end
                end
            end
            if not inPair then
                local bg = (sel == m.id) and C.warn or colors.gray
                writeAt(4, row, padR(m.name or m.id, 16), C.black, bg)
                row = row + 1
                if row >= H - 1 then break end
            end
        end
    end

    wButton(math.floor(W/2)-6, H-1, "FINISH", C.black, C.accent)
end

local wStepDrawers = { wDrawStep1, wDrawStep2, wDrawStep3, wDrawStep4 }

local function wDraw()
    if wStepDrawers[wStep] then wStepDrawers[wStep]() end
end

local function wHandleKey(key)
    if not wFocused then return end
    if wStep == 1 then
        if key == keys.backspace then
            wData.shipName = (wData.shipName or ""):sub(1,-2)
        elseif key ~= keys.enter then
            local ch = keys.getName(key)
            if ch and #ch == 1 then
                wData.shipName = (wData.shipName or "") .. ch
            end
        end
        wDraw()
    elseif wStep == 2 then
        if key == keys.backspace then
            wData.shipID = (wData.shipID or ""):sub(1,-2)
        elseif key ~= keys.enter then
            local ch = keys.getName(key)
            if ch and #ch == 1 then
                wData.shipID = (wData.shipID or "") .. (ch:upper())
            end
        end
        wDraw()
    end
end

local function wHandleChar(ch)
    if not wFocused then return end
    if wStep == 1 then
        wData.shipName = (wData.shipName or "") .. ch
        wDraw()
    elseif wStep == 2 then
        wData.shipID = (wData.shipID or "") .. ch:upper()
        wDraw()
    end
end

local function wHandleClick(x, y)
    if wStep == 1 then
        -- CONFIRM button approx position
        local cx = math.floor(W/2)-6
        if y == 11 and x >= cx and x <= cx+9 then
            if (wData.shipName or "") ~= "" then
                wStep = 2
            end
        elseif y == 11 and x >= math.floor(W/2)+2 then
            wData.shipName = ""
        end
        wDraw()

    elseif wStep == 2 then
        local cx = math.floor(W/2)-6
        if y == 10 and x >= cx and x <= cx+9 then
            if (wData.shipID or "") ~= "" then
                wStep = 3
            end
        elseif y == 10 and x >= math.floor(W/2)+2 then
            wData.shipID = ""
        end
        wDraw()

    elseif wStep == 3 then
        -- Toggle module buttons
        local colW = math.floor(W / 2) - 1
        local row  = 5
        for i, m in ipairs(modules) do
            local col = (i-1) % 2
            local bx  = col * (colW + 2) + 2
            if y == row and x >= bx and x <= bx + colW - 1 then
                wData.enabled[m.id] = not wData.enabled[m.id]
            end
            if col == 1 then row = row + 1 end
        end
        -- Continue button
        local cx = math.floor(W/2)-6
        if y == H-1 and x >= cx then
            wStep = 4
        end
        wDraw()

    elseif wStep == 4 then
        local staticIds   = { flight=true, engines=true }
        local rotatables  = {}
        for _, m in ipairs(modules) do
            if wData.enabled[m.id] and not staticIds[m.id] then
                rotatables[#rotatables+1] = m
            end
        end

        -- Check FINISH button
        local cx = math.floor(W/2)-6
        if y == H-1 and x >= cx then
            -- Build final config and save
            local moduleOrder = {}
            for _, m in ipairs(modules) do moduleOrder[#moduleOrder+1] = m.id end
            cfg = {
                shipName    = wData.shipName,
                shipID      = wData.shipID,
                enabled     = wData.enabled,
                moduleOrder = moduleOrder,
                rotPairs    = wData.rotPairs or {},
            }
            saveConfig()
            return true  -- signal wizard complete
        end

        -- Check UNPAIR buttons (approx: right side of screen on pair rows)
        local row = 7
        for pi, pair in ipairs(wData.rotPairs) do
            if y == row and x >= W - 10 then
                table.remove(wData.rotPairs, pi)
                wDraw()
                return false
            end
            row = row + 1
        end

        -- Check unpaired module buttons for pairing
        row = row + 2  -- skip "Unpaired" label
        for _, m in ipairs(rotatables) do
            local inPair = false
            for _, p in ipairs(wData.rotPairs) do
                for _, pid in ipairs(p) do if pid == m.id then inPair = true end end
            end
            if not inPair then
                if y == row and x >= 4 and x <= 20 then
                    if not wData.rotSel then
                        wData.rotSel = m.id
                    elseif wData.rotSel == m.id then
                        wData.rotSel = nil
                    else
                        -- Pair the two
                        wData.rotPairs[#wData.rotPairs+1] = { wData.rotSel, m.id }
                        wData.rotSel = nil
                    end
                    wDraw()
                    return false
                end
                row = row + 1
                if row >= H - 1 then break end
            end
        end

        wDraw()
    end
    return false
end

local function runWizard()
    wStep = 1
    wData = { enabled = {}, rotPairs = {} }
    -- Default all modules to enabled
    for _, m in ipairs(modules) do wData.enabled[m.id] = true end
    wDraw()

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "monitor_touch" then
            local done = wHandleClick(p2, p3)
            if done then return end
        elseif event == "char" then
            wHandleChar(p1)
        elseif event == "key" then
            wHandleKey(p1)
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  IN-HUD RECONFIGURE MENU
-- ══════════════════════════════════════════════════════════════

local function showReconfigMenu()
    mon.setBackgroundColor(C.bg)
    mon.clear()
    fillLine(1, " ", C.accent, C.header_bg)
    centre(1, " RECONFIGURE ", C.accent, C.header_bg)
    centre(4,  "What would you like to do?", C.white, C.bg)
    wButton(math.floor(W/2)-10, 6,  "RE-RUN FULL SETUP",  C.black, C.accent)
    wButton(math.floor(W/2)-8,  8,  "TOGGLE MODULES",     C.black, colors.blue)
    wButton(math.floor(W/2)-6,  10, "CANCEL",             C.black, colors.gray)

    while true do
        local event, _, x, y = os.pullEvent("monitor_touch")
        local mid = math.floor(W/2)
        if y == 6 then
            wData = { enabled={}, rotPairs={} }
            for _, m in ipairs(modules) do wData.enabled[m.id] = cfg.enabled[m.id] end
            wStep = 1
            runWizard()
            buildEnabledList()
            buildRotationSlots()
            initModules()
            activeTab = 1
            return
        elseif y == 8 then
            -- Quick toggle screen
            wData = { enabled={} }
            for _, m in ipairs(modules) do wData.enabled[m.id] = cfg.enabled[m.id] end
            wStep = 3
            wDraw()
            while true do
                local ev, _, cx, cy = os.pullEvent("monitor_touch")
                local done = wHandleClick(cx, cy)
                if done or (cy == H-1) then
                    -- Save just the enabled flags
                    for k,v in pairs(wData.enabled) do cfg.enabled[k] = v end
                    saveConfig()
                    buildEnabledList()
                    buildRotationSlots()
                    initModules()
                    activeTab = 1
                    return
                end
            end
        elseif y == 10 then
            return
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  MAIN BOOT
-- ══════════════════════════════════════════════════════════════

function core.boot()
    -- Find monitor
    mon = peripheral.find("monitor")
    if not mon then
        print("[HUD] No monitor found. Attach a monitor and reboot.")
        return
    end
    mon.setTextScale(TEXT_SCALE)
    W, H = mon.getSize()

    -- Load all module files
    loadModules()

    -- Check for saved config
    local saved = loadConfig()
    if saved then
        cfg = saved
    else
        -- First boot: run wizard
        runWizard()
    end

    -- Build runtime state from config
    buildEnabledList()
    buildRotationSlots()
    initModules()

    activeTab = 1
    redraw()
    rotTimer = os.startTimer(ROTATE_SECS)

    -- ── Main event loop ───────────────────────────────────────
    while running do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            -- Long press top-right corner = reconfigure
            if p2 >= W - 3 and p3 == 1 then
                showReconfigMenu()
                redraw()
                rotTimer = os.startTimer(ROTATE_SECS)
            else
                handleClick(p2, p3)
            end

        elseif event == "timer" and p1 == rotTimer then
            tickRotation()

        elseif event == "rednet_message" then
            -- Forward to any module that wants rednet
            for _, m in ipairs(enabledMods) do
                if m.onRednet then pcall(m.onRednet, p1, p2, p3) end
            end
            if activeTab == 1 then redraw() end

        elseif event == "peripheral" or event == "peripheral_detach" then
            -- Re-init modules so connection states update
            initModules()
            redraw()
        end
    end
end

return core
