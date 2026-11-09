-- Card ids are engine keys; upgradeChoice is indexed by the corresponding Chinese config id.
--
-- Two ways to judge a card. Upgrades.score reads its star rating out of the cloud config and adds
-- a bonus where its text lines up with the ball's traits: cheap, always available, and a guess.
-- Upgrades.bestBySimulation is the real answer, because a card is not a description -- it is an
-- entry in the statLevels and secondary-trait tables the server hands to the battle simulation.
-- Project the card into those tables, replay the next round with the game's own code, and the
-- question "which of these three wins" stops being a keyword match. The heuristic stays as the
-- tie-break and as the fallback for round 1, where there is no seed to replay against.
local Env = use("core/env")
local Sim = use("core/sim")
local Upgrades = {}

local function textOf(value)
    if type(value) ~= "table" then
        return tostring(value or "")
    end
    return table.concat({ tostring(value.behaviorKey or ""), tostring(value.displayName or ""),
        tostring(value.cnId or ""), tostring(value.trigger or "") }, " ")
end

local function contains(text, words)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

function Upgrades.definition(candidate)
    if type(candidate) ~= "table" or type(candidate.id) ~= "string" then
        return nil
    end
    local battle = rawget(Env.Game, "BattleConfig")
    if not battle then return nil end
    local stats = type(battle.tournament_upgrade) == "table" and battle.tournament_upgrade.basicStats or nil
    local defs = candidate.kind == "effect" and battle.traits
        or candidate.kind == "basicStat" and stats
    local effect = type(defs) == "table" and defs[candidate.id] or nil
    local choice = Env.loadModule("Config").upgradeChoice
    local choices = type(choice) == "table" and choice.byTargetCnId or nil
    if type(choices) ~= "table" then
        return nil, effect
    end
    return choices[effect and effect.cnId or candidate.id], effect
end

function Upgrades.score(candidate, roleId, secondary)
    local choice, effect = Upgrades.definition(candidate)
    local star = choice and tonumber(choice.star) or 0
    if not choice then
        return -math.huge, nil -- unknown metadata must not be mistaken for a one-star card
    end
    local config, battle = Env.loadModule("Config"), Env.loadModule("BattleConfig")
    local ball = config.ball.byCnId[roleId]
    local role = battle.roles and battle.roles[roleId]
    local traitsByKey = type(battle.traits) == "table" and battle.traits or {}
    local active = { textOf(ball), textOf(role and role.skill) }
    -- Cloud ball.skills contains Chinese skill ids; resolve them to engine behavior keys.
    for _, id in ipairs(ball and ball.skills or {}) do
        active[#active + 1] = textOf(id)
        for key, trait in pairs(traitsByKey) do
            if type(trait) == "table" and trait.cnId == id then
                active[#active + 1] = key .. " " .. textOf(trait)
            end
        end
    end
    for _, id in ipairs(type(secondary) == "table" and secondary or {}) do
        active[#active + 1] = textOf(id) .. " " .. textOf(traitsByKey[id])
    end
    local traits = string.lower(table.concat(active, " "))
    local target = string.lower(candidate.id .. " " .. textOf(effect) .. " " .. textOf(choice))
    local bonus = 0
    if contains(traits, { "blade", "axe", "burst" })
        and contains(target, { "attackspeed", "attack speed", "bounceaccel", "bounce accel", "ballhitaccel" }) then
        bonus = 15
    elseif contains(traits, { "poison", "acid", "snake", "venom", "virus" })
        and contains(target, { "poisonduration", "poison duration", "poisonampl", "poison ampl", "lastingpoison", "damageamplification", "venom" }) then
        bonus = 15
    elseif contains(traits, { "electric", "electro", "voltaic" })
        and contains(target, { "stun", "paraly", "paralysis", "shockduration", "shock duration" }) then
        bonus = 15
    elseif candidate.id == "hp" or candidate.id == "LowHpArmor"
        or contains(target, { "defense", "shield", "health", "maxhp", "thick skin" }) then
        bonus = 3
    end
    return star * 10 + bonus, star
end

local function usable(candidate)
    return type(candidate) == "table" and type(candidate.id) == "string"
        and (candidate.kind == "effect" or candidate.kind == "basicStat")
end

function Upgrades.best(candidates, roleId, secondary)
    local best, bestScore, maxStar, known = nil, -math.huge, 0, true
    for _, candidate in ipairs(candidates) do
        local score, star = Upgrades.score(candidate, roleId, secondary)
        known = known and star ~= nil
        maxStar = math.max(maxStar, star or 0)
        if usable(candidate) and (not best or score > bestScore) then
            best, bestScore = candidate, score
        end
    end
    return best, maxStar, known
end

-- Projection -----------------------------------------------------------------------------------

-- Replaces one level of a container so the original (the live replay options) is never touched.
local function branch(container, key)
    local copy = table.clone(container)
    copy[key] = type(container[key]) == "table" and table.clone(container[key]) or nil
    return copy
end

-- Where our entry lives in a replay's per-team tables: one value per team in a 1v1, a list by seat
-- in a 2v2. `teamMode` says which, and the stored shape has to agree before anything is projected:
-- a mismatch means the game changed how it keys these, and simulating a guessed layout would be
-- worse than the heuristic it is meant to replace.
local function seat(container, team, index, teamMode)
    local value = type(container) == "table" and container[team]
    if type(value) ~= "table" then
        return nil
    end
    local perSeat = type(value[1]) == "table"
    if perSeat ~= (teamMode == true) then
        return nil
    end
    if not perSeat then
        return value
    end
    return type(value[index]) == "table" and value[index] or nil
end

-- The round's simulation inputs with `candidate` applied, or nil when the layout is unfamiliar.
-- A basic stat raises its level by one; an effect is appended to our secondary traits, which is
-- how the server records a chosen trait card.
function Upgrades.project(candidate, statLevels, traits, team, index, teamMode)
    if not usable(candidate) then
        return nil
    end
    if candidate.kind == "basicStat" then
        local current = seat(statLevels, team, index, teamMode)
        if not current or type(current[candidate.id]) ~= "number" then
            return nil
        end
        local projected = branch(statLevels, team)
        local target = projected[team]
        if teamMode then
            target[index] = table.clone(target[index])
            target = target[index]
        end
        target[candidate.id] += 1
        return projected, traits
    end
    local current = seat(traits, team, index, teamMode)
    if not current then
        return nil
    end
    for _, held in ipairs(current) do
        if held == candidate.id then
            return nil -- already carried; the card would change nothing to simulate
        end
    end
    local projected = branch(traits, team)
    local target = projected[team]
    if teamMode then
        target[index] = table.clone(target[index])
        target = target[index]
    end
    target[#target + 1] = candidate.id
    return statLevels, projected
end

-- Simulated selection -------------------------------------------------------------------------

-- Picks the card that actually wins the next round.
--
-- context = {
--   seed                      -- next round's seed (Match.nextSeed); nil means no simulation
--   team, index, teamMode     -- which entry in the per-team tables is ours
--   roles, directions         -- every ball and launch direction, keyed by team as in a replay
--   statLevels, traits, arena -- the round's inputs, from the last replay
--   roleId, secondary         -- for the heuristic tie-break
--   deadline, valid
-- }
--
-- Returns the card, a line explaining it, and the simulated outcome (1 win, 0.5 draw, 0 loss), or
-- nil when nothing could be simulated in time and the caller should fall back to Upgrades.best.
function Upgrades.bestBySimulation(candidates, context)
    if not context.seed or not Sim.ready() or type(context.roles) ~= "table"
        or type(context.directions) ~= "table" then
        return nil
    end
    local maxDuration = Sim.maxDuration(context.arena)
    local function play(statLevels, traits)
        local winner, elapsed = Sim.run(context.seed, context.roles, context.directions, statLevels, traits,
            context.arena, context.deadline, context.valid)
        if not winner then
            return nil
        end
        return Sim.outcome(winner, context.team), Sim.score(winner, elapsed, context.team, maxDuration)
    end

    -- The same round without any card, so the report can say what the choice is worth.
    local baseline = play(context.statLevels, context.traits)
    local best, bestOutcome, bestScore, bestHeuristic, tried = nil, -1, -1, -math.huge, 0
    for _, candidate in ipairs(candidates) do
        if os.clock() >= context.deadline or (context.valid and not context.valid()) then
            break
        end
        local statLevels, traits = Upgrades.project(candidate, context.statLevels, context.traits,
            context.team, context.index, context.teamMode)
        if statLevels then
            local outcome, score = play(statLevels, traits)
            if outcome then
                tried += 1
                local heuristic = Upgrades.score(candidate, context.roleId, context.secondary)
                -- Outcome first, then how fast, then the star/synergy guess for a genuine tie.
                if outcome > bestOutcome
                    or (outcome == bestOutcome and score > bestScore)
                    or (outcome == bestOutcome and score == bestScore and heuristic > bestHeuristic) then
                    best, bestOutcome, bestScore, bestHeuristic = candidate, outcome, score, heuristic
                end
            end
        end
        Sim.breathe()
    end
    if not best or tried < 2 then
        return nil -- one simulated card is not a comparison
    end
    local result = bestOutcome >= 1 and "wins" or bestOutcome >= 0.5 and "draws" or "loses"
    local change = baseline and bestOutcome > baseline and " (turns the round around)"
        or baseline and bestOutcome < baseline and " (best of a losing round)" or ""
    return best, string.format("%s: simulated, %s next round%s", best.id, result, change), bestOutcome
end

return Upgrades

