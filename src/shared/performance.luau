-- Performance mode, for long AFK farming: cuts what the client draws. Every property it changes is
-- written down first and put back when it goes off or the hub unloads, so nothing sticks.
--   Performance mode   shadows, post effects (bloom, blur, sun rays, colour correction, depth of
--                      field), particles, beams, trails and fire, water waves and reflections, the
--                      render quality, and the frame rate (the FPS limit)
--   3D rendering off   Roblox stops drawing the world at all; the hub's window still shows
-- Effects the game adds while it is on (weather, lightning, hatches) are switched off as they come.

local Env = use("shared/env")
local Life = use("shared/life")
local Ui = use("shared/ui")

local Performance = {}

local EFFECTS = { "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke", "Sparkles", "PostEffect", "Clouds" }
local DEFAULT_FPS = 60 -- what the frame rate goes back to where the executor cannot say what it was

local saved = setmetatable({}, { __mode = "k" }) -- instance -> { property -> original value }
local savedFps
local active = false

local function set(instance, property, value)
    local ok, current = pcall(function()
        return instance[property]
    end)
    if not ok or current == value then
        return
    end
    local entry = saved[instance]
    if not entry then
        entry = {}
        saved[instance] = entry
    end
    if entry[property] == nil then
        entry[property] = current
    end
    pcall(function()
        instance[property] = value
    end)
end

local function isEffect(instance)
    for _, class in ipairs(EFFECTS) do
        if instance:IsA(class) then
            return true
        end
    end
    return false
end

local function quiet(instance)
    if isEffect(instance) then
        set(instance, "Enabled", false)
    end
end

local function applyFps()
    if active and setfpscap then
        pcall(setfpscap, Ui.Options.PerfFps.Value)
    end
end

local function enable()
    if active then
        return
    end
    active = true
    if setfpscap then
        local ok, cap = pcall(function()
            return getfpscap and getfpscap()
        end)
        savedFps = ok and tonumber(cap) or DEFAULT_FPS
        applyFps()
    end
    local lighting = game:GetService("Lighting")
    set(lighting, "GlobalShadows", false)
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        set(terrain, "WaterWaveSize", 0)
        set(terrain, "WaterWaveSpeed", 0)
        set(terrain, "WaterReflectance", 0)
        set(terrain, "Decoration", false)
    end
    pcall(function()
        set(settings().Rendering, "QualityLevel", Enum.QualityLevel.Level01)
    end)
    for _, root in ipairs({ lighting, workspace }) do
        for index, instance in ipairs(root:GetDescendants()) do
            if not active then
                return
            end
            quiet(instance)
            if index % 4000 == 0 then
                task.wait() -- a big map in one go is a visible hitch
            end
        end
    end
end

local function disable()
    active = false
    for instance, properties in pairs(saved) do
        for property, value in pairs(properties) do
            pcall(function()
                instance[property] = value
            end)
        end
    end
    table.clear(saved)
    if savedFps and setfpscap then
        pcall(setfpscap, savedFps)
        savedFps = nil
    end
end

local function setRendering(on)
    pcall(Env.RunService.Set3dRenderingEnabled, Env.RunService, on)
end

-- The "Performance" box on `tab`.
function Performance.build(tab)
    local group = tab:AddGroupbox({ Side = "Left", Name = "Performance", IconName = "gauge" })
    group:AddToggle("PerfMode", {
        Text = "Performance mode",
        Default = false,
        Tooltip = "Turns off shadows, post effects, particles and water animation, lowers the render quality and limits the frame rate. All of it comes back when you switch it off.",
    })
    group:AddSlider("PerfFps", {
        Text = "FPS limit",
        Default = 30,
        Min = 5,
        Max = 240,
        Rounding = 0,
        Tooltip = setfpscap and "The frame rate while performance mode is on. Below about 15 the automation reacts more slowly."
            or "Your executor has no setfpscap, so the frame rate cannot be limited.",
    })
    group:AddToggle("PerfNoRender", {
        Text = "Turn off 3D rendering",
        Default = false,
        Tooltip = "The world is no longer drawn (a blank screen with the hub on it): the biggest saving while AFK. Everything keeps running.",
    })

    Ui.Toggles.PerfMode:OnChanged(function(on)
        if on then
            task.spawn(enable)
        else
            disable()
        end
    end)
    Ui.Options.PerfFps:OnChanged(applyFps)
    Ui.Toggles.PerfNoRender:OnChanged(function(on)
        setRendering(not on)
    end)

    for _, root in ipairs({ game:GetService("Lighting"), workspace }) do
        Life.connect(root.DescendantAdded, function(instance)
            if active then
                quiet(instance)
            end
        end)
    end
    Life.onCleanup(function()
        disable()
        setRendering(true)
    end)
    return group
end

return Performance
