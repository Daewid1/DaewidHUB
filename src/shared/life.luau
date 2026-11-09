-- Lifecycle: one "alive" flag for the whole hub, a teardown list, and guarded loops.
--
-- Every background loop goes through Life.loop so it elevates the thread on each pass, stops on
-- unload, and records its last error in Life.errors[name] instead of dying silently inside a
-- task.spawn (which is how panels used to break without anyone noticing).

local Env = use("shared/env")

local Life = {
    alive = true,
    errors = {},
}

local cleanups = {}
local workers = {}
local connectionId = 0

function Life.onCleanup(fn)
    if not Life.alive then
        pcall(fn)
        return
    end
    cleanups[#cleanups + 1] = fn
end

function Life.call(name, fn, ...)
    if not Life.alive then return false, "hub unloaded" end
    Env.elevate()
    local result = table.pack(xpcall(fn, Env.traceback, ...))
    Env.elevate()
    Life.errors[name] = not result[1] and tostring(result[2]) or nil
    return table.unpack(result, 1, result.n)
end

function Life.spawn(name, fn, ...)
    local args = table.pack(...)
    -- defer lets us track the thread before its first instruction (including a shutdown).
    local thread
    thread = task.defer(function()
        Life.call(name, fn, table.unpack(args, 1, args.n))
        workers[thread] = nil
    end)
    workers[thread] = true
    return thread
end

function Life.connect(signal, fn, name)
    connectionId += 1
    name = name or ("event:" .. connectionId)
    local function guarded(...)
        Life.call(name, fn, ...)
    end
    local connection = signal:Connect(guarded)
    Life.onCleanup(function()
        connection:Disconnect()
    end)
    return connection, guarded
end

-- Runs fn every `interval` seconds (a number, or a function returning one) until unload.
function Life.loop(name, interval, fn)
    Life.spawn("loop:" .. name, function()
        local failures = 0
        while Life.alive do
            local ok = Life.call(name, fn)
            failures = ok and 0 or math.min(failures + 1, 5)
            if not Life.alive then
                break
            end
            local intervalOk, delay = pcall(function()
                return type(interval) == "function" and interval() or interval
            end)
            delay = intervalOk and tonumber(delay) or 1
            if not delay or delay ~= delay or delay == math.huge then delay = 1 end
            -- A broken API should not be hammered several times per frame.
            task.wait(math.max(0.05, delay, failures > 0 and 2 ^ (failures - 1) or 0))
        end
    end)
end

-- Waits up to `seconds`, returning early (false) once the hub is unloading.
function Life.wait(seconds)
    local deadline = os.clock() + seconds
    repeat
        -- In slices of at most 0.1s so an unload is noticed, but never past the deadline: a full
        -- 0.1s slice after a 0.11s wait's first one made it 0.2s.
        task.wait(math.min(0.1, math.max(0, deadline - os.clock())))
    until not Life.alive or os.clock() >= deadline
    Env.elevate()
    return Life.alive
end

function Life.shutdown()
    if not Life.alive then
        return
    end
    Life.alive = false
    for thread in pairs(workers) do
        if thread ~= coroutine.running() then pcall(task.cancel, thread) end
    end
    table.clear(workers)
    for index = #cleanups, 1, -1 do
        pcall(cleanups[index])
    end
    table.clear(cleanups)
end

return Life
