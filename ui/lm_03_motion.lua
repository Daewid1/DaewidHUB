do -- ==== lm_03_motion.lua ====
-- LUMEN :: MOTION
-- One RenderStepped loop drives every animation in the framework.
--
-- Motion.to never resets velocity, so retargeting mid-flight keeps the speed it
-- already had; a tween restarts from a dead stop. Settled springs are dropped
-- from the loop, so idle costs nothing.

local L = getgenv().__DAEWID_BALL_LUMEN
local T = L.T
local Spring = L.Spring

local Motion = {}
L.Motion = Motion

-- ---------------------------------------------------------------- colour space
--
-- Colour is sprung in linear space, not sRGB: gamma-encoded channels average to a
-- chalky, desaturated midpoint. Squaring in and square-rooting out is the cheap
-- gamma-2.0 approximation, two multiplies.
local function toLinear(v) return v * v end
local function toGamma(v) return math.sqrt(v < 0 and 0 or v) end

-- ---------------------------------------------------------------- kinds
--
-- Each animatable type is decomposed into scalars, sprung independently, and
-- reassembled. eps is (position, velocity) for the settle test.
local KINDS = {}

KINDS.number = {
  n = 1, eps = { 0.0015, 0.02 },
  dec = function(v, o) o[1] = v end,
  enc = function(o) return o[1] end,
}

KINDS.UDim2 = {
  n = 4, eps = { 0.002, 0.03 },
  dec = function(v, o)
    o[1], o[2], o[3], o[4] = v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset
  end,
  enc = function(o) return UDim2.new(o[1], o[2], o[3], o[4]) end,
}

KINDS.UDim = {
  n = 2, eps = { 0.002, 0.03 },
  dec = function(v, o) o[1], o[2] = v.Scale, v.Offset end,
  enc = function(o) return UDim.new(o[1], o[2]) end,
}

KINDS.Vector2 = {
  n = 2, eps = { 0.002, 0.03 },
  dec = function(v, o) o[1], o[2] = v.X, v.Y end,
  enc = function(o) return Vector2.new(o[1], o[2]) end,
}

KINDS.Color3 = {
  n = 3, eps = { 0.0008, 0.01 },
  dec = function(v, o)
    o[1], o[2], o[3] = toLinear(v.R), toLinear(v.G), toLinear(v.B)
  end,
  enc = function(o)
    return Color3.new(toGamma(o[1]), toGamma(o[2]), toGamma(o[3]))
  end,
}

local function kindOf(v)
  local t = typeof(v)
  return KINDS[t]
end

-- ---------------------------------------------------------------- track
local Track = {}
Track.__index = Track

local active, activeN = {}, 0
local byObject = setmetatable({}, { __mode = "k" })

local function wake(tr)
  if tr.awake or tr.dead then return end
  tr.awake = true
  activeN = activeN + 1
  active[activeN] = tr
  tr.slot = activeN
end

local function sleep(tr)
  if not tr.awake then return end
  tr.awake = false
  -- swap-remove: order is irrelevant and this keeps removal O(1)
  local last = active[activeN]
  active[tr.slot] = last
  if last then last.slot = tr.slot end
  active[activeN] = nil
  activeN = activeN - 1
  tr.slot = nil
  if tr.onSettle then L.try("motion.settle", tr.onSettle, tr) end
end

function Track:to(value)
  if self.dead then return self end
  local kd = self.kind
  kd.dec(value, self.tmp)
  for i = 1, kd.n do
    self.springs[i]:to(self.tmp[i])
  end
  self.goal = value
  wake(self)
  return self
end

function Track:snap(value)
  if self.dead then return self end
  local kd = self.kind
  kd.dec(value, self.tmp)
  for i = 1, kd.n do self.springs[i]:snap(self.tmp[i]) end
  self.goal = value
  self.last = nil
  self:write(value)
  sleep(self)
  return self
end

function Track:retune(token)
  self.token = token or self.token
  local d, b = Motion.resolve(token or self.token)
  for i = 1, self.kind.n do self.springs[i]:retune(d, b) end
  return self
end

function Track:impulse(v)
  for i = 1, self.kind.n do self.springs[i]:impulse(v) end
  wake(self)
  return self
end

function Track:write(value)
  if self.last == value then return end
  self.last = value
  L.uiWrite(self.obj,self.prop,value)
end

function Track:destroy()
  self.dead = true
  sleep(self)
  local m = byObject[self.obj]
  if m then m[self.prop] = nil end
end

-- ---------------------------------------------------------------- api

-- Accepts a token name ("base") or a raw { duration, bounce } pair. The profile
-- multipliers apply at resolve time, so one pair restyles every animation.
Motion.durScale, Motion.bounceScale = 1, 1

function Motion.resolve(token)
  local d, b
  if type(token) == "table" then d, b = token[1], token[2]
  else
    local m = T.m[token or "base"] or T.m.base
    d, b = m[1], m[2]
  end
  return d * Motion.durScale, math.clamp(b * Motion.bounceScale, -0.95, 0.95)
end

-- A Track builds its springs once, so a token change alone does nothing to what
-- is already on screen. Each track remembers its token so it can be retuned.
function Motion.reprofile()
  local n = 0
  for _, props in pairs(byObject) do
    for _, tr in pairs(props) do
      if not tr.dead and tr.token then
        tr:retune(tr.token)
        n = n + 1
      end
    end
  end
  return n
end

function Motion.track(obj, prop, token)
  local m = byObject[obj]
  if not m then m = {} byObject[obj] = m end
  local existing = m[prop]
  if existing and not existing.dead then
    if token then existing.token = token existing:retune(token) end
    return existing
  end

  local current = L.uiRead(obj,prop)
  local kd = kindOf(current)
  if not kd then
    L.fault("motion.kind", tostring(typeof(current)) .. " on " .. tostring(prop))
    return nil
  end

  local d, b = Motion.resolve(token)
  local tr = setmetatable({
    obj = obj, prop = prop, kind = kd, springs = {}, tmp = {},
    token = token or "base",
    goal = current, last = current, awake = false, dead = false,
  }, Track)

  kd.dec(current, tr.tmp)
  for i = 1, kd.n do tr.springs[i] = Spring.new(d, b, tr.tmp[i]) end
  m[prop] = tr
  return tr
end

-- Animate a property to a value, creating the track on first use.
function Motion.to(obj, prop, value, token)
  local tr = Motion.track(obj, prop, token)
  if tr then tr:to(value) end
  return tr
end

function Motion.set(obj, prop, value, token)
  local tr = Motion.track(obj, prop, token)
  if tr then tr:snap(value) end
  return tr
end

function Motion.stop(obj, prop)
  local m = byObject[obj]
  local tr = m and m[prop]
  if tr then tr:destroy() end
end

function Motion.stopAll(obj)
  local m = byObject[obj]
  if not m then return end
  for _, tr in pairs(m) do tr:destroy() end
  byObject[obj] = nil
end

-- ---------------------------------------------------------------- instrument
--
-- What the tokens do, measured through this exact spring code. `duration` is the
-- period parameter, not the settle time -- they are not the same number:
--
--     token         dur   bnc    t50ms  t90ms  t99ms  overshoot
--     instant      0.10  0.00       27     62    150      -0.0%
--     fast         0.18  0.20       44     86    249       1.5%
--     base         0.30  0.20       72    143    390       1.5%
--     slow         0.44  0.22      105    204    549       2.0%
--     expressive   0.42  0.38       92    161    510       8.4%
--     gentle       0.32 -0.20       99    264    568      -0.0%
--
-- Panels reach 90% of travel in 143 ms, a window entrance in 204 ms. Anything
-- that still feels instant is a property written directly instead of through
-- Motion, not a duration problem.

Motion.BUDGET = 0.002          -- 2 ms of main-thread work per frame

local perf = {
  cap = 240, i = 0, n = 0, ring = table.create(240, 0),
  frames = 0, over = 0, peak = 0, ema = 0,
}

local function record(elapsed)
  perf.frames = perf.frames + 1
  perf.i = perf.i % perf.cap + 1
  perf.ring[perf.i] = elapsed
  if perf.n < perf.cap then perf.n = perf.n + 1 end
  if elapsed > perf.peak then perf.peak = elapsed end
  if elapsed > Motion.BUDGET then perf.over = perf.over + 1 end
  -- EMA drives the degrade decision; a mean over all time reacts far too slowly.
  perf.ema = perf.ema + (elapsed - perf.ema) * 0.05
end

-- Percentiles are computed ON DEMAND, never per frame -- an instrument that
-- costs what it measures is not an instrument.
function Motion.perf()
  local n = perf.n
  if n == 0 then
    return { samples = 0, active = activeN }
  end
  local copy = table.create(n)
  for j = 1, n do copy[j] = perf.ring[j] end
  table.sort(copy)
  local sum = 0
  for j = 1, n do sum = sum + copy[j] end
  local function pct(q)
    local idx = math.clamp(math.ceil(q * n), 1, n)
    return copy[idx] * 1000
  end
  return {
    samples   = n,
    active    = activeN,
    avgMs     = (sum / n) * 1000,
    medianMs  = pct(0.50),
    p95Ms     = pct(0.95),
    worstMs   = copy[n] * 1000,
    peakMs    = perf.peak * 1000,
    budgetMs  = Motion.BUDGET * 1000,
    overPct   = perf.frames > 0 and (perf.over / perf.frames) * 100 or 0,
    frames    = perf.frames,
    quality   = Motion.quality,
  }
end

function Motion.resetPerf()
  perf.i, perf.n, perf.frames, perf.over, perf.peak, perf.ema = 0, 0, 0, 0, 0, 0
  return true
end

-- Measure a token's real response in-client, so the table above can be checked
-- on the machine that is actually complaining rather than trusted.
function Motion.measure(token, dt)
  local d, b = Motion.resolve(token)
  local s = Spring.new(d, b, 0)
  s:to(1)
  dt = dt or 1 / 1000
  local t, t50, t90, t99, peak = 0, nil, nil, nil, 0
  for _ = 1, math.floor(4 / dt) do
    s:step(dt) t = t + dt
    if s.value > peak then peak = s.value end
    if not t50 and s.value >= 0.50 then t50 = t end
    if not t90 and s.value >= 0.90 then t90 = t end
    if not t99 and math.abs(s.value - 1) <= 0.01 and math.abs(s.velocity) < 0.05 then
      t99 = t
    end
  end
  return { token = token, duration = d, bounce = b,
           t50ms = (t50 or 0) * 1000, t90ms = (t90 or 0) * 1000,
           t99ms = (t99 or 0) * 1000, overshootPct = (peak - 1) * 100 }
end

-- ---------------------------------------------------------------- degrade
--
-- Degrading means doing LESS WORK, never moving slower. Stretching durations
-- under load is the exact trick that makes an interface feel worse while
-- looking like it is trying to feel better -- the frames are still late, they
-- are just late for longer.
--
-- Hysteresis is not optional here: a single threshold flips quality on and off
-- every few frames right at the boundary, and a hub that keeps changing its own
-- animation style is worse than one that is simply slow.
Motion.quality = 1        -- 1 full, 0 minimal
Motion.autoDegrade = true

local degradeHold, recoverHold = 0, 0

local function judge()
  if not Motion.autoDegrade then return end
  if perf.ema > Motion.BUDGET then
    degradeHold, recoverHold = degradeHold + 1, 0
    if degradeHold > 60 and Motion.quality > 0 then
      Motion.quality = math.max(0, Motion.quality - 0.5)
      degradeHold = 0
      L.note("motion", string.format(
        "quality -> %.1f (ema %.2f ms over %.2f ms budget)",
        Motion.quality, perf.ema * 1000, Motion.BUDGET * 1000))
    end
  elseif perf.ema < Motion.BUDGET * 0.6 then
    recoverHold, degradeHold = recoverHold + 1, 0
    if recoverHold > 180 and Motion.quality < 1 then
      Motion.quality = math.min(1, Motion.quality + 0.5)
      recoverHold = 0
      L.note("motion", string.format("quality -> %.1f (recovered)", Motion.quality))
    end
  end
end

-- Features consult this before spending frames on something decorative. Weight
-- is how ornamental the animation is: 0 is structural and always runs, 1 is
-- pure decoration and is the first thing dropped.
function Motion.shouldAnimate(weight)
  return Motion.quality >= (weight or 0)
end

function Motion.stats()
  return { active = activeN, gen = L._gen, quality = Motion.quality }
end

-- ---------------------------------------------------------------- loop
local lastT = os.clock()

function Motion.step(dt)
  local i = 1
  while i <= activeN do
    local tr = active[i]
    if not tr or tr.dead then
      i = i + 1
    else
      local obj = tr.obj
      -- Drop tracks whose instance has left the tree. Checked only AFTER the
      -- object has been parented once, because a track is legitimately created
      -- during construction while Parent is still nil.
      if obj.Parent then tr.parented = true end
      if tr.parented and not obj.Parent then
        tr.dead = true
        sleep(tr)
      else
        local kd, sp, tmp = tr.kind, tr.springs, tr.tmp
        local settled = true
        local epsP, epsV = kd.eps[1], kd.eps[2]
        for j = 1, kd.n do
          local s = sp[j]
          s:step(dt)
          tmp[j] = s.value
          if settled and not s:settled(epsP, epsV) then settled = false end
        end
        if settled then
          for j = 1, kd.n do
            sp[j]:finish()
            tmp[j] = sp[j].value
          end
        end
        tr:write(kd.enc(tmp))
        if settled then sleep(tr) else i = i + 1 end
      end
    end
  end
end

function Motion.start()
  if Motion._on then return end
  Motion._on = true
  lastT = os.clock()
  -- RenderStepped so writes land before the frame is drawn; anything on
  -- Heartbeat is a frame late and shows up as UI lagging one frame behind the
  -- cursor during a drag.
  L.hold(L.RunService.RenderStepped:Connect(function(dt)
    if not L.live() then return end
    -- Two os.clock() calls a frame is far below the noise floor of what is being
    -- measured, and without them every claim about smoothness in this project is
    -- somebody's opinion.
    local t0 = os.clock()
    Motion.step(dt)
    record(os.clock() - t0)
    judge()
  end))
end

-- ---------------------------------------------------------------- curves
--
-- Springs cover almost everything, but not quite everything: an indeterminate
-- shimmer or a sweep that must land on an exact frame wants a real curve. These
-- are the Material 3 easing tokens, sampled properly.
--   https://m3.material.io/styles/motion/easing-and-duration/tokens-specs

local function bezierAxis(t, a, b)
  local mt = 1 - t
  return 3 * mt * mt * t * a + 3 * mt * t * t * b + t * t * t
end

-- cubic-bezier(x1,y1,x2,y2) evaluated at x. Newton-Raphson to invert x(t), with
-- a bisection fallback for the flat regions where the derivative vanishes and
-- Newton would otherwise wander off.
function L.bezier(name, x)
  local e = T.ease[name] or T.ease.standard
  local x1, y1, x2, y2 = e[1], e[2], e[3], e[4]
  x = math.clamp(x, 0, 1)
  if x == 0 or x == 1 then return x end

  local t = x
  for _ = 1, 6 do
    local cx = bezierAxis(t, x1, x2) - x
    if math.abs(cx) < 1e-5 then break end
    local mt = 1 - t
    local d = 3 * mt * mt * x1 + 6 * mt * t * (x2 - x1) + 3 * t * t * (1 - x2)
    if math.abs(d) < 1e-6 then
      local lo, hi = 0, 1
      for _ = 1, 20 do
        t = (lo + hi) * 0.5
        if bezierAxis(t, x1, x2) < x then lo = t else hi = t end
      end
      break
    end
    t = t - cx / d
  end
  return bezierAxis(math.clamp(t, 0, 1), y1, y2)
end

-- ---------------------------------------------------------------- helpers

-- Delay for item i of n in a cascade. Capped so a fifty-item list does not take
-- two seconds to finish revealing -- past about ten items the eye reads it as a
-- wave regardless, and the tail just feels slow.
function Motion.stagger(i, step)
  return math.min((i - 1) * (step or T.stagger), 0.34)
end

-- THE STAGGER PRIMITIVE.
--
-- `Motion.stagger` above only computes a delay; every caller then had to wire
-- its own task.delay, which is why almost nothing in the hub actually cascades
-- and why lists arrive all at once. Arriving all at once is most of what reads
-- as "basic" -- the eye gets no order to follow, so a list of twelve rows lands
-- as one flat event instead of a wave.
--
-- Cancellable, because a cascade that is still firing into a panel the user has
-- already closed will animate a dead tree and, worse, pop things back into view
-- after the close finished.
function Motion.seq(items, fn, opts)
  opts = opts or {}
  local step = opts.step or T.stagger or 0.03
  local cap  = opts.cap  or 0.34

  -- Under load the cascade COLLAPSES rather than slowing: the same work happens,
  -- it just stops being spread across frames. Spreading is what costs -- it is
  -- what keeps many tracks alive at once.
  if Motion.quality < 1 then step = step * Motion.quality end

  local h = { cancelled = false, pending = 0 }
  function h:cancel() self.cancelled = true return self end

  for i, item in ipairs(items) do
    local d = math.min((i - 1) * step, cap)
    if d <= 0 then
      if L.live() then L.try("motion.seq", fn, item, i) end
    else
      h.pending = h.pending + 1
      task.delay(d, function()
        h.pending = h.pending - 1
        if h.cancelled or not L.live() then return end
        L.try("motion.seq", fn, item, i)
      end)
    end
  end
  return h
end

-- The common case: animate one property across a list, in order.
function Motion.cascade(objs, prop, value, token, opts)
  return Motion.seq(objs, function(o)
    if o and o.Parent then Motion.to(o, prop, value, token) end
  end, opts)
end

function Motion.after(delay, fn)
  task.delay(delay, function()
    if L.live() then L.try("motion.after", fn) end
  end)
end

Motion.start()

end
