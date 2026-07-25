-- ============================================================
--  AIRSHIP HUD  |  startup.lua
--  Entry point: runs on every boot.
--  Finds the monitor, loads config or launches setup wizard.
-- ============================================================

-- Ensure our hud directory is on the path
package.path = package.path .. ";/hud/?.lua"

local core = require("hud.core")
core.boot()
