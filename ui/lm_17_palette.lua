do -- ==== lm_17_palette.lua ====
-- LUMEN :: COMMAND PALETTE
-- Ctrl+K, type, Enter. Tab is resolved lazily by walking up the ancestry, so
-- moving a control between tabs never leaves a stale entry. Match is subsequence.

local L = getgenv().__DAEWID_BALL_LUMEN
local T, M, A = L.T, L.Motion, L.A
local mk = L.mk

local P = {}
L.Palette = P

P.entries = {}
P.open = false

-- ---------------------------------------------------------------- registry

function P.add(frame, name, hint, run)
  P.entries[#P.entries + 1] = {
    frame = frame, name = name or "?", hint = hint or "", run = run,
  }
end

function P.clear() P.entries = {} end

local function tabOf(entry)
  if entry._tab ~= nil then return entry._tab end
  local win = L.Hub and L.Hub.window
  local n = nil
  if win and entry.frame then
    local node = entry.frame
    while node and node.Parent do
      for i, t in ipairs(win.tabs) do
        if node == t.page then n = i break end
      end
      if n then break end
      node = node.Parent
    end
  end
  entry._tab = n or false
  return entry._tab
end

-- ---------------------------------------------------------------- matching

-- Returns nil for no match, otherwise a score (higher is better).
local function score(query, text)
  if query == "" then return 0 end
  local q, t = query:lower(), text:lower()
  local qi, s, streak = 1, 0, 0
  local prevWordStart = true
  for i = 1, #t do
    local c = t:sub(i, i)
    local isBoundary = (i == 1) or t:sub(i - 1, i - 1):match("[%s%-_/]") ~= nil
    if qi <= #q and c == q:sub(qi, qi) then
      streak = streak + 1
      s = s + 6 + streak * 3
      if isBoundary then s = s + 14 end        -- start of a word matters most
      if i <= 3 then s = s + 4 end             -- near the front of the label
      qi = qi + 1
    else
      streak = 0
    end
    prevWordStart = isBoundary
  end
  local _ = prevWordStart
  if qi <= #q then return nil end              -- not all of the query consumed
  return s - #t * 0.15                         -- prefer shorter, tighter labels
end

function P.search(query)
  local out = {}
  -- TYPE "reset" TO SEE WHAT IS NOT STOCK. Reset rides the palette because it
  -- costs no Instance, no connection, and no meaning stolen from C.pinnable's
  -- right-click -- and it reaches sliders and dropdowns, which have no row
  -- right-click at all. The entry list is the diff view, so there is no second
  -- surface to build. Carrying the control's own frame makes the existing
  -- activate path jump to its tab and flash the row before the value moves.
  local Cfg = L.Cfg
  if Cfg and Cfg.changedFromDefault and query:lower():sub(1, 3) == "res" then
    for _, d in ipairs(Cfg.changedFromDefault()) do
      local h = L.C and L.C.find and L.C.find(d.id)
      if h and h.frame then
        out[#out + 1] = { s = 1e6, e = {
          frame = h.frame,
          name = "Reset " .. tostring(h._label or d.id),
          hint = tostring(d.value) .. "  \226\134\146  " .. tostring(d.default),
          run = function() Cfg.resetFeat(d.id) end,
        } }
      end
    end
  end
  for _, e in ipairs(P.entries) do
    if e.frame and e.frame.Parent then
      local sc = score(query, e.name .. " " .. e.hint)
      if sc then out[#out + 1] = { e = e, s = sc } end
    end
  end
  table.sort(out, function(a, b)
    if a.s ~= b.s then return a.s > b.s end
    return a.e.name < b.e.name
  end)
  return out
end

-- ---------------------------------------------------------------- ui

local gui, root, box, listFrame, rows, sel, results

local function paintSel()
  for i, r in ipairs(rows) do
    local on = (i == sel)
    M.to(r.bg, "BackgroundTransparency", on and 0.86 or 1, "instant")
    M.to(r.name, "TextColor3", on and T.c.text or T.c.textDim, "instant")
  end
end

-- `animate` only on open: cascading per keystroke re-staggers eight rows on
-- every character and reads as lag, so search results snap.
local function render(list, animate)
  results = list
  if P._seq then P._seq:cancel() P._seq = nil end
  for _, r in ipairs(rows) do r.bg.Visible = false end

  local shown = {}
  for i = 1, math.min(#list, 8) do
    local r = rows[i]
    local e = list[i].e
    local ti = tabOf(e)
    local win = L.Hub and L.Hub.window
    r.bg.Visible = true
    r.name.Text = e.name
    r.hint.Text = (ti and win and win.tabs[ti] and win.tabs[ti].name or e.hint or "")
    r.entry = e
    shown[#shown + 1] = r
  end

  if animate and #shown > 0 then
    for _, r in ipairs(shown) do
      M.set(r.name, "TextTransparency", 1)
      M.set(r.hint, "TextTransparency", 1)
      M.set(r.name, "Position", UDim2.fromOffset(18, 0))
    end
    -- Cancellable, so a cascade still running after close cannot fade rows back in.
    P._seq = M.seq(shown, function(r)
      if not r.bg.Parent then return end
      M.to(r.name, "TextTransparency", 0, "base")
      M.to(r.hint, "TextTransparency", 0, "base")
      M.to(r.name, "Position", UDim2.fromOffset(10, 0), "base")
    end, { step = 0.028, cap = 0.2 })
  else
    for _, r in ipairs(shown) do
      M.set(r.name, "TextTransparency", 0)
      M.set(r.hint, "TextTransparency", 0)
      M.set(r.name, "Position", UDim2.fromOffset(10, 0))
    end
  end

  sel = (#list > 0) and 1 or 0
  paintSel()
end

local function activate(i)
  local item = results and results[i]
  if not item then return end
  local e = item.e
  P.hide()
  local ti = tabOf(e)
  local win = L.Hub and L.Hub.window
  if ti and win then
    win:select(ti)
    local ancestor=e.frame
    while ancestor and ancestor~=win.root do
      if ancestor:GetAttribute("DaewidDisclosure") then
        ancestor.Visible=true
        ancestor.Parent.AutomaticSize=Enum.AutomaticSize.Y
      end
      ancestor=ancestor.Parent
    end
  end
  -- Flash the row so the eye lands on the control that was searched for.
  task.delay(0.28, function()
    if not L.live() or not e.frame or not e.frame.Parent then return end
    local was = e.frame.BackgroundColor3
    M.set(e.frame, "BackgroundColor3", T.c.accentDeep)
    M.to(e.frame, "BackgroundColor3", was, "slow")
  end)
  if e.run then L.try("palette.run", e.run) end
end

function P.build()
  if gui and gui.Parent then return end
  gui = mk("ScreenGui", {
    Name = "DaewidLumenPalette", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 40,
  })
  gui.Parent = L.host()
  L.own(gui)
  mk("UIScale", { Scale = L.autoScale(), Parent = gui })

  local scrim = mk("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.c.scrim,
    BackgroundTransparency = 1, BorderSizePixel = 0, Parent = gui,
  })
  local hit = mk("TextButton", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
    AutoButtonColor = false, Parent = scrim,
  })
  hit.Activated:Connect(function() P.hide() end)
  P.scrim = scrim

  -- CanvasGroup, not Frame: a Frame has no single opacity clock, so only
  -- GroupTransparency fades plate, outline and text together.
  root = mk("CanvasGroup", {
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0.18, 0),
    Size = UDim2.fromOffset(520, 60),
    BackgroundColor3 = T.c.overlay, BorderSizePixel = 0,
    GroupTransparency = 0,
    Parent = gui,
  })
  L.corner(T.r.lg, root)
  L.stroke(T.c.lineStrong, 1, 0.25, root)
  A.shadow(nil, { Parent = gui, spread = 30, alpha = 0.4, ZIndex = 0 })
  P.root = root

  A.Icon.search(root, 16, T.c.textMute).Position = UDim2.fromOffset(18, 18)

  box = mk("TextBox", {
    Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -60, 0, 52),
    BackgroundTransparency = 1, Text = "",
    PlaceholderText = "Search controls...",
    PlaceholderColor3 = T.c.textOff, TextColor3 = T.c.text,
    Font = T.font.body, TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
    Parent = root,
  })
  P.box = box

  listFrame = mk("Frame", {
    Position = UDim2.fromOffset(8, 54), Size = UDim2.new(1, -16, 0, 0),
    BackgroundTransparency = 1, Parent = root,
  })
  L.list(2, nil, listFrame)

  rows = {}
  for i = 1, 8 do
    local bg = mk("Frame", {
      Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.c.accent,
      BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
      LayoutOrder = i, Parent = listFrame,
    })
    L.corner(T.r.sm, bg)
    local nm = A.text({
      Text = "", font = T.font.medium, size = T.size.body, colour = T.c.textDim,
      Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -120, 1, 0),
      truncate = true, Parent = bg,
    })
    local hn = A.text({
      Text = "", font = T.font.mono, size = T.size.tiny, colour = T.c.textOff,
      align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5),
      Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 14),
      Parent = bg,
    })
    local btn = mk("TextButton", {
      Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
      AutoButtonColor = false, ZIndex = 3, Parent = bg,
    })
    btn.Activated:Connect(function() activate(i) end)
    btn.MouseEnter:Connect(function() sel = i paintSel() end)
    rows[i] = { bg = bg, name = nm, hint = hn }
  end

  box:GetPropertyChangedSignal("Text"):Connect(function()
    local list = P.search(box.Text)
    render(list)
    local h = 54 + math.min(#list, 8) * 36 + (#list > 0 and 8 or 0)
    M.to(root, "Size", UDim2.fromOffset(520, h), "base")
    M.to(listFrame, "Size", UDim2.new(1, -16, 0, math.min(#list, 8) * 36), "base")
  end)
end

function P.show()
  P.build()
  P.open = true
  gui.Enabled = true
  box.Text = ""
  render(P.search(""), true)
  M.set(root, "Position", UDim2.new(0.5, 0, 0.18, -14))
  A.groupSet(root, 1)
  M.set(P.scrim, "BackgroundTransparency", 1)
  M.to(P.scrim, "BackgroundTransparency", 0.42, "base")
  M.to(root, "Position", UDim2.new(0.5, 0, 0.18, 0), "slow")
  -- Fade is shorter than the slide, so the panel is legible before it lands.
  A.groupTo(root, 0, "base")
  task.defer(function() if P.open then box:CaptureFocus() end end)
end

function P.hide()
  if not P.open then return end
  P.open = false
  if P._seq then P._seq:cancel() P._seq = nil end
  M.to(P.scrim, "BackgroundTransparency", 1, "fast")
  M.to(root, "Position", UDim2.new(0.5, 0, 0.18, -10), "fast")
  A.groupTo(root, 1, "fast")
  pcall(function() box:ReleaseFocus() end)
  task.delay(0.3, function()
    if gui and not P.open then gui.Enabled = false end
  end)
end

function P.toggle() if P.open then P.hide() else P.show() end end

-- ---------------------------------------------------------------- keys
L.hold(L.UIS.InputBegan:Connect(function(i, typing)
  if not L.live() then return end
  local ctrl = L.UIS:IsKeyDown(Enum.KeyCode.LeftControl)
             or L.UIS:IsKeyDown(Enum.KeyCode.RightControl)
  if i.KeyCode == Enum.KeyCode.K and ctrl then P.toggle() return end
  if not P.open then return end
  -- These run while the TextBox has focus, so they cannot be gated on `typing`.
  if i.KeyCode == Enum.KeyCode.Escape then P.hide()
  elseif i.KeyCode == Enum.KeyCode.Down then
    if results and #results > 0 then sel = math.min(sel + 1, math.min(#results, 8)) paintSel() end
  elseif i.KeyCode == Enum.KeyCode.Up then
    if results and #results > 0 then sel = math.max(sel - 1, 1) paintSel() end
  elseif i.KeyCode == Enum.KeyCode.Return then
    activate(sel)
  end
  local _ = typing
end))

end
