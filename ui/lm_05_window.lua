do -- ==== lm_05_window.lua ====
-- LUMEN :: WINDOW
-- The panel: header, nav, pages, drag, resize, minimise.
--
-- Two coordinate systems meet here. The window sits under a UIScale, so Position
-- OFFSETS are pre-scale units while the mouse reports real pixels. Anything
-- mixing the two must convert, and the drag does it as a delta from the grab
-- point so the constant offset cancels.

local L = getgenv().__DAEWID_BALL_LUMEN
local T, M, A = L.T, L.Motion, L.A
local mk = L.mk

local Window = {}
Window.__index = Window
L.Window = Window

-- read per construction so a density change takes effect on rebuild
local HEADER, SIDEBAR, TAB_H

Window.BLUR = 16

-- ---------------------------------------------------------------- mark
function Window.mark(parent, size)
  local h = mk("Frame", {
    Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1,
    Name = "Mark", Parent = parent,
  })
  local outer = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(size * 0.72, size * 0.72), Rotation = 45,
    BackgroundColor3 = T.c.accent, BorderSizePixel = 0, Parent = h,
  })
  L.corner(size * 0.18, outer)
  A.accentGradient(outer, 135)
  local inner = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(size * 0.28, size * 0.28), Rotation = 45,
    BackgroundColor3 = T.c.surface, BorderSizePixel = 0, ZIndex = 3, Parent = h,
  })
  L.corner(size * 0.08, inner)
  return h
end

-- ---------------------------------------------------------------- construct

function Window.new(opts)
  opts = opts or {}
  HEADER, SIDEBAR, TAB_H = T.px("header"), T.px("sidebar"), T.px("tab")
  local self = setmetatable({}, Window)
  self.tabs, self.active = {}, nil
  self.width  = opts.width or 880
  self.height = opts.height or 556
  self.minW, self.minH = 660, 430
  self.cascade = (L.Cfg and tonumber(L.Cfg.data.cascade)) or 0.035

  -- geometry is remembered across sessions; a tool that forgets where you put it
  -- makes you re-place it every launch
  local g = L.Cfg and L.Cfg.data.geom
  if type(g) == "table" and tonumber(g.w) and tonumber(g.h) then
    local vp = L.viewport()
    self.width  = math.clamp(tonumber(g.w), self.minW, math.max(vp.X - 40, self.minW))
    self.height = math.clamp(tonumber(g.h), self.minH, math.max(vp.Y - 40, self.minH))
    self._restorePos = (tonumber(g.x) and tonumber(g.y))
      and UDim2.fromOffset(tonumber(g.x), tonumber(g.y)) or nil
  end

  local gui = mk("ScreenGui", {
    Name = opts.guiName or "DaewidLumen", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
    DisplayOrder = 10,
  })
  gui.Parent = L.host()
  L.own(gui)
  self.gui = gui
  -- a saved scale wins over the auto-fit; nil means "fit this screen"
  local savedScale = L.Cfg and tonumber(L.Cfg.data.scale)
  self.scaleObj = mk("UIScale", { Scale = savedScale or L.autoScale(), Parent = gui })

  self.scrim = mk("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.c.scrim,
    BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
    Name = "Scrim", Parent = gui,
  })

  local shell = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(self.width, self.height),
    BackgroundTransparency = 1, ZIndex = 2, Name = "Shell", Parent = gui,
  })
  self.shell = shell

  -- MEASURE ALWAYS, INCLUDING ON RESTORE.
  --
  -- Collapse the scale term before anything can drag it: Position starts as
  -- fromScale(0.5,0.5) but _saveGeom records only offsets, so a drag would
  -- persist numbers relative to a term nobody stored. Measured, not derived --
  -- one sample at offset zero pins the constant. Two frames, still hidden.
  --
  -- The restore path used to skip all of this and assign the saved offset
  -- straight in. It is a RAW OFFSET IN LOCAL UNITS, recorded under whatever
  -- UIScale and viewport that session happened to have, so on any other screen
  -- it lands somewhere else entirely. Measured on 2560x1369 at scale 1.6: a
  -- saved offset of (134, 5), centre-anchored, put AbsolutePosition at
  -- (-314, -510) -- three quarters of the window above and left of the screen,
  -- with the title bar off the top, so it could not even be dragged back.
  --
  -- Width and height were already clamped to the viewport above. Position was
  -- the one piece of remembered geometry still trusting the old session.
  task.spawn(function()
    L.RunService.Heartbeat:Wait()
    if not shell.Parent then return end
    shell.Position = UDim2.fromOffset(0, 0)
    L.RunService.Heartbeat:Wait()
    if not shell.Parent then return end
    local k = shell.AbsolutePosition
    local sc = (self.scaleObj and self.scaleObj.Scale) or 1
    local vp = L.viewport()
    local sz = shell.AbsoluteSize

    local want
    if self._restorePos then
      -- where that saved offset actually lands on THIS screen
      want = Vector2.new(self._restorePos.X.Offset * sc + k.X,
                         self._restorePos.Y.Offset * sc + k.Y)
    else
      -- centre it PROPERLY. fromScale(0.5,0.5) was landing 59 px high, because
      -- AbsolutePosition and ScreenGui space disagree about the topbar inset --
      -- so the window used to open slightly above the middle of the screen.
      want = Vector2.new(vp.X / 2 - sz.X / 2, vp.Y / 2 - sz.Y / 2)
    end

    -- Keep it reachable. A window larger than the screen is pinned to the
    -- top-left corner rather than centred, because the title bar has to stay
    -- on screen -- it is the only handle for moving it.
    local M_ = 8
    local function fit(v, size, limit)
      if size >= limit then return math.clamp(v, limit - size, 0) end
      return math.clamp(v, M_, limit - size - M_)
    end
    want = Vector2.new(fit(want.X, sz.X, vp.X), fit(want.Y, sz.Y, vp.Y))
    shell.Position = UDim2.fromOffset((want.X - k.X) / sc, (want.Y - k.Y) / sc)
  end)

  -- real drop shadow, in the SHELL so it sits outside the panel bounds
  -- HELD, NOT FIRE-AND-FORGET. This was created and never referenced again, so
  -- hide() faded the panel while the shadow stayed at full opacity until
  -- shell.Visible flipped 0.34 s later -- a black rounded rectangle hanging in
  -- the air after the window had gone.
  self.shadowSpread = 34
  self.shadow = A.shadow(nil, {
    Parent = shell, spread = self.shadowSpread, alpha = 0.34, lift = 10, ZIndex = 3 })
  self.shadowRest = (L.Cfg and tonumber(L.Cfg.data.shadow)) or 0.34

  local root = mk("CanvasGroup", {
    Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(self.width, self.height),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    GroupTransparency = 1, ZIndex = 5, Parent = shell,
  })
  L.corner(T.r.lg, root)
  L.stroke(T.c.lineStrong, 1, 0.3, root)
  self.root = root

  local bg = mk("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.c.surface,
    BorderSizePixel = 0, ZIndex = 0, Name = "Body", Parent = root,
  })
  L.corner(T.r.lg, bg)
  self.body = bg

  -- accent light bleeding from the top edge
  local wash = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 260), BackgroundColor3 = T.c.accent,
    BorderSizePixel = 0, ZIndex = 0, Name = "Wash", Parent = root,
  })
  self.wash = wash
  mk("UIGradient", {
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.925),
      NumberSequenceKeypoint.new(1, 1),
    }), Rotation = 90, Parent = wash,
  })

  -- ANIMATED BACKDROP. A blurred bloom has no high-frequency detail, so it is
  -- rendered at 320x200 and stretched across the whole panel with no visible
  -- loss -- the entire 48-frame loop is under half a megabyte. Sits at a resting
  -- transparency rather than opaque, so it lights the surface instead of
  -- becoming it.
  self.bgVid = L.Video and L.Video.new(bg, {
    folder = "lumen_fx/bg", prefix = "bg", count = 48, fps = 16, loop = true,
    Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5),
    -- 0.30 put the loop at 70% opacity and turned the whole panel blue-purple,
    -- which contradicts the entire near-black premise. At 0.86 it reads as light
    -- moving under the surface and you only notice it when it moves.
    ZIndex = 0, rest = 0.86,
  })
  if not (L.Cfg and L.Cfg.data.grain == false) then A.grain(bg, 0.955) end
  -- (the snap hint used to live here: a full-panel accent wash flashed on every
  -- edge snap. It went with the snapping itself -- see Window:_drag.)

  -- Native rounded pinstripe edges carry the window boundary.

  -- ---- header ---------------------------------------------------------
  local header = mk("Frame", {
    Size = UDim2.new(1, 0, 0, HEADER), BackgroundTransparency = 1,
    Name = "Header", Parent = root,
  })
  self.header = header

  -- The orb from the loading screen, small and strided. Same footage, so the
  -- window and the loader are unmistakably the same product.
  local orbHolder = mk("Frame", {
    Position = UDim2.fromOffset(20, HEADER / 2 - 21),
    Size = UDim2.fromOffset(42, 42), BackgroundTransparency = 1,
    Name = "OrbMark", Parent = header,
  })
  -- FULL SEQUENCE, NO STRIDE. `stride` divides the playback rate to preserve the
  -- loop duration, so stride 6 was running this at 5 fps while the loading screen
  local orbVid = L.Video and L.Video.new(orbHolder, {
    -- 5..96 is this sequence's loop -- 92 frames, the half-rate copy of the
    -- full Saturn's 183. The remaining frames of the folder do not close.
    folder = "lumen_fx/saturn_s", prefix = "sms", first = 5, count = 92, fps = 15, size = 42,
    Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2, loop = true,
  })
  A.glow(orbHolder, 104, T.c.accent, { alpha = 0.80, ZIndex = 1 })
  if not orbVid then Window.mark(orbHolder, 42) end
  self.orbVid = orbVid

  -- LIQUID CHROME WORDMARK, RENDERED OFFLINE. A Roblox TextLabel takes one flat
  local wmH = 42
  local wm = L.Video and L.Video.new(header, {
    folder = "lumen_fx/word", prefix = "wm", count = 60, fps = 20, loop = true,
    Size = UDim2.fromOffset(math.floor(wmH * 575 / 198), wmH),
    Position = UDim2.fromOffset(78 + math.floor(wmH * 575 / 198) / 2, 34),
    ZIndex = 2,
  })
  self.wordVid = wm
  if not wm then
    A.text({
      Text = L.track(opts.title or "LUMEN", 1),
      font = T.font.display, size = T.size.title,
      colour = T.c.text, Position = UDim2.fromOffset(78, 22),
      Size = UDim2.fromOffset(320, 20), Parent = header,
    })
  end
  self.searchHint = A.text({
    Text = "CTRL K", font = T.font.mono, size = T.size.tiny, colour = T.c.textOff,
    align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -190, 0.5, 0), Size = UDim2.fromOffset(60, 14),
    Parent = header,
  })
  self.subtitleLbl = A.text({
    Text = opts.subtitle or "", font = T.font.mono, size = T.size.tiny,
    colour = T.c.textOff, Position = UDim2.fromOffset(80, 58),
    Size = UDim2.fromOffset(360, 12), Parent = header,
  })

  local function chromeBtn(x, draw, onClick)
    local b = mk("Frame", {
      AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0),
      Size = UDim2.fromOffset(30, 30), BackgroundColor3 = T.c.hover,
      BackgroundTransparency = 1, BorderSizePixel = 0, Parent = header,
    })
    L.corner(T.r.sm + 2, b)
    local g = draw(b, 16, T.c.textMute)
    g.AnchorPoint = Vector2.new(0.5, 0.5)
    g.Position = UDim2.fromScale(0.5, 0.5)
    A.interactive(b, { radius = T.r.sm + 2, onClick = onClick,
                       hoverAlpha = 0.9, pressAlpha = 0.82 })
  end
  chromeBtn(-16, A.Icon.close, function() self:hide() end)
  chromeBtn(-50, A.Icon.minus, function() self:minimise() end)

  local pill = mk("Frame", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -88, 0.5, 0),
    Size = UDim2.fromOffset(88, 28), BackgroundColor3 = T.c.raised,
    BorderSizePixel = 0, Parent = header,
  })
  L.corner(999, pill)
  L.stroke(T.c.line, 1, 0.3, pill)
  local pdot = mk("Frame", {
    AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11, 0.5, 0),
    Size = UDim2.fromOffset(6, 6), BackgroundColor3 = T.c.ok,
    BorderSizePixel = 0, Parent = pill,
  })
  L.corner(999, pdot)
  self.pingLbl = A.text({
    Text = "-- ms", font = T.font.mono, size = T.size.tiny, colour = T.c.textDim,
    Position = UDim2.fromOffset(23, 0), Size = UDim2.new(1, -28, 1, 0), Parent = pill,
  })
  self.statusDot = pdot

  -- ---- health chip ------------------------------------------------------
  --
  -- HIDDEN WHILE THERE IS NOTHING TO SAY. A permanent "all good" badge is
  -- decoration: it trains you to stop reading it, so on the day it finally does
  -- say something you stopped looking weeks ago. This exists only when a claim
  -- the interface already made has since failed -- which is the only moment an
  -- indicator earns the space it takes.
  local health = mk("Frame", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -258, 0.5, 0),
    Size = UDim2.fromOffset(118, 26), BackgroundColor3 = T.c.raised,
    BackgroundTransparency = 1, BorderSizePixel = 0,
    Visible = false, Name = "Health", Parent = header,
  })
  L.corner(999, health)
  local healthStroke = L.stroke(T.c.warn, 1, 1, health)
  local hdot = mk("Frame", {
    AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11, 0.5, 0),
    Size = UDim2.fromOffset(6, 6), BackgroundColor3 = T.c.warn,
    BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = health,
  })
  L.corner(999, hdot)
  local hlbl = A.text({
    Text = "", font = T.font.mono, size = T.size.tiny, colour = T.c.warn,
    Position = UDim2.fromOffset(23, 0), Size = UDim2.new(1, -30, 1, 0),
    ZIndex = 2, Parent = health,
  })
  hlbl.TextTransparency = 1
  A.interactive(health, { radius = 999, onClick = function()
    if self.onHealth then L.try("window.onHealth", self.onHealth) end
  end })
  self.healthChip = health

  -- SAMPLED, NOT PUSHED. There is no event that means "a feature stopped
  -- working" -- that is precisely why it goes unnoticed -- so health is derived
  -- and polled, at a rate no one can distinguish from instant.
  local shownState
  task.spawn(function()
    while L.live() and health.Parent do
      local state, nf, nc = L.health()
      if state ~= shownState then
        shownState = state
        if state == "ok" then
          M.to(health, "BackgroundTransparency", 1, "fast")
          M.to(hlbl, "TextTransparency", 1, "fast")
          M.to(healthStroke, "Transparency", 1, "fast")
          M.to(hdot, "BackgroundTransparency", 1, "fast")
          -- hidden only after it has faded, so the chip stops eating clicks in
          -- the middle of the header -- which is also the window's drag handle
          M.after(0.3, function()
            if health.Parent and shownState == "ok" then health.Visible = false end
          end)
        else
          local col = (state == "fault") and T.c.bad or T.c.warn
          hdot.BackgroundColor3, hlbl.TextColor3, healthStroke.Color = col, col, col
          health.Visible = true
          M.to(health, "BackgroundTransparency", 0.06, "fast")
          M.to(hlbl, "TextTransparency", 0, "fast")
          M.to(healthStroke, "Transparency", 0.4, "fast")
          M.to(hdot, "BackgroundTransparency", 0, "fast")
        end
      end
      -- WORST FIRST, BUT NEVER AT THE COST OF HIDING THE REST. Showing only the
      -- fault count while two features were also contested meant fixing the
      -- fault made the chip vanish and took the contested features with it --
      -- the indicator would have gone quiet with the hub still lying.
      if state == "fault" then
        hlbl.Text = nc > 0
          and string.format("%d fault  +%d", nf, nc)
          or string.format("%d fault%s", nf, nf == 1 and "" or "s")
      elseif state ~= "ok" then
        hlbl.Text = string.format("%d contested", nc)
      end
      task.wait(0.4)
    end
  end)

  mk("Frame", {
    Position = UDim2.fromOffset(0, HEADER), Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = T.c.line, BackgroundTransparency = 0.35,
    BorderSizePixel = 0, Parent = root,
  })

  -- ---- sidebar --------------------------------------------------------
  -- THE SIDEBAR IS A TINT, NOT A SLAB. Painting it an opaque darker colour cut
  -- it out of the panel entirely: the bloom loop, the grain and the top accent
  -- wash all stopped at its edge, so it read as a black rectangle glued to a lit
  -- one. Semi-transparent black over the same body lets every one of those pass
  -- underneath, and it is still visibly recessed.
  local side = mk("Frame", {
    Position = UDim2.fromOffset(0, HEADER + 1),
    Size = UDim2.new(0, SIDEBAR, 1, -(HEADER + 1)),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.42,
    BorderSizePixel = 0,
    Name = "Sidebar", Parent = root,
  })
  local seam = mk("Frame", {
    Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0),
    BackgroundColor3 = T.c.accent, BorderSizePixel = 0, Parent = side,
  })
  mk("UIGradient", {
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 0.55),
      NumberSequenceKeypoint.new(0.55, 0.90),
      NumberSequenceKeypoint.new(1, 1),
    }),
    Rotation = 90, Parent = seam,
  })

  -- Scrolls once the tabs outgrow the sidebar. Ten tabs do not fit a shortened
  -- window, and a tab you cannot reach is a feature you do not have.
  self.navHolder = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 14), Size = UDim2.new(1, -24, 1, -84),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 2, ScrollBarImageColor3 = T.c.lineStrong,
    ScrollBarImageTransparency = 0.4, ScrollingDirection = Enum.ScrollingDirection.Y,
    ElasticBehavior = Enum.ElasticBehavior.Never,
    Name = "Nav", Parent = side,
  })

  -- indicator sits BEHIND the rows, in the same coordinate space
  self.pill = mk("Frame", {
    Size = UDim2.new(1, 0, 0, TAB_H), Position = UDim2.fromOffset(0, 0),
    BackgroundColor3 = T.c.accent, BackgroundTransparency = 0.82,
    BorderSizePixel = 0, Visible = false, Name = "Indicator",
    Parent = self.navHolder,
  })
  L.corner(T.r.md, self.pill)
  mk("UIGradient", {
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 0),
      NumberSequenceKeypoint.new(1, 1),
    }), Parent = self.pill,
  })

  self.pillBar = mk("Frame", {
    Size = UDim2.fromOffset(3, TAB_H * 0.45),
    Position = UDim2.fromOffset(-12, TAB_H * 0.275),
    BackgroundColor3 = T.c.accent, BorderSizePixel = 0, Visible = false,
    Name = "IndicatorEdge", Parent = self.navHolder,
  })
  L.corner(999, self.pillBar)
  A.accentGradient(self.pillBar, 90)

  -- AutomaticSize, not fromScale(1,1): inside a scrolling frame a full-height
  -- child pins the canvas to the viewport and nothing ever scrolls.
  self.navList = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1, Name = "NavItems", Parent = self.navHolder,
  })
  L.list(2, nil, self.navList)
  self._navOrder, self._navY, self._sections = 0, {}, {}
  self._navCursor = 0

  -- sidebar footer
  local foot = mk("Frame", {
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -14),
    Size = UDim2.new(1, -24, 0, 42), BackgroundTransparency = 1,
    Name = "Footer", Parent = side,
  })
  mk("Frame", {
    Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.c.line,
    BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = foot,
  })
  -- THE PLAYER'S ACTUAL HEADSHOT. This was a gradient placeholder I never went
  -- back and filled. `rbxthumb://` resolves a user thumbnail without a web
  -- request or a yield -- GetUserThumbnailAsync would block the build for a
  -- round trip, and this is the same image.
  local av = mk("ImageLabel", {
    Position = UDim2.fromOffset(0, 13), Size = UDim2.fromOffset(28, 28),
    BackgroundColor3 = T.c.raised, BorderSizePixel = 0,
    Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", L.LP.UserId),
    Parent = foot,
  })
  L.corner(T.r.sm + 1, av)
  L.stroke(T.c.lineStrong, 1, 0.45, av)
  self.avatar = av
  A.text({
    Text = L.LP.Name, font = T.font.medium, size = T.size.micro,
    colour = T.c.textDim, Position = UDim2.fromOffset(36, 13),
    Size = UDim2.new(1, -38, 0, 13), truncate = true, Parent = foot,
  })
  self.footState = A.text({
    Text = "connected", font = T.font.mono, size = T.size.tiny,
    colour = T.c.textOff, Position = UDim2.fromOffset(36, 27),
    Size = UDim2.new(1, -38, 0, 12), Parent = foot,
  })

  task.spawn(function()
    local Stats = game:GetService("Stats")
    while L.live() and foot.Parent do
      local ok, v = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
      end)
      local ms = (ok and type(v) == "number") and math.floor(v) or -1
      self.pingLbl.Text = (ms >= 0) and (ms .. " ms") or "offline"
      M.to(pdot, "BackgroundColor3",
        (ms < 0 and T.c.textOff) or (ms < 120 and T.c.ok)
        or (ms < 260 and T.c.warn) or T.c.bad, "base")
      task.wait(2)
    end
  end)

  -- ---- content --------------------------------------------------------
  self.content = mk("Frame", {
    Position = UDim2.fromOffset(SIDEBAR + 1, HEADER + 1),
    Size = UDim2.new(1, -(SIDEBAR + 1), 1, -(HEADER + 1)),
    BackgroundTransparency = 1, ClipsDescendants = true,
    Name = "Content", Parent = root,
  })

  -- THE SATURN, AS A BACKGROUND OBJECT. It appeared here once by accident when
  -- two sequences collided on the same basename, stretched edge to edge. It read
  -- well, so it is back on purpose: sized to the panel rather than filling it,
  -- anchored right and allowed to bleed off the edge so it behaves like a hero
  -- object the content sits over, and held well back in opacity so it never
  -- competes with a value the user is trying to read.
  self.heroVid = L.Video and (not (L.Cfg and L.Cfg.data.heroArt == false)) and L.Video.new(self.content, {
    folder = "lumen_fx/saturn", prefix = "sat", first = 68, count = 183, fps = 30,
    size = math.floor(self.height * 0.46),
    -- pulled inside the edge and dropped low, so the ring reads as an object
    -- the content sits over rather than a crop artefact, and it clears the cards
    Position = UDim2.new(1, -58, 1, -48),
    ZIndex = 0, rest = 0.84, loop = true,
  })

  -- ---- the background behind the pages ----------------------------------
  --
  -- THIS IS WHERE THE BACKGROUND STYLES BELONG, and I built them for the
  -- loading screen first, which was a misread: a loading screen is on for four
  -- seconds and this is what you look at for the rest of the session.
  --
  -- The lattice used to carry a note saying it was static ON PURPOSE, because
  -- "a wave running behind live controls is noise rather than atmosphere". That
  -- judgement still holds and it is why Nebula -- static -- stays the default.
  -- It is an argument for a good default, though, not for having no choice.
  --
  -- Sized to the VIEWPORT rather than the window: the panel can be resized, and
  -- a lattice built to the old size would run out of dots the moment it grew.
  -- Content clips, so the overspill costs nothing.
  do
    local vp = L.viewport()
    local gw, gh = 0, 0 -- supplied pinstripe footage replaces the lattice
    local sp = 30
    local host = mk("Frame", {
      Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0,
      Name = "Lattice", Parent = self.content,
    })
    self.bgDots, self.bgBase = {}, 0.93
    local cols = math.floor(gw / sp)
    local rows = math.floor(gh / sp)
    for x = 0, cols do
      for y = 0, rows do
        local d = mk("Frame", {
          Position = UDim2.fromOffset(x * sp + 14, y * sp + 12),
          Size = UDim2.fromOffset(2, 2),
          BackgroundColor3 = Color3.fromRGB(150, 170, 210),
          BackgroundTransparency = 0.93,
          BorderSizePixel = 0, ZIndex = 0, Parent = host,
        })
        self.bgDots[#self.bgDots + 1] =
          { obj = d, u = x / math.max(cols, 1), v = y / math.max(rows, 1) }
      end
    end

    -- The iridescent field, off unless the style asks for it. Five very large,
    -- very soft, very transparent colour discs drifting through one another --
    -- overlap does the blending, and because each is bigger than the panel you
    -- never see an edge, only the colour changing where two of them cross.
    -- Behind the lattice and well under the content in opacity.
    self.bgFields = {}
    if A.img and A.img.glow then
      local fieldHost = mk("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0,
        Visible = false, Name = "Fields", Parent = self.content,
      })
      self.bgFieldHost = fieldHost
      local SPEC = {
        { c = Color3.fromRGB( 92, 128, 255), sx = 0.30, sy = 0.20, rx = 0.017, ry = 0.011, sz = 1.10 },
        { c = Color3.fromRGB(186, 108, 255), sx = 0.26, sy = 0.27, rx = 0.012, ry = 0.021, sz = 0.88 },
        { c = Color3.fromRGB( 88, 220, 220), sx = 0.29, sy = 0.22, rx = 0.022, ry = 0.009, sz = 0.96 },
        { c = Color3.fromRGB(255, 150, 120), sx = 0.20, sy = 0.24, rx = 0.010, ry = 0.016, sz = 0.74 },
        { c = Color3.fromRGB(120, 160, 255), sx = 0.33, sy = 0.17, rx = 0.007, ry = 0.019, sz = 1.24 },
      }
      for i, f in ipairs(SPEC) do
        local d = math.floor(self.width * f.sz)
        self.bgFields[i] = { spec = f, phase = i * 1.7, obj = mk("ImageLabel", {
          AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
          Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1,
          Image = A.img.glow, ImageColor3 = f.c, ImageTransparency = 0.88,
          ZIndex = 0, Name = "Field" .. i, Parent = fieldHost,
        }) }
      end
    end
  end

  -- ---- background style --------------------------------------------------
  --
  -- One setting drives this and the loading screen, so the product has a look
  -- rather than two unrelated ones.
  function self:applyBackground(name)
    name = name or (L.Backdrop and L.Backdrop.styleName()) or "Nebula"
    self.bgStyle = name
    local aurora    = (name == "Aurora")
    local particles = (name == "Particles")
    local plain     = (name == "Plain")

    if self.bgFieldHost then self.bgFieldHost.Visible = aurora end
    -- the hero object is scenery: it belongs to the styles that want scenery
    if self.heroVid and self.heroVid.frameObj then
      self.heroVid.frameObj.Visible = not (plain or aurora)
    end
    -- Aurora lifts the lattice a little so the colour does not read as flat
    -- wallpaper; Plain drops it entirely
    self.bgBase = aurora and 0.955 or 0.93
    for _, d in ipairs(self.bgDots or {}) do
      d.obj.Visible = not plain
      d.obj.BackgroundTransparency = self.bgBase
      if not particles then d.obj.Size = UDim2.fromOffset(2, 2) end
    end
    self:_bgCull()
    return self
  end

  -- THE LATTICE IS BUILT TO THE VIEWPORT AND THE PANEL IS SMALLER THAN THAT.
  --
  -- Deliberately so -- the window resizes, and a lattice built to the old size
  -- would run out of dots the moment it grew. But the wave was walking all of
  -- them, and measured on a 958 x 931 panel only 992 of 3956 were inside it:
  -- three quarters of the work went to dots the content frame clips away. It
  -- showed up exactly where you would expect, in the tail rather than the
  -- median:
  --
  --   Nebula      median 6.11 ms   p95  8.68 ms
  --   Particles   median 6.20 ms   p95 17.44 ms   <- a dropped frame
  --   Aurora      median 6.07 ms   p95  8.16 ms
  --
  -- So the animated subset is resolved once per size change instead of per
  -- frame. Rebuilt on resize because the panel is resizable and a stale list
  -- would leave a rectangle of dead dots after it grew.
  function self:_bgCull()
    local c = self.content
    if not (c and self.bgDots) then return end
    local w, h = c.AbsoluteSize.X, c.AbsoluteSize.Y
    self._bgCullSize = Vector2.new(w, h)
    local live = {}
    for i = 1, #self.bgDots do
      local d = self.bgDots[i]
      local p = d.obj.Position
      if p.X.Offset <= w + 24 and p.Y.Offset <= h + 24 then live[#live + 1] = d end
    end
    self.bgActive = live
  end

  -- One clock for every animated nav icon. Advancing only the active and hovered
  -- ones keeps four of the five sequences completely still at rest.
  self._iconT = 0
  L.hold(L.RunService.RenderStepped:Connect(function(dt)
    if not L.live() or self.hidden or (L.Cfg and L.Cfg.data.reduceMotion) then return end
    self._iconT = self._iconT + dt

    -- BACKGROUND. Only whichever style is live does any work, and the whole
    -- thing is skipped while the window is hidden by the guard above.
    if self.bgStyle == "Aurora" and self.bgFields then
      local t = self._iconT
      for i = 1, #self.bgFields do
        local fd = self.bgFields[i]
        local sp = fd.spec
        fd.obj.Position = UDim2.fromScale(
          0.5 + math.sin(t * sp.rx * 6.283 + fd.phase) * sp.sx,
          0.5 + math.cos(t * sp.ry * 6.283 + fd.phase * 1.31) * sp.sy)
        fd.obj.ImageTransparency = 0.88 + math.sin(t * 0.11 + fd.phase) * 0.05
      end
    elseif self.bgStyle == "Particles" and self.bgActive then
      -- 30 Hz: this touches every dot, and at 60 it is the single most
      -- expensive thing on an otherwise idle window for no visible gain
      self._bgAcc = (self._bgAcc or 0) + dt
      if self._bgAcc >= 1 / 30 then
        self._bgAcc = 0
        -- a resize invalidates the culled list, and the panel is resizable
        local cs = self.content and self.content.AbsoluteSize
        if cs and self._bgCullSize and (cs - self._bgCullSize).Magnitude > 8 then
          self:_bgCull()
        end
        local t, base = self._iconT, self.bgBase
        local live = self.bgActive
        for i = 1, #live do
          local d = live[i]
          local w = math.sin((d.u * 3.1 + d.v * 1.7) * 3.14159 - t * 0.85)
                  + math.sin((d.u * 1.3 - d.v * 2.9) * 3.14159 - t * 0.55)
          local k = math.clamp((w + 2) / 4, 0, 1)
          k = k * k * k                       -- most of the field stays quiet
          d.obj.BackgroundTransparency = base - (base - 0.62) * k
          local sz = 2 + math.floor(k * 2.4)
          if d.sz ~= sz then
            d.sz = sz
            d.obj.Size = UDim2.fromOffset(sz, sz)
          end
        end
      end
    end

    local f = math.floor(self._iconT * 12) + 1
    -- the chrome page title rides the same clock, at its own rate
    local tf = math.floor(self._iconT * 20) + 1
    local act = self.tabs[self.active]
    -- THE SWEEP RIDES THE WINDOW CLOCK, and only for the page you are looking
    -- at. Left to itself every page would animate its own gradient forever,
    -- including the ten nobody has open -- which is exactly the problem the old
    -- sequence solved with manual playback, kept here for the same reason.
    if act and act.titleGrad then
      -- SECONDS, NOT THE FRAME INDEX. This first shipped reading `tf`, which is
      -- the 20 fps counter the old image sequence stepped through -- so the
      -- sweep advanced twenty times a second instead of once, and math.floor
      -- quantised it into 20 visible steps on top. At speed 0.16 that is 1.6
      -- full passes per second and at Movement's 0.30 it is three: a strobe,
      -- not a shimmer. Caught on video.
      --
      -- Driven from the raw clock it is one pass every 2/speed seconds --
      -- 12.5 s at the default, which is slow enough to read as light moving
      -- across metal rather than as the title flashing.
      local sp = act.titleGrad:GetAttribute("Speed") or 0.16
      -- one full pass every 2/speed seconds, unchanged from the offset version
      -- so the measured 12.5 s at the default still holds -- but the pattern
      -- wraps, so there is no dead half of the cycle to sit through.
      local phase = (self._iconT * sp * 0.5) % 1
      -- Rebuilding 20 keypoints on every frame is needless allocation for a
      -- highlight that takes twelve seconds to cross a word. 24 Hz is far under
      -- the threshold where that reads as stepped. NOTE this throttles how often
      -- the colours are rebuilt, NOT the phase -- quantising the phase is what
      -- turned this into a strobe last time, and it is a different quantity.
      self._titleAcc = (self._titleAcc or 1) + dt
      if self._titleAcc >= 1 / 24 then
        self._titleAcc = 0
        act.titleGrad.Color = A.chromeSeq(act.titlePattern
                                          or A.chromePattern(A.CHROME.__default), phase)
      end
    end
    for i, t in ipairs(self.tabs) do
      if t.iconVid then
        local live = (i == self.active) or (i == self._hover)
        if live then
          t.iconVid:setFrame(f)
          t.iconVid.rest = (i == self.active) and 0 or 0.1
        else
          t.iconVid.rest = 0.5
        end
      end
    end
  end))

  -- while the pointer is over the hub, the wheel belongs to the hub
  A.addWheelGuard(function()
    return (not self.hidden) and self.root.Visible and self:_pointerInside()
  end)

  -- POPOVER LAYER. A dropdown cannot render inside the page: the content frame
  -- clips, and the page scrolls, so an expanding list is both cut off and
  -- dragged around by the scroll under it. This sits on the window root, above
  -- everything, clipped by nothing.
  self.overlay = mk("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    ZIndex = 30, Name = "Overlay", Parent = root,
  })

  self:_resize()
  self:_drag()
  self:_hotkeys(opts.toggleKey)

  -- ---- minimised dock -------------------------------------------------
  local dock = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -60),
    Size = UDim2.fromOffset(142, 36), BackgroundColor3 = T.c.overlay,
    BorderSizePixel = 0, Name = "Dock", Parent = gui,
  })
  L.corner(999, dock)
  local dockStroke = L.stroke(T.c.lineStrong, 1, 0.3, dock)

  -- A HALO THAT BREATHES, so the pill reads as the one live thing on screen
  -- while everything else is gone. It sits behind the pill and outside it, which
  -- is the only way to glow without washing out the mark sitting on top.
  local dockGlow = A.img and A.img.glow and mk("ImageLabel", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(1, 74, 1, 58), BackgroundTransparency = 1,
    Image = A.img.glow, ImageColor3 = T.c.accent, ImageTransparency = 0.82,
    ZIndex = 0, Name = "DockGlow", Parent = dock,
  })

  -- a small halo of its own, drifting around the mark. The pill's glow says
  -- "this is here"; this one says the mark is alive while nothing else is.
  local orbGlow = A.img and A.img.glow and mk("ImageLabel", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(22, 18), Size = UDim2.fromOffset(46, 46),
    BackgroundTransparency = 1, Image = A.img.glow,
    ImageColor3 = T.c.accent, ImageTransparency = 0.72,
    ZIndex = 1, Name = "OrbGlow", Parent = dock,
  })

  -- the Saturn, not the drawn diamond: the same mark the loader and the header
  -- already use, so the minimised state is recognisably the same product
  local dockOrb = L.Video and L.Video.new(dock, {
    folder = "lumen_fx/saturn_s", prefix = "sms", first = 5, count = 92,
    fps = 15, size = 24, loop = true,
    Position = UDim2.fromOffset(22, 18), ZIndex = 2,
  })
  if not dockOrb then Window.mark(dock, 20).Position = UDim2.fromOffset(10, 8) end

  local dockLbl = A.text({
    Text = opts.title or "LUMEN", font = T.font.strong, size = T.size.label,
    colour = T.c.textDim, Position = UDim2.fromOffset(38, 0),
    Size = UDim2.new(1, -48, 1, 0), Parent = dock,
  })

  A.interactive(dock, {
    radius = 999, onClick = function() self:restore() end,
    onState = function(st)
      -- the whole pill answers the cursor: the halo swells, the edge lights up
      -- and the wordmark brightens, all on one token so it reads as one object
      M.to(dockStroke, "Color", st.hovered and T.c.accent or T.c.lineStrong, "fast")
      M.to(dockStroke, "Transparency", st.hovered and 0.05 or 0.3, "fast")
      M.to(dockLbl, "TextColor3", st.hovered and T.c.text or T.c.textDim, "fast")
      if dockGlow then
        M.to(dockGlow, "Size",
          st.hovered and UDim2.new(1, 104, 1, 80) or UDim2.new(1, 74, 1, 58), "base")
      end
      self._dockHover = st.hovered
    end,
  })

  -- One loop for the halo. A spring cannot express a cycle -- it settles by
  -- definition -- so the breathing is a cosine, and hovering only shifts the
  -- band it breathes within rather than interrupting it.
  if dockGlow then
    self._dockT = 0
    L.hold(L.RunService.RenderStepped:Connect(function(dt)
      if not L.live() or not dock.Parent then return end
      if dock.Position.Y.Offset < -20 then return end     -- parked offscreen
      self._dockT = self._dockT + dt
      local puls = 0.5 + 0.5 * math.cos(self._dockT * 2.1)
      local lo = self._dockHover and 0.52 or 0.74
      local hi = self._dockHover and 0.72 or 0.90
      dockGlow.ImageTransparency = hi - (hi - lo) * puls

      -- the mark's own halo drifts around it on a slower, offset cycle, so the
      -- two glows never breathe in step and the pill does not read as one pulse
      if orbGlow then
        local a = self._dockT * 0.75
        orbGlow.Position = UDim2.fromOffset(22 + math.cos(a) * 2.6,
                                            18 + math.sin(a * 1.3) * 2.2)
        local p2 = 0.5 + 0.5 * math.cos(self._dockT * 1.55 + 1.1)
        orbGlow.ImageTransparency = (self._dockHover and 0.50 or 0.66)
                                    + 0.16 * p2
      end
    end))
  end

  self.dock, self.dockGlow, self.dockOrb, self.orbGlow =
    dock, dockGlow, dockOrb, orbGlow

  -- the pinned-feature strip lives beside the pill, as a CHILD of it, so it
  -- inherits every minimise and restore rather than chasing them
  if L.Pins and L.Pins.attach then L.try("pins.attach", L.Pins.attach, dock) end

  -- last, because it reaches into the hero video and the lattice, both of which
  -- have to exist first
  L.try("window.background", function() self:applyBackground() end)

  return self
end

-- ---------------------------------------------------------------- nav

-- A group heading in the sidebar. Five flat entries read as a list; two groups
-- of two or three read as a structure.
function Window:navSection(name)
  local h = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1,
    LayoutOrder = self._navOrder, Name = "NavSection", Parent = self.navList,
  })
  self._navOrder = self._navOrder + 1
  self._navCursor = self._navCursor + 26 + 2
  A.text({
    Text = L.track(string.upper(name or ""), 1),
    font = T.font.medium, size = T.size.nano,
    colour = T.c.textOff, Position = UDim2.fromOffset(12, 12),
    Size = UDim2.new(1, -14, 0, 12), Parent = h,
  })
  self._sections[#self._sections + 1] = h
  self._pendingSection = name
  return h
end

function Window:tab(opts)
  opts = opts or {}
  local index = #self.tabs + 1

  local btn = mk("Frame", {
    Size = UDim2.new(1, 0, 0, TAB_H), BackgroundTransparency = 1,
    LayoutOrder = self._navOrder, Name = "Tab_" .. (opts.name or index),
    Parent = self.navList,
  })
  self._navOrder = self._navOrder + 1
  local navY = self._navCursor
  self._navCursor = self._navCursor + TAB_H + 2

  -- ANIMATED CHROME TILE. The reference icons are not stills -- the objects turn.
  -- Each is a 48-frame loop at 96 px, which is near 1:1 at the 30 px display size
  -- and costs 1.7 MB per icon.
  --
  -- ONLY THE ACTIVE AND HOVERED ONES RUN. Five sequences turning at once is
  -- noise, and it makes the nav compete with the page for attention. A resting
  -- tab holds a single frame, which costs nothing.
  local glyph, iconVid, isChrome
  if opts.chrome then
    iconVid = L.Video and L.Video.new(btn, {
      folder = "lumen_fx/icons_anim", prefix = opts.chrome, count = 48, fps = 12,
      size = 30, Position = UDim2.fromOffset(8 + 15, TAB_H / 2), ZIndex = 2,
      manual = true, loop = true,
    })
    if iconVid then
      glyph = iconVid.frameObj
      isChrome = true
    end
  end
  if not glyph and opts.chrome then
    glyph = A.chrome(btn, opts.chrome, 30, {
      Position = UDim2.fromOffset(8, TAB_H / 2 - 15), ZIndex = 2 })
    isChrome = glyph ~= nil
  end
  if not glyph then
    local iconFn = A.Icon[opts.icon or "dot"] or A.Icon.dot
    glyph = iconFn(btn, 16, T.c.textMute)
    glyph.Position = UDim2.fromOffset(12, TAB_H / 2 - 8)
  end

  -- Same derivation as every other two-part row in this project: the name's box
  -- ends where the number's begins, plus a gap. It used to reserve `1, -76`
  -- while the number occupied the last 32 px, so the two overlapped by 4 px on
  -- every tab -- invisible only because the name truncates first.
  local NAV_X, NUM_W, NUM_RIGHT, NUM_GAP = 48, 20, 12, 8
  local label = A.text({
    Text = opts.name or ("Tab " .. index), font = T.font.medium,
    size = T.size.body, colour = T.c.textMute,
    Position = UDim2.fromOffset(NAV_X, 0),
    Size = UDim2.new(1, -(NAV_X + NUM_W + NUM_RIGHT + NUM_GAP), 1, 0),
    truncate = true, Parent = btn,
  })
  -- the number key that selects it, stated rather than hidden in a help screen
  A.text({
    Text = tostring(index), font = T.font.mono, size = T.size.tiny,
    colour = T.c.textOff, align = Enum.TextXAlignment.Right,
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -NUM_RIGHT, 0.5, 0),
    Size = UDim2.fromOffset(NUM_W, 12), Parent = btn,
  })

  local page = mk("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false,
    Name = "Page_" .. (opts.name or index), Parent = self.content,
  })

  -- Heading lives OUTSIDE the CanvasGroup so it renders natively.
  --
  -- THREE TIERS, WIDE APART. The reference gets its hierarchy from RANGE: a tiny
  -- wide-tracked eyebrow, then a large title, then a small dim line. Sizes only
  local head = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 88), BackgroundTransparency = 1,
    Name = "Heading", Parent = page,
  })
  local eyebrow = A.text({
    Text = L.track(string.upper(self._pendingSection or "SECTION"), 1),
    font = T.font.medium, size = T.size.nano, colour = T.c.textOff,
    Position = UDim2.fromOffset(24, 16), Size = UDim2.new(1, -48, 0, 12),
    Parent = head,
  })
  local titleLbl = A.text({
    Text = opts.name or "", font = T.font.display, size = T.size.display,
    colour = T.c.text,
    Position = UDim2.fromOffset(24, 30), Size = UDim2.new(1, -48, 0, 28),
    Parent = head,
  })

  -- ---- chrome title -----------------------------------------------------
  --
  -- THIS USED TO BE A 36-FRAME IMAGE SEQUENCE, and the reason given was:
  -- "Roblox cannot fill text with a gradient, mask an image to glyphs, or
  -- animate a reflection across a TextLabel". The first of those is false and
  -- has been for years -- a UIGradient parented to a TextLabel tints its
  -- glyphs. Verified on this client with a side-by-side probe and a screenshot
  -- before any of this was written.
  --
  -- What that assumption cost:
  --   * only SIX words existed. Movement, Combat, Visuals, AI and Config fell
  --     back to flat white, because nobody had run the generator for them.
  --   * the frames were baked at a 96 px glyph. Expand the window past the
  --     scale that assumed and the title is an UPSCALED BITMAP -- which is the
  --     "text goes soft when I resize" complaint, and it could not be fixed by
  --     any amount of care at the call site.
  --   * about 490 ms of the window build, by the old comment's own measurement.
  --
  -- Rendering it live costs one UIGradient per page and is resolution
  -- independent, so it is sharp at any window size and any DPI, and every tab
  -- gets one for free -- including tabs that do not exist yet.
  local titleGrad, titlePattern
  do
    -- PER-PAGE CHARACTER, from one engine -- now shared with the loading screen.
    -- See A.CHROME / A.chromeSeq in atoms for why the sweep resamples the
    -- gradient's colours instead of sliding its Offset. Short version: Offset
    -- clamps, so half of every cycle had the highlight outside the letters and
    -- the title just sat there as dark grey text.
    local cfg = A.CHROME[opts.name or ""] or A.CHROME.__default
    titlePattern = A.chromePattern(cfg)
    titleGrad = mk("UIGradient", {
      Color = A.chromeSeq(titlePattern, 0),
      Rotation = cfg.rot,
      Parent = titleLbl,
    })
    titleGrad:SetAttribute("Speed", cfg.speed)
  end

  local sub = A.text({
    Text = opts.desc or "", font = T.font.body, size = T.size.micro,
    colour = T.c.textMute, Position = UDim2.fromOffset(24, 60),
    Size = UDim2.new(1, -48, 0, 14), Parent = head,
  })
  -- (object, property) pairs, not bare labels: the heading is no longer all
  -- text -- the chrome title fades on GroupTransparency -- and a fade list that
  -- assumes TextTransparency would silently skip whatever is not a label.
  local heads = {
    { eyebrow,  "TextTransparency" },
    { titleLbl, "TextTransparency" },
    { sub,      "TextTransparency" },
  }

  local grp = mk("CanvasGroup", {
    Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 1, -88),
    BackgroundTransparency = 1, GroupTransparency = 1,
    ClipsDescendants = true,          -- or the scroll runs up under the heading
    Parent = page,
  })

  local scroll = A.scroll({ Parent = grp, gap = T.gap.md, Name = "PageScroll" })
  L.pad(4, 24, 24, 24, scroll)

  local tab = { index = index, name = opts.name, button = btn, label = label,
                glyph = glyph, chrome = isChrome, iconVid = iconVid,
                page = page, group = grp, head = head, heads = heads,
                titleGrad = titleGrad, titlePattern = titlePattern,
                body = scroll, sub = sub, navY = navY, window = self }

  A.interactive(btn, {
    radius = T.r.md, hoverAlpha = 0.97, pressAlpha = 0.95,
    onClick = function() self:select(index) end,
    -- The chrome tile grows and brightens under the pointer. Springs, so moving
    -- quickly along the nav makes each icon catch and release rather than
    -- snapping between two states.
    onState = function(st)
      if not isChrome then return end
      local on = (self.active == index)
      local big = st.hovered and 34 or 30
      M.to(glyph, "Size", UDim2.fromOffset(big, big), "fast")
      self._hover = st.hovered and index or (self._hover == index and nil or self._hover)
      if not on and not iconVid then
        M.to(glyph, "ImageTransparency", st.hovered and 0.12 or 0.5, "fast")
      end
    end,
  })

  if L.Palette then
    L.Palette.add(page, opts.name or ("Tab " .. index), opts.desc or "")
  end
  self.tabs[index] = tab
  self._navY[index] = nil
  if index == 1 then self:select(1, true) end
  return tab
end

function Window:select(index, immediate)
  local tab = self.tabs[index]
  if not tab or self.active == index then return end
  -- A popover belongs to the page that opened it; leaving that page must take it
  -- with you, or it hangs over the new one. Closed through its OWNER, not by
  -- destroying the overlay behind its back -- doing that left the dropdown still
  -- flagged open, so its next click closed nothing and it read as broken.
  if L.C and L.C.closePopovers then L.C.closePopovers() end
  if self.overlay then
    for _, d in ipairs(self.overlay:GetChildren()) do pcall(function() d:Destroy() end) end
  end
  local prev = self.active and self.tabs[self.active]
  self.active = index

  local y = tab.navY
  self.pill.Visible, self.pillBar.Visible = true, true
  local setter = immediate and M.set or M.to
  setter(self.pill, "Position", UDim2.fromOffset(0, y), "base")
  setter(self.pillBar, "Position", UDim2.fromOffset(-12, y + TAB_H * 0.275), "base")

  for i, t in ipairs(self.tabs) do
    local on = (i == index)
    M.to(t.label, "TextColor3", on and T.c.text or T.c.textMute, "fast")
    if t.chrome then
      -- brightness, not hue. Tinting a rendered chrome object toward the accent
      -- flattens every reflection in it.
      if t.iconVid then
        t.iconVid.rest = on and 0 or 0.5
        local cur = t.iconVid.labels[t.iconVid.shown]
        if cur then M.to(cur, "ImageTransparency", t.iconVid.rest, "fast") end
      else
        M.to(t.glyph, "ImageTransparency", on and 0 or 0.5, "fast")
      end
    else
      for _, d in ipairs(t.glyph:GetDescendants()) do
        if d:IsA("Frame") then
          M.to(d, "BackgroundColor3", on and T.c.accent or T.c.textMute, "fast")
        elseif d:IsA("UIStroke") then
          M.to(d, "Color", on and T.c.accent or T.c.textMute, "fast")
        end
      end
    end
  end

  if prev and prev ~= tab then
    local old = prev
    A.groupTo(old.group, 1, "fast")
    M.to(old.group, "Position", UDim2.fromOffset(0, 98), "fast")
    -- the heading leaves with the body it belongs to, or the two pages' titles
    -- sit on top of each other for the whole handover
    if old.heads then
      for _, h in ipairs(old.heads) do M.to(h[1], h[2], 1, "fast") end
      M.to(old.head, "Position", UDim2.fromOffset(0, 10), "fast")
    end
    -- DERIVED FROM THE TOKEN, NOT TYPED. 0.18 was the "fast" duration at scale
    -- 1.0 and nothing else -- on the Calm profile that token runs 1.4x longer,
    -- so the page was hidden 71% of the way through its own fade and the swap
    -- popped. Motion.resolve applies the live profile scale, so this tracks
    -- whatever the user picked.
    local fadeOut = select(1, M.resolve("fast"))
    task.delay(fadeOut + 0.04, function()
      if L.live() and self.active ~= old.index then old.page.Visible = false end
    end)
  end

  -- the chrome title for this page is built the first time it is opened

  tab.page.Visible = true
  if immediate then
    A.groupSet(tab.group, 0)
    M.set(tab.group, "Position", UDim2.fromOffset(0, 88))
    if tab.heads then
      M.set(tab.head, "Position", UDim2.fromOffset(0, 0))
      for _, h in ipairs(tab.heads) do M.set(h[1], h[2], 0) end
    end
  else
    M.set(tab.group, "Position", UDim2.fromOffset(0, 102))
    A.groupSet(tab.group, 1)
    A.groupTo(tab.group, 0, "base")
    M.to(tab.group, "Position", UDim2.fromOffset(0, 88), "slow")
    if tab.heads then
      M.set(tab.head, "Position", UDim2.fromOffset(0, 14))
      for _, h in ipairs(tab.heads) do M.set(h[1], h[2], 1) end
      M.to(tab.head, "Position", UDim2.fromOffset(0, 0), "slow")
      for _, h in ipairs(tab.heads) do M.to(h[1], h[2], 0, "base") end
    end
  end
  -- Return to the top. AutomaticCanvasSize grows the canvas AFTER the one-shot
  -- reset in A.scroll, so a page built later can end up scrolled with its first
  -- heading clipped above the viewport.
  -- reset through the controller: writing CanvasPosition alone would leave the
  -- spring still aiming at the old offset and it would scroll straight back
  A.scrollReset(tab.body)
  task.defer(function()
    if tab.body.Parent then A.scrollReset(tab.body) end
  end)

  -- deferred so the rows have been laid out and can be sorted by where they
  -- actually sit; skipped on the programmatic path, where nobody is watching
  if not immediate then
    task.defer(function()
      if L.live() and self.active == index then self:_cascade(tab) end
    end)
  end

  -- ONLY A TAB THE USER CHOSE IS WORTH REMEMBERING. This wrote on every select,
  -- including the `self:select(1, true)` that Window:tab fires while the nav is
  -- still being built -- so construction overwrote the saved tab with 1 before
  -- anything had a chance to read it back, and "reopen where you left off" could
  -- never have worked no matter how it was restored. `immediate` is true for
  -- exactly the programmatic paths (construction and restore) and false for the
  -- click handler, which makes it the intent flag this needs.
  if L.Cfg and not immediate then L.Cfg.set("tab", index) end
  if self.onTab then L.try("window.onTab", self.onTab, tab) end
end

-- ---------------------------------------------------------------- chrome

function Window:show(transitionGen)
  if transitionGen then
    if self._transitionGen ~= transitionGen then return self end
  else
    self._transitionGen = (self._transitionGen or 0) + 1
    transitionGen = self._transitionGen
  end
  self.hidden = false
  self.shell.Visible, self.root.Visible = true, true
  A.groupSet(self.root, 1)
  M.set(self.root, "Size", UDim2.fromOffset(self.width * 0.95, self.height * 0.95))
  -- Restore authored child alpha before the shared group clock starts.
  if self.body then M.set(self.body, "BackgroundTransparency", 0) end
  if self.wash then M.set(self.wash, "BackgroundTransparency", 0) end
  local fadeDur = select(1, M.resolve("base"))
  local fadeToken = { fadeDur, 0 }
  A.groupTo(self.root, 0, fadeToken)
  M.to(self.root, "Size", UDim2.fromOffset(self.width, self.height), "slow")
  if self.shadow then
    local sp = (self.shadowSpread or 34) * 2
    M.set(self.shadow, "ImageTransparency", 1)
    M.set(self.shadow, "Size", UDim2.new(0.97, sp, 0.97, sp))
    M.to(self.shadow, "ImageTransparency", self.shadowRest, fadeToken)
    M.to(self.shadow, "Size", UDim2.new(1, sp, 1, sp), "slow")
  end
  -- The root CanvasGroup is the one opacity clock. Animating the body again
  -- multiplied two fades, so the outline/text appeared a few frames before the
  -- dark plate in recordings. Restore child resting alpha synchronously.
  M.to(self.dock, "Position", Window.DOCK_OUT, "base")
  A.blurTo(Window.BLUR, "slow")
  M.to(self.scrim, "BackgroundTransparency", 0.5, fadeToken)
  return self
end

function Window:hide(token, keepDock, transitionGen)
  token = token or "fast"
  if transitionGen then
    if self._transitionGen ~= transitionGen then return self end
  else
    self._transitionGen = (self._transitionGen or 0) + 1
    transitionGen = self._transitionGen
  end
  self.hidden = true
  -- an open menu must not be waiting for you when the window comes back
  if L.C and L.C.closePopovers then L.C.closePopovers() end
  -- The drawer lives inside the shell, so it would be carried and squashed by
  -- the morph. It is handed its own window instead and becomes draggable, and
  -- comes back when this one does.
  if L.Side and L.Side.open and L.Side.detach then L.Side.detach() end
  -- ONE TOKEN FOR EVERY OUTGOING PROPERTY. The panel was leaving on `fast` while
  -- the scrim and blur left on `base`, so the dimming lingered after the window
  -- had already gone. Anything that arrives together has to leave together.
  local dur = select(1, M.resolve(token))
  local opacityToken = { dur, 0 }
  A.groupTo(self.root, 1, opacityToken)
  M.to(self.root, "Size", UDim2.fromOffset(self.width * 0.97, self.height * 0.97), token)
  -- Shadow geometry is outside the root group, so it receives the exact same
  -- duration explicitly. A shorter shadow/plate clock produced the dark edge
  -- lead visible in the minimise recording.
  if self.shadow then
    local sp = (self.shadowSpread or 34) * 2
    M.to(self.shadow, "ImageTransparency", 1, opacityToken)
    M.to(self.shadow, "Size", UDim2.new(0.97, sp, 0.97, sp), token)
  end

  -- Body, wash, icons and text leave through GroupTransparency. THE STROKE
  -- DOES NOT -- it is parented to the CanvasGroup rather than being one of
  -- the children the group composites, so it kept drawing at its resting 0.30
  -- for the whole hide: a solid rounded outline around an empty rectangle,
  -- snapped away only by Visible = false at the very end. A.groupTo carries
  -- the stroke with the group. Their authored resting values stay intact for
  -- an interruption-safe restore.
  if self.body then M.set(self.body, "BackgroundTransparency", 0) end
  if self.wash then M.set(self.wash, "BackgroundTransparency", 0) end
  A.blurTo(0, token)
  M.to(self.scrim, "BackgroundTransparency", 1, opacityToken)

  -- THE DOCK LEAVES TOO. It is the one drawn thing outside the root CanvasGroup
  -- that hide() never touched -- an opaque 227x58 bar parked just off the top
  -- edge. Anything the group fade cannot reach has to be faded by name, or it
  -- outlives the window that owned it.
  -- minimise owns the dock while the genie runs, so it opts out of this
  if not keepDock then M.to(self.dock, "Position", Window.DOCK_OUT, token) end

  -- DERIVED, NOT TYPED. 0.30 was the `fast` duration at scale 1.0 and nothing
  -- else: on the Calm profile the fade needs 0.35 s, so the window was switched
  -- off 15% before it finished fading and popped. Third instance of this exact
  -- bug in the project -- a literal that silently mirrors a motion token.
  task.delay(dur + 0.06, function()
    if L.live() and self.hidden and self._transitionGen == transitionGen then
      self.root.Visible, self.shell.Visible = false, false
    end
  end)
  return self
end

-- Everything on `o` that is currently drawn, with the value it rests at.
local function drawnParts(o, into)
  into = into or {}
  for _, p in ipairs({ "BackgroundTransparency", "TextTransparency",
                       "ImageTransparency", "Transparency" }) do
    local ok, v = pcall(function() return o[p] end)
    if ok and type(v) == "number" and v < 1 then into[#into + 1] = { o, p, v } end
  end
  return into
end

function Window:minimise()
  if self._morphBusy then return end
  self._transitionGen = (self._transitionGen or 0) + 1
  local transitionGen = self._transitionGen
  self._morphBusy = true

  -- THE PILL IS PLACED FIRST AND REVEALED LAST. Putting it at its resting spot
  -- immediately but invisible means the genie has a real target to measure, and
  -- fading it up as the bands land makes the stack look like it BECAME the
  -- pill rather than pulling up alongside one that was already there.
  M.stop(self.dock, "Position")
  self.dock.Position = Window.DOCK_IN

  -- CAPTURED ONCE, EVER. minimise() sets these to transparent and restore() has
  -- to put them back; re-reading them per minimise meant the second one sampled
  -- a dock the first had already hidden, recorded "invisible" as its resting
  -- state, and the pill never appeared again. Same trap as the row cascade.
  if not self._dockParts then
    local parts = drawnParts(self.dock)
    -- BOTH pin bars, not just the right-hand one. Pins now fill left as well as
    -- right, and each strip is its own CanvasGroup -- so treating only the
    -- first as a single unit left the left-hand chips being walked
    -- element-by-element, revealing on their own clocks while the right side
    -- faded as one.
    local pinBars = (L.Pins and L.Pins.bars) or (L.Pins and L.Pins.bar and { L.Pins.bar }) or {}
    local function isBar(x)
      for _, b in ipairs(pinBars) do if x == b then return b end end
      return nil
    end
    local function insideBar(x)
      for _, b in ipairs(pinBars) do
        if b and x:IsDescendantOf(b) then return true end
      end
      return false
    end
    for _, x in ipairs(self.dock:GetDescendants()) do
      local b = isBar(x)
      if b then
        parts[#parts + 1] = { b, "GroupTransparency", L.uiRead(b,"GroupTransparency") }
      elseif not insideBar(x) then
        drawnParts(x, parts)
      end
    end
    self._dockParts = parts
  end
  local pill = self._dockParts
  for _, e in ipairs(pill) do M.set(e[1], e[2], 1) end

  -- THE SATURN HAS TO BE PAUSED, NOT JUST HIDDEN. It runs its own playback loop,
  -- which re-shows the current frame the instant it advances -- so walking the
  -- pill's parts hid it for a sixteenth of a second and then it came straight
  -- back, leaving the logo hanging alone at the pill's destination while the
  -- morph was still travelling. Caught on video: a Saturn floating in the sky
  -- above a curve that had not arrived yet.
  if self.dockOrb then
    self.dockOrb:pause()
    for _, lb in ipairs(self.dockOrb.labels) do lb.ImageTransparency = 1 end
  end

  local function revealAt(p)
    if self._transitionGen ~= transitionGen then return end
    local a = math.clamp((p - 0.78) / 0.22, 0, 1)
    a = a * a * (3 - 2 * a)
    for _, e in ipairs(pill) do
      if e[1].Parent then L.uiWrite(e[1],e[2],1 + (e[3] - 1) * a) end
    end
  end
  self:_morph(function()
    if self._transitionGen ~= transitionGen then return end
    revealAt(1)
    self._morphBusy = false
    if self.dockOrb then self.dockOrb:play() end
  end, revealAt)

  -- the real panel goes at once: the proxy is what the eye is following
  self:hide("fast", true, transitionGen)
end

function Window:restore()
  self._transitionGen = (self._transitionGen or 0) + 1
  local transitionGen = self._transitionGen
  -- put the detached drawer back where it belongs before anything animates
  if L.Side and L.Side.detached and L.Side.reattach then
    task.defer(function()
      if self._transitionGen == transitionGen then L.try("side.reattach", L.Side.reattach) end
    end)
  end
  -- CANCEL ANY GENIE STILL IN FLIGHT. _morphBusy is otherwise only cleared when
  -- the animation finishes, so restoring part-way through left it set and the
  -- NEXT minimise returned immediately and did nothing -- a dead button with no
  -- error to explain it. Reopening the window is an explicit "stop that".
  self._morphBusy = false
  local stale = L.host():FindFirstChild("DaewidLumenMorph")
  if stale then pcall(function() stale:Destroy() end) end

  -- and hand the pill its opacity back, or the next minimise has nothing to
  -- reveal: minimise() is what set these to 1, so restore() is what must undo it
  if self._dockParts then
    for _, e in ipairs(self._dockParts) do
      if e[1].Parent then M.set(e[1], e[2], e[3]) end
    end
  end
  if self.dockOrb then self.dockOrb:play() end

  M.to(self.dock, "Position", Window.DOCK_OUT, "base")
  self:show(transitionGen)
end

-- TWO THINGS THE HOTKEY COULD REASONABLY MEAN, so it is a setting rather than a
-- decision made for everyone. Hiding drops the window instantly and brings it
-- straight back -- fastest, and nothing is left on screen. Minimising runs the
-- morph down to the dock pill, which takes longer but leaves a visible handle
-- and reads as the window going somewhere rather than blinking out.
--
-- Minimise is the default because the pill is the discoverable way back: hide
-- leaves nothing on screen, so anyone who forgets the key has lost the hub.
function Window:toggle()
  local wantMinimise = not (L.Cfg and L.Cfg.data.toggleAction == "Hide")

  -- minimise routes through hide, so `hidden` already covers "parked on the
  -- pill" as well as "gone" -- one branch brings it back from either
  if self.hidden then
    self:restore()
    return
  end
  if wantMinimise and self.minimise then
    self:minimise()
  else
    self:hide()
  end
end

function Window:subtitle(text)
  if self.subtitleLbl then self.subtitleLbl.Text = tostring(text) end
end

-- ---------------------------------------------------------------- input

-- Persist where and how big the window is, debounced by Cfg.
function Window:_saveGeom()
  if not L.Cfg then return end
  local p, sz = self.shell.Position, self.root.Size
  L.Cfg.set("geom", {
    x = math.floor(p.X.Offset), y = math.floor(p.Y.Offset),
    w = math.floor(sz.X.Offset), h = math.floor(sz.Y.Offset),
  })
end

-- EDGE SNAPPING IS GONE, AND SO IS THE CODE FOR IT. It pulled the window to
-- places the cursor was not, and its confirmation flash -- a half-transparent
-- accent wash over the entire panel -- fired again every time a snap line was
-- crossed, which is what read as the window flickering blue while being
-- dragged. A drag is the one interaction that should have no opinions.

-- The minimise pill's two positions, named once. They were typed out at four
-- call sites with three different motion tokens between them, which is how the
-- dock ended up leaving on a different clock from the window it belongs to.
Window.DOCK_OUT = UDim2.new(0.5, 0, 0, -60)
Window.DOCK_IN  = UDim2.new(0.5, 0, 0, 18)

-- ---------------------------------------------------------------- morph
--
-- Minimising does not shrink the window, it REDRAWS it as a line and folds that
-- line away: the panel's outline contracts to a circle, the circle folds into an
-- infinity, and the infinity spins down into the pill.
--
-- Roblox has no vector paths, so the curve is a string of small frames placed on
-- it each frame. Two bits of maths do all the work and neither needs a lookup
-- table:
--
--   SUPERELLIPSE for the outline. |x/a|^n + |y/b|^n = 1 is an ellipse at n = 2
--   and approaches a rectangle as n grows. Sweeping the exponent turns the
--   window's rounded rectangle into a circle in one continuous family -- there
--   is no rectangle-to-circle interpolation to hand-write.
--
--   GERONO LEMNISCATE for the fold. A circle is (cos t, sin t); the figure-eight
--   is (cos t, sin t cos t). Only Y differs, so the morph is a single lerp on
--   one coordinate: y = sin t * (1 + m(cos t - 1)). At m = 0 it is exactly a
--   circle, at m = 1 exactly an infinity, and every value between is a clean
--   in-between rather than an approximation.

local MORPH_SEGS = 60
local MORPH_TOK  = { 0.95, -0.10 }   -- one long overdamped sweep, no bounce

-- The morph's bloom, as a fraction of the SHORTER viewport axis. 0.62 keeps it
-- clearly a glow around the panel rather than a wash across the display; the
-- uncapped version reached 2256 px on a 2560x1369 screen.
local MORPH_GLOW_CAP = 0.62
-- The span, in pixels, at which the bloom emits its full authored opacity.
-- Larger glows are faded in proportion so the light delivered stays even.
local MORPH_GLOW_REF = 620

-- 0..1 with eased ends, over an arbitrary window of the timeline
local function ramp(p, from, to)
  if to <= from then return p >= to and 1 or 0 end
  local t = math.clamp((p - from) / (to - from), 0, 1)
  return t * t * (3 - 2 * t)
end

function Window:_morph(onDone, onProgress)
  local dock = self.dock
  local r = { x = self.root.AbsolutePosition.X, y = self.root.AbsolutePosition.Y,
              w = self.root.AbsoluteSize.X,     h = self.root.AbsoluteSize.Y }
  local d = { x = dock.AbsolutePosition.X, y = dock.AbsolutePosition.Y,
              w = dock.AbsoluteSize.X,     h = dock.AbsoluteSize.Y }
  if r.w < 4 or d.w < 4 then if onDone then onDone() end return 0 end

  -- own ScreenGui, no UIScale: everything below is raw screen pixels, which is
  -- the only space the window rect and the dock rect are both measured in
  local gui = mk("ScreenGui", {
    Name = "DaewidLumenMorph", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 12,
  })
  gui.Parent = L.host()

  local probe = mk("Frame", { Size = UDim2.fromOffset(1, 1),
    Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Parent = gui })
  L.RunService.Heartbeat:Wait()
  if not gui.Parent then return 0 end
  local k = probe.AbsolutePosition
  probe:Destroy()

  local glow = A.img and A.img.glow and mk("ImageLabel", {
    AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(r.w, r.h),
    BackgroundTransparency = 1, Image = A.img.glow,
    ImageColor3 = T.c.accent, ImageTransparency = 0.86,
    ZIndex = 1, Parent = gui,
  })

  local dotW = math.max(3, math.floor(r.h / 150))
  local segs = {}
  for i = 1, MORPH_SEGS do
    local s = mk("Frame", {
      AnchorPoint = Vector2.new(0.5, 0.5),
      Size = UDim2.fromOffset(dotW, dotW),
      BackgroundColor3 = T.c.text, BorderSizePixel = 0,
      ZIndex = 3, Name = "Seg", Parent = gui,
    })
    L.corner(999, s)
    segs[i] = s
  end

  local ar, br = r.w / 2, r.h / 2
  local R = math.min(r.w, r.h) * 0.30          -- radius of the circle stage
  local cx0, cy0 = r.x + ar, r.y + br
  local cx1, cy1 = d.x + d.w / 2, d.y + d.h / 2

  -- RESOLVED, NOT RAW. This built its spring straight from MORPH_TOK while the
  -- timeout below took the same token THROUGH Motion.resolve, so the two
  -- disagreed about how long the morph lasts the moment any motion profile was
  -- active: under a slower profile the spring finished early and the morph sat
  -- waiting, and under a faster one the timeout cut it off mid-flight. It also
  -- meant the minimise was the one animation in the hub that ignored the motion
  -- profile entirely -- which is exactly why it still felt snappy after the
  -- profile was corrected.
  local morphDur, morphBounce = M.resolve(MORPH_TOK)
  local spring = L.Spring.new(morphDur, morphBounce, 0)
  spring:to(1)

  local conn
  conn = L.RunService.RenderStepped:Connect(function(dt)
    if not gui.Parent then if conn then conn:Disconnect() end return end
    local p = math.clamp(spring:step(dt), 0, 1)
    if onProgress then L.try("window.morphProgress", onProgress, p) end

    local toCircle = ramp(p, 0.00, 0.42)   -- rectangle outline -> circle
    local toInf    = ramp(p, 0.30, 0.72)   -- circle -> infinity
    local away     = ramp(p, 0.62, 1.00)   -- shrink and travel to the pill
    local fade     = ramp(p, 0.80, 1.00)

    local scale = 1 - 0.86 * away
    local cx = cx0 + (cx1 - cx0) * away
    local cy = cy0 + (cy1 - cy0) * away
    local rot = p * 2.6                     -- radians; the fold turns as it goes

    -- exponent sweeps 8 (near-rectangular) down to 2 (a true ellipse)
    local n = 8 - 6 * toCircle
    local cosR, sinR = math.cos(rot), math.sin(rot)

    for i, s in ipairs(segs) do
      local t = (i - 1) / MORPH_SEGS * math.pi * 2
      local ct, st = math.cos(t), math.sin(t)

      -- outline of the panel, as a superellipse
      local ex = (ct >= 0 and 1 or -1) * math.abs(ct) ^ (2 / n)
      local ey = (st >= 0 and 1 or -1) * math.abs(st) ^ (2 / n)
      local rx, ry = ar * ex, br * ey

      -- the symbol: circle at toInf 0, infinity at toInf 1
      local ix = R * ct
      local iy = R * st * (1 + toInf * (ct - 1))

      local x = rx + (ix - rx) * toCircle
      local y = ry + (iy - ry) * toCircle
      x, y = x * scale, y * scale
      local px = cx + x * cosR - y * sinR
      local py = cy + x * sinR + y * cosR

      s.Position = UDim2.fromOffset(px - k.X, py - k.Y)
      s.BackgroundTransparency = fade

      -- a brighter head runs round the curve, so the line reads as drawn
      -- rather than as a ring of dots sitting still
      local head = ((i / MORPH_SEGS) + p * 1.7) % 1
      local lit = head < 0.14 and (1 - head / 0.14) or 0
      s.BackgroundColor3 = T.c.text:Lerp(T.c.accent, 1 - lit * 0.85)
      local sz = dotW * (1 + lit * 1.25) * (0.5 + 0.5 * scale)
      s.Size = UDim2.fromOffset(math.max(sz, 1), math.max(sz, 1))
    end

    if glow then
      -- WHAT THE EYE READS IS AREA x OPACITY, NOT OPACITY.
      --
      -- This was r.w * scale * 1.5 at a flat 0.80. r is the whole window rect,
      -- so on a 1507x1139 panel the first frame drew a 2256x1704 glow -- larger
      -- than a 2560x1369 screen -- in a ScreenGui at DisplayOrder 12, i.e. over
      -- the game and over the hub. On a dark game that is a bloom. On a bright
      -- one it is a screen-wide wash with a soft edge, which is what a user
      -- photographed and reasonably called the visuals leaking.
      --
      -- Two changes. The size is capped against the VIEWPORT, so a bigger panel
      -- or a bigger monitor cannot turn a local bloom into full-bleed. And the
      -- opacity now falls as the glow grows, holding the total light roughly
      -- constant -- a big soft glow and a small tight one deliver the same
      -- amount of light, which is the thing that was actually wrong.
      local vp = L.viewport()
      local cap = math.min(vp.X, vp.Y) * MORPH_GLOW_CAP
      local gw = math.min(r.w * scale * 1.5, cap)
      local gh = math.min(r.h * scale * 1.5, cap)
      glow.Position = UDim2.fromOffset(cx - k.X, cy - k.Y)
      glow.Size = UDim2.fromOffset(gw, gh)

      local opaque = 1 - (0.80 + 0.20 * fade)          -- what it used to emit
      local span = math.max(math.sqrt(gw * gh), 1)
      opaque = opaque * math.clamp(MORPH_GLOW_REF / span, 0.30, 1)
      glow.ImageTransparency = 1 - opaque
    end
  end)

  local total = morphDur + 0.12          -- one source of truth with the spring
  task.delay(total, function()
    if conn then conn:Disconnect() end
    pcall(function() gui:Destroy() end)
    if onDone then onDone() end
  end)
  return total
end


-- ---------------------------------------------------------------- cascade
--
-- Rows arrive one after another instead of the page appearing all at once.
--
-- It has to be an opacity stagger, not a slide: the page uses a UIListLayout,
-- which owns child Position outright, so anything moved is snapped straight back.

local FADE_PROP = {
  Frame = "BackgroundTransparency", TextLabel = "TextTransparency",
  TextButton = "TextTransparency", ImageLabel = "ImageTransparency",
  UIStroke = "Transparency",
}

-- Every part of a row that is currently drawn, with the value it rests at.
local function rowParts(row)
  local parts = {}
  local function add(o)
    local p = FADE_PROP[o.ClassName]
    if not p then return end
    local v = o[p]
    -- already invisible at rest: fading it changes nothing and costs a spring
    if type(v) == "number" and v < 1 then parts[#parts + 1] = { o, p, v } end
  end
  add(row)
  for _, d in ipairs(row:GetDescendants()) do add(d) end
  return parts
end

function Window:_cascade(tab)
  if not self.cascade or self.cascade <= 0 then return end

  -- REST VALUES ARE CAPTURED ONCE, EVER. Reading them at cascade time looks
  -- right until you change tabs twice quickly: the second pass samples rows the
  -- first pass has already faded, records "invisible" as their resting state,
  -- and settles them there. The page comes back permanently blank.
  if not tab._cascadeParts then
    local rows = {}
    for _, c in ipairs(tab.body:GetChildren()) do
      if c:IsA("GuiObject") then rows[#rows + 1] = c end
    end
    -- sorted by where they actually sit: LayoutOrder is 0 for most of these, so
    -- child order would not match reading order
    table.sort(rows, function(a, b) return a.AbsolutePosition.Y < b.AbsolutePosition.Y end)
    local parts = {}
    for i, row in ipairs(rows) do
      if i > 12 then break end        -- past the fold nobody sees the stagger
      parts[i] = rowParts(row)
    end
    tab._cascadeParts = parts
  end

  -- CANCELLABLE. This used to fan out one bare M.after per element, which
  -- nothing could call back: switch tabs twice quickly and the first page's
  -- cascade kept firing into a page you had already left, fading rows back in
  -- underneath the new one. M.seq hands back a handle, so starting a cascade
  -- cancels the one before it.
  if self._cascadeSeq then self._cascadeSeq:cancel() end
  for _, group in ipairs(tab._cascadeParts) do
    for _, e in ipairs(group) do
      if e[1].Parent then M.set(e[1], e[2], 1) end
    end
  end
  self._cascadeSeq = M.seq(tab._cascadeParts, function(group)
    for _, e in ipairs(group) do
      if e[1].Parent then M.to(e[1], e[2], e[3], "base") end
    end
  end, { step = self.cascade, cap = 0.34 })
end

-- MOMENTUM ON RELEASE, because a window that stops dead the instant you let go
-- feels like a decal being repositioned rather than an object being moved. The
-- drag itself stays absolutely direct -- one-to-one with the cursor, no easing,
-- no lag, because anything else makes it feel broken -- and the glide happens
-- only after the button comes up.
--
-- The throw is measured from the last few frames of actual pointer motion, not
-- from the total drag, so flicking it and then pausing before release does
-- nothing: you get the momentum you were carrying at the moment you let go.
function Window:_drag()
  local dragging, startAbs, startOffset, startMouse
  local lastPos, lastT, vel = nil, nil, Vector2.new(0, 0)

  self.header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
      or i.UserInputType == Enum.UserInputType.Touch then
      -- double click the header to maximise / restore
      local now = os.clock()
      if self._lastHeaderClick and now - self._lastHeaderClick < 0.32 then
        self._lastHeaderClick = nil
        self:maximise()
        return
      end
      self._lastHeaderClick = now
      dragging = true
      -- the shell is anchored at its centre, so its centre in screen pixels is
      startAbs = self.shell.AbsolutePosition + self.shell.AbsoluteSize / 2
      startOffset = Vector2.new(self.shell.Position.X.Offset,
                                self.shell.Position.Y.Offset)
      startMouse = i.Position
      lastPos, lastT, vel = i.Position, os.clock(), Vector2.new(0, 0)
      M.stop(self.shell, "Position")
    end
  end)

  L.hold(L.UIS.InputChanged:Connect(function(i)
    if not dragging then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement
      or i.UserInputType == Enum.UserInputType.Touch then
      -- THE WHOLE DRAG LIVES IN REAL SCREEN PIXELS, AND CONVERTS ONCE AT THE END.
      --
      -- The window sits under a UIScale, so a Position OFFSET is in pre-scale
      local sc = (self.scaleObj and self.scaleObj.Scale) or 1
      local d = i.Position - startMouse
      local px, py = startAbs.X + d.X, startAbs.Y + d.Y

      -- the only rule left: keep a grabbable strip on screen, so the window can
      -- always be dragged back rather than lost off an edge
      local vp = L.viewport()
      local hw, hh = self.shell.AbsoluteSize.X / 2, self.shell.AbsoluteSize.Y / 2
      local KEEP = 90
      px = math.clamp(px, -hw + KEEP, vp.X + hw - KEEP)
      py = math.clamp(py, -hh + KEEP, vp.Y + hh - KEEP)

      -- carry the pointer's own speed, smoothed, so one stuttering frame does
      -- not decide the throw
      local now = os.clock()
      if lastPos and lastT and now > lastT then
        local dt = now - lastT
        if dt > 0.002 then
          local inst = Vector2.new((i.Position.X - lastPos.X) / dt,
                                   (i.Position.Y - lastPos.Y) / dt)
          vel = vel:Lerp(inst, 0.4)
          lastPos, lastT = i.Position, now
        end
      end

      M.stop(self.shell, "Position")
      self.shell.Position = UDim2.fromOffset(
        startOffset.X + (px - startAbs.X) / sc,
        startOffset.Y + (py - startAbs.Y) / sc)
    end
  end))

  L.hold(L.UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
      or i.UserInputType == Enum.UserInputType.Touch then
      if dragging then
        dragging = false

        -- GLIDE. A spring toward a point a fraction of a second ahead along the
        -- release velocity: overdamped, so it slides and settles rather than
        -- overshooting and bouncing back, which would read as elastic rather
        -- than heavy. Skipped entirely below a threshold so a careful
        -- repositioning lands exactly where it was put.
        local speed = vel.Magnitude
        if speed > 220 and L.Cfg and L.Cfg.data.dragGlide ~= false then
          local sc = (self.scaleObj and self.scaleObj.Scale) or 1
          local carry = math.clamp(speed / 4200, 0, 1) * 0.16
          local vp = L.viewport()
          local hw = self.shell.AbsoluteSize.X / 2
          local hh = self.shell.AbsoluteSize.Y / 2
          local KEEP = 90
          local absNow = self.shell.AbsolutePosition + self.shell.AbsoluteSize / 2
          local tx = math.clamp(absNow.X + vel.X * carry, -hw + KEEP, vp.X + hw - KEEP)
          local ty = math.clamp(absNow.Y + vel.Y * carry, -hh + KEEP, vp.Y + hh - KEEP)
          local cur = self.shell.Position
          M.to(self.shell, "Position", UDim2.fromOffset(
            cur.X.Offset + (tx - absNow.X) / sc,
            cur.Y.Offset + (ty - absNow.Y) / sc), "gentle")
          M.after(0.42, function() self:_saveGeom() end)
        else
          self:_saveGeom()
        end
        vel = Vector2.new(0, 0)
      end
    end
  end))
end

-- ---------------------------------------------------------------- resize

function Window:_resize()
  local grip = mk("Frame", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -3, 1, -3),
    Size = UDim2.fromOffset(18, 18),
    BackgroundTransparency = 1, ZIndex = 20,
    Name = "Grip", Parent = self.root,
  })
  -- three short diagonals, the universal resize affordance
  for i = 0, 2 do
    local bar = mk("Frame", {
      AnchorPoint = Vector2.new(1, 1),
      Position = UDim2.new(1, -i * 5, 1, 0),
      Size = UDim2.fromOffset(1, 12 - i * 4),
      Rotation = 45,
      BackgroundColor3 = T.c.textOff, BorderSizePixel = 0,
      ZIndex = 21, Parent = grip,
    })
    local _ = bar
  end
  local hit = mk("TextButton", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
    AutoButtonColor = false, ZIndex = 22, Parent = grip,
  })
  self.grip = grip

  local sizing, startSize, startMouse
  hit.MouseButton1Down:Connect(function()
    sizing = true
    startSize = self.root.Size
    startMouse = L.UIS:GetMouseLocation()
    M.to(grip, "BackgroundTransparency", 1, "instant")
  end)

  L.hold(L.UIS.InputChanged:Connect(function(i)
    if not sizing then return end
    if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local m = L.UIS:GetMouseLocation()
    local sc = (self.scaleObj and self.scaleObj.Scale) or 1
    local vp = L.viewport()
    -- the drag happens in screen pixels; the size is authored in unscaled units,
    local dw = (m.X - startMouse.X) / sc
    local dh = (m.Y - startMouse.Y) / sc
    local w = math.clamp(startSize.X.Offset + dw * 2, self.minW, (vp.X - 24) / sc)
    local h = math.clamp(startSize.Y.Offset + dh * 2, self.minH, (vp.Y - 24) / sc)
    self.width, self.height = math.floor(w), math.floor(h)
    self.root.Size = UDim2.fromOffset(self.width, self.height)
    self.shell.Size = UDim2.fromOffset(self.width, self.height)
    M.stop(self.root, "Size")
  end))

  L.hold(L.UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 and sizing then
      sizing = false
      self:_saveGeom()
    end
  end))
end

function Window:maximise()
  local vp = L.viewport()
  local sc = (self.scaleObj and self.scaleObj.Scale) or 1
  if self._maxed then
    local g = self._preMax
    if g then
      M.to(self.root, "Size", UDim2.fromOffset(g.w, g.h), "slow")
      M.to(self.shell, "Position", g.pos, "slow")
      self.shell.Size = UDim2.fromOffset(g.w, g.h)
      self.width, self.height = g.w, g.h
    end
    self._maxed = false
  else
    self._preMax = { w = self.width, h = self.height, pos = self.shell.Position }
    local w = math.floor((vp.X - 48) / sc)
    local h = math.floor((vp.Y - 48) / sc)
    self.width, self.height = w, h
    M.to(self.root, "Size", UDim2.fromOffset(w, h), "slow")
    M.to(self.shell, "Position", UDim2.fromScale(0.5, 0.5), "slow")
    self.shell.Size = UDim2.fromOffset(w, h)
    self._maxed = true
  end
  task.delay(0.5, function() if L.live() then self:_saveGeom() end end)
  return self._maxed
end

function Window:_pointerInside()
  -- INSET-EXCLUDED, to match AbsolutePosition. This used to read
  -- GetMouseLocation, which is the inset-INCLUDED value, so the test was 58 px
  -- out -- the window counted the pointer as inside while it was still above
  -- the title bar, and stopped counting it 58 px before the bottom edge.
  local m = L.pointer()
  local p, sz = self.root.AbsolutePosition, self.root.AbsoluteSize
  return m.X >= p.X and m.X <= p.X + sz.X and m.Y >= p.Y and m.Y <= p.Y + sz.Y
end

function Window:_hotkeys(key)
  self.toggleKey = key or (L.Cfg and L.Cfg.keyCode()) or Enum.KeyCode.RightControl
  local NUM = {
    [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
    [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
    [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
  }
  L.hold(L.UIS.InputBegan:Connect(function(i, typing)
    if typing or not L.live() or (L.Binds and L.Binds.capturing) or L.UIS:GetFocusedTextBox() then return end
    if i.KeyCode == self.toggleKey then self:toggle() return end
    -- ONLY WHILE THE POINTER IS OVER THE WINDOW. 1-5 is the Roblox tool hotbar;
    -- binding them globally means every weapon swap in a game also changes tab.
    local n = NUM[i.KeyCode]
    if n and not self.hidden and self.tabs[n] and self:_pointerInside() then
      self:select(n)
    end
  end))
end

end
