-- Runs the game's own battle simulation (BattleDemo.BattleSimulation) to see how a round would
-- end. It uses the game's deterministic inputs and yields between groups of simulation steps
-- so a slower client can still draw frames, handle events, and stop an obsolete search.
--
-- Balls and directions are keyed by team, as in the server's replays: { Blue = "刀片球" } in a 1v1,
-- { Blue = { "刀片球", "蛇球" } } (by seat) in a 2v2, which also needs the 2v2 arena.

local Env = use("core/env")
local Life = use("shared/life")

local Sim = {}

-- Only these two decide a battle. ArenaOverride and GameModeRegistry shape the 2v2 board, and
-- both callers already fall back to the 1v1 config when they are missing, so a place that does
-- not ship them must not hold Smart aim off for the whole session.
local REQUIRED = { "BattleConfig", "BattleSimulation" }
local OPTIONAL = { "ArenaOverride", "GameModeRegistry" }

-- Reads the module cache rather than a flag this file sets, so readiness follows what is actually
-- loaded instead of whether the loader loop below has had its turn yet.
function Sim.ready()
    for _, name in ipairs(REQUIRED) do
        if rawget(Env.Game, name) == nil then
            return false
        end
    end
    return true
end

local optionalTries = {}
Life.loop("duel:simulation-modules", 5, function()
    if not Sim.ready() then
        for _, name in ipairs(REQUIRED) do
            Env.loadModule(name)
        end
        return
    end
    -- The arena modules only matter in 2v2. A few attempts, then they are left alone: each miss
    -- costs this thread a 30-second wait, and the 1v1 board works without them.
    for _, name in ipairs(OPTIONAL) do
        if rawget(Env.Game, name) == nil and (optionalTries[name] or 0) < 3 then
            optionalTries[name] = (optionalTries[name] or 0) + 1
            pcall(Env.loadModule, name)
        end
    end
end)

local SCORE = { win = 1, draw = 0.5, loss = 0 }
local FAST_WIN_BONUS = 0.01 -- tie-break: a quicker win is a safer one

-- Giving a frame back costs ~16ms of a think budget measured in seconds, so yielding once per
-- simulation spent more time waiting for the next frame than simulating. Every search yields off
-- one shared slice clock instead.
local SLICE = 0.008
local sliceStart = os.clock()

function Sim.breathe()
    if os.clock() - sliceStart >= SLICE then
        task.wait()
        Env.elevate()
        sliceStart = os.clock()
    end
    return Life.alive
end

-- Battles run on the game's own step(). A copy of it used to reuse one event table per battle, but
-- the Halloween update added clean-up calls (CandySpill, GraveHaunt) to the real step that the copy
-- missed, so rounds with the new balls were predicted on different rules. The copy saved about 1.5%.

-- The battle config for an arena (nil: the 1v1 board), resolved once per board.
local configs = {}
local function battleConfig(arena)
    local key = arena and arena.boardAssetName or "default"
    if not configs[key] then
        local ok, resolved = Env.call(Env.loadModule("ArenaOverride").resolveConfig, Env.loadModule("BattleConfig"), arena)
        configs[key] = ok and resolved or Env.loadModule("BattleConfig")
    end
    return configs[key]
end

-- The longest a battle can run on this board, for scoring a fast win.
function Sim.maxDuration(arena)
    local ok, duration = pcall(function()
        return battleConfig(arena).replay.maxDuration
    end)
    return ok and type(duration) == "number" and duration > 0 and duration or 1
end

-- A battle is a pure function of (seed, balls, directions, stats, traits, board), and the same
-- combination comes up again and again: the coarse and refine passes share scenarios, the ball
-- search re-tests the same opponents, and the matrix solver re-reads rows it has already filled.
local CACHE_LIMIT = 4096
local cache, cacheCount = {}, 0

local function keyOf(value, out)
    local kind = typeof(value)
    if kind == "Vector2" then
        -- Rounded to the tolerance directions are compared by everywhere else (1e-3).
        out[#out + 1] = string.format("v%.4f,%.4f", value.X, value.Y)
    elseif kind == "table" then
        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        out[#out + 1] = "{"
        for _, key in ipairs(keys) do
            out[#out + 1] = tostring(key)
            out[#out + 1] = "="
            keyOf(value[key], out)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = tostring(value)
    end
    return out
end

-- The board goes in by name: resolveConfig already keys its own cache that way, and serialising a
-- whole arena layout per simulation would cost more than the lookup saves.
local function cacheKey(seed, roles, directions, statLevels, traits, arena)
    local out = { tostring(seed), "|", arena and tostring(arena.boardAssetName) or "default", "|" }
    keyOf(roles, out)
    out[#out + 1] = "|"
    keyOf(directions, out)
    out[#out + 1] = "|"
    keyOf(statLevels, out)
    out[#out + 1] = "|"
    keyOf(traits, out)
    return table.concat(out)
end

function Sim.clearCache()
    table.clear(cache)
    cacheCount = 0
end

-- Plays one battle out. Returns the winning team ("Blue", "Yellow" or "Draw") and its length in
-- seconds, or nil and the error.
function Sim.run(seed, roles, directions, statLevels, traits, arena, deadline, valid)
    if not Sim.ready() then return nil, "simulation modules are still loading" end
    local key = cacheKey(seed, roles, directions, statLevels, traits, arena)
    local hit = cache[key]
    if hit then
        return hit[1], hit[2]
    end
    local cfg = battleConfig(arena)
    local ok, winner, elapsed = Env.call(function()
        local sim = Env.loadModule("BattleSimulation").new(cfg, seed, roles, traits, statLevels, directions)
        local dt = cfg.replay.fixedDt
        assert(type(dt) == "number" and dt > 0 and dt < math.huge, "invalid simulation time step")
        local duration = cfg.replay.maxDuration
        assert(type(duration) == "number" and duration > 0 and duration < math.huge, "invalid simulation duration")
        for step = 1, math.ceil(duration / dt) do
            if sim:step(dt).finished then
                break
            end
            if step % 32 == 0 and os.clock() - sliceStart >= SLICE then
                task.wait()
                Env.elevate()
                sliceStart = os.clock()
                if not Life.alive or (deadline and os.clock() >= deadline) or (valid and not valid()) then
                    return nil, "simulation cancelled"
                end
            end
        end
        local state = sim:getState()
        return state.finished and state.winner or "Draw", state.elapsed
    end)
    if not ok then
        return nil, winner
    end
    -- A cancelled run reports no winner; only a finished battle is a fact worth keeping.
    if winner == nil then
        return nil, elapsed
    end
    if cacheCount >= CACHE_LIMIT then
        Sim.clearCache()
    end
    cache[key] = { winner, elapsed }
    cacheCount += 1
    return winner, elapsed
end

-- `count` launch directions spread evenly around the circle.
function Sim.directions(count)
    local out = {}
    for index = 0, count - 1 do
        local angle = index / count * math.pi * 2
        out[#out + 1] = Vector2.new(math.cos(angle), math.sin(angle))
    end
    return out
end

local random = Random.new()

function Sim.randomDirection()
    local angle = random:NextNumber(0, math.pi * 2)
    return Vector2.new(math.cos(angle), math.sin(angle))
end

function Sim.randomSeed()
    return math.floor(workspace:GetServerTimeNow() * 1000) + random:NextInteger(-600000, 600000)
end

-- The plain result for `team`: 1 win, 0.5 draw, 0 loss. A draw costs no hp, so it really is worth
-- half a win and must never be lumped in with a loss.
function Sim.outcome(winner, team)
    if winner == team then
        return SCORE.win
    end
    return winner == "Draw" and SCORE.draw or SCORE.loss
end

-- How good one outcome is for `team`, plus a little for winning fast.
function Sim.score(winner, elapsed, team, maxDuration)
    local base = Sim.outcome(winner, team)
    if base ~= SCORE.win then
        return base
    end
    return base + FAST_WIN_BONUS * (1 - math.clamp((elapsed or 0) / maxDuration, 0, 1))
end

local score = Sim.score

-- The coarse pass gets this share of the think time; the rest refines around its best directions,
-- since a winning window can be narrower than the gap between two coarse directions.
local COARSE_SHARE = 0.65
local REFINE_TOP = 3
local REFINE_STEPS = { -1 / 3, -1 / 6, 1 / 6, 1 / 3 } -- of the gap between coarse directions

local function rotate(direction, angle)
    local c, s = math.cos(angle), math.sin(angle)
    return Vector2.new(direction.X * c - direction.Y * s, direction.X * s + direction.Y * c)
end

-- Tries every direction against each scenario in turn until the deadline (scenario 1 may run on to
-- `firstDeadline`). A scenario only counts once every direction has been tried against it, so the
-- directions stay comparable. Returns the weighted total per direction, how many scenarios
-- completed, and who wins scenario 1 with each.
local function evaluate(spec, directions, scenarios, deadline, firstDeadline)
    local maxDuration = Sim.maxDuration(spec.arena)
    local totals, rates, completed, firstWinners = {}, {}, 0, {}
    for scenarioIndex, scenario in ipairs(scenarios) do
        local results, outcomes = {}, {}
        local stopAt = scenarioIndex == 1 and (firstDeadline or deadline) or deadline
        for index, direction in ipairs(directions) do
            if not Life.alive or (spec.valid and not spec.valid()) or os.clock() > stopAt then
                break
            end
            local winner, elapsed = Sim.run(scenario.seed, spec.roles, spec.place(direction, scenario),
                spec.statLevels, spec.traits, spec.arena, stopAt, spec.valid)
            results[index] = winner and score(winner, elapsed, spec.team, maxDuration) or 0
            if not winner then
                return totals, completed, firstWinners, rates -- errors are not predicted losses
            end
            outcomes[index] = Sim.outcome(winner, spec.team)
            if scenarioIndex == 1 then
                firstWinners[index] = winner
            end
            Sim.breathe()
        end
        if #results < #directions then
            break -- out of time: this scenario is incomplete, so it is left out
        end
        for index, value in ipairs(results) do
            totals[index] = (totals[index] or 0) + value * scenario.weight
            rates[index] = (rates[index] or 0) + outcomes[index] * scenario.weight
        end
        completed = scenarioIndex
    end
    return totals, completed, firstWinners, rates
end

-- Finds our best launch direction.
-- spec = {
--   team            -- our team ("Blue" or "Yellow"): the winner we want
--   roles           -- every ball, keyed by team as in a replay
--   place           -- function(ourDirection, scenario) -> every direction, keyed by team
--   directions      -- our coarse candidate directions, evenly spaced (Sim.directions)
--   scenarios       -- { { seed, weight, ... } }, most likely first; `place` reads the rest
--   statLevels, traits, arena -- from the match's last replay (nil in round 1, arena nil in a 1v1)
--   deadline        -- os.clock() by which to answer
-- }
-- A coarse pass over `directions`, then a finer one around its best few, against the scenarios the
-- coarse pass completed. Returns the best direction, its expected score (0..1), how many coarse
-- directions win the first scenario, and who wins the first scenario with the best direction.
function Sim.bestDirection(spec)
    if not Sim.ready() or not Life.alive then return nil, 0, 0, nil end
    local started = os.clock()
    local coarseDeadline = started + (spec.deadline - started) * COARSE_SHARE
    -- Scenario 1 (the likely one) may use the whole think time; more only fit in the coarse share.
    local totals, completed, winners, rates = evaluate(spec, spec.directions, spec.scenarios, coarseDeadline, spec.deadline)
    if completed == 0 then
        return nil, 0, 0, nil
    end
    local weights = 0
    for index = 1, completed do
        weights += spec.scenarios[index].weight
    end
    local firstWins = 0
    for _, winner in pairs(winners) do
        firstWins += winner == spec.team and 1 or 0
    end

    local best, bestTotal, bestWinner, bestRate = nil, -1, nil, 0
    local order = {}
    for index, total in ipairs(totals) do
        order[#order + 1] = index
        if total > bestTotal then
            best, bestTotal, bestWinner = spec.directions[index], total, winners[index]
            bestRate = rates[index]
        end
    end

    -- Refine: directions between the best coarse ones and their neighbours, scored on the same
    -- scenarios. Kept only if every one of them finishes, so the comparison stays fair.
    table.sort(order, function(a, b)
        return totals[a] > totals[b]
    end)
    local gap = math.pi * 2 / #spec.directions
    local finer = {}
    for rank = 1, math.min(REFINE_TOP, #order) do
        for _, step in ipairs(REFINE_STEPS) do
            finer[#finer + 1] = rotate(spec.directions[order[rank]], step * gap)
        end
    end
    local scenarios = table.move(spec.scenarios, 1, completed, 1, {})
    local fineTotals, fineCompleted, fineWinners, fineRates = evaluate(spec, finer, scenarios, spec.deadline)
    if fineCompleted == completed then
        for index, total in ipairs(fineTotals) do
            if total > bestTotal then
                best, bestTotal, bestWinner = finer[index], total, fineWinners[index]
                bestRate = fineRates[index]
            end
        end
    end
    return best, math.clamp(bestRate / weights, 0, 1), firstWins, bestWinner
end

Life.onCleanup(function()
    table.clear(configs)
    table.clear(optionalTries)
    Sim.clearCache()
end)

return Sim

