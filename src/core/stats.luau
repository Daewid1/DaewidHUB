-- Every ball's win rate across all players, from the game's own BallBattleStats (the numbers its
-- Ball Index shows): overall, and head to head against each other ball.

local Env = use("core/env")
local Life = use("shared/life")

local Stats = {}

local REFRESH = 600 -- seconds; the server rate-limits the call
local MIN_MATCHUP_GAMES = 500 -- fewer head-to-head games than this and the overall rate is used

local raw, fetchedAt = nil, -math.huge
local fetching = false

local function all()
    if not fetching and os.clock() - fetchedAt > REFRESH then
        fetching, fetchedAt = true, os.clock()
        Life.spawn("duel:statistics", function()
            local moduleOk = Env.call(Env.loadModule, "StatsCore")
            local ok, result = Env.invoke("BallBattleStats/GetAll")
            if Life.alive and moduleOk and ok and type(result) == "table" then
                raw = type(result.data) == "table" and result.data or result
            else
                fetchedAt = os.clock() - REFRESH + 30
            end
            fetching = false
        end)
    end
    return raw
end

-- Refresh off the picking path: a slow statistics service must not use the pick timer.
all()

-- A ball's overall win rate (0..1), or nil when the game has no numbers for it.
function Stats.winRate(ball)
    local entry = (all() or {})[ball]
    if type(entry) ~= "table" then
        return nil
    end
    local core = rawget(Env.Game, "StatsCore")
    if not core then return nil end
    local ok, summary = Env.call(core.summarize, entry)
    return ok and summary and summary.winRate or nil
end

-- How often `ball` beats `versus`, falling back to its overall rate on too few games.
function Stats.against(ball, versus)
    local entry = (all() or {})[ball]
    local record = versus and type(entry) == "table" and type(entry.opponents) == "table" and entry.opponents[versus]
    if type(record) == "table" then
        local games = (record.wins or 0) + (record.losses or 0) + (record.draws or 0)
        if games >= MIN_MATCHUP_GAMES then
            return (record.wins + 0.5 * (record.draws or 0)) / games
        end
    end
    return Stats.winRate(ball)
end

return Stats

