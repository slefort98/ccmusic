-- ============================================================
--  hud_probe.lua
--  Writes full peripheral info to probe_results.txt
--  then lets you read it page by page on screen.
--
--  Usage: hud_probe        (scans all connected peripherals)
--         hud_probe left   (probe just one side)
-- ============================================================

local target = ...
local OUT = "probe_results.txt"

-- Write to file AND print a short status to screen
local f = fs.open(OUT, "w")
if not f then
    print("ERROR: Could not open " .. OUT .. " for writing.")
    return
end

local function w(line)
    f.writeLine(line or "")
end

local function probePeriph(name)
    local ptype = peripheral.getType(name)
    if not ptype then return end

    w("")
    w("=================================")
    w("NAME : " .. name)
    w("TYPE : " .. ptype)
    w("=================================")

    local p = peripheral.wrap(name)
    if not p then
        w("  (could not wrap)")
        return
    end

    local methods = peripheral.getMethods(name)
    if not methods or #methods == 0 then
        w("  (no methods exposed)")
        return
    end

    w("METHODS:")
    for _, method in ipairs(methods) do
        local ok, result = pcall(function() return p[method]() end)
        local resultStr
        if ok then
            if type(result) == "table" then
                resultStr = textutils.serialise(result):sub(1, 80)
            elseif result == nil then
                resultStr = "(nil / no return value)"
            else
                resultStr = tostring(result):sub(1, 80)
            end
        else
            resultStr = "(needs args, or errored)"
        end
        w(string.format("  %-30s => %s", method .. "()", resultStr))
    end
end

w("HUD PERIPHERAL PROBE")
w("====================")
w("")

local names = target and { target } or peripheral.getNames()

if #names == 0 then
    w("No peripherals found.")
    w("")
    w("Check that:")
    w("  - Wired modems are right-clicked (turned green)")
    w("  - Cable connects the peripheral to this computer")
    w("  - Wireless modem is attached if using wireless perifs")
else
    for _, name in ipairs(names) do
        probePeriph(name)
    end
end

w("")
w("=================================")
w("Probe complete.")
w("Copy the TYPE string into your")
w("module's peripheral.find() call.")
w("=================================")

f.close()

-- Now display the file page by page using the built-in more viewer
print("Probe written to " .. OUT)
print("Opening file viewer... (press Space or Enter to scroll)")
print("")
sleep(1)
shell.run("more", OUT)
