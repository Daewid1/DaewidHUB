do -- ==== lm_01_tokens.lua ====
-- LUMEN :: TOKENS
-- Colours, type, radii, spacing and motion. Every UI value comes from here.
-- Motion tokens are (duration, bounce) pairs, not stiffness/damping.

local L = getgenv().__DAEWID_BALL_LUMEN
local T = {}
L.T = T

local rgb = Color3.fromRGB

-- ---------------------------------------------------------------- colour
-- A cool, near-black base rather than neutral grey.
T.c = {
  scrim      = rgb(0, 0, 0),
  bg         = rgb(2, 2, 3),        -- sidebar / recessed
  surface    = rgb(5, 5, 7),        -- the window body
  raised     = rgb(11, 12, 16),     -- cards, control rows
  overlay    = rgb(17, 18, 24),     -- dropdowns, popovers
  hover      = rgb(24, 26, 33),
  active     = rgb(31, 33, 42),

  -- Borders are nearly invisible on purpose: visible outlines read as a wireframe.
  line       = rgb(24, 26, 33),
  lineSoft   = rgb(15, 16, 21),
  lineStrong = rgb(46, 50, 62),

  text       = rgb(247, 248, 251),
  textDim    = rgb(146, 153, 168),
  textMute   = rgb(94, 101, 116),
  textOff    = rgb(58, 63, 76),

  -- The bloom: a light source behind the page, never used on a control.
  bloom      = rgb(26, 43, 107),

  -- Chrome accent: cool and pale, so it reads as metal rather than paint.
  accent     = rgb(138, 176, 255),
  accentAlt  = rgb(196, 182, 255),
  accentDeep = rgb(30, 44, 84),
  accentInk  = rgb(4, 5, 8),

  -- Dispersion: icon and chrome edges only, never UI furniture.
  irisA      = rgb(120, 220, 255),
  irisB      = rgb(255, 150, 220),
  irisC      = rgb(255, 196, 120),

  ok         = rgb(80, 224, 168),
  warn       = rgb(252, 200, 88),
  bad        = rgb(255, 120, 140),
}

-- ---------------------------------------------------------------- type
-- Authored against a 1080p reference; the root UIScale handles everything else.
T.font = {
  display = Enum.Font.GothamBlack,
  strong  = Enum.Font.GothamBold,
  medium  = Enum.Font.GothamMedium,
  body    = Enum.Font.Gotham,
  mono    = Enum.Font.Code,
}

-- Hierarchy comes from range, not weight: a large display against 9-10 px labels.
T.size = {
  hero    = 34,
  display = 24,
  title   = 17,
  head    = 15,
  body    = 13,
  label   = 12,
  micro   = 11,
  tiny    = 10,
  nano    = 9,      -- nav section labels, always upper case and tracked
}

-- ---------------------------------------------------------------- space
T.gap = { xs = 4, sm = 6, md = 10, lg = 14, xl = 20, xxl = 28 }

T.r = { sm = 7, md = 12, lg = 16, xl = 22, pill = 999 }

-- ---------------------------------------------------------------- density
-- Every structural height in one place, multiplied by one number. Read through
-- T.px at construction; a module local would be frozen at load.
T.base = { row = 52, tab = 46, header = 84, sidebar = 212, pad = 24, gap = 10 }
T.dense = 1.0                      -- 1.0 comfortable, 0.82 compact

function T.px(key)
  return math.floor((T.base[key] or 0) * T.dense + 0.5)
end

-- Elevation is a surface colour plus a border: Roblox has no box-shadow.
T.elev = {
  [0] = { fill = T.c.surface, line = T.c.lineSoft,   lineT = 0.55 },
  [1] = { fill = T.c.raised,  line = T.c.line,       lineT = 0.50 },
  [2] = { fill = T.c.overlay, line = T.c.lineStrong, lineT = 0.45 },
}

-- ---------------------------------------------------------------- motion
-- Named by role. Each token is (duration in seconds, bounce); see lm_02_spring.
T.m = {
  instant    = { 0.10,  0.00 },   -- hover/press state layers: no overshoot
  fast       = { 0.18,  0.20 },   -- toggles and checkmarks; 1.5% overshoot
  base       = { 0.30,  0.20 },   -- the default: panels, the tab indicator
  slow       = { 0.44,  0.22 },   -- window entrance, tab content swap
  expressive = { 0.42,  0.38 },   -- the loader mark, 8% overshoot. Overshoot is
                                  -- set by bounce alone; at 0.58 duration it
                                  -- settled in 0.97 s and read as lag
  gentle     = { 0.32, -0.20 },   -- progress and meters, overdamped on purpose:
}                                 -- at 0.50 it took 1.14 s to settle

-- Material 3 easing curves, for the rare case a curve beats a spring (anything
-- that must land on an exact frame). Sampled by L.bezier in lm_03_motion.
--   https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
T.ease = {
  standard            = { 0.20, 0.00, 0.00, 1.00 },
  standardDecelerate  = { 0.00, 0.00, 0.00, 1.00 },  -- entering the screen
  standardAccelerate  = { 0.30, 0.00, 1.00, 1.00 },  -- leaving the screen
  emphasizedDecelerate= { 0.05, 0.70, 0.10, 1.00 },  -- prominent entries
  emphasizedAccelerate= { 0.30, 0.00, 0.80, 0.15 },  -- prominent exits
  linear              = { 0.00, 0.00, 1.00, 1.00 },  -- indeterminate only
}

-- Delay between successive items in a list reveal.
T.stagger = 0.035

function T.motion(name)
  local m = T.m[name] or T.m.base
  return m[1], m[2]
end

-- ---- reverse map, for the repaint registry ---------------------------------
-- Which token a colour came from. L.mk consults this while building so palette
-- colours are remembered by name and can repaint in place. Reindex whenever the
-- accent moves.
local reverse = {}

function T.reindex()
  reverse = {}
  for name, v in pairs(T.c) do
    if typeof(v) == "Color3" then reverse[tostring(v)] = name end
  end
end

function T.tokenOf(colour)
  return reverse[tostring(colour)]
end

T.reindex()
end
