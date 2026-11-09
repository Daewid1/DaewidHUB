do -- ==== lm_27_infinity.lua ====
-- LUMEN :: BOOT MARKS
--
-- Two shapes, one renderer. `Inf.new` is the morphing infinity; `Inf.newRing`
-- is the arc that replaced it on the loading screen. They share `update`'s
-- chord-laying step and the same small interface, so the loader swaps between
-- them on one line.
--
-- ---------------------------------------------------------------- infinity
-- A port of loading-ui.com's morphing-infinity, which is an SVG whose single
-- stroked path animates through circle -> infinity -> circle -> infinity over
-- five seconds.
--
-- Roblox draws no vector paths, so the curve is walked and rebuilt every frame
-- out of 64 rounded segments. That sounds worse than it is: at this size each
-- segment is about three pixels long under a six pixel stroke, so the round
-- caps overlap into one continuous line with no visible facets.
--
-- WHY THE TWO CIRCLES ARE NOT THE SAME CIRCLE. circleA starts at the top and
-- runs clockwise; circleB starts at the bottom and runs anticlockwise. They
-- draw an identical ring. Interpolating between them THROUGH the lemniscate is
-- what makes the loop read as one ribbon turning inside out, because no two
-- consecutive transitions are the same motion -- swap circleB for circleA and
-- the whole thing collapses into a circle that flexes and un-flexes on the
-- spot. That asymmetry is the entire idea and it costs nothing.
--
-- All three paths share a structure -- a start point and four cubic segments --
-- so morphing is interpolating 26 numbers and re-walking the curve, which is
-- exactly what the web version's path interpolation does underneath.

local L = getgenv().__DAEWID_BALL_LUMEN
local T = L.T
local mk = L.mk

local Inf = {}
L.Infinity = Inf

-- flat, in the source's own 24x24 box: x0 y0 then four (c1 c2 end) triples
local circleA = {
  12, 8,
  14.21, 8,     16, 9.79,   16, 12,
  16, 14.21,    14.21, 16,  12, 16,
  9.79, 16,     8, 14.21,   8, 12,
  8, 9.79,      9.79, 8,    12, 8,
}
local infinity = {
  12, 12,
  14, 8.5,      19, 8.5,    19, 12,
  19, 15.5,     14, 15.5,   12, 12,
  10, 8.5,      5, 8.5,     5, 12,
  5, 15.5,      10, 15.5,   12, 12,
}
local circleB = {
  12, 16,
  14.21, 16,    16, 14.21,  16, 12,
  16, 9.79,     14.21, 8,   12, 8,
  9.79, 8,      8, 9.79,    8, 12,
  8, 14.21,     9.79, 16,   12, 16,
}

local KEYS  = { circleA, infinity, circleB, infinity, circleA }
local TIMES = { 0, 0.25, 0.50, 0.75, 1.00 }
local CYCLE = 5.0            -- seconds, from the source
local SUB   = 16             -- samples per cubic; 4 cubics -> 64 segments
local N     = SUB * 4

-- The source eases each keyframe-to-keyframe leg with motion's "easeInOut",
-- which is cubic-bezier(0.42, 0, 0.58, 1). Its Y curve happens to be exactly
-- smoothstep, but its X curve is not linear, so feeding time straight into
-- smoothstep is wrong by up to 0.03 -- visible here as the shape lingering at
-- the circle and rushing the crossing. Solve X for the curve parameter first,
-- then read Y off it.
local function easeInOut(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local s = t
  for _ = 1, 4 do
    local x = ((0.52 * s - 0.78) * s + 1.26) * s - t
    local dx = (1.56 * s - 1.56) * s + 1.26
    if dx <= 1e-6 then break end
    s = s - x / dx
  end
  return (3 - 2 * s) * s * s
end

function Inf.new(parent, size, opts)
  opts = opts or {}
  local self = setmetatable({}, { __index = Inf })

  local px = size / 24                      -- the source box is 24 units wide
  local thick = math.max(2, math.floor(1.5 * px + 0.5))   -- strokeWidth 1.5
  self.size, self.px, self.thick = size, px, thick
  self.t, self.settle = 0, 0

  -- One CanvasGroup so the whole curve fades on a single property. There is no
  -- text inside it, so nothing pays the resampling cost that keeps the loading
  -- screen's wordmark out of one.
  local holder = mk("CanvasGroup", {
    AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5),
    Position = opts.Position or UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(size, size),
    BackgroundTransparency = 1,
    GroupTransparency = opts.transparency or 0,
    ZIndex = opts.ZIndex or 2,
    Name = "Infinity", Parent = parent,
  })
  self.holder = holder

  local colour = opts.colour or T.c.accent
  self.segs = table.create(N)
  for i = 1, N do
    local s = mk("Frame", {
      AnchorPoint = Vector2.new(0.5, 0.5),
      Size = UDim2.fromOffset(thick, thick),
      BackgroundColor3 = colour,
      BorderSizePixel = 0,
      Name = "S" .. i, Parent = holder,
    })
    L.corner(999, s)                        -- round caps, and so round joins
    self.segs[i] = s
  end

  -- scratch, reused every frame: this runs 60 times a second and allocating
  -- three tables per frame is how a loading screen ends up stuttering
  self._n = table.create(26)
  self._x = table.create(N)
  self._y = table.create(N)

  self:update(0)

  if opts.drive ~= false then
    self.conn = L.hold(L.RunService.RenderStepped:Connect(function(dt)
      if not (L.live() and holder.Parent) then return end
      self:update(self.t + dt)
    end))
  end
  return self
end


-- ---------------------------------------------------------------- ring
--
-- WHY THE INFINITY WAS REPLACED, having been the thing that replaced a bar.
--
-- Its whole argument was that a bar tells you a number the percentage already
-- says, and says it worse. That is true. But the infinity then says NOTHING --
-- it is equally busy at 4% and at 96%, so the screen has one element that
-- carries information and one that is purely decorative, and they sit in
-- separate places doing separate jobs.
--
-- This does both at once, and answers the bar objection on its own terms:
--
--   the TRACK is the whole ring, always there, so there is a shape to read
--   the ARC lights from twelve o'clock as progress arrives  -- the number
--   the COMET keeps orbiting regardless                     -- still alive
--
-- The bar's real failure is that 40% and 45% look identical because a bar has
-- no motion of its own to compare against. The comet supplies exactly that: it
-- laps a stationary arc, so the arc's edge is always being pointed at. And
-- unlike the infinity, at 96% it visibly nearly-closed.
--
-- The percentage goes in the middle of it, which is the other half of the
-- reason: three scattered elements (mark, status, percent) become one object
-- with a caption.
local TAIL = 15                 -- comet segments; ~85 degrees at N = 64
local SPIN = 1.45               -- seconds per lap

function Inf.newRing(parent, size, opts)
  opts = opts or {}
  local self = setmetatable({}, { __index = Inf })
  self.isRing = true
  self.size   = size
  self.thick  = opts.thick or math.max(3, math.floor(size * 0.055))
  self.t, self._last = 0, nil
  self.progress, self.progressTo = 0, 0
  self.settle, self.settleTo = 0, 0

  local holder = mk("CanvasGroup", {
    AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5),
    Position = opts.Position or UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(size, size),
    BackgroundTransparency = 1,
    GroupTransparency = opts.transparency or 0,
    ZIndex = opts.ZIndex or 2,
    Name = "Ring", Parent = parent,
  })
  self.holder = holder

  self.colour = opts.colour or T.c.accent
  self.segs = table.create(N)
  for i = 1, N do
    local seg = mk("Frame", {
      AnchorPoint = Vector2.new(0.5, 0.5),
      Size = UDim2.fromOffset(self.thick, self.thick),
      BackgroundColor3 = self.colour,
      BackgroundTransparency = 1,
      BorderSizePixel = 0,
      Name = "S" .. i, Parent = holder,
    })
    L.corner(999, seg)
    self.segs[i] = seg
  end

  -- LAID OUT ONCE. The infinity rebuilds its geometry every frame because its
  -- geometry actually changes; a circle's does not. Only transparency and
  -- colour move here, which is the difference between 64 CFrame-equivalent
  -- writes per frame and 64 float writes.
  local r = size * 0.5 - self.thick * 0.5 - 1
  local half = size / 2
  for i = 1, N do
    local a0 = ((i - 1) / N) * math.pi * 2 - math.pi / 2
    local a1 = (i / N) * math.pi * 2 - math.pi / 2
    local x0, y0 = half + math.cos(a0) * r, half + math.sin(a0) * r
    local x1, y1 = half + math.cos(a1) * r, half + math.sin(a1) * r
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    local seg = self.segs[i]
    seg.Position = UDim2.fromOffset(x0 + dx * 0.5, y0 + dy * 0.5)
    seg.Size = UDim2.fromOffset(len + self.thick, self.thick)
    seg.Rotation = math.deg(math.atan2(dy, dx))
  end

  self:update(0)
  if opts.drive ~= false then
    self.conn = L.hold(L.RunService.RenderStepped:Connect(function(dt)
      if not (L.live() and holder.Parent) then return end
      self:update(self.t + dt)
    end))
  end
  return self
end

-- 0..1. Eased toward rather than snapped, for the same reason the percentage is
-- sprung: a stage boundary is a step in the DATA, never in the picture.
function Inf:setProgress(a)
  self.progressTo = math.clamp(a or 0, 0, 1)
  return self
end

local TRACK_ALPHA = 0.88
local ARC_ALPHA   = 0.30

function Inf:updateRing(t)
  local dt = math.clamp(t - (self._last or t), 0, 0.25)
  self._last, self.t = t, t

  self.progress = self.progress
    + (self.progressTo - self.progress) * (1 - math.exp(-dt / 0.22))
  if self.settleTo ~= self.settle then
    self.settle = self.settle + (self.settleTo - self.settle) * (1 - math.exp(-dt / 0.10))
    if math.abs(self.settleTo - self.settle) < 0.002 then self.settle = self.settleTo end
  end

  -- resolving fills the ring and puts the comet away: the lap is a promise that
  -- something is still happening, and once it is not, the promise has to stop
  local p = self.progress + (1 - self.progress) * self.settle
  local litTo = p * N
  local head = (t / SPIN) % 1 * N
  local cometFade = 1 - self.settle

  for i = 1, N do
    -- partial credit on the leading segment, so the arc grows smoothly instead
    -- of in 1/64 steps -- at this size one step is a visible tick
    local fill = math.clamp(litTo - (i - 1), 0, 1)
    local alpha = TRACK_ALPHA + (ARC_ALPHA - TRACK_ALPHA) * fill

    if cometFade > 0.01 then
      -- distance BEHIND the head, wrapped: the comet is a tail, not a dot
      local d = (head - (i - 1)) % N
      if d < TAIL then
        local w = (1 - d / TAIL)
        w = w * w * cometFade
        alpha = math.min(alpha, TRACK_ALPHA + (0.02 - TRACK_ALPHA) * w)
      end
    end
    self.segs[i].BackgroundTransparency = alpha
  end
  return self
end

-- absolute time in, so a caller that already has a clock can hand us theirs and
-- the two can never drift apart
function Inf:update(t)
  if self.isRing then return self:updateRing(t) end
  local dt = math.clamp(t - (self._last or t), 0, 0.25)
  self._last, self.t = t, t
  local n = self._n

  -- exponential approach rather than a Motion track: Motion's tracks are built
  -- for Instances, and this is a plain table. tau 0.09 puts it at rest inside a
  -- quarter second, under the loader's own handover.
  if self.settleTo and self.settleTo ~= self.settle then
    self.settle = self.settle + (self.settleTo - self.settle) * (1 - math.exp(-dt / 0.09))
    if math.abs(self.settleTo - self.settle) < 0.001 then self.settle = self.settleTo end
  end

  local phase = (t / CYCLE) % 1
  local k = 1
  while k < #TIMES - 1 and phase >= TIMES[k + 1] do k = k + 1 end
  local span = TIMES[k + 1] - TIMES[k]
  local e = easeInOut(span > 0 and (phase - TIMES[k]) / span or 0)
  local a, b = KEYS[k], KEYS[k + 1]
  for i = 1, 26 do n[i] = a[i] + (b[i] - a[i]) * e end

  -- settling blends whatever we are toward the resting circle, so finishing
  -- does not wait for the five second cycle to come back around
  local s = self.settle
  if s > 0 then
    for i = 1, 26 do n[i] = n[i] + (circleA[i] - n[i]) * s end
  end

  -- walk the four cubics
  local px, half = self.px, self.size / 2
  local X, Y = self._x, self._y
  local p = 0
  for seg = 0, 3 do
    local o = seg * 6
    local x0, y0 = n[o + 1], n[o + 2]
    local x1, y1 = n[o + 3], n[o + 4]
    local x2, y2 = n[o + 5], n[o + 6]
    local x3, y3 = n[o + 7], n[o + 8]
    for j = 0, SUB - 1 do
      local u = j / SUB
      local m = 1 - u
      local w0 = m * m * m
      local w1 = 3 * m * m * u
      local w2 = 3 * m * u * u
      local w3 = u * u * u
      p = p + 1
      X[p] = (w0 * x0 + w1 * x1 + w2 * x2 + w3 * x3) * px
      Y[p] = (w0 * y0 + w1 * y1 + w2 * y2 + w3 * y3) * px
    end
  end

  -- lay a rounded bar along each chord. Length carries the full stroke width so
  -- consecutive caps overlap; without it the curve beads at every joint.
  local thick = self.thick
  local segs = self.segs
  for i = 1, N do
    local j = (i % N) + 1
    local ax, ay = X[i], Y[i]
    local dx, dy = X[j] - ax, Y[j] - ay
    local len = math.sqrt(dx * dx + dy * dy)
    local f = segs[i]
    if len < 0.05 then
      -- the lemniscate's own crossing point, where two samples coincide: a zero
      -- length chord has no direction, and atan2(0,0) would spin it randomly
      f.Visible = false
    else
      f.Visible = true
      f.Position = UDim2.fromOffset(ax + dx * 0.5, ay + dy * 0.5)
      f.Size = UDim2.fromOffset(len + thick, thick)
      f.Rotation = math.deg(math.atan2(dy, dx))
    end
  end
  return self
end

-- Bring it to rest on the circle NOW rather than letting it run out its cycle.
-- Loading finishing is the event; the animation has no business adding another
-- two and a half seconds to it.
function Inf:resolve()
  self.settleTo = 1
  return self
end

function Inf:setColour(c)
  self.colour = c
  for i = 1, N do self.segs[i].BackgroundColor3 = c end
  return self
end

function Inf:destroy()
  if self.conn then pcall(function() self.conn:Disconnect() end) end
  pcall(function() self.holder:Destroy() end)
end

end
