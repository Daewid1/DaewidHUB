do -- ==== lm_00_core.lua ====
-- LUMEN :: CORE
-- Shared table, instance helpers, and the diagnostics everything else reports to.
--
-- Failures are split three ways because the right response differs: `user` (bad
-- input, say it and move on), `refused` (the environment said no -- the feature
-- is genuinely off, so the control must stop claiming otherwise), `fault` (our
-- bug, the only kind that lights the health indicator red).

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local TweenService= game:GetService("TweenService")
local UIS         = game:GetService("UserInputService")
local Workspace   = game:GetService("Workspace")
local Http        = game:GetService("HttpService")
local GuiService  = game:GetService("GuiService")

local LP = Players.LocalPlayer

-- Generation guard. Re-running the script retires the previous instance rather
-- than leaving two copies fighting over the same ScreenGui and both stepping
-- their own render loops.
local GEN = (getgenv().__DAEWID_BALL_LUMEN_GEN or 0) + 1
getgenv().__DAEWID_BALL_LUMEN_GEN = GEN

local L = {}
L._gen = GEN
L.NAME = "LUMEN"
L.VERSION = "1.0.0"

function L.live() return getgenv().__DAEWID_BALL_LUMEN_GEN == GEN end
local live = L.live

L.Players, L.RunService, L.Tween, L.UIS, L.Workspace, L.Http, L.LP =
  Players, RunService, TweenService, UIS, Workspace, Http, LP

-- ---------------------------------------------------------------- diagnostics
L.KIND = { user = "user", refused = "refused", fault = "fault",
           note = "note", ok = "ok" }

L.faults, L._faultOrder = {}, {}

-- ---- activity log ----------------------------------------------------------
--
-- A ring buffer of what the hub actually did, so a claim can be checked instead
-- of believed. Capped, because the thing being logged is often a loop.
L.logs, L.LOG_CAP, L._logSeq = {}, 240, 0

function L.log(kind, src, text)
  local logs = L.logs
  text = tostring(text or "")
  src = tostring(src or "?")
  local last = logs[#logs]
  if last and last.kind == kind and last.src == src and last.text == text then
    last.n, last.t = last.n + 1, os.clock()
    return last
  end
  L._logSeq = L._logSeq + 1
  logs[#logs + 1] = {
    kind = kind, src = src, text = text, seq = L._logSeq,
    t = os.clock(), at = os.date("%H:%M:%S"), n = 1,
  }
  if #logs > L.LOG_CAP then table.remove(logs, 1) end
  return logs[#logs]
end

function L.note(src, text) return L.log("note", src, text) end

function L.fault(label, msg)
  local f = L.faults[label]
  if not f then
    f = { n = 0, first = os.clock() }
    L.faults[label] = f
    L._faultOrder[#L._faultOrder + 1] = label
  end
  f.n = f.n + 1
  f.msg = msg and tostring(msg) or f.msg
  f.last = os.clock()
  L.log("fault", label, msg)
end

-- The one sanctioned place a failure is swallowed, and it is still counted.
-- Two results are carried back, not one, so a callback can answer `false, why`
-- and the caller gets the reason rather than just the refusal.
function L.try(label, fn, ...)
  local ok, a, b = pcall(fn, ...)
  if not ok then L.fault(label, a) end
  return ok, a, b
end

-- ---- contested features ----------------------------------------------------
--
-- Something the user asked for, still wants, and which is demonstrably not in
-- effect -- almost always the game setting a property back. This is the state
-- every hub has and none of them show: the switch says on, the world says off,
-- and the user is left to work out which is lying.
L.contested = {}

function L.contest(key, why)
  local was = L.contested[key]
  L.contested[key] = { why = why, since = (was and was.since) or os.clock() }
  if not was then L.log("refused", key, why) end       -- log the edge, not the state
  return false
end

function L.uncontest(key)
  if L.contested[key] then
    L.contested[key] = nil
    L.log("ok", key, "holding again")
  end
end

-- "fault" beats "contested" beats "ok" -- worst thing that is true.
function L.health()
  local nc = 0
  for _ in pairs(L.contested) do nc = nc + 1 end
  local nf = #L._faultOrder
  return (nf > 0 and "fault") or (nc > 0 and "contested") or "ok", nf, nc
end

function L.faultList()
  local out = {}
  for _, k in ipairs(L._faultOrder) do
    out[#out + 1] = string.format("%s x%d %s", k, L.faults[k].n, L.faults[k].msg or "")
  end
  return out
end

-- ---------------------------------------------------------------- lifecycle
L._conns, L._insts, L._binds, L._cleanups = {}, {}, {}, {}
L._cleanupOrder = 0

function L.hold(c)
  -- A deferred callback can wake after teardown. Never let a retired
  -- generation repopulate the lists teardown already emptied.
  if not live() then
    pcall(function() c:Disconnect() end)
    return c
  end
  L._conns[#L._conns + 1] = c
  return c
end

function L.own(i)
  if not live() then
    -- Anything handed to `own` is newly created by LUMEN. If its generation is
    -- already retired, hiding and destroying it now is the only leak-free
    -- ownership contract.
    pcall(function() i.Enabled = false end)
    pcall(function() i.Visible = false end)
    pcall(function() i:Destroy() end)
    return i
  end
  L._insts[#L._insts + 1] = i
  return i
end

function L.cleanup(fn, priority)
  if type(fn) == "function" then
    if not live() then
      -- Stateful features commonly register their undo immediately after
      -- applying a snapshot. If teardown won the race, run that undo now.
      pcall(fn)
      return fn
    end
    L._cleanupOrder = L._cleanupOrder + 1
    L._cleanups[#L._cleanups + 1] = {
      fn = fn, priority = tonumber(priority) or 0, order = L._cleanupOrder,
    }
  end
  return fn
end

-- THE HELD LISTS ARE APPEND-ONLY, AND THAT IS A SLOW LEAK.
--
-- L.hold exists so teardown can disconnect everything, and L.own so it can reap
-- everything. Neither ever REMOVED anything, so a feature that connects on
-- enable and disconnects on disable leaves a dead entry behind every cycle --
-- and the panel, the ESP and the toasts all do exactly that. Measured over five
-- open/close cycles: twenty-seven already-disconnected connections still being
-- carried, growing about ten per cycle.
--
-- Nothing here changes behaviour; it only stops the bookkeeping from growing
-- without bound in a session left running for hours, which is the whole point
-- of a hub you leave on.
function L.prune()
  local conns, n = L._conns, 0
  local kept = {}
  for i = 1, #conns do
    local c = conns[i]
    local ok, alive = pcall(function() return c.Connected end)
    -- keep anything we cannot ask: some connection objects have no Connected
    if (not ok) or alive ~= false then
      kept[#kept + 1] = c
    else
      n = n + 1
    end
  end
  L._conns = kept

  local insts, m = L._insts, 0
  local keptI = {}
  for i = 1, #insts do
    local inst = insts[i]
    local ok, parent = pcall(function() return inst.Parent end)
    if ok and parent ~= nil then keptI[#keptI + 1] = inst else m = m + 1 end
  end
  L._insts = keptI
  return n, m
end

-- Cheap and infrequent: this is housekeeping, not a hot path.
task.spawn(function()
  while L.live() do
    task.wait(20)
    if not L.live() then break end
    pcall(L.prune)
  end
end)

function L.bind(name, pri, fn)
  if not live() then return end
  RunService:BindToRenderStep(name, pri, fn)
  L._binds[#L._binds + 1] = name
end

-- CONNECTIONS DIE NOW, INSTANCES TRAIL.
--
-- Re-running the script tears down the previous generation, and that generation
-- owns four ScreenGuis holding 5792 descendants between them. Destroying that
-- inline blocks the frame for ~300 ms, which is the freeze you get the instant
-- you execute -- before the new loading screen has drawn anything at all.
--
-- What actually has to happen immediately is stopping its loops and hiding it;
-- both are effectively free. The instances can be reaped over the next few
-- frames, behind the new loading screen, in batches small enough to fit inside
-- one frame each.
function L.teardown()
  -- Stateful features (fling, fly, physics overrides) need synchronous undo;
  -- destroying their instances later is too late to restore world/player state.
  local cleanups = L._cleanups
  L._cleanups = {}
  -- Higher-level transactions unwind before the feature state they borrowed.
  -- Equal-priority finalizers retain the historical reverse-registration order.
  table.sort(cleanups, function(a, b)
    if a.priority == b.priority then return a.order > b.order end
    return a.priority > b.priority
  end)
  for i = 1, #cleanups do pcall(cleanups[i].fn) end
  for _, c in ipairs(L._conns) do pcall(function() c:Disconnect() end) end
  for _, n in ipairs(L._binds) do pcall(function() RunService:UnbindFromRenderStep(n) end) end
  local insts = L._insts
  L._conns, L._insts, L._binds = {}, {}, {}

  -- gone from the screen this frame, whatever the reaper is doing
  for _, i in ipairs(insts) do
    pcall(function() i.Enabled = false end)
    pcall(function() i.Visible = false end)
  end

  task.spawn(function()
    for _, root in ipairs(insts) do
      if typeof(root) == "Instance" then
        local kids = {}
        pcall(function() kids = root:GetDescendants() end)
        -- deepest first: destroying a leaf cannot orphan the ones after it
        for k = #kids, 1, -1 do
          pcall(function() kids[k]:Destroy() end)
          if k % 250 == 0 then RunService.Heartbeat:Wait() end
        end
        pcall(function() root:Destroy() end)
        RunService.Heartbeat:Wait()
      end
    end
  end)
end

-- ---------------------------------------------------------------- instances

-- Declarative constructor. The array part of the table is children, so a whole
-- subtree reads as one expression instead of twenty lines of assignment.
--
-- PARENT IS ASSIGNED LAST, ALWAYS. Parenting first makes every subsequent
-- property write a change to an object already in the render tree, which costs
-- a re-layout per property on anything with a UIListLayout under it.
-- ---- repaint registry ------------------------------------------------------
--
-- Changing the accent used to rebuild the entire window, because the colour is
-- read once at construction and baked into every stroke, fill and gradient.
--
-- Registering each one by hand would mean touching a hundred call sites and
-- would rot the first time somebody added a hundred and first. Instead this
-- hooks the ONE place every instance in the framework is built: any property set
-- to a value that IS a palette colour is remembered along with which token it
-- came from, so a palette change can walk the list and repaint in place.
L.paints = {}

function L.repaint(token)
  local n = 0
  local keep = {}
  for _, e in ipairs(L.paints) do
    local obj, prop, name = e[1], e[2], e[3]
    if obj.Parent then
      keep[#keep + 1] = e
      if (not token or name == token) and L.T and L.T.c[name] then
        n = n + 1
        if L.Motion then L.Motion.to(obj, prop, L.T.c[name], "base")
        else obj[prop] = L.T.c[name] end
      end
    end
  end
  L.paints = keep          -- prune anything a rebuild already discarded
  return n
end

function L.uiRead(object,property)
  local native=L.Giorgio and L.Giorgio.Native
  if native then return native.get(object,property) end
  return object[property]
end
function L.uiWrite(object,property,value)
  local native=L.Giorgio and L.Giorgio.Native
  if native then native.set(object,property,value) else object[property]=value end
end
function L.mk(class, props)
  local native=L.Giorgio and L.Giorgio.Native
  local nativeGroup=native and class=="CanvasGroup"
  local inst = Instance.new(nativeGroup and "Frame" or class)
  local parent
  if props then
    local tokenOf = L.T and L.T.tokenOf
    for k, v in pairs(props) do
      if type(k) == "number" then
        v.Parent = inst
      elseif k == "Parent" then
        parent = v
      elseif nativeGroup and k=="GroupTransparency" then -- handled as logical opacity
      else
        inst[k] = v
        if tokenOf and typeof(v) == "Color3" then
          local name = tokenOf(v)
          if name then L.paints[#L.paints + 1] = { inst, k, name } end
        end
      end
    end
  end
  if parent then inst.Parent = parent end
  if native then native.register(inst,nativeGroup and (props and props.GroupTransparency or 0) or nil) end
  return inst
end

local mk = L.mk

-- Every rounded edge in the framework goes through here, so one multiplier
-- takes the whole interface from square to fully rounded. 999 is the "pill"
-- sentinel and is left alone -- scaling it would just un-round circles.
function L.corner(r, parent)
  local k = (L.Cfg and tonumber(L.Cfg.data.radius)) or 1
  if r < 900 then r = math.floor(r * k + 0.5) end
  return mk("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

-- THE RESTING VALUE IS RECORDED AT BIRTH, and that is not fussiness.
--
-- Every mechanism that fades a stroke has to know what to fade it back TO, and
-- the only moment that value is reliably readable is before anything has
-- animated it. Read later -- from inside a fade, from a teardown, from a
-- restore -- it returns whatever the animation happens to be passing through,
-- and "invisible" gets recorded as the resting state. A.fadeSet already learned
-- this the hard way; putting the answer on the instance means nothing else has
-- to.
function L.stroke(colour, thickness, transparency, parent)
  local st = mk("UIStroke", {
    Color = colour, Thickness = thickness or 1, Transparency = transparency or 0,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,   -- NEVER Contextual: on a
    Parent = parent,                                 -- TextLabel that strokes the
  })                                                 -- glyphs, not the border
  pcall(function() st:SetAttribute("__rest", st.Transparency) end)
  return st
end

-- The resting transparency of any stroke, whatever has happened to it since.
function L.strokeRest(st)
  if not st then return 1 end
  local v = st:GetAttribute("__rest")
  if type(v) ~= "number" then
    v = st.Transparency
    pcall(function() st:SetAttribute("__rest", v) end)
  end
  return v
end

function L.pad(t, r, b, l, parent)
  return mk("UIPadding", {
    PaddingTop = UDim.new(0, t or 0), PaddingRight = UDim.new(0, r or t or 0),
    PaddingBottom = UDim.new(0, b or t or 0), PaddingLeft = UDim.new(0, l or r or t or 0),
    Parent = parent,
  })
end

function L.list(gap, dir, parent, extra)
  local o = mk("UIListLayout", {
    Padding = UDim.new(0, gap or 0),
    FillDirection = dir or Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = parent,
  })
  if extra then for k, v in pairs(extra) do o[k] = v end end
  return o
end

-- ---------------------------------------------------------------- host

-- gethui() hides the GUI from scripts that walk CoreGui, and survives some
-- anti-cheat sweeps that clear PlayerGui. CoreGui is the fallback, PlayerGui the
-- last resort so we never silently render nowhere.
function L.host()
  local hui = rawget(getgenv(), "gethui")
  if type(hui) == "function" then
    local ok, h = pcall(hui)
    if ok and h then return h end
  end
  local ok, cg = pcall(function() return game:GetService("CoreGui") end)
  if ok and cg then return cg end
  return LP:FindFirstChildOfClass("PlayerGui")
end

function L.viewport()
  local cam = Workspace.CurrentCamera
  return (cam and cam.ViewportSize) or Vector2.new(1920, 1080)
end

-- Every offset in this framework is authored against a 1080p reference height.
-- A hub does not get smaller on a 1440p monitor -- the screen gets bigger around
-- it -- so one UIScale on the root keeps physical size roughly constant instead
-- of leaving 11 px labels unreadable on the displays people actually own.
function L.autoScale()
  local vy = L.viewport().Y
  return math.clamp(math.floor((vy / 1080) * 100 + 0.5) / 100, 0.8, 1.75)
end

-- ---------------------------------------------------------------- pointer
--
-- THE ONE PLACE THE CURSOR CROSSES BETWEEN COORDINATE SPACES.
--
-- Roblox has two of them, and mixing them is what put both the FOV ring and the
-- hover glow a fixed distance below the pointer:
--
--   INSET-INCLUDED   origin at the true top-left of the screen, above the
--                    topbar. `UserInputService:GetMouseLocation()` reports in
--                    this space, and so does a local offset inside a ScreenGui
--                    with IgnoreGuiInset = true.
--   INSET-EXCLUDED   origin below the topbar. `AbsolutePosition` reports here,
--                    and so does `Mouse.X/Y` and a child of a normal ScreenGui.
--
-- MEASURED ON A LIVE CLIENT, NOT ASSUMED. Three separate comments in this
-- codebase asserted that GetMouseLocation is the inset-EXCLUDED one, including
-- one claiming the result had been "verified at (0, -1) px". All three were
-- wrong, and the recordings showed it:
--
--     GetGuiInset()                              (0, 58)
--     GetMouseLocation()                    (1554, 1366)   inset-INCLUDED
--     Mouse.X / Mouse.Y                     (1554, 1308)   inset-excluded
--     local (0,0) of an IgnoreGuiInset
--       ScreenGui, read as AbsolutePosition      (0, -58)
--
-- 1366 - 58 = 1308: the two spaces differ by exactly the inset and by nothing
-- else. The old code ADDED the inset to GetMouseLocation before using it, so
-- the ring sat 58 px low. The glow then subtracted an AbsolutePosition from
-- that already over-corrected value, which doubles the error to 116 px -- which
-- is why the glow looked further out than the ring in the same session.
--
-- Both replacements below were verified live at (0, 0) px error before they
-- shipped. `L.pointerProbe()` re-runs that check on demand.

function L.pointer()
  -- Cursor in INSET-EXCLUDED space: the same space AbsolutePosition is measured
  -- in, which is what makes this safe to subtract from any AbsolutePosition.
  local ok, p = pcall(function()
    return UIS:GetMouseLocation() - GuiService:GetGuiInset()
  end)
  return ok and p or Vector2.new(0, 0)
end

function L.pointerOffset(screenGui)
  -- The LOCAL OFFSET that lands a child of `screenGui` under the cursor.
  -- It ASKS the ScreenGui which space it lives in rather than assuming, so a
  -- caller cannot silently get this wrong by parenting somewhere unexpected --
  -- which is exactly how the original bug survived three rounds of comments.
  local p = L.pointer()
  local ok, ignore = pcall(function()
    return screenGui and screenGui:IsA("ScreenGui") and screenGui.IgnoreGuiInset
  end)
  if ok and ignore then
    local ok2, inset = pcall(function() return GuiService:GetGuiInset() end)
    if ok2 then p = p + inset end
  end
  return p
end

function L.pointerIn(frame, scale)
  -- Cursor relative to `frame`, expressed in that frame's PRE-UIScale offsets.
  -- AbsolutePosition is real pixels and a UDim2 offset is not, so the scale
  -- divide is not optional: without it the light drifts further from the
  -- pointer the further the control sits from the window origin, which reads as
  -- "the glow is broken on some rows but fine on others".
  if not (frame and frame.Parent) then return Vector2.new(0, 0) end
  local sc = scale or 1
  if sc <= 0 then sc = 1 end
  return (L.pointer() - frame.AbsolutePosition) / sc
end

-- Self-test. Places a probe under the cursor by both routes and reports the
-- error in pixels, so "the pointer maths is right" is a number rather than an
-- opinion. Returns ringErr, spotErr as Vector2 -- both should read (0, 0).
function L.pointerProbe()
  local host = L.host()
  if not host then return nil, nil, "no host" end
  local gui = Instance.new("ScreenGui")
  gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn = "DaewidLumenPointerProbe", true, false
  gui.Parent = host

  local box = Instance.new("Frame")
  box.Size = UDim2.fromOffset(300, 120)
  box.Position = UDim2.fromOffset(400, 300)
  box.BackgroundTransparency = 1
  box.Parent = gui

  local spot = Instance.new("Frame")
  spot.Size, spot.AnchorPoint = UDim2.fromOffset(2, 2), Vector2.new(0.5, 0.5)
  spot.BackgroundTransparency = 1
  spot.Parent = box

  local ring = Instance.new("Frame")
  ring.Size, ring.AnchorPoint = UDim2.fromOffset(2, 2), Vector2.new(0.5, 0.5)
  ring.BackgroundTransparency = 1
  ring.Parent = gui

  local function snap(v) return math.floor(v + 0.5) end

  task.wait()
  local off = L.pointerOffset(gui)
  ring.Position = UDim2.fromOffset(snap(off.X), snap(off.Y))
  local rel = L.pointerIn(box, 1)
  spot.Position = UDim2.fromOffset(snap(rel.X), snap(rel.Y))
  task.wait()

  -- A UDim2 offset is an INTEGER and the pointer is a float, so a sub-pixel
  -- residual is the quantisation floor of the representation, not a placement
  -- error. Comparing raw floats made this instrument report 0.5 px on a
  -- placement that is exact, which would have had someone chasing a bug that
  -- does not exist. Compare against what an integer offset can actually hold.
  local truth = L.pointer()
  local tq = Vector2.new(snap(truth.X), snap(truth.Y))
  local ringErr = (ring.AbsolutePosition + ring.AbsoluteSize / 2) - tq
  local spotErr = (spot.AbsolutePosition + spot.AbsoluteSize / 2) - tq
  gui:Destroy()
  return ringErr, spotErr
end

-- ---------------------------------------------------------------- util

function L.clamp(v, a, b) return math.clamp(v, a, b) end
function L.lerp(a, b, t) return a + (b - a) * t end

function L.round(v, places)
  local m = 10 ^ (places or 0)
  return math.floor(v * m + 0.5) / m
end

-- Map a value from one range to another, clamped. Sliders, meters, progress.
function L.map(v, inA, inB, outA, outB)
  if inB == inA then return outA end
  local t = math.clamp((v - inA) / (inB - inA), 0, 1)
  return outA + (outB - outA) * t
end

-- LETTER TRACKING, BY HAND. Roblox TextLabel has no letter-spacing property, and
-- wide-tracked small caps is most of what makes the reference nav read as
-- expensive rather than as default UI. Interleaving spaces is the only way to
-- get it, so it is done once here instead of being typed into every label.
function L.track(text, spaces)
  local gap = string.rep(" ", spaces or 1)
  local out = {}
  for i = 1, #text do out[#out + 1] = text:sub(i, i) end
  return table.concat(out, gap)
end

function L.shortNum(n)
  n = tonumber(n) or 0
  local a = math.abs(n)
  local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
  for _, u in ipairs(units) do
    if a >= u[1] then return string.format("%.2f%s", n / u[1], u[2]) end
  end
  return tostring(math.floor(n))
end

do
  local old = getgenv().__DAEWID_BALL_LUMEN
  if old and old.teardown then pcall(old.teardown) end
end
getgenv().__DAEWID_BALL_LUMEN = L

end
