-- What the server tells us about our table: its state, the ball and upgrade offers, and the
-- replays of this match.
--
-- A match is rounds of Picking (30s to choose one of 3 offered balls), Aiming (30s to set the
-- launch direction) and Playing (the server simulates the battle and streams a replay). Each
-- player has 3 hp and a lost round costs 1. Battles are deterministic: the replay's seed, balls and
-- directions reproduce the result exactly (see core/sim), and round r's seed is round 1's seed
-- plus (r - 1) * 1009. So once round 1 has been replayed, every later round's seed is known while
-- we still choose.

local Env = use("core/env")
local Life = use("shared/life")

local SEED_STEP = 1009

local Match = {
    tableModel = nil,
    tableId = nil,
    state = nil, -- the latest DuelTableState of our table
    slot = nil, -- our key in state.players ("Blue", "Yellow", "Blue1"...)
    left = false, -- a state showed our table, or every table, without us
    offer = nil, -- the latest ball offer: { offer = {roleIds}, selectPrice, rerollPrice, at }
    selectList = nil, -- the free pick's list: { roleIds, at }
    weeklyFreeRoleIds = {}, -- server-provided weekly choices for this match; never infer owned items
    upgradeOffer = nil, -- { offer = { { kind, id } }, at }
    ballLocked = nil, -- { roleId, at }
    aimToken = nil, -- a new table each time Aiming starts
    aimStartedAt = 0, -- os.clock() when it did
    aimLocked = nil, -- { direction, at }
    teammateAim = nil, -- 2v2: { userId, direction, at } as the teammate drags their aim
    liveAims = {}, -- per-userId { direction, at } from any aim-preview relay seen this round
    replays = {}, -- this match's replays by round
    lastReplay = nil,
    capped = false, -- the server said today's duel coins are used up
    queueRefusal = nil, -- { reason, at } when Quick Play last said no
    status = nil, -- what auto duel is doing (set by features/duel, shown on Home)
    prediction = nil, -- the solver's reasoning for the round in play (set by features/duel)
    history = nil, -- recent rounds and whether their predictions held (set by features/duel)
    session = nil, -- this session's match, round and coin tally (set by features/duel)
}

local listeners = {}

function Match.phase()
    return Match.state and Match.state.state or nil
end

-- Bind independently so one missing optional event cannot prevent all match tracking. The
-- connector retries after replication and disconnects a replaced remote before rebinding.
--
-- Exported because binding a remote at module load means a renamed or absent one errors out of
-- the whole feature on the way up: a hub that loses the coin tally should not also lose auto duel.
function Match.listen(name, fn, unreliable)
    local current, connection
    Life.loop("remote:" .. name, 5, function()
        if connection and connection.Connected and current and current.Parent then return end
        if connection then connection:Disconnect() end
        current = unreliable and Env.unreliable(name) or Env.event(name)
        connection = Life.connect(current.OnClientEvent, fn, "match:" .. name)
    end)
end
local listen = Match.listen

-- fn(replay, won) after each replay of our table. `won` is true, false, or nil for a draw.
function Match.onRound(fn)
    listeners[#listeners + 1] = fn
end

local function hasMe(state)
    local players = type(state) == "table" and state.players
    if type(players) ~= "table" then
        return nil
    end
    for slot, player in pairs(players) do
        if type(player) == "table" and player.userId == Env.LocalPlayer.UserId then
            return slot
        end
    end
    return nil
end

local function newMatch()
    table.clear(Match.replays)
    table.clear(Match.weeklyFreeRoleIds)
    Match.lastReplay = nil
    Match.offer, Match.selectList, Match.upgradeOffer = nil, nil, nil
    Match.ballLocked, Match.aimLocked = nil, nil
    Match.aimToken, Match.teammateAim = nil, nil
    table.clear(Match.liveAims)
end

local function applyState(state)
    local slot = hasMe(state)
    if not slot then
        return false
    end
    if state.tableId ~= Match.tableId or (state.state == "Countdown" and Match.phase() ~= "Countdown") then
        newMatch()
    end
    -- A fresh token each time the table enters Aiming, so each round is aimed once.
    if state.state == "Aiming" and (Match.phase() ~= "Aiming" or Match.aimToken == nil) then
        Match.aimToken, Match.aimLocked, Match.teammateAim = {}, nil, nil
        Match.aimStartedAt = os.clock()
        table.clear(Match.liveAims)
    end
    Match.tableId = state.tableId
    if typeof(state.table) == "Instance" then
        Match.tableModel = state.table
    end
    Match.state, Match.slot, Match.left = state, slot, false
    return true
end

-- The server only sends states when a table changes, so there can be long quiet stretches (a
-- whole battle): being seated is decided by what the states say, never by how long ago one came.
listen("DuelTableState", function(payload)
    if type(payload) ~= "table" then
        return
    end
    if payload.table then
        if not applyState(payload) and payload.tableId == Match.tableId then
            Match.left = true
        end
        return
    end
    if type(payload.tables) ~= "table" then
        return
    end
    local found = false
    for _, state in pairs(payload.tables) do
        found = applyState(state) or found
    end
    -- A full snapshot (every table) without us: we are not at any table.
    if not found and Match.state then
        Match.left = true
    end
end)

-- Offers and locks are only sent to the players at the table, so they are ours.
local function stamp(payload)
    local copy = table.clone(type(payload) == "table" and payload or {})
    copy.at = os.clock()
    copy.revision = 0
    return copy
end

local function updateWeeklyFree(payload)
    if type(payload) ~= "table" or type(payload.weeklyFreeRoleIds) ~= "table" then
        return
    end
    table.clear(Match.weeklyFreeRoleIds)
    for _, id in ipairs(payload.weeklyFreeRoleIds) do
        if type(id) == "string" then
            Match.weeklyFreeRoleIds[id] = true
        end
    end
end

function Match.isWeeklyFree(roleId)
    return Match.weeklyFreeRoleIds[roleId] == true
end

listen("DuelTableBallOffer", function(model, payload)
    if typeof(model) ~= "Instance" or type(payload) ~= "table" then return end
    -- The first offer of a match is not a reselect: whatever we saw before belongs to another match
    -- (even at the same table), and its seed must not be used.
    if type(payload) == "table" and not payload.isReselect then
        newMatch()
    end
    Match.tableModel = model
    Match.offer, Match.selectList, Match.ballLocked = stamp(payload), nil, nil
    updateWeeklyFree(payload)
end)
-- Keep the offer's identity and original deadline. A reroll is a revision of that offer,
-- not another picking window. Failed replies also release the response wait.
local function rerolled(model, payload, offer)
    if not Life.alive or model ~= Match.tableModel or type(payload) ~= "table" or not offer then
        return
    end
    offer.rerollReplyAt = os.clock()
    offer.rerollPending = false
    offer.rerollError = payload.reason
    if payload.ok ~= false and type(payload.offer) == "table" then
        offer.offer = payload.offer
        offer.revision += 1
        updateWeeklyFree(payload)
    end
    for _, key in ipairs({ "rerollPrice", "rerollCurrency", "canReroll", "rerollsRemaining", "freeRerolls" }) do
        if payload[key] ~= nil then
            offer[key] = payload[key]
        end
    end
end
listen("DuelTableBallRerollResult", function(model, payload)
    if Match.phase() == "Picking" and not Match.ballLocked then
        rerolled(model, payload, Match.offer)
    end
end)
listen("DuelTableUpgradeRerollResult", function(model, payload)
    if Match.phase() == "Upgrading" then
        rerolled(model, payload, Match.upgradeOffer)
    end
end)
listen("DuelTableRerollDenied", function(model, reason)
    local offer = Match.phase() == "Picking" and Match.offer or Match.upgradeOffer
    rerolled(model, { ok = false, reason = reason }, offer)
end)
listen("DuelTableBallSelectPurchaseResult", function(model, payload)
    if model == Match.tableModel and type(payload) == "table" and payload.ok ~= false
        and type(payload.roleIds) == "table" and Match.phase() == "Picking" and not Match.ballLocked then
        Match.selectList = stamp(payload)
        if Match.offer then
            Match.offer.selectPending = false
            Match.offer.selectError = nil
        end
        updateWeeklyFree(payload)
    end
end)
listen("DuelTableBallSelectDenied", function(model, reason)
    if model == Match.tableModel and Match.offer then
        Match.offer.selectPending = false
        Match.offer.selectError = reason or "unavailable"
    end
end)
listen("DuelTableBallSelectConfirmDenied", function(model, reason, price)
    if model == Match.tableModel and Match.offer then
        Match.offer.selectConfirmError = reason or "refused"
        if type(price) == "number" then
            Match.offer.selectPrice = price
        end
    end
end)
listen("DuelTableBallLocked", function(model, payload)
    if model == Match.tableModel then
        Match.ballLocked = stamp(payload)
    end
end)
listen("DuelTableBallSelectConfirmed", function(model, payload)
    if model == Match.tableModel then
        Match.ballLocked = stamp(payload)
    end
end)
listen("DuelTableUpgradeOffer", function(model, payload)
    Match.tableModel = model
    Match.upgradeOffer = stamp(payload)
end)
listen("DuelTableUpgradeLocked", function(model)
    if model == Match.tableModel then
        Match.upgradeOffer = nil
    end
end)
listen("DuelTableLaunchLocked", function(model, payload)
    if model == Match.tableModel then Match.aimLocked = stamp(payload) end
end)
-- In 2v2 the server relays the teammate's aim while they drag it: (table, their userId, direction).
listen("DuelTableAimPreview", function(model, userId, direction)
    if model == Match.tableModel and typeof(direction) == "Vector2" then
        Match.teammateAim = { userId = userId, direction = direction, at = os.clock() }
        if type(userId) == "number" then
            Match.liveAims[userId] = { direction = direction, at = os.clock() }
        end
    end
end, true)
listen("DuelCoinLimitReached", function()
    Match.capped = true
end)
-- Quick Play's answer: (false, "noAvailableTable") when this server has no free seat. The game
-- then offers to move you to another server; auto duel only reports it.
listen("DuelQuickPlayResult", function(ok, reason)
    Match.queueRefusal = ok == false and { reason = tostring(reason or "refused"), at = os.clock() } or nil
end)

listen("DuelTableReplayStream", function(replay)
    if type(replay) ~= "table" or replay.tableId ~= Match.tableId or type(replay.round) ~= "number" then
        return
    end
    Match.replays[replay.round] = replay
    Match.lastReplay = replay
    local me = Env.LocalPlayer.UserId
    local won = nil
    if replay.isDraw ~= true then
        won = table.find(type(replay.winnerUserIds) == "table" and replay.winnerUserIds or {}, me) ~= nil
            or replay.winnerUserId == me
    end
    for index, fn in ipairs(listeners) do
        Life.spawn("match:round:" .. index, fn, replay, won)
    end
end)

local function canReroll(offer, allowDiamonds)
    if not offer or offer.rerollTried or offer.rerollPending or offer.canReroll == false
        or (type(offer.rerollsRemaining) == "number" and offer.rerollsRemaining <= 0) then
        return false
    end
    if type(offer.freeRerolls) == "number" and offer.freeRerolls > 0 then
        return true
    end
    -- The shipped client hides a zero-price reroll; only explicit metadata enables a free one.
    local price = offer.rerollPrice
    if price == 0 then
        return offer.canReroll == true
    end
    -- DuelChoice handles an insufficient reroll by opening DiamondTopUpService. Rerolls
    -- without currency metadata are priced in diamonds, so coins cannot fund them.
    local currency = offer.rerollCurrency or "diamonds"
    if currency == "diamonds" and not allowDiamonds then
        return false
    end
    return (currency == "coins" or currency == "diamonds") and type(price) == "number" and price > 0
        and (tonumber(Env.data(currency)) or 0) >= price
end

function Match.canRerollBall(allowDiamonds)
    return Match.seated() and Match.phase() == "Picking" and not Match.ballLocked and canReroll(Match.offer, allowDiamonds)
end

function Match.canRerollUpgrade(allowDiamonds)
    return Match.seated() and Match.phase() == "Upgrading" and canReroll(Match.upgradeOffer, allowDiamonds)
end

-- True while we sit at a table whose match is not over.
function Match.seated()
    return Match.state ~= nil and not Match.left and Match.phase() ~= "Finished"
end

function Match.teamSize()
    return Match.state and Match.state.teamSize or 1
end

-- Everyone at our table: { { userId, team, index, roleId, me, teammate } }, from the latest state.
-- roleId is only there once balls are locked (Aiming on). `index` is the seat within the team
-- (always 1 in a 1v1).
function Match.players()
    local out = {}
    local players = Match.state and Match.state.players
    local mine = players and players[Match.slot]
    for slot, player in pairs(type(players) == "table" and players or {}) do
        if type(player) == "table" then
            local team = player.team or slot
            out[#out + 1] = {
                userId = player.userId,
                team = team,
                index = player.teamIndex or 1,
                roleId = player.roleId,
                me = slot == Match.slot,
                teammate = slot ~= Match.slot and mine ~= nil and team == (mine.team or Match.slot),
            }
        end
    end
    return out
end

-- Our team's name ("Blue" or "Yellow"): what the simulation reports as the winner.
function Match.team()
    local players = Match.state and Match.state.players
    local mine = players and players[Match.slot]
    return mine and mine.team or Match.slot
end

function Match.hp(player)
    local state = Match.state
    if not (state and type(state.hp) == "table" and player) then
        return nil
    end
    return state.hp[player.userId] or state.hp[tostring(player.userId)]
end

-- The round being chosen or aimed right now (1 before this match's first replay).
function Match.round()
    local replay = Match.lastReplay
    if not replay or type(replay.round) ~= "number" then
        return 1
    end
    local phase = Match.phase()
    local playing = phase == "Playing" or phase == "Finished"
    return replay.round + (playing and 0 or 1)
end

-- Our hp and the lowest hp on the other team, which is what decides whether a round is worth a
-- risk: a loss at 1 hp ends the match, and so does a win against someone on their last one.
function Match.stakes()
    local ours, theirs
    for _, player in ipairs(Match.players()) do
        local hp = tonumber(Match.hp(player))
        if hp then
            if player.me then
                ours = hp
            elseif not player.teammate then
                theirs = math.min(theirs or math.huge, hp)
            end
        end
    end
    return ours, theirs
end

-- The seed of the round being chosen now, or nil before this match's first replay.
function Match.nextSeed()
    local replay = Match.lastReplay
    if not replay or type(replay.seed) ~= "number" then
        return nil
    end
    return replay.seed + SEED_STEP
end

-- A replay keeps balls and directions by team: one value in a 1v1, a list by seat in team modes.
function Match.forPlayer(byTeam, team, index)
    local value = type(byTeam) == "table" and byTeam[team]
    if type(value) == "table" then
        return value[index]
    end
    return value
end

-- The ball and direction `player` (from Match.players) used last round, or nil.
function Match.lastPlay(player)
    local options = Match.lastReplay and Match.lastReplay.replayOptions
    if not options then
        return nil, nil
    end
    return Match.forPlayer(options.selectedRoles, player.team, player.index),
        Match.forPlayer(options.initialDirections, player.team, player.index)
end

-- Whether `player` launched in the same direction in this match's last two rounds: true or false,
-- or nil with fewer than two rounds played. Someone who re-aims is not worth predicting.
function Match.keepsAim(player)
    local last = Match.lastReplay
    local before = last and Match.replays[last.round - 1]
    if not before then
        return nil
    end
    local a = Match.forPlayer((last.replayOptions or {}).initialDirections, player.team, player.index)
    local b = Match.forPlayer((before.replayOptions or {}).initialDirections, player.team, player.index)
    return typeof(a) == "Vector2" and typeof(b) == "Vector2" and (a - b).Magnitude < 1e-3
end

-- A direction relayed for `userId` this round, if fresher than `maxAge` seconds. The server relays
-- a teammate's drag; this reads the same store for anyone, so an opponent direction is used the
-- moment the server ever leaks one, and costs nothing while it never does.
function Match.liveAim(userId, maxAge)
    local found = Match.liveAims[userId]
    if found and typeof(found.direction) == "Vector2" and (not maxAge or os.clock() - found.at <= maxAge) then
        return found.direction
    end
    return nil
end

-- The arena the round is fought in: nil for the 1v1 board, the 2v2 board's layout otherwise.
function Match.arena()
    local options = Match.lastReplay and Match.lastReplay.replayOptions
    if options then
        return options.arena
    end
    if Match.teamSize() > 1 and Match.tableModel then
        local ok, arena = Env.call(function()
            return Env.loadModule("ArenaOverride").buildArenaData(Env.loadModule("GameModeRegistry").getForTable(Match.tableModel))
        end)
        return ok and arena or nil
    end
    return nil
end

function Match.excitementSelection()
    local ok, result = Env.call(function()
        local config = Env.loadModule("BattleConfig")
        local replay = config and config.replay
        if not replay then return nil end
        return {
            enabled = replay.enableExcitementSelection == true,
            candidates = type(replay.candidateCount) == "number" and replay.candidateCount or 1,
        }
    end)
    return ok and result or nil
end

Life.onCleanup(function()
    newMatch()
    table.clear(listeners)
    Match.tableModel, Match.tableId, Match.state, Match.slot = nil, nil, nil, nil
    Match.left, Match.status = true, "Off"
    Match.prediction, Match.history, Match.session = nil, nil, nil
end)

return Match

