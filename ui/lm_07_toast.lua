do -- ==== lm_07_toast.lua ====
-- LUMEN :: TOAST
-- Notifications, bottom-right, four visible at once and the rest queued.
-- Repeats of the same message collapse into a count rather than stacking, and
-- the stack springs into gaps instead of relaying out.
-- The card is a CanvasGroup so its whole subtree fades as one image; fading
-- label by label reads as several things appearing separately.

local L = getgenv().__DAEWID_BALL_LUMEN
local T, M, A = L.T, L.Motion, L.A
local mk = L.mk

local Toast = {}
L.Toast = Toast

local W, GAP, MARGIN = 364, 10, 20
local RISE  = 22      -- how far below its resting place a toast starts
local SMALL = 0.90    -- and how far under full size
-- read live, so changing it in Interface takes effect on the next toast
local function MAX_VISIBLE()
  return math.floor((L.Cfg and tonumber(L.Cfg.data.toastMax)) or 4)
end

local live, queue = {}, {}
local notificationSide = "Right"
local departing = 0

-- ---------------------------------------------------------------- easing
-- A curve, not a spring: duration 0.4s, cubic-bezier(0.25, 0.46, 0.45, 0.94).
-- TweenService has no arbitrary bezier, so the curve is solved directly (Newton
-- on X for the parameter, then read Y) and driven per frame.
local EASE = { 0.25, 0.46, 0.45, 0.94 }

local function bezier(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local x1, y1, x2, y2 = EASE[1], EASE[2], EASE[3], EASE[4]
  local u = t
  for _ = 1, 5 do
    local mu = 1 - u
    local x = 3 * mu * mu * u * x1 + 3 * mu * u * u * x2 + u * u * u
    local dx = 3 * mu * mu * x1 + 6 * mu * u * (x2 - x1) + 3 * u * u * (1 - x2)
    if math.abs(dx) < 1e-6 then break end
    u = u - (x - t) / dx
  end
  local mu = 1 - u
  return 3 * mu * mu * u * y1 + 3 * mu * u * u * y2 + u * u * u
end

-- One driver per (object, property). Re-targeting mid-flight restarts from where
-- it is, so a toast still sliding when the stack shifts does not jump.
-- Keyed on the instance, not tostring(it): tostring(Instance) returns its Name
-- and every wrapper is called "Toast", so string keys collapse onto one entry.
local drives = setmetatable({}, { __mode = "k" })
local function easeTo(obj, prop, target, dur, onDone)
  if not obj then return end
  local perObj = drives[obj]
  if not perObj then perObj = {} drives[obj] = perObj end
  local d = perObj[prop]
  if d then d.dead = true end
  local from = L.uiRead(obj,prop)
  local t0 = os.clock()
  dur = dur or 0.4
  local rec = { dead = false }
  perObj[prop] = rec
  task.spawn(function()
    while not rec.dead do
      if not obj.Parent then
        if perObj[prop] == rec then perObj[prop] = nil end
        return
      end
      local a = math.clamp((os.clock() - t0) / dur, 0, 1)
      local e = bezier(a)
      if typeof(from) == "UDim2" then
        obj[prop] = UDim2.new(
          from.X.Scale + (target.X.Scale - from.X.Scale) * e,
          from.X.Offset + (target.X.Offset - from.X.Offset) * e,
          from.Y.Scale + (target.Y.Scale - from.Y.Scale) * e,
          from.Y.Offset + (target.Y.Offset - from.Y.Offset) * e)
      else
        L.uiWrite(obj,prop,from + (target - from) * e)
      end
      if a >= 1 then
        -- only clear our OWN row: a newer drive may already own this slot
        if perObj[prop] == rec then perObj[prop] = nil end
        if onDone then L.try("toast.done", onDone) end
        return
      end
      L.RunService.Heartbeat:Wait()
    end
  end)
end


local KIND = {
  info = { colour = T.c.accent, icon = "dot" },
  ok   = { colour = T.c.ok,     icon = "check" },
  warn = { colour = T.c.warn,   icon = "bars" },
  bad  = { colour = T.c.bad,    icon = "close" },
}

local function ensureHost()
  if Toast.gui and Toast.gui.Parent then return Toast.host end
  local gui = mk("ScreenGui", {
    Name = "GiorgioNotices", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 20,
  })
  gui.Parent = L.host()
  L.own(gui)
  mk("UIScale", { Scale = L.autoScale(), Parent = gui })
  local screen = gui
  gui = mk("Frame", { Name = "Notices", BackgroundTransparency = 1,
    Size = UDim2.new(0, W + MARGIN * 2, 1, 0),
    AnchorPoint = Vector2.new(notificationSide == "Left" and 0 or 1, 0),
    Position = UDim2.fromScale(notificationSide == "Left" and 0 or 1, 0), Parent = screen })
  Toast.host = gui

  -- The column fades at its top edge so a tall stack dissolves upward instead of
  -- reading as a wall.
  local fade = mk("Frame", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(W + MARGIN * 2, 420),
    BackgroundTransparency = 1, ZIndex = 0, Name = "FadeHost", Parent = gui,
  })
  Toast.fadeHost = fade
  Toast.gui = screen
  return gui
end

-- ---------------------------------------------------------------- overflow pill

local morePill, moreLbl
local function updateMore()
  local n = #queue
  if n == 0 then
    if morePill then A.groupTo(morePill, 1, "fast") end
    return
  end
  if not morePill then
    local gui = ensureHost()
    morePill = mk("CanvasGroup", {
      AnchorPoint = Vector2.new(1, 1),
      Position = UDim2.new(1, -MARGIN, 1, -MARGIN),
      Size = UDim2.fromOffset(112, 22),
      BackgroundColor3 = T.c.overlay, BackgroundTransparency = 0.05,
      GroupTransparency = 1,
      BorderSizePixel = 0, Parent = gui,
    })
    L.corner(999, morePill)
    L.stroke(T.c.lineStrong, 1, 0.35, morePill)
    moreLbl = A.text({
      Text = "", font = T.font.mono, size = T.size.tiny, colour = T.c.textDim,
      align = Enum.TextXAlignment.Center, Parent = morePill,
    })
  end
  moreLbl.Text = string.format("+%d waiting", n)
  A.groupTo(morePill, 0, "fast")
end

-- Recompute every visible toast's resting Y from the bottom up and spring it.
local function restack()
  local y = -MARGIN - (#queue > 0 and 28 or 0)
  for i = #live, 1, -1 do
    local t = live[i]
    if t.wrap.Parent then
      t.restY = y
      easeTo(t.wrap, "Position", UDim2.new(1, -MARGIN, 1, y), 0.4)
      y = y - (t.height + GAP)
    end
  end
  updateMore()
end

local spawnOne   -- forward declaration: dismiss promotes from the queue

-- Fade, shrink and sink: the entrance played backwards.
local function dismiss(entry)
  if not entry.alive then return end
  entry.alive = false
  for i, e in ipairs(live) do
    if e == entry then table.remove(live, i) break end
  end
  departing = departing + 1

  -- Every part of the exit shares OUT, or the card keeps settling after it has
  -- left.
  local OUT = 0.26
  local finished = false
  local function finishDeparture()
    if finished then return end
    finished = true
    departing = math.max(0, departing - 1)
    pcall(function() entry.wrap:Destroy() end)
    -- A queued card takes the slot only once the departing one is fully gone.
    if #queue > 0 and (#live + departing) < MAX_VISIBLE() then
      local nextOpts = table.remove(queue, 1)
      spawnOne(nextOpts)
    else
      updateMore()
    end
  end
  entry.wrap.Destroying:Connect(finishDeparture)
  easeTo(entry.wrap, "GroupTransparency", 1, OUT, finishDeparture)
  easeTo(entry.scale, "Scale", SMALL, OUT)
  easeTo(entry.wrap, "Position",
    UDim2.new(1, -MARGIN + W * 0.5, 1, entry.restY or -MARGIN), OUT)

  restack()
end

function spawnOne(opts)
  local kind = KIND[opts.kind or "info"] or KIND.info
  local gui = ensureHost()
  local hasBody = opts.body and opts.body ~= ""
  local height = hasBody and 108 or 76
  local elev = T.elev[2]

  -- The wrapper carries position and scale only. Everything visible is a child
  -- of it, so one UIScale pulls the card, its halo and its shadow together --
  -- scaling the card alone would leave the shadow the wrong size mid-flight.
  local wrap = mk("CanvasGroup", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -MARGIN, 1, -MARGIN + RISE),
    Size = UDim2.fromOffset(W, height),
    BackgroundTransparency = 1, GroupTransparency = 1, BorderSizePixel = 0,
    Name = "Toast", Parent = gui,
  })
  local scale = mk("UIScale", { Scale = SMALL, Parent = wrap })

  -- THE DEFOCUS GHOST IS GONE, and it is worth saying why because the idea was
  -- sound and the result was not.
  --
  -- The entrance used to crossfade a soft silhouette of the card into the sharp
  -- card, imitating something pulling into focus. The silhouette was the 9-slice
  -- shadow sprite tinted with the card's own fill -- which on a dark theme is a
  -- DARK RECTANGLE, larger than the card, drawn at 0.06 transparency on the
  -- first frame while the card itself was still fully invisible.
  --
  -- So every notification opened with a dark box appearing on its own, holding
  -- for a beat, and then dissolving as the card arrived. Read as an artifact,
  -- because it is one: nothing in the interface has a reason to be a dark
  -- rectangle. The concept only works if the blob is genuinely a blurred copy of
  -- the card, and Roblox has no GUI blur, so there was never a version of this
  -- that was going to land.
  --
  -- What replaces it: the card fades and rises on one clock, and its shadow is
  -- on the SAME clock so the pair arrives as one object. No stand-in, nothing
  -- that exists only during the transition.
  local drop = A.shadow(nil, {
    Parent = wrap, spread = 24, alpha = 0.42, lift = 8, ZIndex = 0,
  })

  -- A small, PERMANENT colour bloom behind the icon well -- not a flash that
  -- fades out. The old one animated from visible to invisible during the
  -- entrance, which is another thing appearing and then leaving for no reason
  -- the viewer can name.
  local bloom = A.glow(wrap, 78, kind.colour, {
    alpha = 0.72, ZIndex = 2,
    Position = UDim2.new(0, 22, 0.5, 0),
  })

  local card = mk("CanvasGroup", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(W, height),
    BackgroundColor3 = elev.fill, BackgroundTransparency = 0,
    BorderSizePixel = 0, GroupTransparency = 0,
    ZIndex = 4, Name = "Card", Parent = wrap,
  })
  L.corner(T.r.md, card)
  L.stroke(elev.line, 1, elev.lineT, card)
  mk("Frame", {
    Size = UDim2.new(1, -T.r.md * 2, 0, 1), Position = UDim2.new(0, T.r.md, 0, 0),
    BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.92,
    BorderSizePixel = 0, ZIndex = 2, Parent = card,
  })

  -- ---- the card's face ---------------------------------------------------
  --
  -- The first version was a coloured bar, a glyph and two lines of text, which
  -- is the shape every hub ships and reads as a debug print with rounded
  -- corners. What was missing was HIERARCHY: nothing told the eye where to land
  -- first, so it landed everywhere.
  --
  -- Now the status colour is carried by a filled disc that the glyph sits
  -- inside, which gives the card one clear anchor point on the left; the title
  -- is heavier and the body is dimmer, so the two lines separate at a glance;
  -- and the accent runs as a soft vertical wash off the left edge rather than a
  -- hard three-pixel rule, so the colour is present without being a stripe.
  local edge = mk("Frame", {
    Size = UDim2.new(0, 64, 1, 0), BackgroundColor3 = kind.colour,
    BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = 1, Parent = card,
  })
  mk("UIGradient", {
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0.00, 0.10),
      NumberSequenceKeypoint.new(1.00, 1.00),
    }),
    Parent = edge,
  })

  -- the icon well: a filled disc in the status colour, glyph knocked out of it
  local well = mk("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(26, 26),
    BackgroundColor3 = kind.colour, BackgroundTransparency = 0.18,
    BorderSizePixel = 0, ZIndex = 3, Parent = card,
  })
  L.corner(999, well)
  L.stroke(kind.colour, 1, 0.45, well)

  local glyph = (A.Icon[kind.icon] or A.Icon.dot)(well, 13, T.c.accentInk)
  glyph.AnchorPoint = Vector2.new(0.5, 0.5)
  glyph.Position = UDim2.fromScale(0.5, 0.5)
  glyph.ZIndex = 4

  -- ---- the two lines ------------------------------------------------------
  -- Title heavier, body dimmer and a size smaller: the separation is what lets
  -- the pair be read as one message with a headline rather than two sentences.
  local titleLbl = A.text({
    Text = opts.title or "Notice",
    font = T.font.strong, size = T.size.label, colour = T.c.text,
    Position = UDim2.fromOffset(50, hasBody and 12 or 0),
    Size = hasBody and UDim2.new(1, -96, 0, 15) or UDim2.new(1, -96, 1, 0),
    truncate = true, ZIndex = 3, Parent = card,
  })
  if hasBody then
    A.text({
      Text = opts.body, font = T.font.body, size = T.size.micro,
      colour = T.c.textMute, valign = Enum.TextYAlignment.Top,
      Position = UDim2.fromOffset(50, 29), Size = UDim2.new(1, -62, 0, 24),
      wrap = true, ZIndex = 3, Parent = card,
    })
  end

  -- repeat counter, hidden until it is needed
  local countLbl = A.text({
    Text = "", font = T.font.mono, size = T.size.tiny, colour = kind.colour,
    align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, hasBody and 12 or 0),
    Size = hasBody and UDim2.fromOffset(40, 15) or UDim2.new(0, 40, 1, 0),
    ZIndex = 4, Parent = card,
  })

  -- INSET AND ROUNDED, not a full-width rule welded to the bottom edge. A bar
  -- that runs corner to corner fights the card's own radius and reads as a
  -- progress bar for the card rather than a clock on the message.
  local timerTrack = mk("Frame", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 12, 1, -7), Size = UDim2.new(1, -24, 0, 2),
    BackgroundColor3 = T.c.line, BackgroundTransparency = 0.55,
    BorderSizePixel = 0, ZIndex = 3, Parent = card,
  })
  L.corner(999, timerTrack)
  local timer = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = kind.colour,
    BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 4,
    Parent = timerTrack,
  })
  L.corner(999, timer)

  if L.Giorgio and L.Giorgio.styleToast then
    L.Giorgio.styleToast({card=card,wrap=wrap,title=titleLbl,count=countLbl,
      well=well,glyph=glyph,edge=edge,bloom=bloom,timer=timer,track=timerTrack},opts)
  end
  local entryHovered = false
  local entry = {
    wrap = wrap, card = card, scale = scale, bloom = bloom,
    drop = drop, height = height, alive = true, count = 1,
    key = (opts.title or "") .. "|" .. (opts.body or ""),
    countLbl = countLbl, title = titleLbl,
    life = opts.duration or (L.Cfg and tonumber(L.Cfg.data.toastDur)) or 4.5, born = os.clock(),
    onAction = opts.onAction,
  }
  live[#live + 1] = entry
  -- AN ACTIONABLE TOAST. A card click has always dismissed; if the caller
  -- supplies onAction it now RUNS first and dismisses after, so a notice can
  -- offer the one obvious response to itself instead of only reporting.
  -- Used by the restored-settings notice, which needs a one-click undo to be
  -- honest about re-arming features.
  A.interactive(card, { radius = T.r.md, onClick = function()
    if type(entry.onAction) == "function" then
      L.try("toast.action", entry.onAction)
    end
    dismiss(entry)
  end })

  -- ---- entrance ----------------------------------------------------------
  --
  -- Slide in from the right on the list's own curve, while the stack above
  -- shifts up on the SAME curve and duration -- so the arrival and the
  -- rearrangement read as one motion instead of two things happening near each
  -- other. Scale and the defocus blob ride along, which is what stops it
  -- looking like a rectangle being translated.
  -- ONE CLOCK FOR EVERY PART OF IT.
  --
  -- These used to run on 0.4 / 0.4 / 0.4 / 0.45 / 0.34, which is five things
  -- finishing at four different moments. Individually each is defensible;
  -- together they read as a card that keeps settling after it has arrived, and
  -- the shadow in particular finished last, so it looked like it was catching
  -- up with the card it belongs to.
  --
  -- Everything that is part of "the toast appearing" now shares IN, so the
  -- whole thing lands as a single object.
  local IN = 0.40
  wrap.Position = UDim2.new(1, -MARGIN + W * 0.55, 1, -MARGIN)
  restack()
  easeTo(scale, "Scale", 1, IN)
  easeTo(wrap, "GroupTransparency", 0, IN)

  -- ---- hover: lift, and hold the clock ------------------------------------
  -- Reading a notification should not be a race. Hovering pauses the timer and
  -- lifts the card slightly, which is also the affordance that says it can be
  -- interacted with at all.
  local hit = card:FindFirstChild("Hit")
  if hit then
    hit.MouseEnter:Connect(function()
      entryHovered = true
      easeTo(scale, "Scale", 1.03, 0.18)
    end)
    hit.MouseLeave:Connect(function()
      entryHovered = false
      easeTo(scale, "Scale", 1, 0.18)
    end)
  end

  -- The timer bar is the one place a linear curve is correct: it is a literal
  -- readout of remaining time, so easing it would misreport the clock.
  task.spawn(function()
    local held = 0
    while L.live() and entry.alive do
      -- paused while hovered: the clock stops rather than the bar freezing at a
      -- lie, so releasing resumes from where it actually was
      if entryHovered then
        held = held + L.RunService.Heartbeat:Wait()
      else
        L.RunService.Heartbeat:Wait()
      end
      local a = 1 - math.clamp((os.clock() - entry.born - held) / entry.life, 0, 1)
      timer.Size = UDim2.new(a, 0, 1, 0)
      -- dims as it empties, so a nearly-spent toast recedes
      timer.BackgroundTransparency = 0.15 + (1 - a) * 0.45
      if a <= 0 then break end
    end
    if entry.alive then dismiss(entry) end
  end)

  return entry
end

-- ---------------------------------------------------------------- api

function Toast.push(opts)
  opts = opts or {}
  local key = (opts.title or "") .. "|" .. (opts.body or "")

  -- collapse a repeat of the most recent message rather than stacking it
  local newest = live[#live]
  if newest and newest.alive and newest.key == key then
    newest.count = newest.count + 1
    newest.countLbl.Text = "x" .. newest.count
    newest.born = os.clock()             -- restart its clock
    -- a nudge of the same focus pull, so a repeat reads as the SAME card being
    -- struck again rather than as a new one that failed to appear
    M.set(newest.scale, "Scale", 0.965)
    M.to(newest.scale, "Scale", 1, "fast")
    return { dismiss = function() dismiss(newest) end, frame = newest.card }
  end

  if (#live + departing) >= MAX_VISIBLE() then
    queue[#queue + 1] = opts
    -- never let the backlog itself become a leak
    if #queue > 40 then table.remove(queue, 1) end
    updateMore()
    return { queued = true }
  end

  local e = spawnOne(opts)
  return { dismiss = function() dismiss(e) end, frame = e.card }
end

function Toast.clear()
  -- EMPTY THE QUEUE FIRST. dismiss() promotes the next queued toast into the
  -- freed slot, so clearing while the queue still had items refilled the stack
  -- as fast as it was emptied -- a burst of 14 "cleared" straight back into 4
  -- live toasts, and the next push then failed to collapse against them because
  -- it was comparing itself to a resurrected message.
  queue = {}
  for i = #live, 1, -1 do dismiss(live[i]) end
  updateMore()
end

function Toast.setSide(side)
  notificationSide = side
  if Toast.host then
    Toast.host.AnchorPoint = Vector2.new(side == "Left" and 0 or 1, 0)
    Toast.host.Position = UDim2.fromScale(side == "Left" and 0 or 1, 0)
  end
end
function Toast.stats() return { visible = #live, departing = departing, queued = #queue } end

function Toast.info(title, body) return Toast.push({ title = title, body = body, kind = "info" }) end
function Toast.ok(title, body)   return Toast.push({ title = title, body = body, kind = "ok" }) end
function Toast.warn(title, body) return Toast.push({ title = title, body = body, kind = "warn" }) end
function Toast.bad(title, body)  return Toast.push({ title = title, body = body, kind = "bad" }) end

end
