-- Entry point. Core systems first, then features in tab order, then settings (autoload last).

-- The loader waits for this too, but the bundle can also be run on its own (a local build, an
-- auto-execute folder) before the game has finished loading.
if not game:IsLoaded() then
    local deadline = os.clock() + 90
    repeat task.wait(0.1) until game:IsLoaded() or os.clock() >= deadline
    assert(game:IsLoaded(), "DaewidHUB: the game has not finished loading; run the script again once it loads")
end

local Env = use("core/env")
local Life = use("shared/life")
local activeBoot = Env.genv.__DaewidHUBBallBoot
if type(activeBoot) == "table" and type(activeBoot.at) == "number" and os.clock() - activeBoot.at < 120 then
    return "DaewidHUB is already loading"
end
local bootToken = { at = os.clock() }
Env.genv.__DaewidHUBBallBoot = bootToken
local Ui
local function boot()

-- Everything reads the game's own ModuleScripts. An executor that cannot require them cannot run
-- the hub, so that is said once here instead of by every feature failing on its own.
local canRequire, requireError = pcall(function()
    return Env.loadModule("Config")
end)
Env.elevate()
if not canRequire then
    error("your executor could not load the game's modules (require): " .. tostring(requireError), 0)
end

-- A copy already running (the bundle executed twice, or a local build after the loader's) is
-- closed first: two hubs fight over the game, and only the loader used to close the old one.
local previous = Env.genv.__DaewidHUB
if type(previous) == "table" and type(previous.Ui) == "table" and previous.Ui.Library then
    if type(previous.Life) == "table" and type(previous.Life.shutdown) == "function" then
        pcall(previous.Life.shutdown)
    end
    pcall(previous.Ui.Library.Unload, previous.Ui.Library)
    Env.genv.__DaewidHUB = nil
    Env.elevate()
end

Ui = use("core/ui")
local handle = { Ui = Ui, Life = Life, Features = {} }
Env.genv.__DaewidHUB = handle
Life.onCleanup(function()
    Env.stopped = true
    if Env.genv.__DaewidHUB == handle then Env.genv.__DaewidHUB = nil end
end)

local FEATURES = {
    "features/home",
    "features/duel",
    "features/intel",
    "features/rewards",
}
-- One feature failing (a missing remote, a game update) is reported and the rest carry on.
local function load(name)
    if not Life.alive then return nil end
    local ok, result = xpcall(use, Env.traceback, name)
    Env.elevate()
    if not ok then
        Life.errors["load:" .. name] = tostring(result)
        Ui.notify("DaewidHUB", string.format("%s failed to load; the rest still works.", name), 8)
        warn("[DaewidHUB] " .. name .. ": " .. tostring(result))
    end
    return ok and result or nil
end

local loaded = {}
for _, name in ipairs(FEATURES) do
    loaded[name] = load(name)
end

local Settings = load("features/settings")
if Settings then
    Life.call("settings:autoload", Settings.finish)
end
-- After the autoload, so a saved "Redeem codes on load: off" is respected.
local Home = loaded["features/home"]
if Home then
    Life.call("home:after-load", Home.afterLoad)
end

-- Handle for debugging from Real (and for the next version to unload this one).
handle.Features = loaded
-- Match may be unavailable after a game update; that must not undo the working Settings tab.
local matchOk, match = pcall(use, "core/match")
handle.Match = matchOk and match or nil

if Life.alive and type(Env.RuntimeState) == "table" and type(Env.RuntimeState.onCleanup) == "function" then
    Env.RuntimeState.onCleanup(function()
        Env.elevate()
        pcall(function()
            Ui.Library:Unload()
        end)
    end)
end

return "DaewidHUB loaded"
end

local ok, result = xpcall(boot, Env.traceback)
if Env.genv.__DaewidHUBBallBoot == bootToken then Env.genv.__DaewidHUBBallBoot = nil end
if not ok then
    Life.shutdown()
    -- shared/ui stores the library before CreateWindow, allowing partial startup to be cleaned.
    local sharedUi = use("shared/ui")
    if sharedUi.Library then pcall(sharedUi.Library.Unload, sharedUi.Library) end
    error("[DaewidHUB] " .. Env.executor .. ": " .. tostring(result), 0)
end
return result
