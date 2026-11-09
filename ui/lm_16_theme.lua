do -- ==== lm_16_theme.lua ====
-- LUMEN :: THEME
-- Accent palettes, motion profiles, density and blur.

local L = getgenv().__DAEWID_BALL_LUMEN
local T, M = L.T, L.Motion

local Theme = {}
L.Theme = Theme

-- ---------------------------------------------------------------- palettes
local rgb = Color3.fromRGB

Theme.palettes = {
  chrome = { name = "Chrome", accent = rgb(138, 176, 255), alt = rgb(196, 182, 255),
             deep = rgb(30, 44, 84) },
  ember  = { name = "Ember",  accent = rgb(255, 170, 92),  alt = rgb(255, 122, 122),
             deep = rgb(86, 44, 24) },
  mint   = { name = "Mint",   accent = rgb(94, 232, 190),  alt = rgb(140, 232, 255),
             deep = rgb(20, 74, 66) },
  orchid = { name = "Orchid", accent = rgb(206, 148, 255), alt = rgb(255, 148, 214),
             deep = rgb(64, 34, 90) },
  bone   = { name = "Bone",   accent = rgb(226, 228, 236), alt = rgb(180, 186, 204),
             deep = rgb(52, 55, 66) },
  -- Sampled from the Heaven footage: amber swirl, green type, bone-white reveal.
  heaven = { name = "Heaven", accent = rgb(224, 178, 92),  alt = rgb(150, 214, 150),
             deep = rgb(74, 52, 20) },
}
Theme.order = { "chrome", "ember", "mint", "orchid", "bone" }
Theme.current = "chrome"

function Theme.names()
  local out = {}
  for _, k in ipairs(Theme.order) do out[#out + 1] = Theme.palettes[k].name end
  return out
end

function Theme.keyFor(displayName)
  for _, k in ipairs(Theme.order) do
    if Theme.palettes[k].name == displayName then return k end
  end
  return "chrome"
end

-- Applies the colours only. Callers that need the UI to reflect it must rebuild.
function Theme.poke(key)
  local p = Theme.palettes[key] or Theme.palettes.chrome
  T.c.accent, T.c.accentAlt, T.c.accentDeep = p.accent, p.alt, p.deep
  Theme.current = key
  -- The reverse map is keyed by colour value, so it has to follow the accent.
  if T.reindex then T.reindex() end
end

function Theme.set(key, opts)
  opts = opts or {}
  if not Theme.palettes[key] then return false, "no palette " .. tostring(key) end
  Theme.poke(key)
  if L.Cfg then L.Cfg.set("theme", key) end

  -- Repainted in place: L.mk registered every palette-coloured property with the
  -- token it came from. Gradients need their own pass because a ColorSequence is
  -- not a Color3 and the registry cannot see them. A rebuild cost ~700 instances
  -- plus scroll positions, open popovers and the focus ring.
  if opts.rebuild ~= false then
    local painted = L.repaint and L.repaint() or 0
    local grads = L.A and L.A.repaintGradients and L.A.repaintGradients() or 0
    L.note("theme", string.format("%s -- repainted %d properties, %d gradients",
      Theme.palettes[key].name, painted, grads))
  end
  return true, (Theme.palettes[key].name .. " applied")
end

-- For changes a repaint cannot cover: density row metrics are read at
-- construction.
function Theme.rebuild()
  if not (L.Hub and L.Hub.window) then return false end
  local old = L.Hub.window
  local tab = old.active or 1
  local pos = old.shell and old.shell.Position
  local scale = old.scaleObj and old.scaleObj.Scale
  pcall(function() old.gui:Destroy() end)
  if old.dock then pcall(function() old.dock:Destroy() end) end

  local win = L.Hub.build()
  L.Hub.window = win
  if scale and win.scaleObj then win.scaleObj.Scale = scale end
  if pos then win.shell.Position = pos end
  win:show()
  if win.tabs[tab] then win:select(tab, true) end
  return true
end

-- ---------------------------------------------------------------- motion

-- Multipliers applied to every token as it is resolved. Measured through the
-- shipped spring at 2 kHz; t90 is when the value first reaches 90% of travel:
--
--     profile     dur   bnc |  base t90 / ov  |  slow t90 / ov  | expressive ov
--     Calm       1.40  0.35 |   238ms   0.0%  |   345ms   0.1%  |     0.4%
--     Silk       1.20  0.80 |   181ms   0.8%  |   259ms   1.0%  |     4.8%
--     Default    1.00  1.00 |   143ms   1.5%  |   204ms   2.0%  |     8.4%
--     Lively     0.72  1.60 |    89ms   5.4%  |   125ms   6.9%  |    26.2%
--
-- Silk is the default: the fastest profile that still clears 180 ms, at 0.8%
-- overshoot, with expressive left at 4.8% so the loader mark keeps its bounce.
Theme.motionProfiles = {
  Calm    = { dur = 1.40, bounce = 0.35 },
  Silk    = { dur = 1.20, bounce = 0.80 },
  -- Heaven mode's own pace, measured alongside the others:
  --     Heaven  0.80  0.75 |  base 122ms 0.6%  |  fast 73ms 0.6%
  -- Quicker than Silk, but at 0.6% overshoot rather than Lively's 5.4%.
  Heaven  = { dur = 0.80, bounce = 0.75 },
  Default = { dur = 1.00, bounce = 1.00 },
  Lively  = { dur = 0.72, bounce = 1.60 },
}
Theme.motionOrder = { "Calm", "Silk", "Default", "Lively", "Heaven" }
Theme.motion = "Silk"

-- Id the Config tab registers its profile picker under. This setting is stored
-- twice and both copies must be written together -- see setMotion.
Theme.MOTION_CTL = "config.motion.Animation profile"

function Theme.setMotion(name)
  local p = Theme.motionProfiles[name]
  if not p then return false, "no profile " .. tostring(name) end
  Theme.motion = name
  M.durScale, M.bounceScale = p.dur, p.bounce
  M.reprofile()

  -- The profile lives in two keys: Cfg "motion" and the Config picker's
  -- Cfg.features[MOTION_CTL]. Cfg.applyOnLoad restores the picker and fires its
  -- callback back into here with the old value, so writing only one key means a
  -- profile set from anywhere else reverts on the next execute. Write both.
  if L.Cfg then
    L.Cfg.set("motion", name)
    if L.Cfg.setFeat then pcall(L.Cfg.setFeat, Theme.MOTION_CTL, name) end
  end
  -- Move the visible control so the dropdown cannot show a stale profile.
  if L.C and L.C.find then
    local h = L.C.find(Theme.MOTION_CTL)
    if h and h.set then pcall(function() h:set(name, true) end) end
  end
  return true, name
end

-- ---------------------------------------------------------------- heaven
-- Heaven mode is a parameter set, not a second interface: it moves palette,
-- motion profile and loading screen together, and stores what it replaced so
-- turning it off restores the operator's own values.
Theme.HEAVEN = { palette = "heaven", motion = "Heaven", loader = "Made in Heaven" }
Theme.heavenOn = false

function Theme.setHeaven(on, silent)
  on = on and true or false
  local H = Theme.HEAVEN

  if on and not Theme.heavenOn then
    Theme._preHeaven = {
      palette = (L.Cfg and L.Cfg.data and L.Cfg.data.theme) or "chrome",
      motion  = Theme.motion,
      loader  = (L.Loader and L.Loader.skinName and L.Loader.skinName()) or nil,
    }
  end

  local want = on and H or (Theme._preHeaven or
    { palette = "chrome", motion = "Silk", loader = "Aurora" })

  Theme.heavenOn = on
  pcall(function() Theme.set(want.palette) end)
  pcall(function() Theme.setMotion(want.motion) end)
  if L.Loader and L.Loader.setSkin and want.loader then
    -- Loader may be absent on this install; then the next execute opens Aurora.
    pcall(L.Loader.setSkin, want.loader)
  end
  if L.Cfg then L.Cfg.set("heaven", on) end

  if not silent and L.Toast then
    if on then
      L.Toast.info("Made in Heaven", "Palette, motion and loading screen switched")
    else
      L.Toast.info("Heaven off", "Everything back to how you had it")
    end
  end
  return true
end

-- ---------------------------------------------------------------- density

Theme.densities = { Comfortable = 1.0, Compact = 0.82 }
Theme.densityOrder = { "Comfortable", "Compact" }
Theme.density = "Comfortable"

function Theme.setDensity(name)
  local d = Theme.densities[name]
  if not d then return false, "no density " .. tostring(name) end
  Theme.density = name
  T.dense = d
  if L.Cfg then L.Cfg.set("density", name) end
  -- Row heights are read at construction, so density needs a real rebuild.
  Theme.rebuild()
  return true, name
end

-- ---------------------------------------------------------------- blur

function Theme.setBlur(v)
  v = math.clamp(tonumber(v) or 16, 0, 40)
  L.Window.BLUR = v
  if L.Cfg then L.Cfg.set("blur", v) end
  if L.Hub and L.Hub.window and not L.Hub.window.hidden then
    L.A.blurTo(v, "base")
  end
  return true, string.format("blur %d", v)
end

-- ---------------------------------------------------------------- restore
if L.Cfg then
  local k = L.Cfg.data.theme
  if type(k) == "string" and Theme.palettes[k] then Theme.poke(k) end
  local dn = L.Cfg.data.density
  if type(dn) == "string" and Theme.densities[dn] then
    Theme.density = dn
    T.dense = Theme.densities[dn]
  end
  local bl = tonumber(L.Cfg.data.blur)
  if bl then L.Window.BLUR = math.clamp(bl, 0, 40) end
  local m = L.Cfg.data.motion
  if type(m) == "string" and Theme.motionProfiles[m] then
    Theme.motion = m
    local p = Theme.motionProfiles[m]
    M.durScale, M.bounceScale = p.dur, p.bounce
  end
  -- Only the flag is restored; the three values came from their own keys above.
  -- Re-applying the mode here would overwrite a palette changed while it was on.
  Theme.heavenOn = (L.Cfg.data.heaven == true)
end

end
