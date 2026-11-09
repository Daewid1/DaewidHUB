-- Services, the local player, and the executor, the same for every game. Each game's core/env
-- extends this table with what only that game has (its ModuleScripts, its places).
--
-- Two Real quirks shape everything here:
--  * Calling into one of the game's modules, or yielding, can leave the thread without the
--    capability the UI needs ("lacking capability Plugin") while getthreadidentity() still says
--    8. Env.elevate() puts it back; Env.call() wraps a game call and elevates afterwards.
--  * Game modules are required lazily (Env.modules), so a feature only pays for what it uses.

local Env = {}

Env.Players = game:GetService("Players")
Env.ReplicatedStorage = game:GetService("ReplicatedStorage")
Env.RunService = game:GetService("RunService")
Env.CollectionService = game:GetService("CollectionService")
Env.VirtualUser = game:GetService("VirtualUser")
Env.TeleportService = game:GetService("TeleportService")
Env.HttpService = game:GetService("HttpService")
Env.LocalPlayer = Env.Players.LocalPlayer
if not Env.LocalPlayer then
    local deadline = os.clock() + 30
    repeat
        task.wait(0.05)
        Env.LocalPlayer = Env.Players.LocalPlayer
    until Env.LocalPlayer or os.clock() >= deadline
    assert(Env.LocalPlayer, "DaewidHUB: local player is not ready; run the script again once the game loads")
end

local function first(...)
    for index = 1, select("#", ...) do
        local fn = select(index, ...)
        if type(fn) == "function" then return fn end
    end
end

local setIdentity = first(setthreadidentity, set_thread_identity, setidentity, setthreadcontext)

function Env.elevate()
    if setIdentity then
        pcall(setIdentity, 8)
    end
end

-- Calls fn (usually a game-module function) and restores the thread afterwards.
-- Returns ok, ... like pcall.
function Env.call(fn, ...)
    local results = table.pack(pcall(fn, ...))
    Env.elevate()
    return table.unpack(results, 1, results.n)
end

-- Executor functions -------------------------------------------------------------------------
-- Functions are optional unless the feature actually needs them. An executor's name or sUNC
-- score does not establish that any particular operation will succeed on this client.
-- The hub must not break where a function is
-- missing or goes by another name: everything executor-specific is looked up here once, and a
-- feature that cannot work without one says so instead of silently doing nothing.

local executorEnv = getfenv()
local function member(container, key)
    return type(container) == "table" and container[key] or nil
end
local syn, fluxus = executorEnv.syn, executorEnv.fluxus
local envOk, globalEnv = pcall(function() return getgenv() end)
Env.genv = envOk and type(globalEnv) == "table" and globalEnv or _G
Env.request = first(request, http_request, member(http, "request"), member(syn, "request"), member(fluxus, "request"))
Env.queueOnTeleport = first(queue_on_teleport, queueonteleport, member(syn, "queue_on_teleport"), member(fluxus, "queue_on_teleport"))
Env.setClipboard = first(setclipboard, toclipboard, set_clipboard, member(Clipboard, "set"))
Env.loadstring = first(loadstring)
Env.files = {}
for _, name in ipairs({ "readfile", "writefile", "isfile", "isfolder", "makefolder", "listfiles", "delfile" }) do
    Env.files[name] = first(executorEnv[name], Env.genv[name])
end
Env.canCache = Env.files.readfile ~= nil and Env.files.isfile ~= nil
Env.canSave = true
for _, name in ipairs({ "readfile", "writefile", "isfile", "isfolder", "makefolder", "listfiles", "delfile" }) do
    if not Env.files[name] then Env.canSave = false end
end
Env.traceback = debug and first(debug.traceback) or tostring
local executorOk, executorName = pcall(function()
    return identifyexecutor()
end)
Env.executor = executorOk and type(executorName) == "string" and executorName or "Unknown"

-- Missing functions that switch a feature off or change how it works, for the Settings tab.
-- A list, not a map: a map literal drops the missing (nil) ones before they can be counted.
-- Each game names the functions it cares about (Env.checkMissing), since what one needs another
-- never calls.
Env.missing = {}
local missingSet = {}
function Env.checkMissing(entries)
    for _, entry in ipairs(entries) do
        if type(entry[2]) ~= "function" and not missingSet[entry[1]] then
            missingSet[entry[1]] = true
            Env.missing[#Env.missing + 1] = entry[1]
        end
    end
end

-- Triggers a ProximityPrompt. Without fireproximityprompt it is pressed the way a player would,
-- with its hold lifted for the moment: that only takes while the prompt is on screen, i.e. in
-- range, which every caller already stands within (the server checks range either way).
function Env.firePrompt(prompt)
    if fireproximityprompt and pcall(fireproximityprompt, prompt) then
        Env.elevate()
        return true
    end
    local hold, sight = prompt.HoldDuration, prompt.RequiresLineOfSight
    local ok = pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        task.wait(0.1)
        prompt:InputHoldBegin()
        task.wait()
        prompt:InputHoldEnd()
    end)
    pcall(function()
        prompt.HoldDuration, prompt.RequiresLineOfSight = hold, sight
    end)
    Env.elevate()
    return ok
end

-- Simulates a touch (start then end) of `part` by `by`. False where the executor cannot.
function Env.touch(by, part)
    if not firetouchinterest then
        return false
    end
    local began = pcall(firetouchinterest, by, part, 0)
    task.wait() -- some executors only register the touch on the next physics step
    pcall(firetouchinterest, by, part, 1)
    return began
end

-- True when this client simulates `part`'s physics (so moving it replicates). Nil when the
-- executor cannot tell.
function Env.ownsPart(part)
    if not isnetworkowner then
        return nil
    end
    local ok, owns = pcall(isnetworkowner, part)
    return ok and owns == true
end

-- parent:WaitForChild(name) that gives up after `seconds` (30 by default) with an error naming
-- what is missing, so one absent folder fails its own feature instead of freezing the hub.
function Env.need(parent, name, seconds)
    local child = parent:WaitForChild(name, seconds or 30)
    Env.elevate()
    if not child then
        error(string.format("%s.%s is missing", parent:GetFullName(), name), 2)
    end
    return child
end

-- A lazy table of the game's ModuleScripts: modules.Name is required on first use and cached.
-- `paths` maps each name to its path under `root` (a list of child names).
--
-- Also returns load(name), the same loader as a plain function. Indexing runs it inside __index,
-- and Luau cannot yield there ("attempt to yield across metamethod/C-call boundary"), which a
-- module does while it waits on the game: right after a teleport from the main menu the client
-- controllers wait for the character and inventory. Load those with load() (Env.preload) first.
function Env.modules(root, paths)
    local cache, pending = {}, {}
    local function load(name)
        local loaded = rawget(cache, name)
        if loaded ~= nil then
            return loaded
        end
        local path = paths[name]
        assert(path, "DaewidHUB: unknown game module " .. tostring(name))
        if Env.stopped then error("DaewidHUB: hub unloaded", 2) end
        local work = pending[name]
        if not work then
            work = {}
            pending[name] = work
            task.spawn(function()
                work.result = table.pack(Env.call(function()
                    local node = root
                    local deadline = os.clock() + 30
                    for _, part in ipairs(path) do
                        node = Env.need(node, part, math.max(0.1, deadline - os.clock()))
                    end
                    return require(node)
                end))
                work.done = true
            end)
        end
        local deadline = os.clock() + 30
        repeat
            if work.done then break end
            task.wait(0.05)
        until Env.stopped or os.clock() >= deadline
        Env.elevate()
        if Env.stopped then error("DaewidHUB: hub unloaded", 2) end
        if not work.done then
            error("DaewidHUB: game module " .. name .. " is still loading; try again after the game finishes loading", 2)
        end
        pending[name] = nil
        if not work.result[1] then error(work.result[2], 2) end
        local module = work.result[2]
        rawset(cache, name, module)
        return module
    end
    return setmetatable(cache, {
        __index = function(_, name)
            return load(name)
        end,
    }), load
end

-- The live-reload handle when Real's live-reload started us (nil from the GitHub loader).
Env.RuntimeState = getfenv().STATE

return Env
