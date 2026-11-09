do -- ==== lm_06_controls.lua ====
-- LUMEN :: CONTROLS
-- Toggle, slider, segmented, dropdown, keybind, input, buttons, log view.
--
-- Every control is the same row shape, so a new one inherits the right padding,
-- hover feel and disabled state for free.
--
-- A control never claims a state it did not reach: if its callback throws or
-- returns false, it puts itself back.

local L = getgenv().__DAEWID_BALL_LUMEN
local T, M, A = L.T, L.Motion, L.A
local mk = L.mk

local C = {}
L.C = C

-- EVERY OPEN POPOVER, SO SOMETHING ELSE CAN SHUT IT.
--
-- Leaving a tab used to destroy the overlay's children directly, which removed
-- the menu from the screen but left the dropdown that owned it still believing
-- it was open -- so the next click on it ran the close path against a destroyed
-- frame and did nothing visible. The control looked dead until you clicked it
-- twice. Closing through the owner keeps the state and the pixels in agreement.
--
-- A plain list, pruned on use: weak keys cannot track this, because the frame is
-- an Instance held by the Roblox tree and would be collected out from under us.
C._pops = {}

-- Controls by their persistence id, so anything that changes a setting from
-- outside its own row can move the visible control too. Theme.setMotion has
-- called C.find since it was written and it has never existed, so that call has
-- been silently doing nothing -- which is how a dropdown ends up showing a
-- profile that is not the one running.
-- STRONG VALUES, PRUNED BY FRAME LIVENESS. Weak values could never work here:
-- every register() call site is fire-and-forget, so nothing else in Lua holds
-- the api and the collector took live controls at random.
C._reg = {}
C._regN = 0

-- The L._insts test from L.prune, applied to the frame each api carries.
function C.prune()
  local kept, n = {}, 0
  for id, h in pairs(C._reg) do
    local ok, parent = pcall(function() return h.frame and h.frame.Parent end)
    if ok and parent ~= nil then kept[id] = h n = n + 1 end
  end
  C._reg, C._regN = kept, n
  return n
end

function C.find(id)
  local h = C._reg[id]
  if h and h.frame and h.frame.Parent then return h end
  if h then C._reg[id] = nil C._regN = C._regN - 1 end
  return nil
end

local function register(opts, api)
  if not (opts and api) then return api end

  -- THE CONTRACT GOES ON EVERY CONTROL, not the one that happened to get it.
  -- register is the last line of every constructor, so the api is finished and
  -- the frame exists -- nothing else in this file is true of all of them. It
  -- sits above the id check on purpose: a control with no id still gets to be
  -- disabled and to declare a dependency.
  if api.frame and not api.setEnabled then
    api._label = api._label or opts.text or opts._id
    api.setEnabled = function(on, why)
      if api._ix then api._ix.setEnabled(on) end
      C.setEnabled(api, on, why)
    end
    C.dependent(api, opts)
  end

  -- Controls that never persist have no _id. Derive the id bindPersist would
  -- have used rather than leaving them unfindable, but do NOT write it back:
  -- C.pinnable reads opts._id as permission to persist a pin.
  local id = opts._id or (C.autoId and C.autoId(opts))
  if not id then return api end
  if C._reg[id] == nil then
    C._regN = C._regN + 1
    -- A rebuild re-registers the same ids, so growth past the watermark means
    -- genuinely new ones; sweep the retired generation instead of carrying it.
    if C._regN > 256 then C.prune() end
  end
  C._reg[id] = api
  return api
end

-- teardown destroys the frames; the table would otherwise outlive them
L.cleanup(function() C._reg, C._regN = {}, 0 end)

function C.closePopovers(instant)
  local kept = {}
  for _, p in ipairs(C._pops) do
    if p.frame and p.frame.Parent then
      kept[#kept + 1] = p
      L.try("popover.close", p.close, instant)
    end
  end
  C._pops = kept
  return #kept
end

-- read at construction, not captured at load -- see T.px
local function ROWH() return T.px("row") end

-- Register a control as a keyboard focus stop. Order of registration is order of
-- construction, which is top-to-bottom on the page, so Tab already moves the way
-- the eye does without anyone maintaining a tab-index.
--
-- A CONTROL WITH NO KEYBOARD BEHAVIOUR IS NOT A STOP. Tabbing onto something
-- that ignores every key is worse than skipping it: the ring stops somewhere
-- inert and the keyboard appears to have broken.
local function focusable(frame, spec)
  if not L.Focus or not frame then return nil end
  return L.Focus.register(frame, spec)
end

-- ---------------------------------------------------------------- scaffolding

local function row(parent, opts)
  local f = A.surface({
    Parent = parent, elev = 1, radius = T.r.md, sheen = true,
    Size = UDim2.new(1, 0, 0, opts.height or ROWH()),
    Name = "Row",
  })
  f.AutomaticSize = opts.grow and Enum.AutomaticSize.Y or Enum.AutomaticSize.None

  local hasDesc = opts.desc and opts.desc ~= ""
  A.text({
    Text = opts.text or "",
    font = T.font.medium, size = T.size.body, colour = T.c.text,
    Position = UDim2.fromOffset(12, hasDesc and 7 or 0),
    Size = hasDesc and UDim2.new(1, -(opts.rightRoom or 80), 0, 15)
                   or UDim2.new(1, -(opts.rightRoom or 80), 1, 0),
    truncate = true, Parent = f,
  })
  if hasDesc then
    A.text({
      Text = opts.desc,
      font = T.font.body, size = T.size.micro, colour = T.c.textMute,
      Position = UDim2.fromOffset(12, 23),
      Size = UDim2.new(1, -(opts.rightRoom or 80), 0, 13),
      truncate = true, Parent = f,
    })
  end
  -- Self-registration. The control does not know or care which tab it is in --
  -- the palette walks up from this frame when it needs to know, so moving a
  -- control between tabs never leaves a stale entry behind.
  if L.Palette and opts.text then
    L.Palette.add(f, opts.text, opts.desc or "")
  end
  return f
end

-- ---------------------------------------------------------------- static

-- ---------------------------------------------------------------- persistence
--
-- EVERY CONTROL SAVES ITSELF. Before this, a setting survived a reload only if
-- somebody had also declared it in Cfg.SCHEMA by hand -- which covered the
-- twenty interface preferences and none of the hundred-odd controls in the
-- feature tabs. Aim FOV, hitbox size, fling power, every dropdown: rebuilt from
-- source defaults on every execute.
--
-- Rather than add an id to a hundred call sites, the id is derived from where
-- the control sits: the owning module sets a context with C.ctx, C.section
-- tracks the group, and the control's own label finishes it -- "combat.fling.
-- Launch power". Stable across rebuilds because all three come from source, and
-- unique because no two controls in one section share a label. An explicit
-- opts.id always wins if a call site wants to pin one down.
C._ctx, C._section = "hub", ""

-- id -> the default the SOURCE gave the control. Rebuilt at construction every
-- execute, never stored: a saved default outlives the code that changed it, and
-- a stale default is worse than none -- it makes a wrong value look correct.
C._def = {}

function C.ctx(name)
  C._ctx = tostring(name or "hub")
  C._section = ""
  return C
end

local function autoId(opts)
  if type(opts.id) == "string" and opts.id ~= "" then return opts.id end
  local label = opts.text or opts.placeholder
  if type(label) ~= "string" or label == "" then return nil end
  return C._ctx .. "." .. C._section .. "." .. label
end

-- Resolves the saved value into opts.default and wraps opts.callback so the new
-- value is written back. Mutating opts is deliberate: every call site builds it
-- inline, and the alternative is threading two return values through six
-- constructors that each read opts.default in several places.
local function bindPersist(opts)
  if opts.persist == false then return end
  local Cfg = L.Cfg
  if not (Cfg and Cfg.feat and Cfg.setFeat) then return end
  local id = autoId(opts)
  if not id then return end
  opts._id = id

  -- THE CONTROL IS THE SCHEMA. Everything needed to validate this id is already
  -- in opts -- it is the same data the constructor below builds the widget from.
  -- Harvesting it here rather than declaring it in lm_15 is the difference
  -- between 104 declarations somebody maintains and none. The fallbacks match
  -- C.slider's own, so a spec can never be tighter than the control it describes.
  if Cfg.declare then
    local spec
    if type(opts.min) == "number" or type(opts.max) == "number" then
      spec = { t = "number", min = opts.min or 0, max = opts.max or 100 }
    elseif type(opts.items) == "table" and opts.items[1] ~= nil then
      local set, ok = {}, true
      for _, it in ipairs(opts.items) do
        if type(it) == "string" then set[it] = true else ok = false end
      end
      -- a control's own default is legal by definition, even if a call site
      -- forgot to put it in the list
      if ok then
        if type(opts.default) == "string" then set[opts.default] = true end
        spec = { t = "string", enum = set }
      end
    else
      local d = type(opts.default)
      if d == "boolean" or d == "string" or d == "number" then spec = { t = d } end
    end
    if spec then Cfg.declare(id, spec) end
  end

  local sourceDefault = opts.default
  -- THE ONE MOMENT id -> default EXISTS. opts.default becomes the saved value
  -- below and the source fact is gone for the rest of the session.
  if sourceDefault ~= nil then C._def[id] = sourceDefault end
  local saved = Cfg.feat(id, nil)
  local restored

  -- only accept a stored value of the same shape the control expects, so a
  -- hand-edited file cannot hand a slider a string
  if saved ~= nil and (sourceDefault == nil or type(saved) == type(sourceDefault)) then
    -- A STORED **ON** IS REMEMBERED BUT NOT RE-APPLIED. See Cfg.ARM_SAFE: the
    -- only booleans that come back armed are the ones that cannot act on their
    -- own (appearance sub-options, anti-AFK). Everything else starts off, so
    -- executing the hub never leaves something already running.
    --
    -- Numbers, strings and a stored `false` skip this entirely -- a slider
    -- cannot switch anything on by itself, and restoring an OFF is a no-op.
    local allowed = true
    if Cfg.NO_APPLY and Cfg.NO_APPLY[id] then
      -- A number that writes straight to the character. Same surprise as a
      -- switch coming back on, so it gets the same answer.
      allowed = false
    elseif type(saved) == "boolean" and saved and Cfg.restorable then
      allowed = Cfg.restorable(id)
    end
    if allowed then
      opts.default = saved
      restored = saved
    end
  end

  -- LIVE VALUES, NOT THE STORE, are what opts.when reads -- ARM_SAFE above can
  -- leave disk holding a `true` for a switch that came back off. Notifying here
  -- is also what covers a dependency built AFTER its dependent.
  C._live[id] = opts.default
  C.notify(id)

  local cb = opts.callback

  -- ANYTHING THAT CAME BACK ARMED GETS RECORDED. Restoring switched-on features
  -- is only reasonable if the operator can see what was restored and undo it in
  -- one click; without that it is the old silent-rearm bug with better
  -- intentions. The ledger is what buys the denylist in lm_15_config.
  if restored == true and Cfg.noteRestored then
    Cfg.noteRestored(id, restored, cb)
  end

  opts.callback = function(v)
    local r, why
    if cb then r, why = cb(v) end
    -- C.toggle reverts on an explicit false, so a refused change must not be
    -- the one that gets written to disk
    if r ~= false then
      Cfg.setFeat(id, v)
      if C._live[id] ~= v then C._live[id] = v C.notify(id) end
    end
    return r
  end

  -- RESTORING THE KNOB IS NOT RESTORING THE SETTING. The control now shows the
  -- saved value, but the feature module still holds whatever its source default
  -- was -- so the panel would read 7250 while the engine used 3000, which is
  -- worse than not saving at all. Push it through the original callback once,
  -- deferred so the page has finished building first, and using `cb` rather
  -- than the wrapper so restoring does not write the value straight back.
  if restored ~= nil and restored ~= sourceDefault and cb then
    task.defer(function() L.try("cfg.restore", cb, restored) end)
  end
end

C.bindPersist = bindPersist
C.autoId = autoId

-- A refusal is an answer, not a crash. `false[, why]` back from a callback means
-- the feature declined, so the control has to put the visible value back --
-- otherwise the knob, the disk and the engine hold three different numbers and
-- the next launch looks like the hub lost the setting. Returns ok, why.
local function commitValue(kind, opts, v, quiet)
  if not opts.callback then return true end
  local label = kind .. ":" .. tostring(opts.text or opts.placeholder or "?")
  local ran, res, why = L.try(label, opts.callback, v)
  if ran and res ~= false then return true end
  why = why or (ran and "Did not engage." or "Threw while applying.")
  if ran then L.log("refused", label, why) end   -- refused, not broken: fault log stays clean
  if not quiet and L.Toast then
    L.Toast.warn(tostring(opts.text or "Setting"), tostring(why))
  end
  return false, why
end

C.commitValue = commitValue

-- ------------------------------------------------------- enabled + dependency
--
-- ONE VEIL RATHER THAN FIFTEEN DISABLED PATHS. A.interactive returns a
-- setEnabled, but it reaches exactly one constructor; the other fourteen bury
-- their input in track, pill, popover and TextBox children that share no shape.
-- A scrim parented to the row sits above all of them.
--
-- Transparency, not a new colour token: a T.c.disabled would have to be painted
-- on every label, knob, stroke and gradient inside each control -- six
-- instances in the slider alone -- which is the per-constructor work this is
-- meant to delete, and lm_16_theme would need a swap entry for it. A scrim in
-- the page ground colour washes the whole row at once and follows any theme.
local VEIL_A = 0.42

function C.setEnabled(api, on, why)
  local f = api and api.frame
  if not f then return end
  on = on and true or false
  api._why = (not on) and (why or "Not available yet.") or nil

  local v = f:FindFirstChild("Veil")
  if on and not v then return end
  if not v then
    -- clear of A.interactive's Hit overlay at frame.ZIndex + 5 and the content
    -- lift at + 6; under Sibling behaviour it cannot escape its own row
    v = mk("TextButton", {
      Name = "Veil", Text = "", AutoButtonColor = false, Active = true,
      Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.c.surface,
      BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
      ZIndex = (f.ZIndex or 1) + 20, Parent = f,
    })
    local rc = f:FindFirstChildOfClass("UICorner")
    mk("UICorner", {
      CornerRadius = rc and rc.CornerRadius or UDim.new(0, T.r.md), Parent = v,
    })
    -- SAY WHY ON HOVER, TOAST IT ON CLICK: the segmented locked pattern, the
    -- only unavailable state in this library nobody reads as a bug. A.explain
    -- freezes its text, so keep the hint entry to retarget it.
    A.explain(v, api._why or "Not available yet.", tostring(api._label or ""))
    api._hint = A.hints[#A.hints]
    v.MouseButton1Click:Connect(function()
      if L.Toast then
        L.Toast.info(tostring(api._label or "Unavailable"),
                     tostring(api._why or "Not available yet."))
      end
    end)
  end
  if api._hint then api._hint.text = api._why or "Not available yet." end

  f:SetAttribute("lmDisabled", (not on) or nil)
  -- a fully transparent GuiButton still eats clicks, so enabling hides it
  -- rather than fading it out
  if on then
    v.Visible = false
    M.set(v, "BackgroundTransparency", 1)
  elseif not v.Visible then
    M.set(v, "BackgroundTransparency", 1)
    v.Visible = true
    M.to(v, "BackgroundTransparency", VEIL_A, "fast")
  end
end

-- opts.when: what a control needs before it means anything. A string is a
-- bindPersist auto-id ("combat.aim.Aim assist"); a function is called as-is.
-- Declared once at the call site instead of a setEnabled fan-out hand-written
-- into every owning module's callback.
C._deps, C._any, C._live = {}, {}, {}

local function met(when)
  if type(when) == "function" then
    local ok, val = pcall(when)
    return ok and val ~= nil and val ~= false
  end
  -- NOT Cfg.feat: ARM_SAFE can leave the store holding a `true` for a switch
  -- that deliberately came back off, and a dependent follows the knob. A
  -- numeric id is satisfied by 0, so point `when` at a toggle.
  local val = C._live[when]
  return val ~= nil and val ~= false
end

local function applyDep(e)
  local f = e.api.frame
  if not (f and f.Parent) then return false end     -- rebuilt page: drop it
  e.api.setEnabled(met(e.when), e.why)
  return true
end

local function sweepAny()
  for i = #C._any, 1, -1 do
    if not applyDep(C._any[i]) then table.remove(C._any, i) end
  end
end

function C.notify(id)
  local list = C._deps[id]
  if list then
    for i = #list, 1, -1 do
      if not applyDep(list[i]) then table.remove(list, i) end
    end
  end
  -- A function dependency cannot be keyed by id, so it is re-read on any
  -- change -- at most once a frame, or dragging a slider would run every
  -- predicate in the hub sixty times a second.
  if #C._any > 0 and not C._anyQueued then
    C._anyQueued = true
    task.defer(function() C._anyQueued = false sweepAny() end)
  end
end

function C.dependent(api, opts)
  local w = opts.when
  if w == nil then return end
  local e = {
    api = api, when = w,
    why = opts.whyDisabled or (type(w) == "string"
      and ("Turn on " .. (string.match(w, "[^.]+$") or w) .. " first.")
      or "Not available yet."),
  }
  if type(w) == "string" then
    local l = C._deps[w]
    if not l then l = {} C._deps[w] = l end
    l[#l + 1] = e
  else
    C._any[#C._any + 1] = e
  end
  applyDep(e)                    -- the state at construction, before first paint
end

-- ---------------------------------------------------------------- pinnable
--
-- Registers a built control with L.Pins and makes the row itself the pin
-- affordance: RIGHT-CLICK ANY ROW TO PIN IT. A dedicated pin glyph on every
-- control would have to be drawn, positioned and kept clear of the value
-- readout on six different row layouts; the secondary click is already unused
-- everywhere in the hub and costs one connection.
function C.pinnable(frame, opts, spec)
  local id = opts._id
  if not (id and L.Pins and frame) then return end
  spec.label = opts.text or id
  spec.ctx = C._ctx
  L.Pins.register(id, spec)

  local btn = frame:FindFirstChild("Hit")
  if not btn then return end
  btn.MouseButton2Click:Connect(function()
    local Cfg = L.Cfg
    if not (Cfg and Cfg.setPin) then return end
    local now = Cfg.pinned(id)
    Cfg.setPin(id, not now)
    if L.Toast then
      L.Toast.info(now and "Unpinned" or "Pinned",
        tostring(opts.text or id) ..
        (now and " removed from the dock." or " added to the dock strip."))
    end
  end)
end

-- `shown` overrides only what is PAINTED. `text` still sets C._section, which
-- is half of every id underneath, so a section can be relabelled or moved to
-- another tab without orphaning a single saved value.
function C.section(parent, text, shown)
  C._section = tostring(text or "")
  local h = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1,
    Name = "Section", Parent = parent,
  })
  A.text({
    Text = L.track(string.upper(shown or text or ""), 1),
    font = T.font.medium, size = T.size.nano, colour = T.c.textOff,
    Position = UDim2.fromOffset(2, 12), Size = UDim2.new(1, -4, 0, 14),
    Parent = h,
  })
  return h
end

function C.paragraph(parent, text)
  local f = A.surface({
    Parent = parent, elev = 1, radius = T.r.md,
    Size = UDim2.new(1, 0, 0, 0), Name = "Paragraph",
  })
  f.AutomaticSize = Enum.AutomaticSize.Y
  L.pad(12, 12, 12, 12, f)
  A.text({
    Text = text or "", wrap = true,
    font = T.font.body, size = T.size.label, colour = T.c.textDim,
    valign = Enum.TextYAlignment.Top,
    Size = UDim2.new(1, 0, 0, 0), autoSize = Enum.AutomaticSize.Y,
    Parent = f,
  })
  return f
end

-- ---------------------------------------------------------------- tiles
--
-- A row of small metric cards. Numbers get the mono face and the accent; their
-- captions get the muted face. Keeping the figure and its label in different
-- weights is what lets the eye read a row of these at a glance instead of
-- parsing each one.
function C.tiles(parent, items, opts)
  opts = opts or {}
  local n = math.max(#items, 1)
  local holder = mk("Frame", {
    Size = UDim2.new(1, 0, 0, opts.height or 62),
    BackgroundTransparency = 1, Name = "Tiles", Parent = parent,
  })
  local gap = T.gap.md
  local layout = L.list(gap, Enum.FillDirection.Horizontal, holder)
  layout.VerticalAlignment = Enum.VerticalAlignment.Center

  local api = { frame = holder, cells = {} }
  for i, item in ipairs(items) do
    local cell = A.surface({
      Parent = holder, elev = 1, radius = T.r.md, sheen = true,
      -- width is scale-based minus its share of the gaps, so the row fills
      -- exactly regardless of how many tiles are passed
      Size = UDim2.new(1 / n, -(gap * (n - 1)) / n, 1, 0),
      Name = "Tile", LayoutOrder = i,
    })
    A.text({
      Text = string.upper(item.label or ""),
      font = T.font.medium, size = T.size.tiny, colour = T.c.textOff,
      Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, 12),
      truncate = true, Parent = cell,
    })
    local val = A.text({
      Text = tostring(item.value or "-"),
      font = T.font.mono, size = T.size.head,
      colour = item.colour or T.c.accent,
      Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 18),
      truncate = true, Parent = cell,
    })
    api.cells[item.key or i] = val
  end

  -- ROLL THE NUMBER rather than swapping it. A figure that jumps reads as a
  -- readout being overwritten; one that travels reads as a value changing.
  --
  -- Only plain "number" or "number unit" rolls. "29/35" and "0:24" are two
  -- numbers and a clock -- interpolating either produces nonsense on the way.
  local rolls = {}

  function api:set(key, text, colour)
    local lbl = self.cells[key]
    if not lbl then return end
    if colour then M.to(lbl, "TextColor3", colour, "fast") end
    text = tostring(text)

    local num, unit = text:match("^%s*(%-?%d+)%s*(%a*)%s*$")
    if not L.Cfg or L.Cfg.data.rollNumbers == false or not num then
      rolls[key] = nil
      lbl.Text = text
      return
    end
    local target = tonumber(num)
    local r = rolls[key]
    if not r then
      -- first value is not a change, so it appears rather than counting up
      rolls[key] = { spring = L.Spring.new(0.55, -0.2, target), unit = unit, lbl = lbl }
      lbl.Text = text
      return
    end
    r.unit, r.lbl = unit, lbl
    r.spring:to(target)
  end

  task.spawn(function()
    while L.live() and holder.Parent do
      local dt = L.RunService.Heartbeat:Wait()
      for _, r in pairs(rolls) do
        if not r.spring:settled(0.5, 2) then
          local v = r.spring:step(dt)
          r.lbl.Text = string.format("%d%s%s", v + 0.5,
                                     r.unit ~= "" and " " or "", r.unit)
        end
      end
    end
  end)

  return api
end

-- ---------------------------------------------------------------- actions
--
-- A row of small pills, not a stack of full-width bars. A button that spans the
-- whole column reads as the most important thing on the page; three of them
-- stacked read as a page made entirely of alarms. The reference uses compact
-- pills for exactly this reason -- weight is spent on the one primary action and
-- nothing else.
function C.actions(parent, items)
  local holder = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1,
    Name = "Actions", Parent = parent,
  })
  local lay = L.list(T.gap.sm, Enum.FillDirection.Horizontal, holder)
  lay.VerticalAlignment = Enum.VerticalAlignment.Center

  local api = { frame = holder }
  for i, item in ipairs(items) do
    -- width follows the label: TextBounds after a frame, so the pill hugs its
    -- text instead of every action being the same arbitrary size
    local w = 22 + #tostring(item.text) * 7
    local f = A.surface({
      Parent = holder, elev = item.primary and 1 or 1, radius = T.r.pill,
      Size = UDim2.fromOffset(w, 32), Name = "Pill", LayoutOrder = i,
      fill = item.primary and T.c.accent or nil,
      line = not item.primary,
    })
    if item.primary then A.accentGradient(f, 100) end
    A.text({
      Text = item.text, font = T.font.medium, size = T.size.label,
      colour = item.primary and T.c.accentInk or T.c.textDim,
      align = Enum.TextXAlignment.Center, Parent = f,
    })
    A.interactive(f, {
      radius = T.r.pill,
      layerColour = item.primary and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
      hoverAlpha = item.primary and 0.9 or 0.95,
      pressAlpha = item.primary and 0.8 or 0.9,
      onClick = function() if item.callback then item.callback() end end,
    })
    -- each pill is its own stop: a row of three actions is three decisions
    focusable(f, {
      radius = T.r.pill, label = item.text,
      activate = function() if item.callback then item.callback() end end,
    })
    -- Buttons are pinnable too, which is most of the point: "Open player panel"
    -- is a thing you want one click away, and it is not a setting so nothing
    -- else in this file would ever have given it an id.
    C.pinnable(f, { _id = "action." .. C._ctx .. "." .. tostring(item.text),
                    text = item.text }, {
      kind = "action",
      run = function() if item.callback then item.callback() end end,
    })
  end
  return api
end

-- ---------------------------------------------------------------- button

function C.button(parent, opts)
  opts = opts or {}
  local f = A.surface({
    Parent = parent, elev = 1, radius = T.r.md,
    Size = UDim2.new(1, 0, 0, 38), Name = "Button",
    fill = opts.primary and T.c.accent or nil,
    line = not opts.primary,
  })
  if opts.primary then A.accentGradient(f, 90) end

  A.text({
    Text = opts.text or "Button",
    font = T.font.strong, size = T.size.body,
    colour = opts.primary and T.c.accentInk or T.c.text,
    align = Enum.TextXAlignment.Center,
    Parent = f,
  })

  local api = {}
  local ix = A.interactive(f, {
    radius = T.r.md,
    layerColour = opts.primary and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
    hoverAlpha = opts.primary and 0.9 or 0.95,
    pressAlpha = opts.primary and 0.8 or 0.90,
    onClick = function() if opts.callback then opts.callback() end end,
  })
  api.frame, api._ix = f, ix
  register(opts, api)
  focusable(f, {
    radius = T.r.md, label = opts.text,
    activate = function() if opts.callback then opts.callback() end end,
  })
  return api
end

-- ---------------------------------------------------------------- toggle

function C.toggle(parent, opts)
  opts = opts or {}
  bindPersist(opts)
  local state = opts.default and true or false
  local f = row(parent, { text = opts.text, desc = opts.desc, rightRoom = 68 })

  local track = mk("Frame", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.fromOffset(38, 21),
    BackgroundColor3 = T.c.active,
    BorderSizePixel = 0, ZIndex = 2,
    Parent = f,
  })
  L.corner(999, track)
  local trackStroke = L.stroke(T.c.lineStrong, 1, 0.4, track)

  -- The "on" state is a GRADIENT, not a flat accent. A UIGradient tints whatever
  -- BackgroundColor3 it sits on, so it cannot be faded in and out on the track
  -- itself without also dragging the off-state colour through it -- hence a
  -- separate fill layer whose transparency is what actually animates.
  local fill = mk("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0, ZIndex = 2, Parent = track,
  })
  L.corner(999, fill)
  A.accentGradient(fill, 0)

  local knob = mk("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 3, 0.5, 0),
    Size = UDim2.fromOffset(15, 15),
    BackgroundColor3 = T.c.textDim,
    BorderSizePixel = 0, ZIndex = 3,
    Parent = track,
  })
  L.corner(999, knob)

  local api = {}
  local function paint(immediate)
    local tok = immediate and nil or "fast"
    local pos = UDim2.new(0, state and 20 or 3, 0.5, 0)
    local setter = immediate and M.set or M.to
    setter(knob, "Position", pos, tok)
    setter(fill, "BackgroundTransparency", state and 0 or 1, tok)
    setter(knob, "BackgroundColor3", state and T.c.accentInk or T.c.textDim, tok)
    setter(trackStroke, "Transparency", state and 1 or 0.4, tok)
  end

  -- A CONTROL MAY NOT CLAIM A STATE IT NEVER REACHED. This used to paint the new
  -- state and fire the callback with no interest in the answer, so a feature
  function api:set(v, silent)
    v = v and true or false
    if v == state then return end
    state = v
    paint(false)
    if silent or not opts.callback then return end

    -- labelled with the control's own text: "toggle.cb" in a fault list tells
    -- you a toggle broke but not which one, which is barely better than silence
    local label = "toggle:" .. tostring(opts.text or "?")
    local ran, res, why = L.try(label, opts.callback, state)
    if ran and res ~= false then return end

    state = not state
    paint(false)
    if ran then                       -- refused, not broken: the fault log stays clean
      L.log("refused", label, why or "did not engage")
    end
    if L.Toast and state == false then
      L.Toast.warn(tostring(opts.text or "Feature"),
                   tostring(why or (ran and "Did not engage." or "Threw while starting.")))
    end
  end
  function api:get() return state end

  A.interactive(f, { radius = T.r.md, onClick = function() api:set(not state) end })
  -- Enter flips it; Left and Right set it outright, so a keyboard user can force
  -- a known state instead of toggling and having to look to find out which way
  -- it went.
  focusable(f, {
    radius = T.r.md, label = opts.text,
    activate = function() api:set(not state) end,
    adjust = function(dir) api:set(dir > 0) end,
  })
  paint(true)
  api.frame = f
  register(opts, api)
  -- pinnable: the strip drives THIS api, so a pinned switch and the switch in
  -- the tab are one object and cannot drift apart
  C.pinnable(f, opts, {
    kind = "toggle",
    get = function() return api:get() end,
    set = function(v) api:set(v) end,
  })
  return api
end

-- ---------------------------------------------------------------- segmented

-- Three or four mutually exclusive choices, all visible at once. A dropdown
-- hides the options behind a click and gives no sense of where the current one
-- sits in the range; a segmented control shows the whole scale.
function C.segmented(parent, opts)
  opts = opts or {}
  bindPersist(opts)
  local items = opts.items or {}
  local value = opts.default or items[1]

  -- CELLS ARE MEASURED, NOT ASSUMED. Every cell used to be exactly 54 px wide
  -- and the bar 38 + n*54, both independent of what the labels actually said.
  -- That fitted "Calm" and "Default" and clipped "Comfortable" to "Comfortab"
  -- while the selected pill overhung the panel edge -- and the control it broke
  -- was Density, which is itself the thing that changes text size. The one
  -- control most able to invalidate a hardcoded width was the one relying on it.
  local CELL_PAD, GAP, BAR_PAD, MIN_CELL = 16, 3, 3, 44
  local TextService = game:GetService("TextService")
  local function widthOf(s)
    local ok, sz = pcall(function()
      return TextService:GetTextSize(s, T.size.micro, T.font.medium,
                                     Vector2.new(4096, 100))
    end)
    if ok and sz then return math.ceil(sz.X) end
    return #s * math.ceil(T.size.micro * 0.62)      -- generous, so it clips last
  end

  local widths, total = {}, 0
  for i, item in ipairs(items) do
    widths[i] = math.max(widthOf(tostring(item)) + CELL_PAD, MIN_CELL)
    total = total + widths[i]
  end
  local barW = total + GAP * math.max(#items - 1, 0) + BAR_PAD * 2

  -- the row reserves what the bar actually needs, so a long option pushes the
  local f = row(parent, { text = opts.text, desc = opts.desc, rightRoom = barW + 24 })

  local bar = mk("Frame", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.fromOffset(barW, 26),
    BackgroundColor3 = T.c.overlay, BorderSizePixel = 0, ZIndex = 2, Parent = f,
  })
  L.corner(T.r.sm + 2, bar)
  L.stroke(T.c.line, 1, 0.35, bar)
  L.pad(3, 3, 3, 3, bar)
  local lay = L.list(3, Enum.FillDirection.Horizontal, bar)
  lay.VerticalAlignment = Enum.VerticalAlignment.Center

  local api, cells = {}, {}
  local function paint()
    for _, c in ipairs(cells) do
      local on = (c.value == value)
      M.to(c.pill, "BackgroundTransparency", on and 0 or 1, "fast")
      M.to(c.label, "TextColor3",
        on and T.c.accentInk
        or (c.locked and T.c.textOff or T.c.textMute), "fast")
    end
  end

  for i, item in ipairs(items) do
    local cell = mk("Frame", {
      Size = UDim2.fromOffset(widths[i], 20), BackgroundTransparency = 1,
      LayoutOrder = i, ZIndex = 3, Parent = bar,
    })
    local pill = mk("Frame", {
      Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.c.accent,
      BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = cell,
    })
    L.corner(T.r.sm, pill)
    A.accentGradient(pill, 135)
    local lbl = A.text({
      Text = tostring(item), font = T.font.medium, size = T.size.micro,
      colour = T.c.textMute, align = Enum.TextXAlignment.Center,
      ZIndex = 4, Parent = cell,
    })
    -- A LOCKED OPTION STILL HAS TO SAY WHY, or it reads as a bug.
    --
    -- Hiding an option the user has already seen is worse than showing it
    -- unavailable: they go looking for the thing that vanished. So it stays in
    -- the bar, visibly out of reach, and says what it is waiting for the moment
    -- the pointer touches it.
    local why = opts.locked and opts.locked[item]
    if why then
      A.explain(cell, why, tostring(item))
      A.interactive(cell, { radius = T.r.sm, hoverAlpha = 0.97, spot = false,
        onClick = function()
          L.Toast.info(tostring(item), why)
        end })
    else
      A.interactive(cell, { radius = T.r.sm, hoverAlpha = 0.95,
        onClick = function() api:set(item) end })
    end
    cells[#cells + 1] = { pill = pill, label = lbl, value = item, locked = why }
  end

  function api:set(v, silent)
    if v == value then return end
    local prev = value
    value = v
    paint()
    if silent then return end
    if not commitValue("segmented", opts, v) then
      value = prev
      paint()
    end
  end
  function api:get() return value end

  -- ONE STOP FOR THE WHOLE CONTROL, not one per cell. The cells are a single
  -- choice shown in full; making each its own stop would mean four Tab presses
  -- to cross one setting, and the ring would say "this option" when what is
  -- actually selected is the row.
  focusable(f, {
    radius = T.r.md, label = opts.text,
    adjust = function(dir)
      local i = 1
      for k, item in ipairs(items) do if item == value then i = k break end end
      -- step OVER locked options rather than stopping on one: arrowing into a
      -- dead end feels like the control broke
      local j = i
      repeat
        j = math.clamp(j + dir, 1, #items)
        if not (opts.locked and opts.locked[items[j]]) then api:set(items[j]) return end
      until j <= 1 or j >= #items
    end,
    activate = function()                       -- Enter cycles forward, wrapping
      local i = 1
      for k, item in ipairs(items) do if item == value then i = k break end end
      for step = 1, #items do
        local j = ((i - 1 + step) % #items) + 1
        if not (opts.locked and opts.locked[items[j]]) then api:set(items[j]) return end
      end
    end,
  })

  paint()
  api.frame = f
  register(opts, api)
  return api
end

-- ---------------------------------------------------------------- slider

function C.slider(parent, opts)
  opts = opts or {}
  bindPersist(opts)
  local min   = opts.min or 0
  local max   = opts.max or 100
  local step  = opts.step or 1
  local value = math.clamp(opts.default or min, min, max)

  local f = row(parent, { text = opts.text, desc = opts.desc,
                          rightRoom = 150, height = 50 })

  local readout = A.text({
    Text = "", font = T.font.mono, size = T.size.micro, colour = T.c.accent,
    align = Enum.TextXAlignment.Right,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(60, 13),
    ZIndex = 2, Parent = f,
  })

  -- ---- typed entry ----------------------------------------------------
  --
  -- A SLIDER CANNOT EXPRESS AN EXACT NUMBER. Dragging to precisely 137 on a
  -- 16..250 track is roughly a one-pixel target, and the keyboard route added in
  -- Wave 3 is 121 key presses. The readout was already showing the value, so it
  -- becomes the place you can also type it -- the number and the field for the
  -- number are the same object, which is the only version nobody has to discover.
  local entry = mk("TextBox", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, 4), Size = UDim2.fromOffset(64, 20),
    BackgroundColor3 = T.c.active, BackgroundTransparency = 1,
    Text = "", TextColor3 = T.c.accent, Font = T.font.mono,
    TextSize = T.size.micro, TextXAlignment = Enum.TextXAlignment.Right,
    ClearTextOnFocus = false, Visible = false, ZIndex = 4, Name = "Entry",
    Parent = f,
  })
  L.corner(T.r.sm, entry)
  L.pad(0, 6, 0, 6, entry)
  local entryStroke = L.stroke(T.c.accent, 1, 0.35, entry)

  local hitReadout = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(68, 20),
    BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
    ZIndex = 3, Name = "ReadoutHit", Parent = f,
  })

  local track = mk("Frame", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -12, 1, -12),
    Size = UDim2.fromOffset(132, 4),
    BackgroundColor3 = T.c.active,
    BorderSizePixel = 0, ZIndex = 2,
    Parent = f,
  })
  L.corner(999, track)

  local fill = mk("Frame", {
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = T.c.accent,
    BorderSizePixel = 0, ZIndex = 3,
    Parent = track,
  })
  L.corner(999, fill)
  A.accentGradient(fill, 0)

  local knob = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0, 0.5),
    Size = UDim2.fromOffset(11, 11),
    BackgroundColor3 = T.c.text,
    BorderSizePixel = 0, ZIndex = 4,
    Parent = track,
  })
  L.corner(999, knob)

  local hit = mk("TextButton", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(1, 20, 0, 22),
    BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
    ZIndex = 5, Parent = track,
  })

  -- ---- the curve ---------------------------------------------------------
  --
  -- A LINEAR SLIDER OVER A WIDE RANGE IS NOT A CONTROL, IT IS A LOTTERY.
  -- "Launch power" ran 500 to 250,000 across about 130 pixels: every pixel was
  -- roughly nineteen hundred units, so the low half of the range -- where most
  -- of the useful values live -- could not be aimed at at all, and lowering the
  -- floor or raising the ceiling only makes that worse.
  --
  -- `curve = "log"` spends slider travel proportionally instead: equal distance
  -- for equal RATIO, so 1->10 takes as much room as 100,000->1,000,000. That is
  -- the only way one control can offer both fine tuning at the bottom and
  -- millions at the top, which is exactly what these settings need.
  --
  -- Quantisation follows the curve too: snapping a logarithmic value to a fixed
  -- linear step would put every stop at the bottom and none at the top.
  local logCurve = (opts.curve == "log")
  local logLo, logSpan
  if logCurve then
    logLo = math.log(math.max(min, 1e-4))
    logSpan = math.log(math.max(max, min + 1e-3)) - logLo
    if logSpan <= 0 then logCurve = false end
  end

  local function toAlpha(v)
    if logCurve then
      return math.clamp((math.log(math.max(v, 1e-4)) - logLo) / logSpan, 0, 1)
    end
    return (max > min) and math.clamp((v - min) / (max - min), 0, 1) or 0
  end

  local function fromAlpha(a)
    a = math.clamp(a, 0, 1)
    if logCurve then return math.exp(logLo + a * logSpan) end
    return min + a * (max - min)
  end

  local api = {}
  local function quantise(v)
    v = math.clamp(v, min, max)
    if logCurve then
      -- significant figures rather than a fixed step: 1.2, then 12, then 120,
      -- so the readout stays legible across five orders of magnitude
      local mag = math.floor(math.log10(math.max(math.abs(v), 1e-4)))
      local q = 10 ^ math.max(mag - 2, -3)
      v = math.floor(v / q + 0.5) * q
    elseif step > 0 then
      v = math.floor((v - min) / step + 0.5) * step + min
    end
    return math.clamp(v, min, max)
  end

  local function paint(immediate)
    local a = toAlpha(value)
    -- 1,250,000 rather than 1250000: past four digits the eye cannot count
    -- zeroes, and these ranges now reach seven
    local shown
    if math.abs(value) >= 10000 then
      local whole = string.format("%d", math.floor(value + 0.5))
      local sep = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
      shown = sep
    else
      shown = tostring(L.round(value, 3))
    end
    readout.Text = opts.suffix and (shown .. opts.suffix) or shown
    if immediate then
      M.set(fill, "Size", UDim2.fromScale(a, 1))
      M.set(knob, "Position", UDim2.fromScale(a, 0.5))
    else
      -- `gentle` is overdamped on purpose: a slider fill that springs PAST the
      -- value the readout already shows looks like a bug, not like polish.
      M.to(fill, "Size", UDim2.fromScale(a, 1), "gentle")
      M.to(knob, "Position", UDim2.fromScale(a, 0.5), "gentle")
    end
  end

  local dragging, dragRefused = false, nil
  local lastGood = value

  function api:set(v, silent)
    local nv = quantise(v)
    if nv == value then return end
    local prev = value
    value = nv
    paint(false)
    if silent then return end
    -- MID-DRAG A REVERT WOULD FIGHT THE POINTER: the knob snaps back, the next
    -- mouse-move refuses again, and that is a toast per frame. A drag is one
    -- gesture, so it records the refusal and settles once on release.
    if dragging then
      local ok, why = commitValue("slider", opts, value, true)
      if ok then lastGood, dragRefused = value, nil else dragRefused = why end
      return
    end
    if commitValue("slider", opts, value) then
      lastGood = value
    else
      value = prev
      paint(false)
    end
  end
  function api:get() return value end
  local function fromX(px)
    -- IGNORE ANY POINTER MATH BEFORE THE TRACK IS LAID OUT. A slider on a tab
    -- that is active at load (the persisted tab) exists a frame or two before
    -- Roblox gives it a real AbsoluteSize. Until then AbsoluteSize.X is 0, the
    -- max(...,1) floor makes the divisor 1, and any stray Activated turns a
    -- 900px mouse X into a=900 -> clamp to 1 -> the slider SLAMS to its maximum.
    -- That is what was quietly pinning fling power to max on load. No real drag
    -- can happen on a zero-width track, so there is nothing to lose by waiting.
    local w = track.AbsoluteSize.X
    if w < 8 then return end
    local a = (px - track.AbsolutePosition.X) / w
    api:set(fromAlpha(a))
  end

  hit.MouseButton1Down:Connect(function()
    dragging = true
    M.to(knob, "Size", UDim2.fromOffset(14, 14), "fast")
  end)
  hit.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
      fromX(i.Position.X)
    end
  end)
  L.hold(L.UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
      or i.UserInputType == Enum.UserInputType.Touch) then
      fromX(i.Position.X)
    end
  end))
  L.hold(L.UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
      or i.UserInputType == Enum.UserInputType.Touch then
      if dragging then
        dragging = false
        M.to(knob, "Size", UDim2.fromOffset(11, 11), "fast")
        if dragRefused then
          local why = dragRefused
          dragRefused = nil
          if value ~= lastGood then value = lastGood paint(false) end
          if L.Toast then L.Toast.warn(tostring(opts.text or "Setting"), tostring(why)) end
        end
      end
    end
  end))
  -- A CLICK ON A SLIDER IS, BY DEFINITION, ON THE SLIDER.
  --
  -- Activated used to be trusted outright and the mouse X mapped straight onto
  -- the track. That is unsound whenever the track has not been placed yet: a
  -- fresh row reports its real width a frame before Roblox resolves its
  -- position, so AbsoluteSize.X is 132 while AbsolutePosition.X is still 0, and
  -- (900 - 0) / 132 clamps to 1 -- the slider would jump to its maximum from a
  -- click nowhere near it.
  --
  -- Requiring the pointer to actually be over the track closes that off. This
  -- is defence, not a bug fix: the max-value readings that prompted it turned
  -- out to be a stale global left by a silently-failing obfuscated build, not
  -- this code path.
  hit.Activated:Connect(function()
    local w = track.AbsoluteSize.X
    if w < 8 then return end
    local x0 = track.AbsolutePosition.X
    -- X-only, and the inset is vertical on every current platform, so this was
    -- never visibly wrong -- but it is read through the same helper as the rest
    -- so it cannot rot if a platform ever reports a horizontal inset.
    local mx = L.pointer().X
    -- hit is 20px wider than the track on each side, so allow that much slack
    if mx < x0 - 24 or mx > x0 + w + 24 then return end
    fromX(mx)
  end)

  local function closeEntry(commit)
    if not entry.Visible then return end
    if commit then
      -- accepts "137", "137.5", " 137 " and rejects the rest rather than
      -- silently resolving a typo to 0, which would look like the slider moved
      -- on its own
      local n = tonumber((entry.Text:gsub("%s", "")))
      if n then
        api:set(n)
      elseif entry.Text ~= "" and L.Toast then
        L.Toast.warn(opts.text or "Value",
          string.format("'%s' is not a number -- left at %s.", entry.Text, tostring(value)))
      end
    end
    entry.Visible = false
    readout.Visible = true
    pcall(function() entry:ReleaseFocus() end)
  end

  local function openEntry()
    readout.Visible = false
    entry.Visible = true
    entry.Text = tostring(L.round(value, 2))
    M.set(entry, "BackgroundTransparency", 1)
    M.to(entry, "BackgroundTransparency", 0.4, "fast")
    entry:CaptureFocus()
    pcall(function() entry.CursorPosition = #entry.Text + 1 entry.SelectionStart = 1 end)
  end

  hitReadout.Activated:Connect(openEntry)
  entry.FocusLost:Connect(function(enter) closeEntry(enter) end)
  -- Escape abandons the edit. Without it the only way out of a half-typed value
  -- is to commit it, and the engine takes Escape before anything can sink it, so
  -- this listener is the whole mechanism.
  L.hold(L.UIS.InputBegan:Connect(function(i)
    if entry.Visible and i.KeyCode == Enum.KeyCode.Escape then closeEntry(false) end
  end))
  local _ = entryStroke

  -- One step per press, ten with Shift. A slider whose only keyboard speed is
  -- one step makes a 16..250 range a 234-press job, and one that always jumps
  -- coarsely cannot be aimed -- so the modifier picks which you wanted.
  focusable(f, {
    radius = T.r.md, label = opts.text,
    suspend = function() return entry.Visible end,
    activate = openEntry,          -- Enter on a focused slider types the value
    adjust = function(dir)
      local mult = (L.UIS:IsKeyDown(Enum.KeyCode.LeftShift)
                 or L.UIS:IsKeyDown(Enum.KeyCode.RightShift)) and 10 or 1
      if logCurve then
        -- a fixed step is meaningless on a ratio scale; move along the track
        api:set(fromAlpha(toAlpha(value) + dir * 0.02 * mult))
      else
        api:set(value + dir * (step > 0 and step or 1) * mult)
      end
    end,
  })

  -- Hover wash, rim and pointer spotlight, same as the toggle above it. Wired
  -- last on purpose: the guard inside A.interactive lifts the track, the readout
  -- button and the entry box clear of the full-size Hit overlay, and it can only
  -- lift children that already exist.
  A.interactive(f, { radius = T.r.md })

  paint(true)
  api.frame = f
  register(opts, api)
  return api
end

-- ---------------------------------------------------------------- dropdown
--
-- A POPOVER, NOT AN INLINE EXPANSION.

local DD_ROW, DD_MAX, DD_FILTER_AT = 32, 232, 8
-- geometry of the closed row: left padding, the value label's width and its
-- distance from the right edge (clearing the chevron), and the gap the title
-- must leave before the value starts
local DD_PAD, DD_VAL_W, DD_VAL_RIGHT, DD_GAP = 12, 160, 32, 10

local function overlayLayer()
  local w = L.Hub and L.Hub.window
  return w and w.overlay
end

function C.dropdown(parent, opts)
  opts = opts or {}
  bindPersist(opts)
  local items = opts.items or {}
  local value = opts.multi and table.clone(opts.default or {}) or opts.default
  local function displayValue(selected)
    if not opts.multi then return tostring(selected or "None") end
    local labels = {}
    for _, item in ipairs(items) do
      if selected[item] then labels[#labels + 1] = tostring(item) end
    end
    return #labels > 0 and table.concat(labels, ", ") or "None"
  end
  local open, pop, rows, filterBox, shadow = false, nil, {}, nil, nil

  local f = A.surface({
    Parent = parent, elev = 1, radius = T.r.md,
    Size = UDim2.new(1, 0, 0, ROWH()), Name = "Dropdown",
  })

  A.text({
    Text = opts.text or "Select",
    font = T.font.medium, size = T.size.body, colour = T.c.text,
    Position = UDim2.fromOffset(DD_PAD, 0),
    -- DERIVED, NOT GUESSED. The title used to reserve `1, -150` while the value
    -- label occupied the last 192 px, so the two boxes overlapped by ~42 px --
    -- measured at 86 px on screen at 1.6x scale. Both truncate, so short titles
    -- hid it, but a long one drew straight through the value it sits beside.
    -- Every number below comes from the same four constants, so the two boxes
    -- cannot drift apart again.
    Size = UDim2.new(1, -(DD_PAD + DD_VAL_W + DD_VAL_RIGHT + DD_GAP), 1, 0),
    truncate = true, Parent = f,
  })

  local valueLbl = A.text({
    Text = displayValue(value),
    font = T.font.body, size = T.size.label, colour = T.c.textDim,
    align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -DD_VAL_RIGHT, 0, 0),
    Size = UDim2.fromOffset(DD_VAL_W, ROWH()),
    truncate = true, ZIndex = 2, Parent = f,
  })

  local _, chevInner = A.Icon.chevron(f, 14, T.c.textMute, "down")
  local chev = chevInner.Parent
  chev.Position = UDim2.new(1, -26, 0, ROWH() / 2 - 7)
  chev.ZIndex = 2

  local api = {}

  local function paintRows()
    for _, r in ipairs(rows) do
      -- one shared treatment, so a chosen row looks the same here, in the
      -- player panel and in the command centre -- see A.selectRow
      A.selectRow(r.frame, r.label, opts.multi and value[r.value] == true or r.value == value, "fast")
    end
  end

  function api:set(v, silent)
    local prev = value
    if opts.multi then
      if type(v) ~= "table" then return end
      value = {}
      for _, item in ipairs(items) do
        if v[item] == true or table.find(v, item) then value[item] = true end
      end
    else
      if v ~= nil and not table.find(items, v) then return end
      value = v
    end
    valueLbl.Text = displayValue(value)
    paintRows()
    if silent then return end
    if not commitValue("dropdown", opts, value) then
      value = prev
      valueLbl.Text = displayValue(prev)
      paintRows()
    end
  end
  function api:get() return value end

  -- THE STACKING SHADOW. The drop shadow was created anonymously --
  -- `A.shadow(nil, { Parent = layer })` -- and only `pop` was ever destroyed, so
  -- every open left another full-strength shadow behind on the overlay. Measured:
  -- five open/close cycles, five orphaned Shadow ImageLabels, each one darkening
  -- the page again. Held by reference now and torn down with the menu it belongs
  -- to.
  local function closePop(instant)
    if not open then return end
    open = false
    M.to(chevInner, "Rotation", 0, "base")
    local p, s = pop, shadow
    pop, shadow = nil, nil
    if s then
      if instant then pcall(function() s:Destroy() end)
      else
        M.to(s, "ImageTransparency", 1, "fast")
        task.delay(0.28, function() pcall(function() s:Destroy() end) end)
      end
    end
    if p and instant then
      -- DISPLACED, NOT DISMISSED. Closing normally leaves the old menu on the
      -- overlay for 0.28 s while it collapses -- which is fine on its own, and
      -- is a stack of two opaque menus when the next one is already opening on
      -- top of it. That is the bug in the recording: a four-item Method list
      -- showing five rows, the extra one belonging to Aim at.
      pcall(function() p:Destroy() end)
      p = nil
    end
    if p then
      M.to(p, "Size", UDim2.fromOffset(p.Size.X.Offset, 0), "fast")
      -- A.fadeTo, not a bare background fade. This popover collapses to zero
      -- HEIGHT as it closes, so an un-faded UIStroke does not merely linger --
      -- it becomes a literal horizontal line sitting where the list used to be.
      A.fadeTo(p, 1, "fast")
      task.delay(0.28, function() pcall(function() p:Destroy() end) end)
    end
    rows = {}
  end
  api.close = closePop

  local function build()
    local layer = overlayLayer()
    if not layer then return end
    local win = L.Hub.window
    local sc = (win.scaleObj and win.scaleObj.Scale) or 1

    -- absolute geometry, converted into the overlay's own space
    local originAbs = layer.AbsolutePosition
    local fAbs, fSize = f.AbsolutePosition, f.AbsoluteSize
    local x = (fAbs.X - originAbs.X) / sc
    local yBelow = (fAbs.Y + fSize.Y - originAbs.Y) / sc + 4
    local width = fSize.X / sc

    -- rows can be taller than the plain-text default when the caller draws more
    -- into them (a headshot needs room a name does not)
    local ROWPX = opts.rowHeight or DD_ROW
    local showFilter = #items >= DD_FILTER_AT
    local listH = math.min(#items * ROWPX + 8, opts.maxHeight or DD_MAX)
    local fullH = listH + (showFilter and 34 or 0)

    -- FLIPPING UP IS NOT ENOUGH ON ITS OWN, and this is the bug the recording
    -- caught: with 32 players in the server the menu is at its full height, and
    -- flipping it above a row near the bottom put its top at a negative Y. It
    -- drew over the title bar and off the top of the window, filter box clipped.
    --
    -- So the menu is clamped into the CONTENT region -- below the header, not
    -- merely inside the window -- and if it still cannot fit, it is shortened
    -- rather than allowed to overhang. It scrolls, so shorter costs nothing.
    local panelH = win.root.AbsoluteSize.Y / sc
    local top = 8
    local content = win.root:FindFirstChild("Content")
    if content then
      top = (content.AbsolutePosition.Y - originAbs.Y) / sc + 6
    end
    local bottom = panelH - 8

    local avail = bottom - top
    if fullH > avail then
      fullH = math.max(DD_ROW + 8, avail)
      listH = fullH - (showFilter and 34 or 0)
    end

    local flip = (yBelow + fullH) > bottom
    local y = flip and ((fAbs.Y - originAbs.Y) / sc - fullH - 4) or yBelow
    y = math.clamp(y, top, math.max(top, bottom - fullH))

    pop = mk("Frame", {
      Position = UDim2.fromOffset(x, y),
      Size = UDim2.fromOffset(width, 0),
      BackgroundColor3 = T.c.overlay, BackgroundTransparency = 0,
      BorderSizePixel = 0,
      ClipsDescendants = true, ZIndex = 31, Name = "Popover", Parent = layer,
    })
    L.corner(T.r.md, pop)
    L.stroke(T.c.lineStrong, 1, 0.25, pop)

    -- Sized and placed to follow the menu, and kept so closePop can remove it.
    -- It cannot be parented to `pop` itself: pop clips its descendants, which
    -- would cut the shadow off at exactly the edge it needs to spill past.
    shadow = A.shadow(nil, { Parent = layer, spread = 22, alpha = 1, ZIndex = 30 })
    if shadow then
      shadow.AnchorPoint = Vector2.new(0, 0)
      shadow.Position = UDim2.fromOffset(x - 22, y - 22 + 6)
      shadow.Size = UDim2.fromOffset(width + 44, fullH + 44)
      M.to(shadow, "ImageTransparency", 0.42, "base")
    end

    -- A DEFENSIVE SWEEP, because one orphan is invisible and ten are not. If any
    -- shadow ever outlives its menu again, the next open clears it rather than
    -- letting the page get darker every time.
    for _, c in ipairs(layer:GetChildren()) do
      if c ~= shadow and c.Name == "Shadow" then pcall(function() c:Destroy() end) end
    end

    M.to(pop, "Size", UDim2.fromOffset(width, fullH), "base")

    local listTop = 0
    if showFilter then
      filterBox = mk("TextBox", {
        Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(width - 16, 24),
        BackgroundColor3 = T.c.raised, BorderSizePixel = 0,
        Text = "", PlaceholderText = "Filter " .. #items .. " items",
        PlaceholderColor3 = T.c.textOff, TextColor3 = T.c.text,
        Font = T.font.body, TextSize = T.size.micro,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        ZIndex = 32, Parent = pop,
      })
      L.corner(T.r.sm, filterBox)
      L.pad(0, 8, 0, 8, filterBox)
      listTop = 34
    end

    local scroll = A.scroll({
      Parent = pop, gap = 2,
      Size = UDim2.new(1, -8, 0, listH - 8),
      Position = UDim2.fromOffset(4, listTop + 4),
      Name = "DDList",
    })
    scroll.ZIndex = 32

    rows = {}
    for i, item in ipairs(items) do
      local r = mk("Frame", {
        Size = UDim2.new(1, -4, 0, ROWPX - 2), LayoutOrder = i,
        BackgroundColor3 = T.c.accent, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 32, Parent = scroll,
      })
      L.corner(T.r.sm, r)
      local lbl = A.text({
        Text = opts.labelFor and opts.labelFor(item) or tostring(item),
        font = T.font.body, size = T.size.label,
        colour = T.c.textDim, Position = UDim2.fromOffset(opts.textInset or 10, 0),
        Size = UDim2.new(1, -((opts.textInset or 10) + 10), 1, 0),
        truncate = true, ZIndex = 33, Parent = r,
      })
      A.interactive(r, {
        radius = T.r.sm, hoverAlpha = 0.94,
        onClick = function()
          if opts.multi then
            local selected = table.clone(value)
            selected[item] = not selected[item] or nil
            api:set(selected)
          else
            api:set(item)
            closePop()
          end
        end,
      })
      rows[#rows + 1] = { frame = r, label = lbl, value = item }
      -- the caller may hang anything it likes on the row (a headshot, a
      -- distance) without this control needing to know what a player is
      if opts.decorate then L.try("dropdown.decorate", opts.decorate, r, item, i) end

      -- STAGGERED ENTRANCE. Thirty rows appearing at once is a block of text
      -- arriving; the same thirty arriving over a fifth of a second reads as a
      -- list being dealt. Capped so a 32-player server does not take a second
      -- to finish dealing.
      -- TEXT ONLY, DELIBERATELY. Fading the row's images too looked right until
      -- the headshots landed: the avatar starts invisible and fades itself in
      -- when the thumbnail returns from the network, so the stagger captured
      -- "invisible" as its rest value and, if the image arrived first, animated
      -- it straight back to nothing. Cached thumbnails lost that race every
      -- time. Anything a decorator draws now owns its own entrance.
      if opts.stagger ~= false then
        for _, d in ipairs(r:GetDescendants()) do
          if d:IsA("TextLabel") then
            local rest = d.TextTransparency
            d.TextTransparency = 1
            M.after(math.min(i, 14) * 0.018, function()
              if d.Parent then M.to(d, "TextTransparency", rest, "base") end
            end)
          end
        end
      end
    end
    paintRows()

    if filterBox then
      filterBox:GetPropertyChangedSignal("Text"):Connect(function()
        local q = string.lower(filterBox.Text)
        local shown = 0
        for _, r in ipairs(rows) do
          local hit = (q == "") or string.find(string.lower(tostring(r.value)), q, 1, true) ~= nil
          r.frame.Visible = hit
          if hit then shown = shown + 1 end
        end
        -- capped by what actually fits, not by DD_MAX: re-deriving from the
        -- constant here would undo the clamp above the moment you typed
        local h = math.min(shown * ROWPX + 8, listH)
        M.to(pop, "Size", UDim2.fromOffset(width, h + 34), "fast")
        M.to(scroll, "Size", UDim2.new(1, -8, 0, h - 8), "fast")
        -- a shorter menu may now sit lower than it needs to; keep it in bounds
        local ny = math.clamp(pop.Position.Y.Offset, top, math.max(top, bottom - (h + 34)))
        if math.abs(ny - pop.Position.Y.Offset) > 0.5 then
          M.to(pop, "Position", UDim2.fromOffset(x, ny), "fast")
        end
      end)
      task.defer(function() if open and filterBox then filterBox:CaptureFocus() end end)
    end
  end

  local function openPop()
    if open then return end
    -- EVERY OTHER MENU GOES FIRST, and goes instantly.
    --
    -- Each dropdown already closed itself on a click outside, which mostly
    -- worked -- but only mostly: the click that opens the next menu can land
    -- inside the OLD menu's rectangle, and that path treats it as a click on
    -- itself and stays open. Two lists then sit on the overlay together, which
    -- is why the recording shows items from one dropdown under another.
    -- Asking directly is both cheaper and correct.
    C.closePopovers(true)
    open = true
    M.to(chevInner, "Rotation", 180, "base")
    build()
  end

  api.open = openPop
  C._pops[#C._pops + 1] = { frame = f, close = closePop }

  local head = mk("TextButton", {
    Size = UDim2.new(1, 0, 0, ROWH()), BackgroundTransparency = 1,
    Text = "", AutoButtonColor = false, ZIndex = 3, Parent = f,
  })
  head.Activated:Connect(function()
    if open then closePop() else openPop() end
  end)

  -- close on a click anywhere else, and on Escape
  L.hold(L.UIS.InputBegan:Connect(function(i, typing)
    if not open then return end
    if i.KeyCode == Enum.KeyCode.Escape then closePop() return end
    if typing then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
      -- INSET-EXCLUDED: every comparison below is against an AbsolutePosition,
      -- and GetMouseLocation is measured in the other space. Mixing them left
      -- this 58 px out on the Y axis, so the dropdown thought the pointer had
      -- left while it was still over the bottom of the list.
      local m = L.pointer()
      local inTrigger = m.X >= f.AbsolutePosition.X and m.X <= f.AbsolutePosition.X + f.AbsoluteSize.X
        and m.Y >= f.AbsolutePosition.Y and m.Y <= f.AbsolutePosition.Y + f.AbsoluteSize.Y
      local inPop = false
      if pop then
        local pa, ps = pop.AbsolutePosition, pop.AbsoluteSize
        inPop = m.X >= pa.X and m.X <= pa.X + ps.X and m.Y >= pa.Y and m.Y <= pa.Y + ps.Y
      end
      if not inTrigger and not inPop then closePop() end
    end
  end))

  paintRows()
  api.frame = f
  register(opts, api)
  -- drivable from code, not only by clicking: needed for tests, and for any
  -- caller that wants to open a chooser in response to something else
  api.open, api.toggle = openPop, function()
    if open then closePop() else openPop() end
  end
  api.isOpen = function() return open end
  function api:setItems(values)
    closePop(true)
    table.clear(items)
    for _, item in ipairs(values) do items[#items + 1] = item end
    if opts.multi then api:set(value) elseif not table.find(items, value) then api:set(items[1]) end
  end

  -- Enter opens the popover; Left and Right change the selection without opening
  -- it at all, which is faster than open-arrow-arrow-Enter for a short list.
  focusable(f, {
    radius = T.r.md, label = opts.text,
    activate = function() if open then closePop() else openPop() end end,
    adjust = function(dir)
      if #items == 0 or opts.multi then return end
      local i = 1
      for k, it in ipairs(items) do if it == api:get() then i = k break end end
      api:set(items[math.clamp(i + dir, 1, #items)])
    end,
  })
  return api
end

-- ---------------------------------------------------------------- keybind

function C.keybind(parent, opts)
  opts = opts or {}
  local key = opts.default
  local listening = false

  local f = row(parent, { text = opts.text, desc = opts.desc, rightRoom = 110 })

  local chip = A.surface({
    Parent = f, elev = 2, radius = T.r.sm,
    Size = UDim2.fromOffset(78, 24), Name = "Chip",
  })
  chip.AnchorPoint = Vector2.new(1, 0.5)
  chip.Position = UDim2.new(1, -12, 0.5, 0)
  chip.ZIndex = 2

  local lbl = A.text({
    Text = key and key.Name or "None",
    font = T.font.mono, size = T.size.micro, colour = T.c.textDim,
    align = Enum.TextXAlignment.Center, ZIndex = 3, Parent = chip,
  })

  local api = {}
  local function paint()
    lbl.Text = listening and "press..." or (key and key.Name or "None")
    M.to(lbl, "TextColor3", listening and T.c.accent or T.c.textDim, "fast")
  end

  function api:set(k, silent)
    key = k
    paint()
    if not silent and opts.callback then L.try("keybind.cb", opts.callback, k) end
  end
  function api:get() return key end

  -- L.Binds is told we are listening, or pressing F to bind fly to F would also
  -- fire fly on the way past -- the key would toggle the feature and record
  -- itself in the same keystroke.
  local function listen(on)
    listening = on
    if L.Binds then L.Binds.capturing = on end
    paint()
  end

  A.interactive(chip, { radius = T.r.sm, onClick = function() listen(true) end })

  L.hold(L.UIS.InputBegan:Connect(function(i, typing)
    if not listening or not L.live() then return end
    if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
    listen(false)
    -- Escape CLEARS rather than binding. A UI that lets you bind Escape and
    -- then needs Escape to get out of the menu has trapped you.
    if i.KeyCode == Enum.KeyCode.Escape or i.KeyCode == Enum.KeyCode.Backspace then api:set(nil) else api:set(i.KeyCode) end
  end))

  -- `suspend` HANDS THE KEYBOARD BACK. While this control is listening it needs
  -- the raw keys -- including the very ones focus navigation claims. Without it
  -- you could never bind Tab, an arrow or Enter, because the navigator would
  -- sink each of them before this control ever saw it.
  focusable(f, {
    radius = T.r.md, label = opts.text,
    suspend = function() return listening end,
    activate = function() listen(true) end,
  })

  paint()
  api.frame = f
  register(opts, api)
  return api
end

-- ---------------------------------------------------------------- input

function C.input(parent, opts)
  opts = opts or {}
  bindPersist(opts)
  local f = row(parent, { text = opts.text, desc = opts.desc, rightRoom = 170 })

  local box = mk("TextBox", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.fromOffset(146, 26),
    BackgroundColor3 = T.c.overlay,
    BorderSizePixel = 0,
    Text = opts.default or "",
    PlaceholderText = opts.placeholder or "",
    PlaceholderColor3 = T.c.textOff,
    TextColor3 = T.c.text,
    Font = T.font.body, TextSize = T.size.label,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    ZIndex = 2, Parent = f,
  })
  L.corner(T.r.sm, box)
  L.pad(0, 8, 0, 8, box)
  local st = L.stroke(T.c.lineStrong, 1, 0.4, box)

  box.Focused:Connect(function() M.to(st, "Color", T.c.accent, "fast") M.to(st, "Transparency", 0.1, "fast") end)
  box.FocusLost:Connect(function(enter)
    M.to(st, "Color", T.c.lineStrong, "fast")
    M.to(st, "Transparency", 0.4, "fast")
    if opts.callback then L.try("input.cb", opts.callback, box.Text) end
  end)

  -- An input row read as dead beside the toggle above it. The guard lifts the
  -- box clear of the Hit overlay so the field still takes the caret, and the
  -- overlay gives the dead space beside a 146 px field a job it never had.
  A.interactive(f, { radius = T.r.md, onClick = function() box:CaptureFocus() end })

  local api = { frame = f, box = box }
  function api:get() return box.Text end
  function api:set(v) box.Text = tostring(v or "") end
  register(opts, api)
  return api
end

-- ---------------------------------------------------------------- textarea
--
-- Full width and several lines tall, for text nobody can write in 146 pixels.
-- MultiLine TextBoxes do not wrap on their own, so TextWrapped is not optional
-- here -- without it a long prompt runs off the right edge and simply vanishes.
function C.textarea(parent, opts)
  opts = opts or {}
  local lines = opts.lines or 4
  local h = 10 + 16 + (lines * 16) + 10

  local f = A.surface({
    Parent = parent, elev = 1, radius = T.r.md,
    Size = UDim2.new(1, 0, 0, h), Name = "TextArea",
  })
  if opts.text then
    A.text({
      Text = opts.text,
      font = T.font.medium, size = T.size.micro, colour = T.c.textMute,
      Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 13),
      truncate = true, Parent = f,
    })
  end

  local box = mk("TextBox", {
    Position = UDim2.fromOffset(10, opts.text and 26 or 10),
    Size = UDim2.new(1, -20, 1, opts.text and -36 or -20),
    BackgroundColor3 = T.c.overlay, BorderSizePixel = 0,
    Text = opts.default or "", PlaceholderText = opts.placeholder or "",
    PlaceholderColor3 = T.c.textOff, TextColor3 = T.c.text,
    Font = T.font.body, TextSize = T.size.label,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    MultiLine = true, ClearTextOnFocus = false, TextWrapped = true,
    ZIndex = 2, Parent = f,
  })
  L.corner(T.r.sm, box)
  L.pad(6, 8, 6, 8, box)
  local st = L.stroke(T.c.lineStrong, 1, 0.4, box)
  box.Focused:Connect(function()
    M.to(st, "Color", T.c.accent, "fast") M.to(st, "Transparency", 0.1, "fast")
  end)
  box.FocusLost:Connect(function()
    M.to(st, "Color", T.c.lineStrong, "fast") M.to(st, "Transparency", 0.4, "fast")
  end)

  local api = { frame = f, box = box }
  function api:get() return box.Text end
  function api:set(v) box.Text = tostring(v or "") end
  register(opts, api)
  return api
end

-- ---------------------------------------------------------------- output
--
-- Read-only prose of unknown length: a model's answer, an error body. Grows with
-- its content and scrolls past a ceiling, because the one thing it must never do
-- is silently clip the end of an answer.
function C.output(parent, opts)
  opts = opts or {}
  local maxH = opts.maxHeight or 260

  local f = A.surface({
    Parent = parent, elev = 0, radius = T.r.md, line = true,
    Size = UDim2.new(1, 0, 0, 64), Name = "Output",
  })

  local scroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = T.c.lineStrong,
    ScrollBarImageTransparency = 0.3,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 2, Parent = f,
  })

  local label = A.text({
    Text = opts.default or "", font = opts.mono and T.font.mono or T.font.body,
    size = T.size.label, colour = T.c.textMute,
    Size = UDim2.new(1, -6, 0, 20), wrap = true,
    Parent = scroll,
  })
  label.TextYAlignment = Enum.TextYAlignment.Top

  -- MEASURED WITH GetTextSize, NOT LEFT TO AutomaticSize. Three separate things
  -- went wrong before this, and the third is why the whole approach changed:
  --
  -- 1. UNITS. AbsoluteSize is real screen pixels, a UDim2 Y offset is pre-UIScale
  --    units. Mixing them multiplied every card by the scale -- measured at 1.6.
  -- 2. TIMING. One deferred frame is not enough for a wrapped label to settle.
  -- 3. TextBounds IS THE RENDERED HEIGHT, AND IT DEADLOCKS. Measured live on the
  --    free-keys card: 490 characters over 14 lines reported TextBounds.Y = 43
  --    while GetTextSize said 224. AutomaticSize faithfully followed the wrong
  --    number, so the label never grew, so its AbsoluteSize never changed, so
  --    nothing ever re-fired the resize. It sat there clipped forever.
  --
  -- GetTextSize asks what the text NEEDS at a given width, which is the question
  -- actually being asked, and it answers before anything is laid out.
  local TS = game:GetService("TextService")
  local function fit()
    if not label.Parent then return end
    local win = L.Hub and L.Hub.window
    local sc = (win and win.scaleObj and win.scaleObj.Scale) or 1
    local w = label.AbsoluteSize.X / sc
    if w < 20 then return end            -- not laid out yet; the signal will call back
    local textH = TS:GetTextSize(label.Text, label.TextSize, label.Font,
                                 Vector2.new(w, 100000)).Y
    if math.abs(label.Size.Y.Offset - textH) >= 1 then
      label.Size = UDim2.new(1, -6, 0, textH)
    end
    local want = math.clamp(textH + 20, 56, maxH)
    if math.abs(f.Size.Y.Offset - want) < 1 then return end
    M.to(f, "Size", UDim2.new(1, 0, 0, want), "fast")
  end
  -- watched on the SCROLL, not the label: the label's size is what fit() writes,
  -- so listening there would retrigger itself
  scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

  local api = { frame = f, label = label, scroll = scroll }
  function api:set(text, colour)
    label.Text = tostring(text or "")
    label.TextColor3 = colour or T.c.textMute
    fit()
  end
  function api:get() return label.Text end
  api:set(opts.default or "")
  return api
end

-- ---------------------------------------------------------------- text dots
--
-- A status line whose trailing dots animate while the words hold still. The
-- point is that the COPY stays ordinary text -- animating the whole string makes
-- a label look like it is malfunctioning, whereas animating only the appended
-- marks reads as "still working".
--
-- The dots are separate labels rather than characters appended to the string,
-- because rewriting `Text` every frame reflows the label and makes the words
-- themselves jitter by a pixel. Each dot runs the same pulse on its own phase.
function C.textDots(parent, opts)
  opts = opts or {}
  local count = opts.count or 3
  local period = opts.duration or 1.30      -- one full pass over all the dots
  local stagger = opts.delay or (period / (count + 1))
  local size = opts.size or T.size.label
  local font = opts.font or T.font.body
  local colour = opts.colour or T.c.textMute

  local holder = mk("Frame", {
    BackgroundTransparency = 1, Name = "TextDots",
    Size = opts.Size or UDim2.new(1, 0, 0, size + 6),
    Position = opts.Position, ZIndex = opts.ZIndex or 2, Parent = parent,
  })

  local label = A.text({
    Text = opts.text or "Thinking", font = font, size = size, colour = colour,
    Size = UDim2.new(1, 0, 1, 0), ZIndex = (opts.ZIndex or 2) + 1, Parent = holder,
  })

  -- measured, never assumed: TextBounds is the RENDERED width and lies whenever
  -- the label truncates, so the dots would stack on top of the last glyph
  local TS = game:GetService("TextService")
  local dots, dotW = {}, 0
  local function layout()
    local w = TS:GetTextSize(label.Text, size, font, Vector2.new(1e5, 1e5)).X
    dotW = TS:GetTextSize(".", size, font, Vector2.new(1e5, 1e5)).X
    for i, d in ipairs(dots) do
      d.Position = UDim2.fromOffset(w + 1 + (i - 1) * (dotW + 1), 0)
    end
  end

  for i = 1, count do
    dots[i] = A.text({
      Text = ".", font = font, size = size, colour = colour,
      Size = UDim2.fromOffset(12, size + 6), ZIndex = (opts.ZIndex or 2) + 1,
      Parent = holder,
    })
    dots[i].TextXAlignment = Enum.TextXAlignment.Left
  end
  layout()

  local conn, t0 = nil, os.clock()
  local api = { frame = holder, label = label }

  function api:setText(s)
    label.Text = tostring(s or "")
    layout()
  end
  function api:setColour(c)
    label.TextColor3 = c
    for _, d in ipairs(dots) do d.TextColor3 = c end
  end

  function api:start()
    if conn then return end
    t0 = os.clock()
    conn = L.hold(L.RunService.RenderStepped:Connect(function()
      if not holder.Parent then return end
      local now = os.clock() - t0
      for i, d in ipairs(dots) do
        -- phase 0..1 per dot, offset so they light in sequence
        local ph = ((now - (i - 1) * stagger) / period) % 1
        -- a short bright pass, then a long rest: the same shape as the CSS
        -- keyframes this is modelled on (peak early, settle back)
        local a
        if ph < 0.30 then
          a = ph / 0.30
        elseif ph < 0.62 then
          a = 1 - (ph - 0.30) / 0.32
        else
          a = 0
        end
        d.TextTransparency = 0.78 - 0.78 * a
        d.Position = UDim2.fromOffset(d.Position.X.Offset, -math.floor(a * 2 + 0.5))
      end
    end))
  end

  function api:stop()
    if conn then conn:Disconnect() conn = nil end
    for _, d in ipairs(dots) do
      d.TextTransparency = 0.78
      d.Position = UDim2.fromOffset(d.Position.X.Offset, 0)
    end
  end

  function api:destroy()
    api:stop()
    pcall(function() holder:Destroy() end)
  end

  if opts.autoStart ~= false then api:start() end
  return api
end

-- ---------------------------------------------------------------- log view
--
-- The activity log, rendered. This is the receipt for everything else in Wave 1:
-- an indicator that says "2 contested" is only worth trusting if you can open it
-- and read WHAT is contested and WHEN it stopped holding.
function C.logView(parent, opts)
  opts = opts or {}
  local MAX = opts.max or 80
  local ROW = 20

  local KINDC = {
    fault   = T.c.bad,     refused = T.c.warn,  ok = T.c.ok,
    note    = T.c.textMute, user   = T.c.textDim,
  }

  local holder = mk("Frame", {
    Size = UDim2.new(1, 0, 0, opts.height or 286),
    BackgroundColor3 = T.c.overlay, BackgroundTransparency = 0.4,
    BorderSizePixel = 0, Parent = parent,
  })
  L.corner(T.r.md, holder)
  L.stroke(T.c.line, 1, 0.55, holder)

  local scroll = A.scroll({ Parent = holder, gap = 1, padding = 10 })

  local empty = A.text({
    Text = "Nothing logged yet.", font = T.font.mono, size = T.size.tiny,
    colour = T.c.textOff, align = Enum.TextXAlignment.Center,
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(1, -20, 0, 16), Parent = holder,
  })

  -- MEASURED, NOT PICKED. The clock column was 52 px wide and "23:56:39" needs
  -- 56 at this font and size, so every row lost the last digit of its seconds --
  -- with no truncation set, so there was not even an ellipsis to hint at it.
  -- Deriving the width from the widest real timestamp cannot drift when the mono
  -- font or the tiny size changes.
  -- Widening the clock pushes every column after it, so the whole row is derived
  -- from one chain. Hardcoding the next offset is how the old 52 survived: each
  -- number looked right on its own.
  local CLOCK_W = math.ceil(game:GetService("TextService")
    :GetTextSize("00:00:00", T.size.tiny, T.font.mono, Vector2.new(1e5, 1e5)).X) + 4
  local GAP, KIND_W, SRC_W = 4, 52, 132
  local KIND_X = CLOCK_W + GAP
  local SRC_X  = KIND_X + KIND_W + GAP
  local MSG_X  = SRC_X + SRC_W + GAP

  local function mkRow(e, order)
    local r = mk("Frame", {
      Size = UDim2.new(1, 0, 0, ROW), BackgroundTransparency = 1,
      LayoutOrder = order, Parent = scroll,
    })
    local col = KINDC[e.kind] or T.c.textMute
    A.text({ Text = e.at, font = T.font.mono, size = T.size.tiny, colour = T.c.textOff,
             Size = UDim2.fromOffset(CLOCK_W, ROW), Parent = r })
    A.text({ Text = e.kind, font = T.font.mono, size = T.size.tiny, colour = col,
             Position = UDim2.fromOffset(KIND_X, 0), Size = UDim2.fromOffset(52, ROW),
             Parent = r })
    -- 132, not 94: sources are qualified ("toggle:Infinite jump"), and a column
    -- that clips them to "toggle:Infinit..." identifies the KIND of control that
    -- failed while hiding WHICH ONE -- the single fact the row exists to carry.
    A.text({ Text = e.src, font = T.font.mono, size = T.size.tiny, colour = T.c.textDim,
             Position = UDim2.fromOffset(SRC_X, 0), Size = UDim2.fromOffset(SRC_W, ROW),
             truncate = true, Parent = r })
    local msg = A.text({ Text = e.text, font = T.font.body, size = T.size.micro,
             colour = T.c.textMute, Position = UDim2.fromOffset(MSG_X, 0),
             Size = UDim2.new(1, -(MSG_X + 42), 0, ROW), truncate = true, Parent = r })
    local cnt = A.text({ Text = e.n > 1 and ("x" .. e.n) or "",
             font = T.font.mono, size = T.size.tiny, colour = col,
             align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
             Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(38, ROW),
             Parent = r })
    return r, cnt, msg
  end

  local seenSeq, topCnt, topEntry, dropLbl = -1, nil, nil, nil

  local function rebuild()
    for _, c in ipairs(scroll:GetChildren()) do
      if c:IsA("Frame") or (c:IsA("TextLabel") and c.Name ~= "Layout") then c:Destroy() end
    end
    local logs = L.logs
    empty.Visible = #logs == 0
    local shown = math.min(#logs, MAX)
    local order = 0
    for i = #logs, #logs - shown + 1, -1 do
      order = order + 1
      local r, cnt = mkRow(logs[i], order)
      if i == #logs then topCnt, topEntry = cnt, logs[i] end
    end
    -- NO SILENT TRUNCATION. A list that quietly stops at 80 reads as "that is
    -- everything that happened", which is a worse lie than the ones this wave
    -- set out to remove.
    if #logs > shown then
      dropLbl = A.text({
        Text = string.format("... %d older entr%s not shown (%d kept in memory)",
                             #logs - shown, (#logs - shown) == 1 and "y" or "ies", #logs),
        font = T.font.mono, size = T.size.tiny, colour = T.c.textOff,
        Size = UDim2.new(1, 0, 0, ROW), LayoutOrder = order + 1, Parent = scroll,
      })
    end
  end

  local function refresh()
    if L._logSeq ~= seenSeq then
      seenSeq = L._logSeq
      rebuild()
    elseif topCnt and topEntry and topCnt.Parent then
      -- only the newest entry can collapse, so nothing else can have changed
      topCnt.Text = topEntry.n > 1 and ("x" .. topEntry.n) or ""
    end
  end

  refresh()
  task.spawn(function()
    while L.live() and holder.Parent do
      L.try("logview.refresh", refresh)
      task.wait(0.5)
    end
  end)

  return { frame = holder, scroll = scroll, refresh = refresh }
end

end
