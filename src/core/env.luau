-- Ball VS Ball: the game's own ModuleScripts and remotes. Everything else (services, the executor,
-- elevate) comes from shared/env.
--
-- Remotes use sleitnick Net names. Resolve their instances under Packages without invoking
-- the module loader while resolving a replicated event or function.

local Env = use("shared/env")

Env.checkMissing({
    { "queue_on_teleport", Env.queueOnTeleport },
    { "setclipboard", Env.setClipboard },
})
for name, _ in pairs({ readfile = true, writefile = true, isfile = true, isfolder = true,
    makefolder = true, listfiles = true, delfile = true }) do
    Env.checkMissing({ { name, Env.files[name] } })
end
table.sort(Env.missing)

local RS = Env.ReplicatedStorage
local SERVICE = { "Engine", "Service" }
local function service(name)
    return { SERVICE[1], SERVICE[2], name }
end

-- Env.loadModule("Config"), Env.loadModule("PlayerData"), ...: required on first use and cached.
Env.Game, Env.loadModule = Env.modules(RS, {
    Net = { "Packages", "Net" },
    Config = service("Config"), -- the game's CloudConfig: balls, codes, quests, crates, limits
    PlayerData = service("PlayerData"),
    ExperienceService = service("ExperienceService"),
    TimeService = service("TimeService"),
    GameModeRegistry = service("GameModeRegistry"),
    CheckInService = service("CheckInService"),
    OnlineRewardConfig = service("OnlineRewardConfig"),
    HalloweenCandyRules = service("HalloweenCandyRules"), -- which event is on, its end, the daily candy cap
    StatsCore = { "Engine", "Service", "BallBattleStatsService", "Core" },
    BattleConfig = { "BattleDemo", "BattleConfig" },
    BattleSimulation = { "BattleDemo", "BattleSimulation" },
    ArenaOverride = { "BattleDemo", "ArenaOverride" },
})

local remotes = {}
local CONSTRUCTORS = { event = "RemoteEvent", unreliable = "UnreliableRemoteEvent", fn = "RemoteFunction" }
local PREFIX = { event = "RE/", unreliable = "URE/", fn = "RF/" }
local function remote(kind, name)
    Env.elevate()
    local key = kind .. name
    if not remotes[key] or not remotes[key].Parent then
        -- Locate the replicated instance without requiring Net in a lazy-table lookup;
        -- matching the class avoids an event/function mixup.
        local packages = Env.need(RS, "Packages", 10)
        local found = packages:FindFirstChild(PREFIX[kind] .. name, true)
        local deadline = os.clock() + 5
        while not found and os.clock() < deadline do
            task.wait(0.1)
            found = packages:FindFirstChild(PREFIX[kind] .. name, true)
        end
        Env.elevate()
        if not found then
            error("DaewidHUB: remote " .. name .. " is not available yet", 2)
        end
        assert(found:IsA(CONSTRUCTORS[kind]), "DaewidHUB: remote " .. name .. " has an unexpected class")
        remotes[key] = found
    end
    return remotes[key]
end

-- The RemoteEvent the game calls `name` ("DuelTableState").
function Env.event(name)
    return remote("event", name)
end

-- The UnreliableRemoteEvent the game calls `name` ("DuelTableAimPreview").
function Env.unreliable(name)
    return remote("unreliable", name)
end

local pending, retryAt = {}, {}
Env.requestIssues = {}

-- A timeout cannot undo a server action. Keep that remote occupied until its original call
-- finishes, then allow replication time before another request. Never retry inside this helper.
function Env.invoke(name, ...)
    if Env.stopped then return false, "hub unloaded" end
    if pending[name] or os.clock() < (retryAt[name] or 0) then
        return false, "waiting for the previous " .. name .. " request"
    end
    local work, args = {}, table.pack(...)
    pending[name] = work
    task.spawn(function()
        work.result = table.pack(Env.call(function()
            local fn = remote("fn", name)
            return fn:InvokeServer(table.unpack(args, 1, args.n))
        end))
        work.done = true
        if work.timedOut then
            retryAt[name] = os.clock() + 30
            Env.requestIssues[name] = "Late reply received; waiting for inventory/balance updates."
            local untilAt = retryAt[name]
            task.delay(30, function()
                if retryAt[name] == untilAt then Env.requestIssues[name] = nil end
            end)
        end
        if pending[name] == work then pending[name] = nil end
    end)
    local deadline = os.clock() + 15
    while not work.done and not Env.stopped and os.clock() < deadline do task.wait(0.05) end
    Env.elevate()
    if Env.stopped then return false, "hub unloaded" end
    if not work.done then
        work.timedOut = true
        Env.requestIssues[name] = "No reply yet; duplicate requests are paused."
        return false, "request timed out; its result is not yet known"
    end
    Env.requestIssues[name] = nil
    return table.unpack(work.result, 1, work.result.n)
end

-- What kind of server this is: "standard" (3 HP tables), "twoVTwoServer" (2v2 tables) or
-- "tradeServer", or nil until the game has said. Since the October 16 update each mode has its own
-- servers and Quick Play seats you at whatever this one has. The game's ServerTeleport package
-- keeps it as an attribute on its module; getServerType() waits for it, this does not.
function Env.serverType()
    local ok, kind = pcall(function()
        for _, child in ipairs(Env.need(RS, "Packages", 10)._Index:GetChildren()) do
            if child.Name:find("serverteleport", 1, true) then
                local module = child:FindFirstChild("serverteleport")
                return module and module:GetAttribute("serverType")
            end
        end
        return nil
    end)
    Env.elevate()
    return ok and type(kind) == "string" and kind or nil
end

-- The local player's saved data as the game's client sees it: Env.data("coins") -> 490.
-- Nil when the value is not there (yet).
function Env.data(key)
    local ok, value = Env.call(function()
        return Env.loadModule("PlayerData").client[key]()
    end)
    if ok then return value end
    return nil
end

-- A ball's English name (roleIds are the game's Chinese ids, e.g. "刀片球" -> "Blade Ball").
function Env.ballName(roleId)
    local ok, ball = pcall(function()
        return Env.loadModule("Config").ball.byCnId[roleId]
    end)
    return ok and ball and ball.displayName or tostring(roleId)
end

return Env

