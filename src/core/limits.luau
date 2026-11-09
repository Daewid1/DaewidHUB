-- How many duel coins are left today and this week. Duels pay nothing once either cap is reached
-- (the game's config: misc.coinsLimit, 6,000 a day and 30,000 a week at the time of writing).
-- The saved counters only count for the day/week key they were written under, the same way the
-- game's DuelCoinLimitService reads them.

local Env = use("core/env")

local Limits = {}

local function limitsConfig()
    local ok, limits = pcall(function()
        return Env.loadModule("Config").misc.coinsLimit
    end)
    return ok and type(limits) == "table" and limits or {}
end

-- { day, dayMax, week, weekMax, capped } (a max is nil when the game has no such cap).
-- The whole lookup is optional: a place without TimeService reports no progress rather than
-- throwing out of the panels and the duel loop that call this every half second.
function Limits.coins()
    local config = limitsConfig()
    local saved = Env.data("duelCoinLimit") or {}
    local dayMax, weekMax = config["每日金币上限"], config["每周金币上限"]
    local okDay, dayKey = Env.call(function()
        return Env.loadModule("TimeService").getDayKey(0, config["每日重置时间"])
    end)
    local okWeek, weekKey = Env.call(function()
        return Env.loadModule("TimeService").getWeekKey(0, config["每周重置时间"], config["每周重置日期"])
    end)
    local day = okDay and saved.dailyKey == dayKey and saved.dailyEarned or 0
    local week = okWeek and saved.weeklyKey == weekKey and saved.weeklyEarned or 0
    local capped = (type(dayMax) == "number" and day >= dayMax) or (type(weekMax) == "number" and week >= weekMax)
    return { day = day, dayMax = dayMax, week = week, weekMax = weekMax, capped = capped == true }
end

-- Halloween candy: every 3 HP or 2v2 match pays 1, won or lost, up to the event's daily cap (30),
-- and keeps paying after the coin cap. Saved per event as halloweenCandy[eventId] =
-- { balance, dayKey, dailyEarned }, where dailyEarned only counts for its own dayKey.
-- { active, eventId, balance, today, dayMax, capped, endsIn }; active is false outside the event.
function Limits.candy()
    local ok, event, now = Env.call(function()
        local now = Env.loadModule("TimeService").now()
        return Env.loadModule("HalloweenCandyRules").active(Env.loadModule("Config").event.list, now), now
    end)
    if not ok or type(event) ~= "table" or type(event.cnId) ~= "string" then
        return { active = false, balance = 0, today = 0, capped = true }
    end
    local dayMax = type(event.feature) == "table" and tonumber(event.feature["每日糖果上限"]) or nil
    local saved = Env.data("halloweenCandy")
    local mine = type(saved) == "table" and type(saved[event.cnId]) == "table" and saved[event.cnId] or {}
    local okDay, dayKey = Env.call(function()
        return Env.loadModule("TimeService").getDayKeyAt(now, 0)
    end)
    local today = okDay and mine.dayKey == dayKey and tonumber(mine.dailyEarned) or 0
    local okLeft, left = Env.call(Env.loadModule("HalloweenCandyRules").remainingSeconds, event, now)
    return {
        active = true,
        eventId = event.cnId,
        balance = tonumber(mine.balance) or 0,
        today = today,
        dayMax = dayMax,
        capped = dayMax ~= nil and today >= dayMax,
        endsIn = okLeft and tonumber(left) or nil,
    }
end

return Limits

