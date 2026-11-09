do -- ==== lm_02_spring.lua ====
-- LUMEN :: SPRING
-- A damped spring solved in closed form, so it is exact at any frame rate and
-- cannot blow up when a frame hitches. Euler integration does both.
--
-- Parameterised by DURATION and BOUNCE (Apple's scheme) rather than stiffness
-- and damping, because duration and bounce are independent and the raw
-- constants are not -- changing stiffness alone changes both.
--
-- Spring.selftest() checks the maths; verify_spring.py runs it head-less.

local L = getgenv().__DAEWID_BALL_LUMEN
local Spring = {}
Spring.__index = Spring
L.Spring = Spring

local TAU = math.pi * 2

-- exp(-x), guarded. x is always >= 0 here by construction, but a NaN dt or a
-- pathological tuning would otherwise poison every later frame silently.
local function negexp(x)
  if x ~= x then return 0 end     -- NaN
  if x <= 0 then return 1 end
  if x > 40 then return 0 end     -- underflows to zero anyway, skip the call
  return math.exp(-x)
end

-- Apple's duration/bounce -> stiffness/damping, mass = 1.
function Spring.params(duration, bounce)
  duration = math.max(tonumber(duration) or 0.3, 1e-3)
  bounce   = math.clamp(tonumber(bounce) or 0, -0.95, 0.95)
  local k = (TAU / duration) ^ 2
  local c
  if bounce >= 0 then
    c = (1 - bounce) * 2 * TAU / duration
  else
    c = 2 * TAU / (duration * (1 + bounce))
  end
  return k, c
end

function Spring.new(duration, bounce, initial)
  local self = setmetatable({}, Spring)
  self.k, self.c = Spring.params(duration, bounce)
  self.duration, self.bounce = duration or 0.3, bounce or 0
  self.value    = initial or 0
  self.target   = initial or 0
  self.velocity = 0
  return self
end

function Spring:retune(duration, bounce)
  self.k, self.c = Spring.params(duration, bounce)
  self.duration, self.bounce = duration, bounce
  return self
end

-- Retarget. VELOCITY IS DELIBERATELY UNTOUCHED -- that is the whole point.
function Spring:to(target)
  self.target = target
  return self
end

-- Teleport: value, target and velocity all reset. For initial state only; using
-- this where `to` belongs is what makes an interface feel like it is snapping.
function Spring:snap(value)
  self.value, self.target, self.velocity = value, value, 0
  return self
end

function Spring:impulse(v)
  self.velocity = self.velocity + v
  return self
end

-- Exact step of  y'' + c*y' + k*y = 0  where y = value - target.
function Spring:step(dt)
  if not dt or dt ~= dt or dt <= 0 then return self.value end
  if dt > 0.25 then dt = 0.25 end     -- a long hitch should not teleport the UI

  local g  = self.target
  local y0 = self.value - g
  local v0 = self.velocity
  local k, c = self.k, self.c

  -- already there and not moving: skip the transcendentals entirely
  if y0 == 0 and v0 == 0 then return self.value end

  local disc = c * c - 4 * k
  local x, v

  if disc < -1e-9 then
    -- UNDERDAMPED: decaying oscillation. This is every bounce > 0 token.
    local zeta = c * 0.5
    local wd   = math.sqrt(4 * k - c * c) * 0.5
    local e    = negexp(zeta * dt)
    local c1   = y0
    local c2   = (v0 + zeta * y0) / wd
    local cs, sn = math.cos(wd * dt), math.sin(wd * dt)
    x = e * (c1 * cs + c2 * sn)
    v = e * ((-zeta * c1 + wd * c2) * cs + (-zeta * c2 - wd * c1) * sn)

  elseif disc <= 1e-9 then
    -- CRITICALLY DAMPED: the bounce = 0 case, fastest arrival without overshoot.
    local zeta = c * 0.5
    local e    = negexp(zeta * dt)
    local a    = y0
    local b    = v0 + zeta * y0
    local pos  = a + b * dt
    x = e * pos
    v = e * (b - zeta * pos)

  else
    -- OVERDAMPED: two real roots, both negative. Every bounce < 0 token.
    local sq = math.sqrt(disc)
    local r1 = (-c + sq) * 0.5
    local r2 = (-c - sq) * 0.5
    local c2 = (r1 * y0 - v0) / (r1 - r2)
    local c1 = y0 - c2
    local e1, e2 = negexp(-r1 * dt), negexp(-r2 * dt)
    x = c1 * e1 + c2 * e2
    v = c1 * r1 * e1 + c2 * r2 * e2
  end

  self.value    = x + g
  self.velocity = v
  return self.value
end

-- Settling is judged on BOTH offset and velocity. Position alone is not enough:
-- a spring passing through its target at speed is momentarily at zero offset,
-- and a position-only test would park it there mid-flight.
function Spring:settled(epsP, epsV)
  return math.abs(self.value - self.target) <= (epsP or 1e-3)
     and math.abs(self.velocity)            <= (epsV or 1e-2)
end

function Spring:finish()
  self.value, self.velocity = self.target, 0
  return self.value
end

-- ---------------------------------------------------------------- self test
--
-- Runnable head-less under luau.exe with no Roblox API, so the maths can be
-- verified without a game client. Checks the three regimes behave as their names
-- claim, that stepping is genuinely frame-rate independent, and -- the one that
-- matters -- that retargeting carries velocity.
function Spring.selftest()
  local out, fail = {}, 0
  local function check(name, cond, detail)
    if cond then out[#out + 1] = "ok    " .. name .. (detail and ("  " .. detail) or "")
    else out[#out + 1] = "FAIL  " .. name .. "  " .. tostring(detail) fail = fail + 1 end
  end

  local function run(dur, bounce, steps, dt, target)
    local s = Spring.new(dur, bounce, 0)
    s:to(target or 1)
    local peak = 0
    for _ = 1, steps do
      s:step(dt)
      if s.value > peak then peak = s.value end
    end
    return s, peak
  end

  -- bounce 0 is critically damped: must never exceed its target
  local _, peak0 = run(0.3, 0, 400, 1 / 240)
  check("bounce 0 does not overshoot", peak0 <= 1.0005, string.format("peak=%.5f", peak0))

  -- positive bounce must overshoot
  local _, peakB = run(0.3, 0.4, 400, 1 / 240)
  check("bounce 0.4 overshoots", peakB > 1.02, string.format("peak=%.4f", peakB))

  -- negative bounce must not, and must be slower to arrive than critical
  local sN, peakN = run(0.3, -0.5, 400, 1 / 240)
  check("bounce -0.5 does not overshoot", peakN <= 1.0005, string.format("peak=%.5f", peakN))

  -- all regimes must actually converge
  local sC = run(0.3, 0, 600, 1 / 240)
  check("critical converges", sC:settled(1e-3, 1e-2), string.format("v=%.5f", sC.velocity))
  check("overdamped converges", sN:settled(1e-2, 1e-1), string.format("d=%.5f", 1 - sN.value))

  -- FRAME-RATE INDEPENDENCE: 240 fps and 30 fps must agree closely over the
  -- same elapsed time. Euler integration fails this badly.
  local a = Spring.new(0.3, 0.2, 0); a:to(1)
  for _ = 1, 240 do a:step(1 / 240) end
  local b = Spring.new(0.3, 0.2, 0); b:to(1)
  for _ = 1, 30 do b:step(1 / 30) end
  check("240fps matches 30fps", math.abs(a.value - b.value) < 0.01,
        string.format("%.5f vs %.5f", a.value, b.value))

  -- STABILITY: an absurd dt must not produce NaN or an explosion
  local s = Spring.new(0.05, 0.5, 0); s:to(1)
  for _ = 1, 20 do s:step(10) end
  check("huge dt stays finite", s.value == s.value and math.abs(s.value) < 10,
        string.format("v=%.4f", s.value))

  -- VELOCITY PRESERVATION: retarget mid-flight and the spring must still be
  -- moving. This is the property the whole framework is built on.
  local r = Spring.new(0.4, 0, 0)
  r:to(1)
  for _ = 1, 12 do r:step(1 / 240) end
  local vBefore = r.velocity
  r:to(0.5)                                   -- retarget while in motion
  check("retarget preserves velocity", math.abs(r.velocity - vBefore) < 1e-12,
        string.format("%.5f -> %.5f", vBefore, r.velocity))
  check("velocity was non-zero", vBefore > 0.05, string.format("%.5f", vBefore))

  -- and snap must NOT preserve it
  r:snap(0)
  check("snap clears velocity", r.velocity == 0)

  return table.concat(out, "\n"), fail
end

end
