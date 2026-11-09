-- What we have learned about the people we duel, kept between sessions.
--
-- The aim solver needs one number from the opponent: how likely they are to launch where they
-- launched last round. The hub used to assume 0.6, or 0.8 after two matching rounds, for everyone.
-- That is a reasonable guess and it is wrong for most individual players: an afk account is re-sent
-- its old aim by the server every round and never deviates, while someone actually playing re-aims
-- constantly. Measuring it per player and remembering it turns a constant into evidence.
--
-- Ball choices are recorded for the same reason. The pick phase simulates our offered balls against
-- what the opponent played last round, which is only a good assumption for someone who keeps
-- playing the same ball -- and now we know who does.
--
-- Nothing here is required. Without file access it is a memory-only model that starts fresh each
-- session, which is still better than a constant.

local Env = use("core/env")
local Life = use("shared/life")

local Profile = {}

local FOLDER = "DaewidHUB/BallVsBall"
local FILE = FOLDER .. "/opponents.json"
local SAVE_INTERVAL = 45
local MAX_ENTRIES = 400

-- The prior, as a count of imaginary rounds: a player seen once does not get a 0% or 100% model.
-- 3 of 5 kept starts everyone at the 0.6 the hub used to assume for all players.
local PRIOR_KEPT, PRIOR_SEEN = 3, 5

local players = {}
local dirty, savedAt = false, os.clock()

local function entry(userId)
    local key = tostring(userId)
    local found = players[key]
    if not found then
        found = { kept = 0, seen = 0, rounds = 0, won = 0, lost = 0, balls = {}, at = os.time() }
        players[key] = found
    end
    return found
end

-- Load ---------------------------------------------------------------------------------------

local function decode(body)
    if type(body) ~= "string" or body == "" then
        return nil
    end
    local ok, decoded = pcall(function()
        return Env.HttpService:JSONDecode(body)
    end)
    Env.elevate()
    return ok and type(decoded) == "table" and decoded or nil
end

-- A saved file is data we wrote, but it is still a file on disk that anything could have edited,
-- so every field is checked before it reaches the solver's weights.
local function sanitise(raw)
    local out = {}
    for key, value in pairs(type(raw) == "table" and raw or {}) do
        if type(key) == "string" and type(value) == "table" then
            local seen = tonumber(value.seen) or 0
            local kept = tonumber(value.kept) or 0
            if seen >= 0 and seen < math.huge and kept >= 0 and kept <= seen then
                local balls = {}
                for ball, count in pairs(type(value.balls) == "table" and value.balls or {}) do
                    local number = tonumber(count)
                    if type(ball) == "string" and number and number > 0 and number < math.huge then
                        balls[ball] = math.floor(number)
                    end
                end
                out[key] = {
                    kept = math.floor(kept),
                    seen = math.floor(seen),
                    rounds = math.max(0, math.floor(tonumber(value.rounds) or 0)),
                    won = math.max(0, math.floor(tonumber(value.won) or 0)),
                    lost = math.max(0, math.floor(tonumber(value.lost) or 0)),
                    balls = balls,
                    at = math.max(0, math.floor(tonumber(value.at) or 0)),
                }
            end
        end
    end
    return out
end

local files = Env.files
local canSave = files.writefile ~= nil and files.isfolder ~= nil and files.makefolder ~= nil

do
    local ok, body = pcall(function()
        return Env.canCache and files.isfile(FILE) and files.readfile(FILE)
    end)
    Env.elevate()
    players = ok and sanitise(decode(body)) or {}
end

-- Save ---------------------------------------------------------------------------------------

-- Oldest first, so a long-lived file keeps the people still being played against.
local function trim()
    local keys = {}
    for key in pairs(players) do
        keys[#keys + 1] = key
    end
    if #keys <= MAX_ENTRIES then
        return
    end
    table.sort(keys, function(a, b)
        return (players[a].at or 0) > (players[b].at or 0)
    end)
    for index = MAX_ENTRIES + 1, #keys do
        players[keys[index]] = nil
    end
end

local function write()
    if not canSave or not dirty then
        return
    end
    dirty, savedAt = false, os.clock()
    trim()
    local ok = pcall(function()
        local path = ""
        for part in FOLDER:gmatch("[^/]+") do
            path = path == "" and part or path .. "/" .. part
            if not files.isfolder(path) then
                files.makefolder(path)
            end
        end
        files.writefile(FILE, Env.HttpService:JSONEncode(players))
    end)
    Env.elevate()
    if not ok then
        canSave = false -- a filesystem that refuses once is not asked again every 45 seconds
    end
end

Life.loop("duel:profile-save", SAVE_INTERVAL, function()
    if dirty and os.clock() - savedAt >= SAVE_INTERVAL then
        write()
    end
end)

-- Record -------------------------------------------------------------------------------------

-- One round of one opponent. `kept` is whether they launched where we assumed (nil when there was
-- no previous round to compare against, which teaches us nothing either way).
function Profile.observe(userId, kept, roleId, won)
    if type(userId) ~= "number" then
        return
    end
    local found = entry(userId)
    found.rounds += 1
    found.at = os.time()
    if kept ~= nil then
        found.seen += 1
        found.kept += kept and 1 or 0
    end
    if type(roleId) == "string" then
        found.balls[roleId] = (found.balls[roleId] or 0) + 1
    end
    if won == true then
        found.lost += 1 -- we won, so they lost
    elseif won == false then
        found.won += 1
    end
    dirty = true
end

-- Read ---------------------------------------------------------------------------------------

-- How likely `userId` is to launch where they launched last round, as a probability the solver can
-- weight its first column by. Everyone starts at the old 0.6 assumption and moves from there.
function Profile.keepRate(userId)
    local found = players[tostring(userId)]
    local kept = (found and found.kept or 0) + PRIOR_KEPT
    local seen = (found and found.seen or 0) + PRIOR_SEEN
    return kept / seen
end

-- The whole table's keep rate, which is what a scenario weight actually needs: one opponent who
-- re-aims is enough to make the "everyone kept their aim" column unlikely.
function Profile.tableKeepRate(opponents)
    local rate = 1
    local counted = 0
    for _, player in ipairs(opponents) do
        if not player.me and not player.teammate then
            rate *= Profile.keepRate(player.userId)
            counted += 1
        end
    end
    return counted > 0 and rate or PRIOR_KEPT / PRIOR_SEEN
end

-- The ball `userId` plays most often, and how often, or nil when we have not seen them pick.
function Profile.likelyBall(userId)
    local found = players[tostring(userId)]
    if not found then
        return nil
    end
    local best, bestCount, total = nil, 0, 0
    for ball, count in pairs(found.balls) do
        total += count
        if count > bestCount then
            best, bestCount = ball, count
        end
    end
    if not best or total == 0 then
        return nil
    end
    return best, bestCount / total
end

-- The opponent's balls as weights that sum to 1, most-played first, up to `max` entries, or nil
-- when we have not seen them pick. Unlike likelyBall this keeps the spread, so a ball-switcher is
-- met with a hedge across their likely balls rather than a bet on one.
function Profile.ballDistribution(userId, max)
    local found = players[tostring(userId)]
    if not found then
        return nil
    end
    local list, total = {}, 0
    for ball, count in pairs(found.balls) do
        list[#list + 1] = { roleId = ball, count = count }
        total += count
    end
    if total == 0 then
        return nil
    end
    table.sort(list, function(a, b)
        return a.count > b.count
    end)
    local out = {}
    for index = 1, math.min(max or #list, #list) do
        out[index] = { roleId = list[index].roleId, weight = list[index].count / total }
    end
    return out
end

-- A line per opponent for the Intel tab. `name` is what to call them (their user id otherwise).
function Profile.describe(player, name)
    local found = players[tostring(player.userId)]
    local keep = math.floor(Profile.keepRate(player.userId) * 100 + 0.5)
    name = name or tostring(player.userId)
    if not found or found.rounds == 0 then
        return string.format("%s: new opponent, assuming %d%% aim repeat", name, keep)
    end
    local ball, share = Profile.likelyBall(player.userId)
    local favourite = ball and string.format(", favours %s (%d%%)", Env.ballName(ball),
        math.floor(share * 100 + 0.5)) or ""
    return string.format("%s: %d rounds, repeats aim %d%% (%d/%d), %d-%d against you%s",
        name, found.rounds, keep, found.kept, found.seen, found.won, found.lost, favourite)
end

function Profile.count()
    local total = 0
    for _ in pairs(players) do
        total += 1
    end
    return total
end

function Profile.forget()
    table.clear(players)
    dirty = true
    write()
end

Life.onCleanup(write)

return Profile

