-- Standalone add-on: direct, nonblocking telemetry. No BeamNG.Earth files are replaced.
local M = {}
local CONFIG = '/settings/beamngEarthPhoneGps.json'
local cfg = { enabled = false, port = 47624, hz = 20, configVersion = 2 }
local loaded, socket, udp, session, seq, timer = false, nil, nil, '', 0, 0
local retryAt, lastError, sent, clock = 0, nil, 0, 0
local prefix, serial = '', 0
local perfLast, perfMax, perfTotal, perfSamples = 0, 0, 0, 0

local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end
local function validHost(host)
  if type(host) ~= 'string' then return false end
  local a,b,c,d = host:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
  if not a then return false end
  for _, v in ipairs({a,b,c,d}) do if tonumber(v) > 255 then return false end end
  return tonumber(a) > 0 and tonumber(a) < 224 and host ~= '255.255.255.255'
end
local function validConfig(c)
  return type(c) == 'table' and validHost(c.host) and type(c.key) == 'string'
    and #c.key >= 8 and #c.key <= 64 and not c.key:find('[^%w%-_]')
    and finite(c.port) and c.port >= 1024 and c.port <= 65535 and c.port % 1 == 0
    and finite(c.hz) and c.hz >= 1 and c.hz <= 100
end

function M.close()
  if udp then pcall(udp.close, udp) end
  udp = nil
end

local function load()
  if loaded then return end
  loaded = true
  if jsonReadFile then
    local ok, saved = pcall(jsonReadFile, CONFIG)
    if ok and validConfig(saved) then
      cfg = saved; cfg.enabled = saved.enabled == true
      -- Reduce work for the legacy default; explicit new rates remain supported.
      if not cfg.configVersion and cfg.hz == 50 then cfg.hz = 20 end
      cfg.configVersion = 2
    end
  end
end

function M.configure(host, key, port, hz)
  load()
  local c = { enabled = true, host = host, key = key, port = port or 47624, hz = hz or 20, configVersion = 2 }
  if not validConfig(c) then return false, 'Use phone IPv4, key 8-64 letters/digits, port 1024-65535, Hz 1-100' end
  M.close()
  cfg, timer, retryAt = c, 1, 0
  if jsonWriteFile then pcall(jsonWriteFile, CONFIG, cfg, true) end
  M.prepare()
  return true
end

function M.disable()
  load()
  cfg.enabled = false
  M.close()
  if jsonWriteFile then pcall(jsonWriteFile, CONFIG, cfg, true) end
end

-- Rotate vectors into the ENU tangent frame AT THE CAR, not only at the world's anchor.
-- This is essential at high latitudes and survives arbitrary floating-origin rotations.
function M.tangentVector(anchor, lat, lon, x, y, z)
  local vx = anchor.ex*x + anchor.nx*y + anchor.ux*z
  local vy = anchor.ey*x + anchor.ny*y + anchor.uy*z
  local vz = anchor.ez*x + anchor.nz*y + anchor.uz*z
  local sl, cl = math.sin(math.rad(lat)), math.cos(math.rad(lat))
  local so, co = math.sin(math.rad(lon)), math.cos(math.rad(lon))
  return -so*vx + co*vy, -sl*co*vx - sl*so*vy + cl*vz
end

function M.bearing(e, n) return (math.deg(math.atan2(e, n)) + 360) % 360 end

function M.sample(anchor, veh, paused)
  local p, v, d = veh:getPosition(), veh:getVelocity(), veh:getDirectionVector()
  local lat, lon, alt = anchor:enuToGeodetic(p.x, p.y, p.z)
  -- Build the tangent projection once for both vectors instead of repeating trig/ECEF work.
  local sl, cl = math.sin(math.rad(lat)), math.cos(math.rad(lat))
  local so, co = math.sin(math.rad(lon)), math.cos(math.rad(lon))
  local ex = -so*anchor.ex + co*anchor.ey
  local ey = -so*anchor.nx + co*anchor.ny
  local ez = -so*anchor.ux + co*anchor.uy
  local nx = -sl*co*anchor.ex - sl*so*anchor.ey + cl*anchor.ez
  local ny = -sl*co*anchor.nx - sl*so*anchor.ny + cl*anchor.nz
  local nz = -sl*co*anchor.ux - sl*so*anchor.uy + cl*anchor.uz
  local ve, vn = ex*v.x + ey*v.y + ez*v.z, nx*v.x + ny*v.y + nz*v.z
  local de, dn = ex*d.x + ey*d.y + ez*d.z, nx*d.x + ny*d.y + nz*d.z
  local heading = M.bearing(de, dn)
  local moving = ve*ve + vn*vn > 0.09 and not paused
  local speed = paused and 0 or math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
  local bearing = moving and M.bearing(ve, vn) or heading
  if not (finite(lat) and finite(lon) and finite(alt) and finite(speed) and finite(bearing) and finite(heading)) then return nil end
  return { lat = lat, lon = lon, alt = alt, speed = speed, bearing = bearing,
    heading = heading, paused = paused == true, valid = true }
end

local function connect()
  socket = socket or require('socket')
  local err
  udp, err = socket.udp()
  if not udp then error(err) end
  udp:settimeout(0)
  local ok
  ok, err = udp:setpeername(cfg.host, cfg.port)
  if not ok then error(err) end
  serial = serial + 1
  session, seq = string.format('%.6f-%d', socket.gettime(), serial), 0
  -- Key is validated ASCII and session is generated numeric text: no general JSON serializer is needed.
  prefix = string.format('{"v":1,"key":"%s","session":"%s",', cfg.key, session)
end

function M.prepare()
  load()
  if not cfg.enabled then return end
  local ok, err = pcall(function() if not udp then connect() end end)
  if not ok then lastError = tostring(err); M.close(); retryAt = clock + 2 end
end

-- Called before the extension even looks up Earth state, including when disabled/high FPS.
function M.due(dtReal)
  if not loaded then M.prepare() end -- compatibility with explicit API calls outside the normal extension lifecycle
  if not cfg.enabled then return false end
  clock = clock + math.max(0, dtReal or 0)
  timer = timer + math.max(0, dtReal or 0)
  if clock < retryAt or timer < 1 / cfg.hz then return false end
  timer = timer % (1 / cfg.hz)
  return true
end

function M.encode(msg, seqNo, sentMs)
  if not msg.valid then
    return prefix .. string.format('"seq":%.0f,"sent_ms":%.3f,"valid":false}', seqNo, sentMs)
  end
  return prefix .. string.format('"seq":%.0f,"sent_ms":%.3f,"valid":true,"paused":%s,"lat":%.9f,"lon":%.9f,"alt":%.3f,"speed":%.4f,"bearing":%.4f,"heading":%.4f}',
    seqNo, sentMs, msg.paused and 'true' or 'false', msg.lat, msg.lon, msg.alt, msg.speed, msg.bearing, msg.heading)
end

local function sendCurrent(dtReal, dtSim, state)
  if not udp then connect() end
  local msg
  local pending = state.pending and state.pending.purpose
  local usable = (state.inOurLevel or state.active) and state.anchor and not state.rebasing and not state.lagProbe
    and not state.placeFrames and pending ~= 'teleport' and pending ~= 'start'
  local veh = usable and getPlayerVehicle(0)
  if veh then msg = M.sample(state.anchor, veh, (dtSim or dtReal or 0) <= 0) end
  msg = msg or { valid = false }
  seq = seq + 1
  local count, sendErr = udp:send(M.encode(msg, seq, socket.gettime() * 1000))
  if not count and sendErr ~= 'timeout' then error(sendErr) end
  if count then sent = sent + 1 end
end

function M.update(dtReal, dtSim, state, alreadyDue)
  if not alreadyDue and not M.due(dtReal) then return end
  local started = socket and socket.gettime()
  local ok, err = pcall(sendCurrent, dtReal, dtSim, state)
  if started then
    perfLast = math.max(0, (socket.gettime() - started) * 1000)
    perfMax, perfTotal, perfSamples = math.max(perfMax, perfLast), perfTotal + perfLast, perfSamples + 1
  end
  if not ok then
    lastError = tostring(err)
    if log then log('W', 'beamngEarthPhoneGps', lastError) end
    M.close()
    retryAt = clock + 2
  else
    lastError = nil
  end
end

function M.status()
  load()
  return { enabled = cfg.enabled, host = cfg.host, port = cfg.port, hz = cfg.hz, sent = sent, error = lastError,
    lastMs = perfLast, maxMs = perfMax, meanMs = perfSamples > 0 and perfTotal / perfSamples or 0 }
end

return M
