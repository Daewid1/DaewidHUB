-- Solves the aim phase as the game it actually is.
--
-- From round 2 the seed is known exactly (core/match), every ball is locked before aiming starts,
-- and the battle is deterministic. The only thing left unknown is where the others launch. That
-- makes one round a finite two-player zero-sum simultaneous game whose payoff function we can
-- evaluate directly, so instead of guessing one opponent aim and answering it, this builds the
-- payoff matrix: our candidate directions down the rows, the opponent's down the columns.
--
-- Three numbers come out of a row, and they answer different questions:
--   expected  how the row does against the opponent we actually expect (core/profile weights it)
--   worst     the worst any opponent direction can do to it: a floor that holds whatever they pick
--   wins      how many opponent directions it beats outright, i.e. how forgiving the aim is
--
-- Ranking by `expected` alone exploits a predictable opponent but can be punished badly by a
-- surprise. Ranking by `worst` alone is the maximin play: it gives up some wins to never be
-- blown out. `lambda` slides between them, and hp moves it on its own, because the value of a
-- round is not symmetric when someone is one loss from going out.

local Life = use("shared/life")
local Sim = use("core/sim")

local Solver = {}

-- A row has to cover every column in the current comparison set before it can be ranked against
-- another row: a partly filled row has a flattering minimum and a meaningless average.
local function rank(a, b)
    if a.score ~= b.score then
        return a.score > b.score
    end
    if a.worst ~= b.worst then
        return a.worst > b.worst
    end
    return a.wins > b.wins
end

-- Fills columns `from`..`to` of one row. False when the search was cancelled or ran out of time,
-- in which case the row keeps whatever it had and must not be ranked at the new column count.
local function fill(spec, row, from, to)
    for column = from, to do
        if not Life.alive or (spec.valid and not spec.valid()) or os.clock() >= spec.deadline then
            return false
        end
        local scenario = spec.opponents[column]
        local winner, elapsed = Sim.run(spec.seed, spec.roles, spec.place(row.direction, scenario),
            spec.statLevels, spec.traits, spec.arena, spec.deadline, spec.valid)
        if not winner then
            return false -- an error or a cancellation is not a predicted loss
        end
        row.scores[column] = Sim.score(winner, elapsed, spec.team, spec.maxDuration)
        row.outcomes[column] = Sim.outcome(winner, spec.team)
        if column == 1 then
            row.winner = winner
        end
        Sim.breathe()
    end
    return true
end

-- Collapses a row's filled columns into the three numbers, under `lambda`.
local function summarise(row, spec, columns)
    local weighted, weights, worst, wins = 0, 0, math.huge, 0
    for column = 1, columns do
        local weight = spec.opponents[column].weight or 1
        weighted += row.scores[column] * weight
        weights += weight
        worst = math.min(worst, row.outcomes[column])
        wins += row.outcomes[column] >= 1 and 1 or 0
    end
    row.expected = weights > 0 and weighted / weights or 0
    row.worst = worst == math.huge and 0 or worst
    row.wins = wins
    row.columns = columns
    row.score = (1 - spec.lambda) * row.expected + spec.lambda * row.worst
end

local function newRow(direction)
    return { direction = direction, scores = {}, outcomes = {}, expected = 0, worst = 0, wins = 0, score = -1 }
end

-- Evaluates every candidate against columns 1..`columns` and returns the ones that covered them
-- all, best first. `done` is false when the stage was cut short, so the caller keeps the previous
-- stage's answer rather than comparing rows judged on different opponents.
local function stage(spec, candidates, columns)
    local complete, done = {}, true
    for _, row in ipairs(candidates) do
        local from = (row.columns or 0) + 1
        if from > columns then
            summarise(row, spec, columns)
            complete[#complete + 1] = row
        elseif fill(spec, row, from, columns) then
            summarise(row, spec, columns)
            complete[#complete + 1] = row
        else
            done = false
            break
        end
    end
    table.sort(complete, rank)
    return complete, done
end

local function rotate(direction, angle)
    local c, s = math.cos(angle), math.sin(angle)
    return Vector2.new(direction.X * c - direction.Y * s, direction.X * s + direction.Y * c)
end

-- How much weight the floor gets. A round is not worth the same to both sides once someone is one
-- loss from out: at 1 hp a loss ends the match, so the floor matters more than the average; when
-- the opponent is at 1 hp a win ends it, so it is worth reaching for.
local STYLE = { Exploit = 0, Balanced = 0.5, Safe = 1 }

function Solver.lambda(style, ourHp, theirHp)
    local lambda = STYLE[style] or STYLE.Balanced
    if ourHp == 1 then
        lambda += 0.25
    end
    if theirHp == 1 then
        lambda -= 0.2
    end
    return math.clamp(lambda, 0, 1)
end

-- The opponent's candidate directions, as scenarios the caller's `place` can read.
--
-- Column 1 is who we think they are: the aim core/profile expects them to keep. The rest cover
-- what else they could do. With one unknown opponent that space is just the circle, so it is
-- covered evenly and the row minimum becomes a real maximin over that discretisation. With two
-- (a 2v2) the joint space is square and sampling it is the only thing that fits the budget.
function Solver.columns(players, likely, modelled, count)
    local unknown = {}
    for _, player in ipairs(players) do
        if not player.me and not player.teammate then
            unknown[#unknown + 1] = player
        end
    end
    -- An opponent who changed their aim last round has no direction to expect. Their slot in
    -- column 1 is then as random as any other column, and giving it the model's weight would let
    -- a coin flip dominate the expected value -- so without a full prediction every column counts
    -- the same and the row's average is a plain average over the sweep.
    local predicted = true
    for _, player in ipairs(unknown) do
        predicted = predicted and likely[player.userId] ~= nil
    end
    local weight = predicted and math.clamp(modelled or 0.6, 0.05, 0.95) or 1 / math.max(1, count)
    local first = { others = {}, weight = weight, modelled = predicted }
    for _, player in ipairs(players) do
        if not player.me then
            first.others[player.userId] = likely[player.userId] or Sim.randomDirection()
        end
    end
    local columns = { first }
    local spread = (1 - first.weight) / math.max(1, count - 1)
    if #unknown == 1 then
        local opponent = unknown[1]
        local sweep = Sim.directions(count - 1)
        for _, direction in ipairs(sweep) do
            local others = {}
            for userId, value in pairs(first.others) do
                others[userId] = value -- the teammate's aim is known and stays put
            end
            others[opponent.userId] = direction
            columns[#columns + 1] = { others = others, weight = spread }
        end
        return columns
    end
    for _ = 2, count do
        local others = {}
        for userId, value in pairs(first.others) do
            others[userId] = value
        end
        for _, player in ipairs(unknown) do
            others[player.userId] = Sim.randomDirection()
        end
        columns[#columns + 1] = { others = others, weight = spread }
    end
    return columns
end

-- spec = {
--   team, seed, roles, statLevels, traits, arena -- the round, exactly as the server will run it
--   ours        -- our candidate directions, evenly spaced (Sim.directions)
--   opponents   -- Solver.columns(...): index 1 is the opponent we expect
--   place       -- function(ourDirection, scenario) -> directions keyed by team, as in a replay
--   lambda      -- Solver.lambda(...): 0 answers the expected opponent, 1 plays the floor
--   deadline, valid
-- }
--
-- Widens in stages so there is always an answer to give back: the whole grid against a few
-- opponent directions first, then the leaders against all of them, then finer directions around
-- the leaders. Every stage compares rows that saw the same opponents.
--
-- Returns the winning row { direction, score, expected, worst, wins, winner, columns } and how
-- many opponent directions it was judged against, or nil when nothing finished in time.
local NARROW = 4 -- opponent columns every one of our directions is tried against
local SURVIVORS = 4
local REFINE_STEPS = { -1 / 3, -1 / 6, 1 / 6, 1 / 3 } -- of the gap between our coarse directions
local PHI = (math.sqrt(5) - 1) / 2

-- Our directions in golden-ratio order rather than round the circle. If the clock runs out
-- partway through the first pass, the rows that did finish are still spread over every side of
-- the board, instead of all sitting in the one arc that happened to come first.
local function spread(directions)
    local order = {}
    for index = 1, #directions do
        order[index] = index
    end
    table.sort(order, function(a, b)
        return ((a - 1) * PHI) % 1 < ((b - 1) * PHI) % 1
    end)
    local out = {}
    for _, index in ipairs(order) do
        out[#out + 1] = directions[index]
    end
    return out
end

function Solver.solve(spec)
    if not Sim.ready() or not Life.alive or not spec.seed or #spec.ours == 0 or #spec.opponents == 0 then
        return nil
    end
    spec.lambda = math.clamp(spec.lambda or 0.5, 0, 1)
    spec.maxDuration = Sim.maxDuration(spec.arena)
    local narrow = math.min(NARROW, #spec.opponents)
    local full = #spec.opponents

    -- Every list `stage` returns holds only rows that covered all of its columns, so a stage cut
    -- short still ranks fairly; it just ranks fewer rows.
    local rows = {}
    for _, direction in ipairs(spread(spec.ours)) do
        rows[#rows + 1] = newRow(direction)
    end
    local best = stage(spec, rows, narrow)
    if #best == 0 then
        return nil
    end

    -- The leaders face every opponent column. The narrow pass is already cached, so this only
    -- pays for the columns it adds. Leaders run best first, so a cut-off loses the weakest.
    local leaders = table.move(best, 1, math.min(SURVIVORS, #best), 1, {})
    local widened, done = stage(spec, leaders, full)
    if #widened == 0 then
        return best[1], narrow
    end
    if not done then
        return widened[1], full
    end

    if widened[1].worst >= 1 then
        return widened[1], full
    end

    -- A winning window can be narrower than the gap between two coarse directions.
    local gap = math.pi * 2 / #spec.ours
    local finer = table.move(widened, 1, #widened, 1, {})
    for place = 1, math.min(2, #widened) do
        for _, step in ipairs(REFINE_STEPS) do
            finer[#finer + 1] = newRow(rotate(widened[place].direction, step * gap))
        end
    end
    -- The widened rows lead the list and are already complete, so this is never empty.
    local refined = stage(spec, finer, full)
    return refined[1], full
end

return Solver

