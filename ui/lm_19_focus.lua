do -- ==== lm_19_focus.lua ====
-- LUMEN :: FOCUS
-- Keyboard navigation. Tab walks the page, arrows move and adjust, Enter
-- activates, [ and ] change tab, Escape or a click leaves.
-- CAS never receives Tab, Escape or the brackets (CoreGui claims them first), so
-- UIS drives and CAS is only used to sink keys.

local L = getgenv().__DAEWID_BALL_LUMEN
local T, M, A = L.T, L.Motion, L.A
local mk = L.mk
local CAS = game:GetService("ContextActionService")

local F = {}
L.Focus = F

F.items = {}
F.current = nil
F.active = false

local ACTION = "DaewidLumenFocusNav"
local EDGE_PAD = 14          -- breathing room when scrolling a control into view

-- ---------------------------------------------------------------- registry

-- spec: { activate = fn, adjust = fn(dir), radius = n, label = s }
function F.register(frame, spec)
  spec = spec or {}
  spec.frame = frame
  F.items[#F.items + 1] = spec
  return spec
end

function F.reset()
  F.items, F.current, F.active = {}, nil, false
end

-- ---------------------------------------------------------------- ring

-- Roblox applies only one UIStroke per instance and A.interactive already owns
-- it, so the ring needs its own frame or hovering away erases it.
local function ringOf(spec)
  if spec._ring and spec._ring.Parent then return spec._ring end
  local f = spec.frame
  local ring = mk("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ZIndex = (f.ZIndex or 1) + 6,
    Name = "FocusRing", Parent = f,
  })
  L.corner(spec.radius or T.r.md, ring)
  spec._ringStroke = L.stroke(T.c.accent, 1.6, 1, ring)
  spec._ring = ring
  return ring
end

local function paintRing(spec, on)
  if not spec or not spec.frame or not spec.frame.Parent then return end
  ringOf(spec)
  if spec._ringStroke then
    M.to(spec._ringStroke, "Transparency", on and 0.1 or 1, "fast")
  end
end

-- ---------------------------------------------------------------- page scope

local function activeTab()
  local win = L.Hub and L.Hub.window
  if not win or win.hidden then return nil end
  return win.tabs[win.active], win
end

local function inside(node, page)
  while node do
    if node == page then return true end
    node = node.Parent
  end
  return false
end

-- Also prunes: a theme change rebuilds the window, so dead specs must be dropped
-- or the registry grows on every rebuild.
local function visibleItems()
  local tab = activeTab()
  if not tab then return {} end
  local out, keep = {}, {}
  for _, s in ipairs(F.items) do
    if s.frame and s.frame.Parent then
      keep[#keep + 1] = s
      -- a veiled control is still Visible and still on the page; skipping it
      -- here is what stops Tab landing on something whose click is refused
      if s.frame.Visible ~= false and not s.frame:GetAttribute("lmDisabled")
         and inside(s.frame, tab.page) then
        out[#out + 1] = s
      end
    end
  end
  F.items = keep
  return out
end

F.visibleItems = visibleItems

-- ---------------------------------------------------------------- movement

local function scrollIntoView(spec)
  local tab = activeTab()
  local body = tab and tab.body
  if not body or not spec.frame.Parent then return end
  local ctrl = A._scrolls and A._scrolls[body]
  if not ctrl then return end

  -- position within the canvas, not on screen: the canvas is what scrolls
  local rel = (spec.frame.AbsolutePosition.Y - body.AbsolutePosition.Y)
              + body.CanvasPosition.Y
  local h, viewH = spec.frame.AbsoluteSize.Y, body.AbsoluteWindowSize.Y
  local top = body.CanvasPosition.Y
  local want = top
  if rel - EDGE_PAD < top then
    want = rel - EDGE_PAD
  elseif rel + h + EDGE_PAD > top + viewH then
    want = rel + h + EDGE_PAD - viewH
  end
  if math.abs(want - top) > 0.5 then ctrl:to(math.max(want, 0)) end
end

function F.focus(spec)
  if F.current and F.current ~= spec then paintRing(F.current, false) end
  F.current = spec
  if spec then
    paintRing(spec, true)
    scrollIntoView(spec)
  end
end

function F.blur()
  if F.current then paintRing(F.current, false) end
  F.current = nil
end

function F.step(dir)
  local list = visibleItems()
  if #list == 0 then F.blur() return false end
  local i = 0
  for k, s in ipairs(list) do if s == F.current then i = k break end end
  i = i + dir
  if i < 1 then i = #list elseif i > #list then i = 1 end   -- wrap
  F.focus(list[i])
  return true
end

-- ---------------------------------------------------------------- keys

local function driving()
  if not L.live() then return false end
  local win = L.Hub and L.Hub.window
  if not win or win.hidden then return false end
  -- the palette is a modal and owns the keyboard while it is up
  if L.Palette and L.Palette.open then return false end
  -- a focused text box wins: sinking Space and the arrows would break typing
  local box = L.UIS:GetFocusedTextBox()
  if box then return false end
  return true, win
end

local PASS, SINK = Enum.ContextActionResult.Pass, Enum.ContextActionResult.Sink

local function shift()
  return L.UIS:IsKeyDown(Enum.KeyCode.LeftShift)
      or L.UIS:IsKeyDown(Enum.KeyCode.RightShift)
end

-- Probed at priority 3000 (above every CoreScript binding): these are the only
-- keys ContextActionService actually receives.
local USED = {
  [Enum.KeyCode.Up] = true, [Enum.KeyCode.Down] = true,
  [Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true,
  [Enum.KeyCode.Return] = true, [Enum.KeyCode.Space] = true,
}

local function suspended()
  local cur = F.current
  return cur and cur.suspend and cur.suspend()
end

CAS:BindActionAtPriority(ACTION, function(_, state, input)
  if state ~= Enum.UserInputState.Begin then return PASS end
  if not F.active or suspended() or not driving() then return PASS end
  if not USED[input.KeyCode] then return PASS end
  -- Left/Right only belong to us when the focused control can use them
  if (input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right)
     and not (F.current and F.current.adjust) then
    return PASS
  end
  if (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space)
     and not (F.current and F.current.activate) then
    return PASS
  end
  return SINK
end, false, Enum.ContextActionPriority.High.Value,
  Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left,
  Enum.KeyCode.Right, Enum.KeyCode.Return, Enum.KeyCode.Space)

-- ---- the driver ------------------------------------------------------------
-- `gameProcessedEvent` is already true for Tab, so an `if typing then return end`
-- guard would drop every Tab press.
L.hold(L.UIS.InputBegan:Connect(function(input)
  local ok, win = driving()
  if not ok then return end
  local k = input.KeyCode

  if not F.active then
    -- enters keyboard mode, and only while the pointer is over the window
    if k == Enum.KeyCode.Tab and win:_pointerInside() then
      F.active = true
      F.step(shift() and -1 or 1)
    end
    return
  end

  -- a control can ask for the raw keyboard back (the keybind chip, while recording)
  if suspended() then return end

  if k == Enum.KeyCode.Escape then
    -- Escape never reaches CAS, so it cannot be sunk at any priority and the
    -- Roblox menu opens either way. Handling it at least releases the ring.
    F.blur()
    F.active = false

  elseif k == Enum.KeyCode.Tab then
    F.step(shift() and -1 or 1)

  elseif k == Enum.KeyCode.Down then F.step(1)
  elseif k == Enum.KeyCode.Up   then F.step(-1)

  elseif k == Enum.KeyCode.LeftBracket or k == Enum.KeyCode.RightBracket then
    local n = win.active + (k == Enum.KeyCode.RightBracket and 1 or -1)
    if n < 1 then n = #win.tabs elseif n > #win.tabs then n = 1 end
    win:select(n)
    F.blur()
    task.defer(function() if F.active then F.step(1) end end)

  elseif k == Enum.KeyCode.Left or k == Enum.KeyCode.Right then
    local s = F.current
    if s and s.adjust then
      L.try("focus.adjust", s.adjust, k == Enum.KeyCode.Right and 1 or -1)
    end

  elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.Space then
    local s = F.current
    if s and s.activate then L.try("focus.activate", s.activate) end
  end
end))

-- Unbind on teardown, or a reloaded hub leaves the old handler holding Tab.
-- L.teardown only knows how to call :Disconnect(), hence the fake connection.
L.hold({ Disconnect = function() pcall(function() CAS:UnbindAction(ACTION) end) end })

-- Clicking anywhere means the user went back to pointing, so drop the ring.
L.hold(L.UIS.InputBegan:Connect(function(i)
  if not L.live() or not F.active then return end
  if i.UserInputType == Enum.UserInputType.MouseButton1
  or i.UserInputType == Enum.UserInputType.Touch then
    F.blur()
    F.active = false
  end
end))

end
