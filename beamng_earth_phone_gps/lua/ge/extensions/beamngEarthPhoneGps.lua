-- Optional companion for BeamNG.Earth 1.6.0-beta. Reads the existing _state() accessor only.
-- No monkey patches, hooks replaced, copied Earth code or writes to Earth state.
local M = {}
local telemetry = require('beamngEarthPhoneGps/telemetry')
local compatible = false

local function earthState()
  local core = rawget(_G, 'beamngEarth_core')
    or (extensions and extensions.beamngEarth_core)
  compatible = core ~= nil and type(core._state) == 'function'
  if not compatible then return {} end
  local ok, state = pcall(core._state)
  if not ok or type(state) ~= 'table' then compatible = false; return {} end
  return state -- read-only; coordinate conversion uses this anchor's existing methods
end

-- After physics: requested vehicle relocations must be visible before exporting the new frame.
-- telemetry also suppresses fixes during rebasing, lagProbe and teleport placement.
function M.onPreRender(dtReal, dtSim)
  if not telemetry.due(dtReal) then return end
  telemetry.update(dtReal, dtSim, earthState(), true)
end

function M.configure(host, key, port, hz) return telemetry.configure(host, key, port, hz) end
function M.stop() telemetry.disable() end
function M.status()
  local result = telemetry.status()
  earthState()
  result.earthCompatible = compatible
  result.addonVersion = '1.1.0'
  return result
end
function M.onClientEndMission() telemetry.update(1, 0, {}) end
function M.onExtensionUnloaded() telemetry.close() end
function M.onExtensionLoaded()
  telemetry.prepare() -- settings/socket initialization happens outside the per-frame render hook
  log('I', 'beamngEarthPhoneGps', 'Standalone Android GPS add-on loaded. Configure with beamngEarthPhoneGps.configure(IP, key).')
end

return M
