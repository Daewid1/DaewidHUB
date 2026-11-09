do -- ==== lm_04_atoms.lua ====
-- LUMEN :: ATOMS
-- The primitives every control is built from: surfaces, text, shadows, glow,
-- grain, scrolling, hover/press states, tooltips.
--
-- Shadows and glows are pre-rendered images because Roblox has no box-shadow and
-- no radial gradient. Stacking circles to fake one always bands.

local L = getgenv().__DAEWID_BALL_LUMEN
local T, M = L.T, L.Motion
local mk = L.mk

local A = {}
L.A = A

-- ---------------------------------------------------------------- surface

function A.surface(props)
  props = props or {}
  local e = T.elev[props.elev or 0]
  local f = mk("Frame", {
    BackgroundColor3 = props.fill or e.fill,
    BorderSizePixel = 0,
    Size = props.Size, Position = props.Position,
    AnchorPoint = props.AnchorPoint, LayoutOrder = props.LayoutOrder,
    Name = props.Name or "Surface",
    ClipsDescendants = props.clip,
    Parent = props.Parent,
  })
  L.corner(props.radius or T.r.md, f)
  if props.line ~= false then
    L.stroke(props.lineColour or e.line, 1, props.lineT or e.lineT, f)
  end
  -- One-pixel highlight along the top edge, and the whole elevation cue --
  -- Roblox has no box-shadow.
  if props.sheen then
    mk("Frame", {
      Size = UDim2.new(1, -(props.radius or T.r.md) * 2, 0, 1),
      Position = UDim2.new(0, props.radius or T.r.md, 0, 0),
      BackgroundColor3 = Color3.new(1, 1, 1),
      BackgroundTransparency = 0.92,
      BorderSizePixel = 0, ZIndex = 2,
      Parent = f,
    })
  end
  return f
end

-- Labels that asked to be truncated. Registered here rather than at each call
-- site so nothing has to remember: if a string can be cut short, it is
-- automatically eligible to be shown in full on hover. See A.truncatable below.
A.tips = {}

-- EXPLANATIONS, as distinct from truncations. A.tips exists so a label that had
-- to be cut short can still be read in full; this is the other half -- a control
-- whose PURPOSE is not obvious from its face. The panel pills are the clearest
-- case: "Goto", "Pick" and "Mark" are four characters each because a card is
-- narrow, and none of them says what it does.
--
-- Deliberately not wired to every control's `desc`: that text is already
-- rendered under the title, and a tooltip that repeats what is visible an inch
-- away is noise. This is for the things with nowhere to put an explanation.
A.hints = {}

-- PRUNED ON A CLOCK, not only when hovered. Both registries were swept inside
-- the hover test, so a window that is rebuilt while the pointer is elsewhere
-- left its labels on the list forever. Measured growing about twenty entries
-- per five panel cycles.
task.spawn(function()
  while true do
    task.wait(15)
    for i = #A.tips, 1, -1 do
      local l = A.tips[i]
      if not (l and l.Parent) then table.remove(A.tips, i) end
    end
    for i = #A.hints, 1, -1 do
      local h = A.hints[i]
      if not (h and h.obj and h.obj.Parent) then table.remove(A.hints, i) end
    end
  end
end)

-- `label` is optional and names the control; without one the card is a single
-- line, exactly as before. With one the card reads as a heading and a sentence,
-- which is the difference between a caption and an explanation.
function A.explain(obj, text, label)
  if not (obj and type(text) == "string" and text ~= "") then return obj end
  A.hints[#A.hints + 1] = { obj = obj, text = text, label = label }
  return obj
end

function A.text(props)
  local l = mk("TextLabel", {
    BackgroundTransparency = 1,
    Text = props.Text or "",
    TextColor3 = props.colour or T.c.text,
    Font = props.font or T.font.body,
    TextSize = props.size or T.size.body,
    TextXAlignment = props.align or Enum.TextXAlignment.Left,
    TextYAlignment = props.valign or Enum.TextYAlignment.Center,
    Size = props.Size or UDim2.fromScale(1, 1),
    Position = props.Position,
    AnchorPoint = props.AnchorPoint,
    LayoutOrder = props.LayoutOrder,
    TextTruncate = props.truncate and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
    TextWrapped = props.wrap or false,
    RichText = props.rich or false,
    ZIndex = props.ZIndex or 1,
    Name = props.Name or "Text",
    Parent = props.Parent,
  })
  if props.autoSize then l.AutomaticSize = props.autoSize end
  if props.truncate and props.tip ~= false then A.tips[#A.tips + 1] = l end
  return l
end

function A.divider(parent, order)
  return mk("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = T.c.line,
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    LayoutOrder = order,
    Name = "Divider",
    Parent = parent,
  })
end

-- Vertical gradient used on the accent. Two stops of the SAME hue family, never
-- two unrelated colours -- a gradient between distant hues passes through a
-- third colour that belongs to no part of the palette.
-- Tracked separately from L.paints: a ColorSequence is not a Color3, so the
-- generic registry in L.mk cannot see it. These are rebuilt on a palette change.
--
-- NOT a weak table. An Instance held only by the Roblox tree is unreachable from
-- Lua's point of view, so weak keys let the entries be collected and the set was
-- empty by the time a repaint asked for it -- 0 gradients repainted while 526
-- plain properties worked. Held strongly and pruned on use instead.
A.accentGradients = {}

function A.accentGradient(parent, rotation)
  local g = mk("UIGradient", {
    Color = ColorSequence.new(T.c.accent, T.c.accentAlt),
    Rotation = rotation or 90,
    Parent = parent,
  })
  A.accentGradients[g] = true
  return g
end

function A.repaintGradients()
  local n = 0
  for g in pairs(A.accentGradients) do
    if g.Parent then
      g.Color = ColorSequence.new(T.c.accent, T.c.accentAlt)
      n = n + 1
    else
      A.accentGradients[g] = nil
    end
  end
  return n
end

-- ---------------------------------------------------------------- depth
--
-- ROBLOX HAS NO BOX-SHADOW AND NO RADIAL GRADIENT. That single fact is why every
-- dark Roblox hub looks flat, including every earlier version of this one. Both
-- fakes were tried here and both failed the same way: a radial falloff built
local getAsset = rawget(getgenv(), "getcustomasset") or rawget(getgenv(), "getsynasset")

-- RESOLVED ON FIRST USE, NOT AT LOAD. getcustomasset copies the file into the
-- content folder, so each call costs real milliseconds -- and resolving all
-- twelve sprites at module scope was most of the 306 ms this script blocked for
-- before the loading screen could draw its first frame. That is the freeze you
-- get the instant you execute. Nothing here is needed until something is built,
-- and by then we are inside a coroutine that yields.
local UI_DIR = "lumen_fx/ui"
local IMG_FILES = { shadow = "shadow.png", glow = "glow.png",
                    ring = "ring.png", grain = "grain.png",
                    flare = "flare.png", beam = "beam.png" }

local function resolveAsset(path)
  if type(getAsset) ~= "function" then return nil end
  local ok, present = pcall(isfile, path)
  if not ok or not present then return nil end
  local gok, id = pcall(getAsset, path)
  return gok and id or nil
end

-- Misses are remembered so a missing file is not re-resolved on every lookup.
-- But they must NOT be remembered forever: a pack can land mid-session, and a
-- permanent negative cache meant the sprite stayed missing until the next
-- execute even though the file was now on disk. A.forgetMisses() clears them.
local imgTried = {}
A.img = setmetatable({}, { __index = function(t, k)
  if imgTried[k] then return nil end
  imgTried[k] = true
  local id = IMG_FILES[k] and resolveAsset(UI_DIR .. "/" .. IMG_FILES[k])
  if id then rawset(t, k, id) end
  return id
end })

---Drop the negative cache so sprites installed since the last lookup resolve.
function A.forgetMisses()
  local n = 0
  for k in pairs(imgTried) do
    if rawget(A.img, k) == nil then imgTried[k] = nil n = n + 1 end
  end
  return n
end

function A.hasImages() return A.img.shadow ~= nil end

-- Soft drop shadow behind a panel. 9-slice, so it stretches to any size without
-- the blurred corners smearing -- Roblox scales only the centre of a sliced
-- image, which is exactly why the blur margin lives inside the slice border.
-- THE DARK BOX. Every one of them, and they were all this.
--
-- The sprite is nine-sliced at (72, 72, 120, 120): 72 px of border on each
-- side, so 144 px is the smallest element that still has room for the soft
-- falloff between its corners.
--
-- A toast's shadow renders at 404 x 137. One hundred and thirty-seven is less
-- than one hundred and forty-four, so vertically there is NO middle left --
-- Roblox squashes the two 72 px corner bands into each other and the gradient
-- collapses into a hard rectangle. At the toast's settled ImageTransparency of
-- 0.42 that is a 58%-opaque black block, slightly larger than the card, fading
-- in over ~0.3 s behind it. Which is exactly what it looked like: a dark box,
-- a beat late, that then goes away.
--
-- It was never a timing bug, which is why twice re-timing it changed nothing.
-- Every shadow in the hub comes through here, so every panel, toast and pin
-- small enough to trip the threshold had the same block behind it.
--
-- SliceScale shrinks the borders proportionally, so the corners always fit and
-- the falloff survives at any size. Bound to AbsoluteSize rather than computed
-- once: these elements are sprung, and a shadow that is correct only at its
-- resting size is wrong for the whole animation -- which is the part you
-- actually see.
local SLICE_PX = 72

function A.shadow(target, opts)
  if not A.img.shadow then return nil end
  opts = opts or {}
  local spread = opts.spread or 26
  local sh = mk("ImageLabel", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, opts.lift or 6),
    Size = UDim2.new(1, spread * 2, 1, spread * 2),
    BackgroundTransparency = 1,
    Image = A.img.shadow,
    ImageTransparency = opts.alpha or 0.35,
    ImageColor3 = opts.colour or Color3.new(0, 0, 0),
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(SLICE_PX, SLICE_PX, 120, 120),
    ZIndex = (opts.ZIndex or 0),
    Name = "Shadow", Parent = opts.Parent or target.Parent,
  })

  local function fitSlice()
    if not sh.Parent then return end
    local s = sh.AbsoluteSize
    local smallest = math.min(s.X, s.Y)
    if smallest <= 0 then return end
    -- keep a sliver of middle rather than exactly zero, or the two corner
    -- bands meet and the seam reads as a line across the shadow
    local want = math.clamp(smallest / (SLICE_PX * 2.25), 0.2, 1)
    if math.abs(sh.SliceScale - want) > 0.01 then sh.SliceScale = want end
  end
  fitSlice()
  L.hold(sh:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSlice))

  return sh
end

-- Real radial bloom. Replaces the stacked-circle version entirely.
function A.glow(parent, size, colour, opts)
  opts = opts or {}
  if not A.img.glow then return nil end
  return mk("ImageLabel", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = opts.Position or UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(size, size),
    BackgroundTransparency = 1,
    Image = A.img.glow,
    ImageColor3 = colour,
    ImageTransparency = opts.alpha or 0.72,
    ZIndex = opts.ZIndex or 1,
    Name = "Glow", Parent = parent,
  })
end

-- Chrome icon tiles, extracted from the reference render. These are real 3D
-- glass objects; nothing drawn from frames gets anywhere near this, and the
-- dispersion along their edges is the only place spectral colour appears.
-- lazy, for the same reason A.img is
local ICON_DIR = "lumen_fx/icons"
local iconTried = {}
A.icons = setmetatable({}, { __index = function(t, k)
  if iconTried[k] then return nil end
  iconTried[k] = true
  local id = resolveAsset(ICON_DIR .. "/" .. tostring(k) .. ".png")
  if id then rawset(t, k, id) end
  return id
end })

function A.chrome(parent, name, size, opts)
  opts = opts or {}
  local id = A.icons[name]
  if not id then return nil end
  return mk("ImageLabel", {
    Size = UDim2.fromOffset(size, size),
    Position = opts.Position,
    AnchorPoint = opts.AnchorPoint,
    BackgroundTransparency = 1,
    Image = id,
    ImageTransparency = opts.alpha or 0,
    ZIndex = opts.ZIndex or 2,
    Name = "Chrome", Parent = parent,
  })
end

-- Tiled grain. A big flat gradient in an 8-bit framebuffer bands; a couple of
-- levels of noise dither it away. Same reason film grain exists.
function A.grain(parent, alpha)
  if not A.img.grain then return nil end
  return mk("ImageLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Image = A.img.grain,
    ImageTransparency = alpha or 0.94,
    ScaleType = Enum.ScaleType.Tile,
    TileSize = UDim2.fromOffset(128, 128),
    ZIndex = 1,
    Name = "Grain", Parent = parent,
  })
end

-- Vertical wash across a surface. Two stops of the same colour at different
-- brightness, never two hues -- this is a light source, not a decoration.
function A.wash(parent, topLift, bottomDrop)
  return mk("UIGradient", {
    Color = ColorSequence.new(
      Color3.new(1, 1, 1),
      Color3.new(1 - (bottomDrop or 0.10), 1 - (bottomDrop or 0.10), 1 - (bottomDrop or 0.10))
    ),
    Transparency = NumberSequence.new(0),
    Rotation = 90,
    Offset = Vector2.new(0, topLift or 0),
    Parent = parent,
  })
end

-- A hairline that fades out at both ends. A full-width 1 px line reads as a
-- border; one that dissolves at the edges reads as a highlight catching light.
function A.hairline(parent, colour, y, alpha)
  local f = mk("Frame", {
    Position = UDim2.new(0, 0, 0, y or 0),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = colour,
    BorderSizePixel = 0, ZIndex = 6,
    Parent = parent,
  })
  mk("UIGradient", {
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 1),
      NumberSequenceKeypoint.new(0.5, alpha or 0.25),
      NumberSequenceKeypoint.new(1, 1),
    }),
    Parent = f,
  })
  return f
end

-- ---------------------------------------------------------------- world blur
--
-- The single largest visual upgrade available, and it costs one instance: blur
-- the 3D world while the hub is open. A crisp game behind a flat panel is
-- exactly what makes an overlay look pasted on; pushing the world out of focus
local Lighting = game:GetService("Lighting")

function A.worldBlur()
  if A._blur and A._blur.Parent then return A._blur end
  local b = Instance.new("BlurEffect")
  b.Name = "DaewidLumenBlur"
  b.Size = 0
  b.Enabled = true
  b.Parent = Lighting
  L.own(b)
  A._blur = b
  return b
end

function A.blurTo(size, token)
  local b = A.worldBlur()
  M.to(b, "Size", size, token or "slow")
end

-- ---------------------------------------------------------------- scrolling
--
-- SPRUNG SCROLLING. Roblox writes CanvasPosition in instant jumps on every wheel
-- notch, which is the one genuinely jerky thing left in the interface -- and it
-- cannot be eased, because the engine owns the property.
A._scrolls = setmetatable({}, { __mode = "k" })

-- THE WHEEL HAS TO BE SUNK, NOT JUST HANDLED.
local CAS = game:GetService("ContextActionService")
A._wheelGuards = {}

function A.addWheelGuard(fn)
  A._wheelGuards[#A._wheelGuards + 1] = fn
end

do
  local NAME = "DaewidLumenWheelSink"
  pcall(function() CAS:UnbindAction(NAME) end)
  CAS:BindActionAtPriority(NAME, function()
    for _, fn in ipairs(A._wheelGuards) do
      local ok, want = pcall(fn)
      if ok and want then return Enum.ContextActionResult.Sink end
    end
    return Enum.ContextActionResult.Pass
  end, false, Enum.ContextActionPriority.High.Value + 10, Enum.UserInputType.MouseWheel)

  L.hold({ Disconnect = function() pcall(function() CAS:UnbindAction(NAME) end) end })
end

local SCROLL_TOKEN = { 0.26, 0.0 }

function A.smoothScroll(scroll, opts)
  opts = opts or {}
  if A._scrolls[scroll] then return A._scrolls[scroll] end

  scroll.ScrollingEnabled = false
  local ctrl = { obj = scroll, target = scroll.CanvasPosition.Y }
  local speed = opts.speed or 96

  local function maxY()
    return math.max(scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y, 0)
  end

  function ctrl:clamp()
    self.target = math.clamp(self.target, 0, maxY())
    return self.target
  end

  function ctrl:to(y, immediate)
    self.target = y
    self:clamp()
    local v = Vector2.new(0, self.target)
    if immediate then M.set(scroll, "CanvasPosition", v)
    else M.to(scroll, "CanvasPosition", v, SCROLL_TOKEN) end
  end

  function ctrl:reset()
    self.target = 0
    M.set(scroll, "CanvasPosition", Vector2.zero)
  end

  function ctrl:nudge(delta)
    self:to(self.target + delta)
  end

  scroll.InputChanged:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    -- Position.Z carries the notch direction: +1 up, -1 down
    ctrl:nudge(-i.Position.Z * speed)
  end)

  A._scrolls[scroll] = ctrl
  return ctrl
end

function A.scrollReset(scroll)
  local c = A._scrolls[scroll]
  if c then c:reset() else scroll.CanvasPosition = Vector2.zero end
end

function A.scroll(props)
  local s = mk("ScrollingFrame", {
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = props.Size or UDim2.fromScale(1, 1),
    Position = props.Position,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ScrollBarThickness = props.bar or 2,
    ScrollBarImageColor3 = T.c.lineStrong,
    ScrollBarImageTransparency = 0.3,
    ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
    Name = props.Name or "Scroll",
    Parent = props.Parent,
  })
  if props.gap then L.list(props.gap, nil, s) end
  -- explicit > 0 test: `padding = 0` is TRUTHY in Lua, so the old check built
  -- a zero UIPadding and any padding the caller added afterwards became a
  -- second one on the same instance, which Roblox silently ignores.
  if props.padding and props.padding > 0 then
    L.pad(props.padding, props.padding, props.padding, props.padding, s)
  end
  -- AutomaticCanvasSize grows the canvas from zero, and CanvasPosition 0 against
  -- a zero-height canvas already counts as "the bottom" -- so a list can end up
  -- pinned to its own end as it fills. Deferring one frame and re-zeroing costs
  -- nothing and removes a genuinely baffling bug.
  task.defer(function()
    if s.Parent then s.CanvasPosition = Vector2.new(0, 0) end
  end)
  if props.smooth ~= false then A.smoothScroll(s) end
  return s
end

-- ---------------------------------------------------------------- icons
--
-- Every glyph is built from `bar`: a rounded rectangle, rotated. A chevron is
-- two bars at +/-45 degrees; a cross is two at +/-45 crossing; a check is two of
-- unequal length. All of it inherits colour from the token palette.
local Icon = {}
A.Icon = Icon

local function bar(parent, w, h, x, y, rot, colour, thickness)
  local b = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(x, y),
    Size = UDim2.fromOffset(w, h or thickness or 2),
    Rotation = rot or 0,
    BackgroundColor3 = colour,
    BorderSizePixel = 0,
    Parent = parent,
  })
  L.corner(999, b)
  return b
end

local function holder(parent, size, name)
  return mk("Frame", {
    Size = UDim2.fromOffset(size, size),
    BackgroundTransparency = 1,
    Name = name or "Icon",
    Parent = parent,
  })
end

-- direction: "right" | "left" | "up" | "down"
function Icon.chevron(parent, size, colour, direction)
  local h = holder(parent, size, "Chevron")
  local c = size / 2
  local arm = size * 0.30
  local rot = ({ right = 0, down = 90, left = 180, up = 270 })[direction or "right"]
  local inner = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
                              Rotation = rot, Parent = h })
  bar(inner, arm, 1.6, c - arm * 0.18, c - arm * 0.35, 45, colour)
  bar(inner, arm, 1.6, c - arm * 0.18, c + arm * 0.35, -45, colour)
  -- `inner` is returned separately so callers can spring its Rotation: an
  -- expanding dropdown turns its chevron rather than swapping the glyph.
  return h, inner
end

function Icon.check(parent, size, colour)
  local h = holder(parent, size, "Check")
  local c = size / 2
  bar(h, size * 0.30, 1.8, c - size * 0.16, c + size * 0.10, 45, colour)
  bar(h, size * 0.52, 1.8, c + size * 0.09, c - size * 0.02, -45, colour)
  return h
end

function Icon.close(parent, size, colour)
  local h = holder(parent, size, "Close")
  local c = size / 2
  bar(h, size * 0.62, 1.6, c, c, 45, colour)
  bar(h, size * 0.62, 1.6, c, c, -45, colour)
  return h
end

function Icon.minus(parent, size, colour)
  local h = holder(parent, size, "Minus")
  bar(h, size * 0.62, 1.6, size / 2, size / 2, 0, colour)
  return h
end

function Icon.dot(parent, size, colour)
  local h = holder(parent, size, "Dot")
  bar(h, size * 0.34, size * 0.34, size / 2, size / 2, 0, colour)
  return h
end

function Icon.search(parent, size, colour)
  local h = holder(parent, size, "Search")
  local r = size * 0.30
  local ring = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(size * 0.44, size * 0.42),
    Size = UDim2.fromOffset(r * 2, r * 2),
    BackgroundTransparency = 1, Parent = h,
  })
  L.corner(999, ring)
  L.stroke(colour, 1.6, 0, ring)
  bar(h, size * 0.26, 1.6, size * 0.72, size * 0.72, 45, colour)
  return h
end

-- Three stacked bars of descending length. Reads as "list" / "menu" / "options".
function Icon.bars(parent, size, colour)
  local h = holder(parent, size, "Bars")
  bar(h, size * 0.62, 1.6, size * 0.5, size * 0.30, 0, colour)
  bar(h, size * 0.62, 1.6, size * 0.5, size * 0.50, 0, colour)
  bar(h, size * 0.40, 1.6, size * 0.4, size * 0.70, 0, colour)
  return h
end

function Icon.grip(parent, size, colour)
  local h = holder(parent, size, "Grip")
  for r = 0, 1 do
    for c = 0, 2 do
      bar(h, 2, 2, size * (0.36 + r * 0.28), size * (0.26 + c * 0.24), 0, colour)
    end
  end
  return h
end

-- A ring with a gap, used as the spinner. Rotating a gapped ring reads as motion
-- far better than a rotating solid, and needs no image.
function Icon.spinner(parent, size, colour)
  local h = holder(parent, size, "Spinner")
  local ring = mk("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = h,
  })
  L.corner(999, ring)
  local st = L.stroke(colour, 2, 0, ring)
  local grad = mk("UIGradient", {
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 0),
      NumberSequenceKeypoint.new(0.55, 0.15),
      NumberSequenceKeypoint.new(1, 1),
    }),
    Parent = st,
  })
  return h, grad
end

-- ---------------------------------------------------------------- interaction

-- Adds a state layer and returns a controller. `hover` and `press` are the two
-- states every control shares; giving them one implementation is what makes the
-- whole framework feel like one product.
-- Puts `spot` exactly under the pointer, expressed in `frame`'s own coordinates.
--
-- The inset correction that used to live here was BACKWARDS, and it is now gone
-- entirely: `L.pointerIn` returns the cursor already in this frame's local,
-- pre-UIScale space. See the measurement in lm_00_core -- GetMouseLocation is
-- the inset-INCLUDED reading, so adding the inset to it (as this did) and then
-- subtracting an AbsolutePosition put the light 116 px below the pointer.
-- ONE FIXED SIZE CANNOT BE RIGHT FOR EVERY CONTROL, and this was 150 x 150 for
-- all of them. On a 26 px dock pill that is a wash of colour over the entire
-- button with no falloff visible anywhere -- there is no gradient left inside
-- the control, just a tinted pill. On a 520 px panel header it is a small dot
-- with a hard end to it. Neither reads as a light source.
--
-- The comment that used to sit on the ImageLabel said the glow was "wider than
-- the row is tall, so the falloff runs along the control". It was square. This
-- makes the comment true: the ellipse is sized from the control every time its
-- bounds change, tall enough to spill past the top and bottom edges (so the
-- falloff you see is horizontal, along the direction you actually move) and
-- never so wide that it stops being a highlight.
local function fitSpot(frame, spot, sc)
  local a = frame.AbsoluteSize
  if a.X < 1 or a.Y < 1 then return end
  local key = math.floor(a.X + 0.5) * 4096 + math.floor(a.Y + 0.5)
  if spot:GetAttribute("__fit") == key then return end
  spot:SetAttribute("__fit", key)
  local h = a.Y / math.max(sc, 0.01)              -- pre-UIScale local units
  local w = a.X / math.max(sc, 0.01)
  -- A POOL, NOT A WASH. The first pass at this scaled off the control and came
  -- out 185 x 119 on a 187 x 46 row -- a glow the size of the whole control,
  -- which is not a highlight, it is a second background. Sized to a little over
  -- the control's HEIGHT instead, so there is lit area and unlit area inside
  -- one row and the light has an edge you can actually see move.
  local gh = math.clamp(h * 1.25, 26, 84)
  local gw = math.clamp(gh * 1.9, 40, 150)
  spot.Size = UDim2.fromOffset(math.floor(gw), math.floor(gh))
end

-- TWO FRAMES OF LAG IS SMOOTH; A SPRING IS LOST.
--
-- The note that stood here said a cursor light has no business being animated,
-- and it was right about what it was describing: the position was going through
-- M.to -- a real spring, ~180 ms -- driven off MouseMoved, which fires less
-- often than the screen redraws. That light was permanently travelling to where
-- the pointer had just been, and between events it did not move at all.
--
-- This is a different quantity: a first-order approach evaluated EVERY frame,
-- with a time constant short enough to be smoothing rather than animation.
-- Worked out rather than eyeballed, at 60 fps (dt = 16.7 ms):
--
--   retention per frame  exp(-16.7/18) = 0.40    -- 60% of the error gone each frame
--   20 px step           7.9 -> 3.1 -> 1.2 -> 0.5 px   (settled in 4 frames, 67 ms)
--   steady-state lag     v * tau: 250 px/s -> 4.5 px, 800 px/s -> 14 px
--
-- The first draft used tau = 35 ms, where the error decays only 38% a frame and
-- a 26 px step needs nearly seven of them -- which is exactly the trailing the
-- note above complains about, just with a smaller constant. 18 ms removes the
-- per-frame jitter of raw pointer sampling and nothing else.
--
-- The distance is clamped too, so a hitch or a flick across the screen cannot
-- leave the light stranded: past MAX_LAG it stops interpolating and teleports.
-- 0.55 was loud enough to read as a coloured smear rather than as light on a
-- surface. At 0.74 the pool has an edge and the control underneath still shows
-- through it, which is the difference between lighting something and painting it.
local SPOT_REST = 0.74

local SPOT_TAU = 0.018
local SPOT_MAX_LAG = 14        -- local px; beyond this, snap rather than trail

function A.aimSpot(frame, spot, dt, h)
  if not (frame and spot and frame.Parent) then return end
  local sc = (L.Hub and L.Hub.window and L.Hub.window.scaleObj
              and L.Hub.window.scaleObj.Scale) or 1
  fitSpot(frame, spot, sc)
  local rel = L.pointerIn(frame, sc)
  local x, y = rel.X, rel.Y

  if h and dt and h.sx then
    local k = 1 - math.exp(-dt / SPOT_TAU)
    local nx = h.sx + (x - h.sx) * k
    local ny = h.sy + (y - h.sy) * k
    local dx, dy = x - nx, y - ny
    if (dx * dx + dy * dy) > (SPOT_MAX_LAG * SPOT_MAX_LAG) then
      nx, ny = x, y
    end
    h.sx, h.sy = nx, ny
    x, y = nx, ny
  elseif h then
    h.sx, h.sy = x, y                    -- first frame of a hover: no trail
  end
  spot.Position = UDim2.fromOffset(x, y)

  -- THE BORDER LIGHTS ON THE SIDE THE POINTER IS ON.
  --
  -- This is the part that stops it reading as a generic blob. A rim whose
  -- bright arc tracks the cursor is a surface catching a moving light; a rim
  -- that is always brightest at the top is a border with a gradient on it.
  -- Costs one Rotation write a frame.
  --
  -- A UIGradient at Rotation R runs along (cos R, sin R) with keypoint 0 on the
  -- far side, so putting the bright key (0.00) under the pointer at bearing
  -- theta means R = theta - 180.
  if h and h.rim then
    local a = frame.AbsoluteSize
    local cx, cy = a.X / (2 * sc), a.Y / (2 * sc)
    local vx, vy = x - cx, y - cy
    if (vx * vx + vy * vy) > 4 then
      h.rim.Rotation = math.deg(math.atan2(vy, vx)) - 180
    end
  end
end

-- ---------------------------------------------------------------- selection
--
-- ONE ANSWER TO "WHICH ONE IS CHOSEN", USED BY EVERY LIST.
--
-- The dropdown said it with a 0.86-transparent wash and accent text -- 14% of
-- an already dark colour, on a row 26 px tall. Against a busy page that is not
-- a state, it is a suggestion, and it looked broken rather than subtle. The
-- side panel and the command centre each had a third and fourth answer.
--
-- Three signals, because one is never enough on a dark surface: a fill you can
-- actually see, the accent on the text, and a bar down the leading edge that
-- has no other meaning anywhere in the interface. The bar is what makes it
-- unambiguous at a glance -- fills read as hover, bars read as chosen.
A.SEL_FILL  = 0.80          -- transparency of the selected row's wash
A.SEL_BAR_W = 3

function A.selectMark(frame)
  local bar = frame:FindFirstChild("SelBar")
  if bar then return bar end
  bar = mk("Frame", {
    AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
    Size = UDim2.new(0, A.SEL_BAR_W, 0, 0),
    BackgroundColor3 = T.c.accent, BorderSizePixel = 0,
    BackgroundTransparency = 0, ZIndex = (frame.ZIndex or 1) + 1,
    Name = "SelBar", Parent = frame,
  })
  L.corner(999, bar)
  return bar
end

-- `on` selects, and the label is optional for callers that colour their own.
function A.selectRow(frame, label, on, token)
  if not frame then return end
  token = token or "fast"
  local bar = A.selectMark(frame)
  M.to(frame, "BackgroundTransparency", on and A.SEL_FILL or 1, token)
  M.to(bar, "Size", UDim2.new(0, A.SEL_BAR_W, 0, on and 14 or 0), token)
  M.to(bar, "BackgroundTransparency", on and 0 or 1, token)
  if label then
    M.to(label, "TextColor3", on and T.c.accent or T.c.textDim, token)
  end
end

-- ---------------------------------------------------------------- chrome
--
-- A TRAVELLING HIGHLIGHT, BUILT BY SAMPLING RATHER THAN BY OFFSET.
--
-- The page titles sweep a UIGradient by animating its Offset from -1 to +1. A
-- UIGradient only defines colour over [0, 1] and CLAMPS outside it, so for a
-- large part of that cycle the bright band is not on the letters at all:
--
--   bright key sits at p = 0.34, appears at object x = 0.34 + offset
--   so it is inside the glyphs only for offset in [-0.34, 0.66]
--   -- one unit out of the two the sweep travels. Half the cycle is flat.
--
-- Which is why the titles spend as long looking like dark grey text as they do
-- looking like metal. Widening the range does not help; the highlight has to
-- LEAVE somewhere, and with a single gradient there is nowhere for it to go.
--
-- So the offset is abandoned and the gradient's colours are resampled instead.
-- The pattern below is defined in a wrapped space, sampled at fixed positions
-- across whatever slice of it a given label occupies, and rebuilt as the phase
-- advances. Nothing clamps, because the keys always span exactly [0, 1] -- and
-- because the pattern wraps, the highlight that leaves the right edge is the
-- same one arriving at the left. It never goes flat.
--
-- The slice is what lets a word split across several labels share ONE sweep:
-- give glyph i the slice [i/n, (i+1)/n] and the highlight crosses the word,
-- rather than five letters each flashing on their own.
A.CHROME = {
  __default = { rot =   8, speed = 0.16, warm = Color3.fromRGB(196, 182, 140) },
  Movement  = { rot =  22, speed = 0.30, warm = Color3.fromRGB(150, 196, 214) },
  Combat    = { rot =   0, speed = 0.11, warm = Color3.fromRGB(214, 150, 140), hard = true },
  Visuals   = { rot = -16, speed = 0.20, warm = Color3.fromRGB(178, 158, 214), prism = true },
  -- The loading screen had its own richer "Boot" preset here. It read as a
  -- different product from the page titles, so it uses __default like they do
  -- -- one preset, and the two cannot drift apart.
}

local STEEL  = Color3.fromRGB(120, 124, 132)
local BRIGHT = Color3.fromRGB(248, 249, 252)
local DARK   = Color3.fromRGB( 78,  82,  90)

-- The pattern is a wrapped ring: position 1 is the same place as position 0, so
-- the first and last colour MUST match or the seam shows as a dark bar.
function A.chromePattern(cfg)
  cfg = cfg or A.CHROME.__default
  if cfg.hard then
    return { {0.00, STEEL}, {0.38, STEEL}, {0.40, BRIGHT}, {0.52, cfg.warm},
             {0.54, DARK},  {0.72, STEEL}, {1.00, STEEL} }
  elseif cfg.prism then
    return { {0.00, STEEL}, {0.18, Color3.fromRGB(150, 196, 214)},
             {0.36, BRIGHT}, {0.50, cfg.warm},
             {0.64, Color3.fromRGB(214, 170, 150)}, {0.82, DARK},
             {1.00, STEEL} }
  end
  return { {0.00, STEEL}, {0.26, BRIGHT}, {0.38, cfg.warm}, {0.54, DARK},
           {0.72, Color3.fromRGB(236, 238, 242)}, {1.00, STEEL} }
end

local function patternAt(pat, t)
  t = t % 1
  for i = 1, #pat - 1 do
    local a, b = pat[i], pat[i + 1]
    if t >= a[1] and t <= b[1] then
      local span = b[1] - a[1]
      return a[2]:Lerp(b[2], span > 0 and (t - a[1]) / span or 0)
    end
  end
  return pat[#pat][2]
end

-- 20 is the ColorSequence keypoint ceiling, and a hard-cut preset wants every
-- one of them -- sampled coarsely the cut turns into a ramp.
local CHROME_SAMPLES = 20

function A.chromeSeq(pat, phase, a, b)
  a, b = a or 0, b or 1
  local keys = {}
  for i = 0, CHROME_SAMPLES - 1 do
    local x = i / (CHROME_SAMPLES - 1)
    keys[i + 1] = ColorSequenceKeypoint.new(x, patternAt(pat, (a + (b - a) * x) - phase))
  end
  return ColorSequence.new(keys)
end

-- ---------------------------------------------------------------- fading
--
-- STROKES ARE PART OF A FADE, AND LEAVING THEM OUT IS WHY THINGS LEAVE A LINE.
--
-- A panel that fades by walking BackgroundTransparency and TextTransparency
-- looks finished and is not: its UIStroke is still sitting at its resting value,
-- so a 1 px outline stays lit over whatever is underneath. On the tooltip that
-- reads as a dark line hanging in the air a beat after the text has gone --
-- reported as "a delayed dark string" and visible in the recordings.
--
-- One map, one walk, used everywhere something fades out as a unit.
A.FADE_PROP = {
  Frame = "BackgroundTransparency",
  ScrollingFrame = "BackgroundTransparency",
  TextLabel = "TextTransparency",
  TextButton = "TextTransparency",
  TextBox = "TextTransparency",
  ImageLabel = "ImageTransparency",
  ImageButton = "ImageTransparency",
  CanvasGroup = "GroupTransparency",
  UIStroke = "Transparency",
}

-- GROUPTRANSPARENCY DOES NOT COVER THE GROUP'S OWN UISTROKE.
--
-- This is the bug behind "the dark outline is still there and it lags". A
-- CanvasGroup composites its CHILDREN and fades that composite; a UIStroke
-- parented to the CanvasGroup itself is not one of those children, so it keeps
-- drawing at its own transparency for the entire fade. Measured on the live
-- window, held mid-fade:
--
--   root.GroupTransparency = 0.92   -- contents faded to almost nothing
--   root's UIStroke        = 0.30   -- a solid rounded outline, full strength
--
-- Which is a bright 1 px rectangle around an empty hole, drawn over the game,
-- for the whole duration of every hide -- and then snapped away by Visible =
-- false at the end, which is what reads as the delay.
--
-- lm_05_window even asserted the opposite in a comment: "Body, wash, stroke,
-- icons and text all leave through GroupTransparency." Everything in that list
-- is true except the stroke.
--
-- Use this anywhere a CanvasGroup is faded by hand.
function A.groupTo(group, alpha, token)
  if not group then return end
  M.to(group, "GroupTransparency", alpha, token)
  if group:GetAttribute("GiorgioFadeGroup") then return end
  for _, d in ipairs(group:GetChildren()) do
    if d:IsA("UIStroke") then
      local rest = L.strokeRest(d)
      M.to(d, "Transparency", rest + (1 - rest) * alpha, token)
    end
  end
end

-- Same, without animating: for the set-then-reveal pattern.
function A.groupSet(group, alpha)
  if not group then return end
  M.set(group, "GroupTransparency", alpha)
  if group:GetAttribute("GiorgioFadeGroup") then return end
  for _, d in ipairs(group:GetChildren()) do
    if d:IsA("UIStroke") then
      local rest = L.strokeRest(d)
      M.set(d, "Transparency", rest + (1 - rest) * alpha)
    end
  end
end

-- Rest values are captured ONCE and cached on the instance. Reading them again
-- mid-fade records "invisible" as the resting state and the thing never comes
-- back -- the same trap the row cascade and the dock pill both hit.
function A.fadeSet(root)
  if not root then return {} end
  local cached = root:GetAttribute("__fadeCached")
  if cached and A._fadeSets and A._fadeSets[root] then return A._fadeSets[root] end
  local parts = {}
  local function add(o)
    local p = A.FADE_PROP[o.ClassName]
    if not p then return end
    local ok, v = pcall(function() return o[p] end)
    if ok and type(v) == "number" and v < 1 then parts[#parts + 1] = { o, p, v } end
  end
  add(root)
  for _, d in ipairs(root:GetDescendants()) do add(d) end
  A._fadeSets = A._fadeSets or setmetatable({}, { __mode = "k" })
  A._fadeSets[root] = parts
  pcall(function() root:SetAttribute("__fadeCached", true) end)
  return parts
end

-- k = 0 is fully at rest, k = 1 is fully gone.
function A.fadeTo(root, k, token)
  for _, e in ipairs(A.fadeSet(root)) do
    if e[1].Parent then
      M.to(e[1], e[2], e[3] + (1 - e[3]) * k, token or "fast")
    end
  end
end

-- The one control currently under the pointer, driven by the shared loop below.
A._hover = nil
L.hold(L.RunService.RenderStepped:Connect(function(dt)
  local h = A._hover
  if h then A.aimSpot(h.frame, h.spot, dt, h) end
end))

function A.interactive(frame, opts)
  opts = opts or {}
  local radius = opts.radius or T.r.md

  -- THE HIGHLIGHT MUST BE THE SAME SHAPE AS THE THING IT HIGHLIGHTS, and the
  -- FRAME'S OWN CORNER IS THE SOURCE OF TRUTH -- not the radius passed in.
  --
  -- Everything added below is rounded: the hover wash, the sweep, the spotlight
  -- host. The press/focus edge is a UIStroke, and a UIStroke follows the corner
  -- of the frame it is parented to. Two ways that went wrong:
  --
  --   NO CORNER AT ALL. Controls built on A.surface carry one, but anything that
  --   did not -- most visibly the sidebar tabs -- got a SQUARE outline drawn
  --   around a rounded fill, sitting outside the frame in Border mode, so it read
  --   as a slightly larger box of the wrong shape.
  --
  --   A DIFFERENT CORNER. A caller passing a radius that disagrees with the one
  --   already on the frame produced a highlight that did not follow the edge it
  --   was highlighting. Trusting the argument here would leave that mismatch in
  --   place, so the frame wins and the argument is only a default.
  --
  -- Radii are read back as PIXELS. L.corner multiplies by the user's radius
  -- setting, so feeding a value that has already been scaled back through it
  -- would scale it twice.
  local existingCorner = frame:FindFirstChildOfClass("UICorner")
  if not existingCorner then
    existingCorner = L.corner(radius, frame)
  end
  local radiusPx = existingCorner.CornerRadius.Offset
  local function matchCorner(parent)
    return mk("UICorner", { CornerRadius = UDim.new(0, radiusPx), Parent = parent })
  end

  local layer = mk("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = opts.layerColour or Color3.new(1, 1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = (frame.ZIndex or 1) + 4,
    Name = "State",
    Parent = frame,
  })
  matchCorner(layer)

  -- ---- the fill rises from the bottom ---------------------------------
  --
  -- A flat tint over the whole control says "hovered" and nothing else. Light
  -- pooling at the base of a surface says the surface has a bottom -- which is
  -- the difference between a coloured rectangle and something that looks lit.
  -- Taken from the reference clip: the fill is strongest at the floor of the
  -- pill and gone by two thirds up, so the top edge stays dark for the rim to
  -- read against.
  local fillGrad = mk("UIGradient", {
    Rotation = 90,
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0.00, 1.00),
      NumberSequenceKeypoint.new(0.34, 0.92),
      NumberSequenceKeypoint.new(0.72, 0.42),
      NumberSequenceKeypoint.new(1.00, 0.10),
    }),
    Parent = layer,
  })

  local btn = mk("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "", AutoButtonColor = false,
    ZIndex = (frame.ZIndex or 1) + 5,
    Name = "Hit",
    Parent = frame,
  })

  -- ---- specular sweep -------------------------------------------------------
  --
  -- A HIGHLIGHT THAT TRAVELS, not a panel that lights up. Every Roblox hub
  -- brightens a row on hover, which communicates "the cursor is here" and
  -- nothing else. A band of light crossing the surface says the surface is made
  local sweepGrad
  local sweepOn = opts.sweep ~= false
                  and not (L.Cfg and L.Cfg.data.sweep == false)
  if sweepOn then
    local sweep = mk("Frame", {
      Size = UDim2.fromScale(1, 1),
      BackgroundColor3 = Color3.new(1, 1, 1),
      BorderSizePixel = 0,
      ZIndex = (frame.ZIndex or 1) + 3,
      Name = "Sweep", Parent = frame,
    })
    matchCorner(sweep)
    sweepGrad = mk("UIGradient", {
      Rotation = 16,
      Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 1),
        NumberSequenceKeypoint.new(0.40, 1),
        NumberSequenceKeypoint.new(0.50, 0.88),
        NumberSequenceKeypoint.new(0.60, 1),
        NumberSequenceKeypoint.new(1.00, 1),
      }),
      Offset = Vector2.new(-1.2, 0),
      Parent = sweep,
    })
  end

  -- ---- cursor spotlight -----------------------------------------------------
  --
  -- A GLOW THAT FOLLOWS THE POINTER, not one that lights the whole control. The
  -- reference clips both do the same thing: a soft radial bloom sits under the
  -- cursor and travels with it along the button, so the surface reads as lit
  -- from a moving source rather than as a state that toggled on.
  --
  -- Clipped by its own host rather than by `frame`: turning on ClipsDescendants
  -- on the control itself would also crop anything a caller has deliberately
  -- hung outside it, and several rows do exactly that.
  --
  -- A CANVASGROUP, BECAUSE ClipsDescendants CLIPS TO A RECTANGLE.
  --
  -- This was a Frame with ClipsDescendants and a matched UICorner, on the
  -- assumption that the corner rounds the clip region. It does not, and that is
  -- the source of the hard edges: bring the pointer near a rounded control and
  -- the glow stopped at the host's square bounds, drawing a straight edge
  -- across a corner that is meant to be curved.
  --
  -- Measured side by side on this client before changing it:
  --
  --   Frame + UICorner + ClipsDescendants   ->  SQUARE corners
  --   CanvasGroup + UICorner                ->  rounded
  --   oversized child in Frame + Clips      ->  square corner, the exact artifact
  --
  -- A CanvasGroup composites its children and THEN applies the corner, so the
  -- clip follows the curve. The usual objection to CanvasGroups -- that they
  -- resample glyphs and soften text -- does not apply here: this subtree holds
  -- one radial image and no type at all.
  local spot, spotHost
  local spotOn = opts.spot ~= false
                 and not (L.Cfg and L.Cfg.data.spot == false)
                 and A.img.glow ~= nil
  if spotOn then
    spotHost = mk("CanvasGroup", {
      Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
      GroupTransparency = 0, ZIndex = (frame.ZIndex or 1) + 2,
      Name = "SpotHost", Parent = frame,
    })
    matchCorner(spotHost)
    spot = mk("ImageLabel", {
      AnchorPoint = Vector2.new(0.5, 0.5),
      Position = UDim2.fromScale(0.5, 0.5),
      -- a placeholder only: fitSpot resizes this from the control's own bounds
      -- the first frame it is hovered, and again whenever those bounds change
      Size = UDim2.fromOffset(opts.spotSize or 150, opts.spotSize or 150),
      BackgroundTransparency = 1,
      Image = A.img.glow,
      ImageColor3 = opts.spotColour or T.c.accent,
      ImageTransparency = 1,
      ZIndex = (frame.ZIndex or 1) + 2,
      Name = "Spot", Parent = spotHost,
    })
  end

  local state = { hovered = false, pressed = false, enabled = true }

  -- A GRADIENT MULTIPLIES, SO ADDING ONE MADE THE HOVER DIMMER.
  --
  -- The fill gradient above does not add light to the wash, it scales it. At the
  -- old flat 0.94 the arithmetic works out as:
  --
  --   opacity           = 1 - 0.94                       = 0.060  (was uniform)
  --   with the gradient = 0.060 * (1 - 0.10) at the base = 0.054
  --                       0.060 * (1 - 1.00) at the top  = 0.000
  --
  -- So the "brighter" bottom edge was fractionally DARKER than the flat tint it
  -- replaced, and the top half lost its wash entirely -- a net loss of hover
  -- feedback, which is the opposite of the point. These are the levels that put
  -- the base meaningfully above the old flat value while still letting the top
  -- go dark for the rim to read against:
  --
  --   base 1 - 0.88 = 0.120, times 0.90 = 0.108   -- 1.8x the old wash
  --   top                                = 0.000   -- rim has something to sit on
  local HOVER = opts.hoverAlpha or 0.88
  local PRESS = opts.pressAlpha or 0.80

  -- PRESS FEEDBACK IS A STROKE WHEREVER A LAYOUT IS WATCHING.
  --
  -- The obvious move is to shrink the control slightly on press. Re-measured on
  -- a live client before touching this, because "a scale would break the layout"
  -- is the kind of claim that ages badly:
  --
  --   4 rows of 40 px in a UIListLayout, UIScale 0.90 on row 2
  --     row 2 AbsoluteSize.Y   40 -> 36
  --     rows 3 and 4 shift     -4 px each
  --
  -- So it is true, and it is true for any scale: at 0.985 the shift is only
  -- ~0.6 px, but it lands on every row below AND reverses on release, so a list
  -- twitches each time you click anything in it. An accent edge that flares and
  -- fades confirms the press without touching layout at all.
  --
  -- But most of what the reference clip shows are BUTTONS, not rows -- dock
  -- pills, header actions, the command centre -- and those have no layout to
  -- disturb. Those get the dip, because forty milliseconds of movement is most
  -- of what makes a button feel physical. The test is simply whether anything
  -- is currently positioning this frame for us.
  local edge = mk("UIStroke", {
    Color = T.c.accent, Thickness = 1.4, Transparency = 1,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame,
  })

  -- Is something else positioning this frame? Two effects need the answer -- the
  -- press dip, which would shove siblings, and the bloom, which would spill onto
  -- them -- so it is worked out once here rather than in each.
  local governedBy = frame.Parent and (frame.Parent:FindFirstChildWhichIsA("UIListLayout")
                   or frame.Parent:FindFirstChildWhichIsA("UIGridLayout")
                   or frame.Parent:FindFirstChildWhichIsA("UITableLayout")) or nil
  local governed = governedBy ~= nil

  -- A UIScale changes the MEASURED size -- that is the whole reason a governed
  -- row reflows -- so scale an INNER node and leave the outer frame alone. The
  -- layout keeps measuring a frame that never changes; the content dips inside
  -- it. Two frames cannot host it: one that sizes itself to its children (a
  -- fromScale child contributes nothing to AutomaticSize, so the row collapses)
  -- and one running its own layout (that layout would be left positioning a
  -- single object). Both keep the stroke-only press they have today.
  local dip
  local pressScale
  if opts.dip ~= false then
    if not governed then
      pressScale = mk("UIScale", { Scale = 1, Parent = frame })
    elseif frame.AutomaticSize == Enum.AutomaticSize.None
       and not frame:FindFirstChildWhichIsA("UILayout") then
      dip = mk("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = frame.ZIndex or 1,
        Name = "Dip", Parent = frame,
      })
      pressScale = mk("UIScale", { Scale = 1, Parent = dip })
    end
  end

  -- ---- rim light and bloom --------------------------------------------
  --
  -- THE RIM IS WHAT SELLS IT. In the reference the pill has a bright thin arc
  -- along its TOP edge that fades away by the sides -- the specular you get when
  -- a light sits above a rounded, slightly glossy surface. A stroke of uniform
  -- brightness reads as a border; the same stroke with a vertical gradient
  -- reads as a lit edge, and it costs one UIGradient.
  --
  -- The bloom is a sibling INSIDE the frame rather than outside it, so a caller
  -- that reparents or destroys the control takes the glow with it. Oversized on
  -- purpose: it is meant to spill past the edge.
  local bloom
  local rimGrad = mk("UIGradient", {
    Rotation = 90,
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0.00, 0.00),
      NumberSequenceKeypoint.new(0.30, 0.35),
      NumberSequenceKeypoint.new(1.00, 0.85),
    }),
    Parent = edge,
  })
  if A.img and A.img.glow then
    -- SPILLING IS RIGHT FOR A BUTTON AND WRONG FOR A ROW.
    --
    -- 1.9 of the host's height is a deliberate overshoot on something standing
    -- on its own -- a dock pill, a header action -- where there is nothing
    -- beside it to light up. Inside a list it is a leak. Measured on the nav
    -- rail: a 300x73 row grew a 403x139 bloom, +33 px past each edge into a
    -- 4 px gap, so hovering one row lit 29 px of the row above AND the row
    -- below. On a recording it reads as the glow following the cursor around
    -- the whole rail rather than sitting under it.
    --
    -- So the vertical overshoot is spent only where there is room for it: half
    -- the layout's own gap, and no more. The horizontal 1.34 is kept either way
    -- -- a vertical list has nothing to its left or right to contaminate.
    local yScale = 1.9
    if governed then
      local gap = 0
      pcall(function() gap = governedBy.Padding.Offset end)
      local h = frame.AbsoluteSize.Y
      local sc = (L.Hub and L.Hub.window and L.Hub.window.scaleObj
                  and L.Hub.window.scaleObj.Scale) or 1
      h = h / math.max(sc, 0.01)
      yScale = (h > 1) and math.clamp(1 + (gap * 0.5) / h, 1, 1.9) or 1
    end
    bloom = mk("ImageLabel", {
      AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
      Size = UDim2.fromScale(1.34, yScale), BackgroundTransparency = 1,
      Image = A.img.glow, ImageColor3 = opts.spotColour or T.c.accent,
      ImageTransparency = 1, ZIndex = math.max(1, (frame.ZIndex or 1) - 1),
      Name = "Bloom", Parent = frame,
    })
  end

  local function apply()
    local a = 1
    if state.enabled then
      if state.pressed then a = PRESS
      elseif state.hovered then a = HOVER end
    end
    M.to(layer, "BackgroundTransparency", a, "instant")
    -- these are the values at the TOP of the stroke; the rim gradient takes the
    -- sides and the base down from here, so a flat 0.78 read as almost nothing
    -- once it was in place
    M.to(edge, "Transparency",
      (state.enabled and state.pressed) and 0.20
      or (state.enabled and state.hovered) and 0.68 or 1, "instant")
    if spot then
      -- the light flares under the finger on press, then settles back
      local base = opts.spotAlpha or SPOT_REST
      M.to(spot, "ImageTransparency",
        (state.enabled and state.pressed) and math.max(0, base - 0.20)
        or (state.enabled and state.hovered) and base or 1, "fast")
    end

    local live = state.enabled and (state.hovered or state.pressed)
    if bloom then
      M.to(bloom, "ImageTransparency",
        state.pressed and 0.68 or (live and 0.82 or 1), "fast")
    end
    if rimGrad then
      -- the rim brightens toward uniform on press: a lit edge tipping to face
      -- the light, rather than a second colour appearing from nowhere
      M.to(rimGrad, "Offset", Vector2.new(0, state.pressed and 0.12 or 0), "fast")
    end
    if pressScale then
      M.to(pressScale, "Scale", state.pressed and 0.978 or 1, "fast")
    end
    if opts.onState then opts.onState(state) end
  end

  -- CENTRED ON THE POINTER, EXACTLY. Two different offsets have to cancel or the
  -- light sits away from the cursor instead of under it, and the first version
  -- got both wrong:
  --
  --   INSET.  Both directions of this were asserted in this file at different
  --           times and the sign was wrong. It is now measured once in
  --           lm_00_core and applied by L.pointerIn; do not re-derive it here.
  --   SCALE.  AbsolutePosition is real pixels, a UDim2 offset is pre-UIScale.
  --
  -- Read from GetMouseLocation rather than from MouseMoved's arguments, so there
  -- is one source of truth for where the pointer is and one correction applied
  -- to it. With AnchorPoint at 0.5 the bloom then centres on the cursor exactly.
  -- ONE FOLLOWER FOR THE WHOLE HUB, NOT ONE PER CONTROL.
  --
  -- Only one thing can be under the pointer at a time, so a RenderStepped per
  -- interactive control means ~60 connections firing every frame to have 59 of
  -- them return immediately. The hovered control publishes itself to A._hover
  -- and a single shared loop drives it -- which also means the follower can be
  -- pointed at a control from outside and its accuracy measured, instead of
  -- being reachable only by a real hand on a real mouse.
  -- SET, NOT TWEENED, AND EVERY FRAME.
  --
  -- The arithmetic below was already correct -- verified at (0, -1) px -- and the
  -- glow still did not sit on the cursor, because the position was going through
  -- M.to. That is a spring: it EASES toward the target, so the light was always
  -- travelling to where the pointer had just been. Worse, it was driven off
  -- MouseMoved, which fires less often than the screen redraws, so between
  -- events it did not move at all. A cursor light has no business being
  -- animated -- it is not going anywhere the pointer is not.
  --
  -- Both corrections now live in L.pointerIn, measured rather than reasoned
  -- about. The claim that once stood here -- that GetMouseLocation excludes the
  -- topbar inset -- was the bug, not the fix.
  local function moveSpot()
    if spot then A.aimSpot(frame, spot) end   -- no dt: snaps, for the enter frame
  end

  btn.MouseEnter:Connect(function()
    state.hovered = true
    -- fired on ENTER only, never held: a highlight that loops while the pointer
    -- rests is a busy row, and thirty of them is a page that will not sit still
    if sweepGrad and state.enabled then
      M.set(sweepGrad, "Offset", Vector2.new(-1.2, 0))
      M.to(sweepGrad, "Offset", Vector2.new(1.2, 0), "slow")
    end
    if spot and state.enabled then
      -- placed where the pointer entered BEFORE it is faded up, so the light
      -- never appears mid-flight from wherever it was last hovered
      moveSpot()
      M.to(spot, "ImageTransparency", opts.spotAlpha or SPOT_REST, "base")
      A._hover = { frame = frame, spot = spot, rim = rimGrad }
    end
    apply()
  end)
  btn.MouseLeave:Connect(function()
    state.hovered, state.pressed = false, false
    -- only surrender the follower if it is still ours: entering the next control
    -- fires before this leaves, and clearing unconditionally would kill the glow
    -- that just took over
    if A._hover and A._hover.spot == spot then A._hover = nil end
    if spot then M.to(spot, "ImageTransparency", 1, "base") end
    apply()
  end)
  btn.MouseButton1Down:Connect(function()
    if not state.enabled then return end
    state.pressed = true apply()
  end)
  btn.MouseButton1Up:Connect(function() state.pressed = false apply() end)
  btn.Activated:Connect(function()
    if not state.enabled then return end
    if opts.onClick then if L.Giorgio then L.Giorgio.sound("click",.35) end; L.try("atoms.click", opts.onClick) end
  end)

  -- ---- keep our overlays off the frame's own buttons -----------------------
  --
  -- Under ZIndexBehavior.Sibling the click is decided at the TOP level of this
  -- frame, not by the raw ZIndex under the cursor: every descendant rides in
  -- its parent's slot. So a button nested in a content frame loses to the Hit
  -- overlay above it no matter how high that button's own ZIndex is, and the
  -- container silently swallows the click. Lift any content branch that
  -- carries buttons of its own clear of the overlays. Transparent, inactive
  -- frames do not take input, so the container stays clickable in the gaps.
  local guard = (frame.ZIndex or 1) + 6
  -- FindFirstChildWhichIsA searches DESCENDANTS, so a child that is itself the
  -- input was missed: the slider's click-to-type readout is a childless
  -- TextButton and its entry -- like every input row's field -- is a TextBox.
  -- Both sat under the overlay and stopped responding.
  local function takesInput(o)
    return o:IsA("GuiButton") or o:IsA("TextBox")
       or o:FindFirstChildWhichIsA("GuiButton", true) ~= nil
       or o:FindFirstChildWhichIsA("TextBox", true) ~= nil
  end
  local lifted = false
  for _, child in ipairs(frame:GetChildren()) do
    if child:IsA("GuiObject") and child ~= layer and child ~= btn
       and child ~= dip and child ~= bloom
       and child.Name ~= "Sweep" and child.Name ~= "SpotHost" then
      if child.ZIndex < guard and takesInput(child) then
        child.ZIndex = guard
        lifted = true
      end
      -- the dip host takes the content; the overlays and the bloom stay put
      if dip then child.Parent = dip end
    end
  end
  -- A branch lifted INSIDE the host still rides in the host's slot, so the lift
  -- has to reach the host or the overlay goes straight back to swallowing it.
  if dip and lifted then dip.ZIndex = guard end

  return {
    button = btn, layer = layer, edge = edge, state = state,
    setEnabled = function(v)
      state.enabled = v and true or false
      apply()
    end,
  }
end

-- ---------------------------------------------------------------- tooltips
--
-- A LABEL CUT SHORT IS A PROMISE THE INTERFACE BROKE. Truncating is the right
do
  local tipGui, tipFrame, tipLbl, tipTitle
  local DWELL = 0.35            -- do not flash at every label swept past
  local shownFor, hoverSince, hovered = nil, 0, nil

  local function ensure()
    if tipFrame and tipFrame.Parent then return end
    tipGui = mk("ScreenGui", {
      Name = "DaewidLumenTip", ResetOnSpawn = false, IgnoreGuiInset = true,
      ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 60,
    })
    tipGui.Parent = L.host()
    L.own(tipGui)
    -- BUILT AT ITS RESTING VALUES, then faded out and hidden.
    --
    -- A.fadeSet captures rest ONCE, on first use, and ignores anything already
    -- sitting at full transparency. Building this card invisible and letting the
    -- first show() capture it therefore recorded "gone" as the resting state for
    -- every text layer in it -- the card would open with its stroke and its
    -- background and no words inside. Build it lit, snapshot it, then put it
    -- away.
    -- NO OUTLINE ON THE TOOLTIP. Asked for directly, and it was the right call.
    --
    -- A 1 px dark border is the single worst thing to fade. A filled background
    -- reads as gone by roughly 0.6 transparency; a thin dark line against a
    -- bright game world is still plainly a line at 0.85. So the card dissolves
    -- and leaves its own edge hanging in the air after it -- and that happens
    -- even though the stroke WAS in the fade set, on the same clock, as of P1.
    -- There is no timing fix available: the outline itself is the problem.
    --
    -- The card does not need one. It is a near-black panel drawn over whatever
    -- the game is rendering, and a soft shadow separates it far better than a
    -- border does -- while fading honestly, because an image's alpha is spread
    -- over area instead of concentrated in a hairline.
    --
    -- STRUCTURE, and it matters: a child ALWAYS draws above its parent's own
    -- background, so a shadow parented to the card would sit on top of it as a
    -- dark smear. The outer frame is therefore an empty container, and the
    -- shadow and the card are siblings inside it.
    tipFrame = mk("Frame", {
      BackgroundTransparency = 1, BorderSizePixel = 0,
      Size = UDim2.fromOffset(10, 24),
      Name = "Tip", Parent = tipGui,
    })
    mk("ImageLabel", {
      AnchorPoint = Vector2.new(0.5, 0.5),
      Position = UDim2.new(0.5, 0, 0.5, 4),
      Size = UDim2.new(1, 34, 1, 30),
      BackgroundTransparency = 1,
      Image = A.img.glow, ImageColor3 = Color3.new(0, 0, 0),
      ImageTransparency = 0.34, ZIndex = 1,
      Name = "TipShadow", Parent = tipFrame,
    })
    local card = mk("Frame", {
      Size = UDim2.fromScale(1, 1),
      BackgroundColor3 = T.c.overlay, BackgroundTransparency = 0,
      BorderSizePixel = 0, ZIndex = 2,
      Name = "TipCard", Parent = tipFrame,
    })
    L.corner(T.r.sm, card)
    tipTitle = A.text({
      Text = "", font = T.font.medium, size = T.size.micro, colour = T.c.text,
      align = Enum.TextXAlignment.Left, valign = Enum.TextYAlignment.Top,
      Size = UDim2.new(1, -20, 0, 14), ZIndex = 3,
      Position = UDim2.fromOffset(10, 8), tip = false, Parent = card,
    })
    tipLbl = A.text({
      Text = "", font = T.font.body, size = T.size.micro, colour = T.c.textDim,
      align = Enum.TextXAlignment.Left, valign = Enum.TextYAlignment.Top,
      Size = UDim2.new(1, -20, 0, 14), ZIndex = 3,
      Position = UDim2.fromOffset(10, 8), tip = false, Parent = card,
    })
    A.fadeSet(tipFrame)                -- rest snapshot, while it is still lit
    A.fadeTo(tipFrame, 1, "instant")
    tipFrame.Visible = false
  end

  -- TEXTBOUNDS IS THE WRONG PROPERTY, AND MEASURED IT IS EXACTLY BACKWARDS. On a
  -- label with TextTruncate.AtEnd, TextBounds reports the width of what was
  -- actually DRAWN -- which is by definition never wider than the box -- so
  -- `TextBounds.X > AbsoluteSize.X` cannot be true even once. A row reading
  -- "the game rewrote WalkSpeed 47 times in the l..." measured TextBounds 459
  -- inside a 494 box while its full string needs 697. The untruncated width has
  -- to be asked for separately, and TextService is the only thing that knows it.
  local TextService = game:GetService("TextService")
  local function truncated(l)
    if l.Text == "" or l.AbsoluteSize.X < 8 then return false end
    local ok, sz = pcall(function()
      return TextService:GetTextSize(l.Text, l.TextSize, l.Font,
                                     Vector2.new(9999, 100))
    end)
    return (ok and sz and sz.X > l.AbsoluteSize.X + 0.5) and true or false
  end

  -- A RECTANGLE TEST ALONE ASKS "WHERE IS IT", NEVER "CAN YOU SEE IT".
  --
  -- This is the tooltip explaining something that is not on your screen. Every
  -- registered label was tested by its AbsolutePosition and nothing else, and
  -- AbsolutePosition is perfectly real for a control on a tab you are not
  -- looking at -- pages are hidden by fading their CanvasGroup, NOT by setting
  -- Visible = false, so `l.Visible` is true and `l.TextTransparency` is still 0
  -- on every page at once. Eleven pages of controls were all live hit targets,
  -- stacked on the same coordinates.
  --
  -- Which is exactly what the recording shows: "Heavy rig showed 0 adjusted
  -- studs locally -- trying Teleport (clean)" -- a fling log line off the
  -- Activity page -- floating over the Config page under a pointer that had
  -- never been near it.
  --
  -- Three things make a label unreachable, and the rect test knows none of them:
  --
  --   an ancestor is Visible = false, or its ScreenGui is disabled
  --   an ancestor CanvasGroup is faded out          <- the inactive pages
  --   a clipping ancestor does not contain the point <- scrolled out of view
  --
  -- Walked once per candidate, and only for candidates the rectangle already
  -- accepted, so the cost lands on one or two objects rather than on hundreds.
  local function reachable(o, pt)
    local n = o
    while n and n ~= game do
      if n:IsA("GuiObject") then
        if not n.Visible then return false end
        -- a clipping ancestor is the only thing that can hide a child that is
        -- itself Visible, and a ScrollingFrame always clips
        if n.ClipsDescendants or n:IsA("ScrollingFrame") then
          local p, sz = n.AbsolutePosition, n.AbsoluteSize
          if pt.X < p.X or pt.X > p.X + sz.X
             or pt.Y < p.Y or pt.Y > p.Y + sz.Y then return false end
        end
        if (n:IsA("CanvasGroup") or n:GetAttribute("GiorgioFadeGroup")) and L.uiRead(n,"GroupTransparency") > 0.5 then return false end
      elseif n:IsA("ScreenGui") then
        if not n.Enabled then return false end
        return true
      end
      n = n.Parent
    end
    return true
  end

  local function under(pt)
    -- Rectangle tests first, measurement second. GetTextSize on every registered
    -- label at 10 Hz would be several hundred text measurements a second to
    -- decide one tooltip; only what the pointer is actually over gets measured.
    local hits, hints
    for i = #A.tips, 1, -1 do
      local l = A.tips[i]
      if not l.Parent then
        table.remove(A.tips, i)                 -- prune rebuilt windows
      elseif l.Visible and l.TextTransparency < 0.9 then
        local p, s = l.AbsolutePosition, l.AbsoluteSize
        if pt.X >= p.X and pt.X <= p.X + s.X and pt.Y >= p.Y and pt.Y <= p.Y + s.Y
           and reachable(l, pt) then
          hits = hits or {}
          hits[#hits + 1] = l
        end
      end
    end
    -- explicit explanations, which need no measurement: if the pointer is over
    -- it, it has something to say
    for i = #A.hints, 1, -1 do
      local h = A.hints[i]
      if not (h.obj and h.obj.Parent) then
        table.remove(A.hints, i)
      elseif h.obj.Visible then
        local p, s = h.obj.AbsolutePosition, h.obj.AbsoluteSize
        if s.X > 0 and pt.X >= p.X and pt.X <= p.X + s.X
           and pt.Y >= p.Y and pt.Y <= p.Y + s.Y
           and reachable(h.obj, pt) then
          hints = hints or {}
          hints[#hints + 1] = h
        end
      end
    end
    if hints then
      table.sort(hints, function(a, b) return (a.obj.ZIndex or 0) > (b.obj.ZIndex or 0) end)
      local h = hints[1]
      return { key = h.obj, text = h.text, label = h.label, src = h.obj }
    end

    if not hits then return nil end
    -- topmost first, so a value label wins over the row title stacked behind it
    table.sort(hits, function(a, b) return a.ZIndex > b.ZIndex end)
    for _, l in ipairs(hits) do
      if truncated(l) then return { key = l, text = l.Text, src = l } end
    end
    return nil
  end

  local function hide()
    if not tipFrame or not tipFrame.Visible then return end
    shownFor = nil
    -- the whole card, stroke included -- see A.fadeTo
    A.fadeTo(tipFrame, 1, "fast")
    M.after(0.22, function()
      if tipFrame and not shownFor then tipFrame.Visible = false end
    end)
  end

  local function show(l, pt)
    ensure()
    shownFor = l.key or l
    tipLbl.Text = l.text or ""
    tipTitle.Text = l.label or ""
    tipTitle.Visible = (l.label ~= nil and l.label ~= "")

    -- SCALED BY HAND, NOT BY A UISCALE. Everything here is positioned and
    -- measured in absolute pixels; a UIScale on the host would silently
    -- multiply all of it and put the tooltip in the wrong place at the wrong
    -- size. Scaling the one font instead keeps the arithmetic honest and still
    -- matches the rest of the interface at 1.6x.
    local win = L.Hub and L.Hub.window
    local sc = (win and win.scaleObj and win.scaleObj.Scale) or L.autoScale()
    tipLbl.TextSize = math.max(9, math.floor(T.size.micro * sc + 0.5))

    -- SIZED FROM THE FULL STRING, measured in the TOOLTIP's own font -- not from
    -- the source label's TextBounds, which is the truncated width and would size
    -- the tooltip to exactly the space that was too small in the first place.
    -- (It did: a 697 px string got a 475 px tooltip, clipping the text the
    -- tooltip existed to reveal.)
    local vp = L.viewport()
    local maxW = math.floor(vp.X * 0.6)
    local pad = math.ceil(8 * sc)
    -- MEASURE THE STRING THIS TOOLTIP IS ACTUALLY SHOWING.
    --
    -- `under()` hands back a plain descriptor, `{ key = ..., text = ... }` --
    -- never an Instance. So `l.Text` was always nil, GetTextSize always threw,
    -- and the fallback then read `l.AbsoluteSize.X` off the same plain table:
    --
    --     attempt to index nil with 'X'
    --
    -- Every hint tooltip in the interface hit it, on every hover. The text is
    -- already on `tipLbl`; measure that, and fall back to the frame we have.
    tipTitle.TextSize = tipLbl.TextSize
    local body  = tipLbl.Text
    local head  = tipTitle.Visible and tipTitle.Text or nil
    local padY  = math.ceil(7 * sc)
    local gapY  = math.ceil(2 * sc)

    local function widthOf(str, lbl)
      if not str or str == "" then return 0 end
      local ok, z = pcall(function()
        return TextService:GetTextSize(str, lbl.TextSize, lbl.Font,
                                       Vector2.new(9999, 200))
      end)
      return (ok and z) and z.X or (#str * lbl.TextSize * 0.55)
    end

    -- the card is as wide as its widest line, never wider than the cap
    local w = pad * 2 + math.ceil(math.max(widthOf(body, tipLbl),
                                           widthOf(head, tipTitle)))
    local lineH = math.ceil(tipLbl.TextSize * 1.35)
    local bodyH = lineH

    -- past the cap it wraps instead of clipping, because a tooltip that runs off
    -- the screen has reproduced the original problem in a larger font
    if w > maxW then
      w = maxW
      tipLbl.TextWrapped = true
      local okw, wz = pcall(function()
        return TextService:GetTextSize(body, tipLbl.TextSize, tipLbl.Font,
                                       Vector2.new(maxW - pad * 2, 9999))
      end)
      bodyH = (okw and wz) and math.ceil(wz.Y) or lineH
    else
      tipLbl.TextWrapped = false
    end

    local headH = head and lineH or 0
    local h = padY * 2 + headH + (head and gapY or 0) + bodyH
    tipTitle.Position = UDim2.fromOffset(pad, padY)
    tipTitle.Size     = UDim2.new(1, -pad * 2, 0, headH)
    tipLbl.Position   = UDim2.fromOffset(pad, padY + headH + (head and gapY or 0))
    tipLbl.Size       = UDim2.new(1, -pad * 2, 0, bodyH)
    -- a lone line is the message, so it gets the message colour; under a heading
    -- it is supporting text and steps back
    tipLbl.TextColor3 = head and T.c.textDim or T.c.text
    tipFrame.Size = UDim2.fromOffset(w, h)

    -- Positioned in tipGui's own space. The claim that used to stand here --
    -- that GetMouseLocation is measured below the topbar -- is false; it is the
    -- inset-INCLUDED reading, so adding the inset to it dropped every tooltip
    -- 58 px. L.pointerOffset asks tipGui which space it is in and answers in
    -- that space, so this stays correct if the ScreenGui's flags ever change.
    -- IT BELONGS TO THE CONTROL, NOT TO THE POINTER.
    --
    -- A card pinned 14 px right and 20 px down from the cursor is a cursor
    -- accessory: it slides around under the hand, it covers whatever is to the
    -- lower right, and it never quite points at the thing it is describing. The
    -- reference does the opposite -- the card sits centred just above the
    -- control and stays put while the pointer moves inside it, so it reads as
    -- that control speaking.
    --
    -- The pointer is still the fallback, for anything that reports no rect.
    local anchor = L.pointerOffset(tipGui)
    local gap = math.ceil(8 * sc)
    local x, y, from
    local src = l.src
    if src and src.Parent and src.AbsoluteSize.X > 0 then
      -- AbsolutePosition is inset-EXCLUDED; tipGui ignores the inset, so the
      -- offset between the two spaces has to be put back. L.pointerOffset
      -- already answers in tipGui's space, and L.pointer() in AbsolutePosition
      -- space, so their difference IS that offset -- no second inset call, and
      -- it stays right if the ScreenGui's flags ever change.
      local shift = anchor - L.pointer()
      local p, sz = src.AbsolutePosition + shift, src.AbsoluteSize
      x = p.X + sz.X * 0.5 - w * 0.5
      y = p.Y - h - gap
      from = y + math.ceil(6 * sc)            -- rises into place
      if y < 6 then                            -- no room above: sit below it
        y = p.Y + sz.Y + gap
        from = y - math.ceil(6 * sc)           -- and drops into place
      end
    else
      x = anchor.X + 14
      y = anchor.Y + 20
      if y + h > vp.Y - 6 then y = anchor.Y - h - 10 end
      from = y + 6
    end
    x = math.clamp(x, 6, math.max(vp.X - w - 6, 6))
    y = math.clamp(y, 6, math.max(vp.Y - h - 6, 6))

    -- Snap to the start of the travel, THEN reveal. Setting Position with M.to
    -- from wherever the last tooltip happened to be would fly the card across
    -- the screen between two unrelated controls.
    M.to(tipFrame, "Position", UDim2.fromOffset(x, math.floor(from)), "instant")
    tipFrame.Visible = true
    M.to(tipFrame, "Position", UDim2.fromOffset(x, y), "base")
    A.fadeTo(tipFrame, 0, "fast")
  end

  local acc = 0
  L.hold(L.RunService.Heartbeat:Connect(function(dt)
    if not L.live() then return end
    acc = acc + dt
    if acc < 0.1 then return end                -- 10 Hz is under human notice
    acc = 0
    local win = L.Hub and L.Hub.window
    if (not win) or (win.hidden and #A.hints == 0)
       or (#A.tips == 0 and #A.hints == 0) then
      if hovered then hovered = nil hide() end
      return
    end
    -- INSET-EXCLUDED, because `under` tests against AbsolutePosition. This used
    -- to pass GetMouseLocation straight in, which is the inset-INCLUDED value,
    -- so the tooltip hit test was 58 px below the label it was testing: rows
    -- claimed the pointer while it was still over the row above them.
    local pt = L.pointer()
    local l = under(pt)
    local key = l and l.key or nil
    if key ~= hovered then
      hovered, hoverSince = key, os.clock()
      if shownFor and shownFor ~= key then hide() end
    elseif l and not shownFor and (os.clock() - hoverSince) >= DWELL then
      show(l, pt)
    end
  end))
end

end
