-- Duel tab: queue with Quick Play, pick the ball, aim, and queue again.
--
-- Picks: inventory choices use the free pick, then a pick voucher or diamonds when enabled.
-- DuelTableBallSelectPurchase lists eligible choices; DuelTableBallSelfSelect confirms one. "Smart"
-- simulates each offered ball against what everyone else played last round once the round's seed is
-- known (round 2 on, see core/match); otherwise, and in round 1, balls go by their win rate across
-- all players.
--
-- Aim: the launch direction decides the battle. Smart aim runs the game's own simulation for each
-- direction and locks the one that wins most. From round 2 the seed is exact and most players keep
-- the same direction every round, so the prediction is usually right; in round 1 it can only pick
-- the direction that wins most often over random seeds. 2v2 works the same way with four balls: the
-- replays key balls and directions by team and seat, the 2v2 board has its own arena, and the
-- server relays the teammate's aim while they drag it.

local Env = use("core/env")
local Life = use("shared/life")
local Ui = use("core/ui")
local Match = use("core/match")
local Sim = use("core/sim")
local Solver = use("core/solver")
local Profile = use("core/profile")
local Stats = use("core/stats")
local Limits = use("core/limits")
local Upgrades = use("core/upgrades")
local Trajectory = use("core/trajectory")

local Options = Ui.Options

local QUEUE_INTERVAL = 6 -- seconds between Quick Play requests while unseated
local PICK_WINDOW = 30 -- seconds the game gives to pick (and to aim)
local PICK_MARGIN = 4 -- answer this long before the game picks for us
local FREE_LIST_WAIT = 4
local LOCK_WAIT = 3
local PICK_DIRECTIONS = 12 -- directions tried per ball when picking by simulation
local AIM_DIRECTIONS = 36
local OPPONENT_SWEEP = 10 -- opponent launch directions the guaranteed floor is measured over
local REROLL_WAIT, REROLL_COOLDOWN = 3, 5
-- Round 1 has no seed, so there is no grid to solve: every scenario is a guessed seed and the
-- opponent's aim can only be averaged over. More think time buys more guesses.
local ROUND_ONE_SAMPLES, ROUND_ONE_MAX = 6, 14
-- 2v2: think once the teammate's aim has stopped moving this long (or when time runs short).
local TEAMMATE_SETTLE = 2
-- 2v2 Smart picks wait up to this long into the pick timer for the teammate to lock their ball,
-- leaving at least PICK_THINK_RESERVE seconds to simulate.
local TEAMMATE_PICK_WAIT, PICK_THINK_RESERVE = 12, 8

local MODES = { "1v1 (3 HP)", "2v2" }
-- Since the October 16 update each mode has its own servers (Env.serverType) and Quick Play seats
-- you at whatever tables this server has, so the mode decides the server, not the request.
local SERVER_FOR_MODE = { ["1v1 (3 HP)"] = "standard", ["2v2"] = "twoVTwoServer" }
local SERVER_NAME = { standard = "1v1", twoVTwoServer = "2v2", tradeServer = "trading" }
local STRATEGIES = { "Smart", "Best win rate", "First offered", "Selected inventory ball" }

-- Ball names for the "Never pick" list.
local ballNames = {}
for _, ball in ipairs(Env.loadModule("Config").ball.list) do
    if ball.canPlayerUse then
        ballNames[#ballNames + 1] = ball.displayName
    end
end
table.sort(ballNames)

local tab = Ui.Tabs.Duel
local auto = tab:AddGroupbox({ Side = "Left", Name = "Auto duel", IconName = "swords" })
auto:AddToggle("AutoDuel", {
    Text = "Auto duel",
    Default = false,
    Tooltip = "Queues with Quick Play, picks your ball, aims, and queues again after each match.",
})
Ui.automation("AutoDuel")
auto:AddDropdown("DuelMode", {
    Text = "Mode", Values = MODES, Default = MODES[1],
    Tooltip = "Each mode has its own servers now. On the wrong kind, auto duel waits: use Switch server below or the game's mode button.",
})
auto:AddToggle("StopAtCoinCap", {
    Text = "Stop at the coin cap",
    Default = true,
    Tooltip = "Duels pay nothing past the daily (and weekly) coin cap. Stops after the match in progress.",
})
auto:AddToggle("DuelForCandy", {
    Text = "Keep going for Halloween candy",
    Default = true,
    Tooltip = "During the Halloween event every match still pays 1 candy past the coin cap, up to 30 a day. Stops at whichever cap comes last.",
})
auto:AddButton({
    Text = "Switch server for this mode",
    Func = function()
        local wanted = SERVER_FOR_MODE[Options.DuelMode.Value]
        if not wanted then return end
        if Env.serverType() == wanted then
            Ui.notify("Auto duel", "You are already on a " .. SERVER_NAME[wanted] .. " server.", 5)
            return
        end
        -- The same request as the game's mode button; the server teleports you.
        Env.event("ModeTeleportRequest"):FireServer(wanted)
        Ui.notify("Auto duel", "Moving to a " .. SERVER_NAME[wanted] .. " server. Run the script again there if it does not load by itself.", 8)
    end,
    Tooltip = "Teleports you to a server for the selected mode, as the game's own mode button does.",
})
auto:AddButton({
    Text = "Leave the table",
    Func = function()
        Env.event("DuelTableLeaveRequest"):FireServer()
    end,
    Tooltip = "Mid-match this forfeits.",
})

local picks = tab:AddGroupbox({ Side = "Left", Name = "Ball picks", IconName = "circle-dot" })
picks:AddDropdown("PickStrategy", {
    Text = "Pick by",
    Values = STRATEGIES,
    Default = STRATEGIES[1],
    Tooltip = "Smart simulates each offered ball against the opponent's last ball once the seed is known, and uses win rates before that.",
})
picks:AddToggle("FreePick", {
    Text = "Use the free pick",
    Default = true,
    Tooltip = "Takes the best server-approved free choice, including owned balls and weekly free balls you have unlocked.",
})
local NO_INVENTORY_BALL = "Choose an inventory ball"
local inventoryByLabel, inventorySignature = {}, nil
local function inventoryChoices()
    local items = Env.data("items")
    if type(items) ~= "table" then
        return nil
    end
    local labels, ids, seen = { NO_INVENTORY_BALL }, {}, {}
    for _, item in pairs(items) do
        if type(item) == "table" and item.itemType == "Ball" and type(item.itemId) == "string"
            and (item.ownerUserId == nil or item.ownerUserId == Env.LocalPlayer.UserId) and not seen[item.itemId] then
            local definition = Env.loadModule("Config").ball.byCnId[item.itemId]
            if definition and definition.canPlayerUse ~= false then
                seen[item.itemId] = true
                local label = Env.ballName(item.itemId) .. " [" .. item.itemId .. "]"
                ids[label] = item.itemId
                labels[#labels + 1] = label
            end
        end
    end
    table.sort(labels, function(a, b)
        if a == NO_INVENTORY_BALL then return b ~= NO_INVENTORY_BALL end
        if b == NO_INVENTORY_BALL then return false end
        return a < b
    end)
    return labels, ids
end
local initialInventory, initialIds = inventoryChoices()
inventoryByLabel = initialIds or {}
picks:AddDropdown("InventoryBall", {
    Text = "Inventory ball", Values = initialInventory or { NO_INVENTORY_BALL },
    Default = NO_INVENTORY_BALL, Searchable = true,
    Tooltip = "Set Pick by to Selected inventory ball to use this ball whenever the game allows it. The list follows your inventory.",
})
picks:AddToggle("PaidInventoryPick", {
    Text = "Allow paid inventory picks", Default = false,
    Tooltip = "After the free pick, allows the game's normal cost: a pick voucher first, otherwise your existing diamonds. Applies to every picking round while Auto duel is on.",
})
local inventoryCostLabel = picks:AddLabel("Inventory picks: waiting for a ball offer.", true)
local function selectedInventoryBall()
    if Options.PickStrategy.Value == "Selected inventory ball" then
        return inventoryByLabel[Options.InventoryBall.Value]
    end
end
local function inventoryPickAvailable(offer)
    local price = offer and offer.selectPrice
    if type(price) ~= "number" or price < 0 or price ~= price or price == math.huge then
        return false, "Inventory selection is unavailable."
    end
    if price == 0 then
        return true, "Inventory pick: free."
    end
    local vouchers = Env.data("vouchers")
    local count = type(vouchers) == "table" and tonumber(vouchers["指定卡"]) or 0
    if (count or 0) >= 1 then
        return Ui.on("PaidInventoryPick"), "Inventory pick: 1 pick voucher" .. (Ui.on("PaidInventoryPick") and "." or " (paid picks off).")
    end
    local enough = (tonumber(Env.data("diamonds")) or 0) >= price
    local suffix = not Ui.on("PaidInventoryPick") and " (paid picks off)." or not enough and " (not enough diamonds)." or "."
    return Ui.on("PaidInventoryPick") and enough, string.format("Inventory pick: %s diamonds%s", tostring(price), suffix)
end
Life.loop("duel:inventory", 3, function()
    local labels, ids = inventoryChoices()
    if labels then
        local signature = table.concat(labels, "\0")
        inventoryByLabel = ids
        if signature ~= inventorySignature then
            inventorySignature = signature
            Env.elevate()
            Options.InventoryBall:SetValues(labels)
        end
    end
    if not Life.alive then return end
    Env.elevate()
    if Match.seated() and Match.phase() == "Picking" and not Match.ballLocked then
        local _, text = inventoryPickAvailable(Match.offer)
        Env.elevate()
        inventoryCostLabel:SetText(text)
    else
        inventoryCostLabel:SetText("Inventory picks: available while choosing a ball.")
    end
end)
picks:AddDropdown("NeverPick", {
    Text = "Never pick",
    Values = ballNames,
    Multi = true,
    Searchable = true,
    Default = {},
})
picks:AddToggle("RerollBadOffers", {
    Text = "Reroll bad offers", Default = true,
    Tooltip = "Rerolls once when every offered ball is excluded or below the threshold. Diamond rerolls require the separate option below.",
})
picks:AddToggle("UseOwnedDiamondsForRerolls", {
    Text = "Use owned diamonds for rerolls", Default = false,
    Tooltip = "Allows ball and upgrade rerolls only when your existing diamonds cover the price. Off by default to avoid the game's Robux top-up prompt.",
})
picks:AddSlider("RerollThreshold", {
    Text = "Reroll below", Default = 50, Min = 30, Max = 70, Rounding = 0, Suffix = "%",
    Tooltip = "Rerolls when every offered ball's win rate across all players is below this. Higher holds out for strong balls but spends more rerolls.",
})
picks:AddSlider("PickDelay", {
    Text = "Pick after",
    Default = 2,
    Min = 0,
    Max = 20,
    Rounding = 0,
    Suffix = "s",
    Tooltip = "Waits this long before picking. The pick always goes in before the game's timer ends.",
})

local aimBox = tab:AddGroupbox({ Side = "Right", Name = "Aim", IconName = "crosshair" })
aimBox:AddToggle("SmartAim", {
    Text = "Smart aim",
    Default = true,
    Tooltip = "Simulates the round for each launch direction with the game's own battle code and locks the best. Also aims for you when you play yourself.",
})
aimBox:AddToggle("AimTrajectory", {
    Text = "Show aim prediction", Default = true,
    Callback = function(value)
        if not value then
            Trajectory.clear()
        end
    end,
})
aimBox:AddDropdown("AimStyle", {
    Text = "Play style",
    Values = { "Balanced", "Exploit", "Safe" },
    Default = "Balanced",
    Tooltip = "Exploit answers the aim this opponent is expected to use. Safe takes the direction with the best worst case, so a surprise aim cannot blow the round out. Balanced weighs both, and all three lean safer at 1 hp and bolder when the opponent is on their last.",
})
aimBox:AddSlider("AimThinkTime", {
    Text = "Think time",
    Default = 10,
    Min = 3,
    Max = 22,
    Rounding = 0,
    Suffix = "s",
    Tooltip = "Longer tries more of the opponent's possible aims. Each simulation stalls the game for a moment.",
})
aimBox:AddLabel("From round 2 the seed is exact and every ball is locked, so the round is solved as a grid: your directions against theirs. You get the aim that beats the opponent you expect and the one that cannot be punished, and the Intel tab shows which is which.", true)
aimBox:AddToggle("SeedResilience", {
    Text = "Seed resilience",
    Default = false,
    Tooltip = "When the game uses excitement selection (BestOfN seeds) or recent seed predictions have failed, falls back to multi-seed sampling instead of trusting one exact seed. Enable when Intel shows seed accuracy dropping.",
})

local matchBox = tab:AddGroupbox({ Side = "Right", Name = "Match", IconName = "activity" })
local panel = Ui.panel(matchBox, 6)
local upgrades = tab:AddGroupbox({ Side = "Left", Name = "Upgrades", IconName = "sparkles" })
upgrades:AddToggle("RerollLowUpgrades", {
    Text = "Reroll one-star offers", Default = true,
    Tooltip = "Rerolls once if every card is one star. Diamond rerolls also require Use owned diamonds for rerolls under Ball picks.",
})
upgrades:AddToggle("SimulateUpgrades", {
    Text = "Simulate upgrade cards", Default = true,
    Tooltip = "A card is an entry in the stat and trait tables the battle simulation reads, so each one can be played out instead of guessed at. Needs a known seed; before that, and whenever the card tables are not in a shape it recognises, the star rating decides.",
})
local upgradeLabel = upgrades:AddLabel("Cards score 10 per star, +15 for a matching ball trait, or +3 for defense, shield and health.", true)

-- Session tally --------------------------------------------------------------------------------

local session = { rounds = { won = 0, lost = 0, draw = 0 }, matches = { won = 0, lost = 0 }, coins = 0 }
Match.status = "Off"
local prediction = nil -- { text, ... } for the round being played
-- The last rounds, newest last, for checking predictions: what was assumed and what happened.
local history = {}
local HISTORY_SIZE = 30
-- Published on Match, the way `status` already is, so features/intel can report on the solver
-- without a feature having to use() another feature (and rebuild its tab if that one failed).
Match.history, Match.session = history, session

local function directionsMatch(a, b)
    return typeof(a) == "Vector2" and typeof(b) == "Vector2" and (a - b).Magnitude < 1e-3
end

local function otherTeam(team)
    return team == "Blue" and "Yellow" or "Blue"
end

-- Balls or directions for everyone at the table, keyed by team the way the simulation and the
-- replays have them: one value per team in a 1v1, a list by seat in a 2v2.
local function byTeam(players, valueOf)
    local out = {}
    local teamMode = Match.teamSize() > 1
    for _, player in ipairs(players) do
        if teamMode then
            out[player.team] = out[player.team] or {}
            out[player.team][player.index] = valueOf(player)
        else
            out[player.team] = valueOf(player)
        end
    end
    return out
end

-- "Ray Ball + Spider Ball" for a team's entry in a replay's selectedRoles.
local function teamBalls(roles, team)
    local value = type(roles) == "table" and roles[team]
    if type(value) ~= "table" then
        return Env.ballName(value)
    end
    local names = {}
    for _, role in ipairs(value) do
        names[#names + 1] = Env.ballName(role)
    end
    return table.concat(names, " + ")
end

Match.onRound(function(replay, won)
    local rounds = session.rounds
    if won == nil then
        rounds.draw += 1
    elseif won then
        rounds.won += 1
    else
        rounds.lost += 1
    end
    if prediction then
        prediction.result = won
    end
    local options = replay.replayOptions or {}
    local team = Match.team()
    local entry = {
        round = replay.round,
        won = won,
        balls = string.format("%s vs %s", teamBalls(options.selectedRoles, team), teamBalls(options.selectedRoles, otherTeam(team))),
    }
    if prediction and prediction.seed then
        -- Was the seed right, and did everyone else aim where we assumed?
        entry.seedRight = prediction.seed == replay.seed
        local kept, opponents, opponentsKept = true, 0, 0
        for _, player in ipairs(Match.players()) do
            local assumed = prediction.assumed[player.userId]
            local same = assumed ~= nil
                and directionsMatch(assumed, Match.forPlayer(options.initialDirections, player.team, player.index))
            if assumed and not same then
                kept = false
            end
            if player.teammate then
                entry.teammateKeptAim = same
            elseif not player.me then
                opponents += 1
                opponentsKept += same and 1 or 0
            end
        end
        entry.othersKeptAim = kept
        entry.opponentsKeptAim = string.format("%d/%d", opponentsKept, opponents)
        entry.opponentsKept, entry.opponents = opponentsKept, opponents
        entry.predicted = prediction.predicted
        entry.expected, entry.worst = prediction.expected, prediction.worst
    end
    -- Learn from the round regardless of whether we predicted it. keepsAim compares the replay
    -- that just landed against the one before it, which is exactly "did they launch there again",
    -- and is nil in round 1 where there is nothing to compare and nothing to learn.
    for _, player in ipairs(Match.players()) do
        if not player.me then
            Profile.observe(player.userId, Match.keepsAim(player),
                Match.forPlayer(options.selectedRoles, player.team, player.index),
                not player.teammate and won or nil)
        end
    end
    history[#history + 1] = entry
    if #history > HISTORY_SIZE then
        table.remove(history, 1)
    end
    if replay.matchFinished then
        local matches = session.matches
        if won then
            matches.won += 1
        else
            matches.lost += 1
        end
    end
end)

-- Through Match, so a renamed currency event costs the session tally and nothing else. Bound
-- directly, it errored on the way up and took auto duel, picks and aim with it.
Match.listen("CurrencyChanged", function(currency, delta, _, source)
    if currency == "coins" and type(delta) == "number" and type(source) == "table" and source.type == "duelReward" then
        session.coins += delta
    end
end)

-- Choosing a ball --------------------------------------------------------------------------------

local function never(ball)
    local chosen = Options.NeverPick and Options.NeverPick.Value or {}
    return chosen[Env.ballName(ball)] == true
end

local function allowed(candidates)
    local out = {}
    for _, ball in ipairs(candidates) do
        if not never(ball) then
            out[#out + 1] = ball
        end
    end
    -- The server requires a pick even when every candidate is excluded; reroll is attempted first.
    return #out > 0 and out or candidates
end

-- The one opponent of a 1v1 (from Match.players), or nil in a 2v2.
local function soleOpponent(players)
    if Match.teamSize() ~= 1 then
        return nil
    end
    for _, player in ipairs(players) do
        if not player.me then
            return player
        end
    end
    return nil
end

-- Best by win rate, head to head against `versus` when the game has enough games of it.
local function byWinRate(candidates, versus)
    if #candidates == 0 then return nil, "no eligible balls" end
    local best, bestRate = candidates[1], -1
    local hasStatistics = false
    for _, ball in ipairs(candidates) do
        local rate = Stats.against(ball, versus)
        hasStatistics = hasStatistics or rate ~= nil
        rate = rate or 0
        if rate > bestRate then
            best, bestRate = ball, rate
        end
    end
    if not hasStatistics then return best, Env.ballName(best) .. ": statistics unavailable" end
    return best, string.format("%s: %d%% win rate%s", Env.ballName(best), math.floor(bestRate * 100 + 0.5),
        versus and " vs " .. Env.ballName(versus) or "")
end

-- Simulates each candidate with the known seed against everyone else's ball and aim from last
-- round (teammate included in a 2v2). Nil when the seed or last round is not known yet.
local function bySimulation(candidates, deadline, valid)
    local seed = Match.nextSeed()
    if not seed or not Sim.ready() then
        return nil
    end
    local players = Match.players()
    local lastRole, lastDirection = {}, {}
    for _, player in ipairs(players) do
        if not player.me then
            local role, direction = Match.lastPlay(player)
            -- A teammate who has already locked this round shows their ball (the pick screen does
            -- too). Failing both, the ball this player is known to favour beats giving up on the
            -- simulation entirely.
            role = player.teammate and player.roleId or role or Profile.likelyBall(player.userId)
            if not (role and direction) then
                return nil
            end
            lastRole[player.userId], lastDirection[player.userId] = role, direction
        end
    end
    local options = Match.lastReplay.replayOptions or {}
    local arena = Match.arena()

    -- The opponent's ball next round is their last one if they keep it; for a switcher (a spread
    -- ball history) hedge our pick across their likeliest balls instead of a single guess. A
    -- concentrated history, no history, or a 2v2 leaves one hypothesis: the old behaviour exactly.
    local opponent = soleOpponent(players)
    local hypotheses = { { roles = lastRole, weight = 1 } }
    if opponent then
        local dist = Profile.ballDistribution(opponent.userId, 2)
        if dist and #dist == 2 and dist[1].weight < 0.75 then
            hypotheses = {}
            for _, item in ipairs(dist) do
                local roles = table.clone(lastRole)
                roles[opponent.userId] = item.roleId
                hypotheses[#hypotheses + 1] = { roles = roles, weight = item.weight }
            end
        end
    end

    local best, bestScore, bestWins = nil, -1, 0
    local perCall = math.max(1, (deadline - os.clock()) / (#candidates * #hypotheses))
    for _, ball in ipairs(candidates) do
        local weighted, weights, minWins = 0, 0, math.huge
        for _, hypothesis in ipairs(hypotheses) do
            local direction, expected, wins = Sim.bestDirection({
                team = Match.team(),
                roles = byTeam(players, function(player)
                    return player.me and ball or hypothesis.roles[player.userId]
                end),
                place = function(direction)
                    return byTeam(players, function(player)
                        return player.me and direction or lastDirection[player.userId]
                    end)
                end,
                directions = Sim.directions(PICK_DIRECTIONS),
                scenarios = { { seed = seed, weight = 1 } },
                statLevels = options.statLevels,
                traits = options.selectedSecondaryTraits,
                arena = arena,
                deadline = math.min(deadline, os.clock() + perCall),
                valid = valid,
            })
            if not direction then return nil end
            weighted += expected * hypothesis.weight
            weights += hypothesis.weight
            minWins = math.min(minWins, wins)
        end
        -- Weighted win chance across the opponent's likely balls, then the most forgiving aim in the
        -- worst of them, then the ball itself. A guaranteed win needs every hypothesis to win.
        local expected = weights > 0 and weighted / weights or 0
        local score = (expected >= 1 and 0.6 or 0) + 0.25 * minWins / PICK_DIRECTIONS + 0.15 * (Stats.winRate(ball) or 0.5)
        if score > bestScore then
            best, bestScore, bestWins = ball, score, minWins
        end
    end
    if not best then
        return nil
    end
    if #hypotheses > 1 then
        return best, string.format("%s: robust across %d likely opponent balls, %d/%d aims win (simulated)",
            Env.ballName(best), #hypotheses, bestWins, PICK_DIRECTIONS)
    end
    return best, string.format("%s: wins with %d/%d aims against last round's balls (simulated)", Env.ballName(best),
        bestWins, PICK_DIRECTIONS)
end

local function choose(candidates, deadline, valid)
    local strategy = Options.PickStrategy.Value
    local selected = selectedInventoryBall()
    if selected and table.find(candidates, selected) then
        return selected, Env.ballName(selected) .. ": selected inventory ball"
    end
    if strategy == "First offered" then
        return candidates[1], Env.ballName(candidates[1]) .. ": first offered"
    end
    if strategy == "Smart" then
        local ball, why = bySimulation(candidates, deadline, valid)
        if ball then
            return ball, why
        end
    end
    local opponent = soleOpponent(Match.players())
    return byWinRate(candidates, opponent and (Match.lastPlay(opponent)))
end

local function waitFor(predicate, seconds)
    local deadline = os.clock() + seconds
    while Life.alive and not predicate() and os.clock() < deadline do
        Life.wait(0.1)
    end
    Env.elevate()
    return Life.alive and predicate()
end

local triedAt = {}
local function mayTry(key, cooldown)
    local now = os.clock()
    if not Life.alive or now - (triedAt[key] or -math.huge) < cooldown then
        return false
    end
    triedAt[key] = now -- acquire before sending, including failed/timed-out calls
    return true
end

local function reroll(kind, offer, deadline, valid)
    local function affordable()
        local allowDiamonds = Ui.on("UseOwnedDiamondsForRerolls")
        if kind == "ball" then
            return Match.canRerollBall(allowDiamonds)
        end
        return Match.canRerollUpgrade(allowDiamonds)
    end
    if offer.rerollTried or deadline - os.clock() < REROLL_WAIT + 1
        or not affordable()
        or not mayTry("reroll:" .. kind, REROLL_COOLDOWN) then
        return
    end
    local remote = Env.event(kind == "ball" and "DuelTableBallReroll" or "DuelTableUpgradeReroll")
    if not valid() or not affordable() then
        return
    end
    offer.rerollTried, offer.rerollPending = true, true
    Match.status = kind == "ball" and "Rerolling bad balls" or "Rerolling one-star upgrades"
    Env.elevate()
    remote:FireServer(Match.tableModel)
    waitFor(function()
        return not valid() or not offer.rerollPending
    end, math.min(REROLL_WAIT, deadline - os.clock()))
    -- If no reply arrives, leave the request pending until near the deadline. A later loop
    -- reads the latest offer rather than choosing from the pre-reroll candidates.
end

local function badBalls(candidates)
    if #candidates == 0 then
        return false
    end
    for _, ball in ipairs(candidates) do
        local rate = Stats.winRate(ball)
        if not never(ball) and (rate == nil or rate * 100 >= Options.RerollThreshold.Value) then
            return false -- unknown stats do not justify spending a reroll
        end
    end
    return true
end

local function pick(offer)
    local model = Match.tableModel
    local deadline = offer.at + (offer.duration or PICK_WINDOW) - PICK_MARGIN
    local function valid()
        return Life.alive and Ui.on("AutoDuel") and Match.seated() and Match.phase() == "Picking"
            and Match.tableModel == model and Match.offer == offer and not Match.ballLocked
    end
    if not valid() then
        return true
    end
    local candidates, inventoryPick = offer.offer or {}, false
    local selected = selectedInventoryBall()
    local alreadyOffered = selected and table.find(candidates, selected) ~= nil
    local wantsInventory = not alreadyOffered and (selected ~= nil
        or (Options.PickStrategy.Value ~= "Selected inventory ball" and (Ui.on("FreePick") or Ui.on("PaidInventoryPick"))))
    local available = wantsInventory and inventoryPickAvailable(offer)
    local useInventory = available and (offer.selectPrice > 0 or Ui.on("FreePick") or selected ~= nil)
    if useInventory and not offer.selectAsked and mayTry("inventoryPick", 5) then
        offer.selectAsked, offer.selectPending, offer.selectError = true, true, nil
        offer.selectAskedAt = os.clock()
        Match.selectList = nil
        Env.elevate()
        Env.event("DuelTableBallSelectPurchase"):FireServer(model)
        waitFor(function()
            return not valid() or not offer.selectPending
        end, math.max(0, math.min(FREE_LIST_WAIT, deadline - os.clock())))
    end
    if not valid() then
        return true
    end
    if useInventory and offer.selectPending and os.clock() < deadline - 1 then
        Match.status = "Waiting for inventory choices"
        return false
    end
    if useInventory and Match.selectList and not offer.selectError and type(Match.selectList.roleIds) == "table"
        and #Match.selectList.roleIds > 0 and (not selected or table.find(Match.selectList.roleIds, selected)) then
        candidates, inventoryPick = Match.selectList.roleIds, true
    end
    if not inventoryPick and not alreadyOffered and Ui.on("RerollBadOffers") and badBalls(candidates)
        and Match.canRerollBall(Ui.on("UseOwnedDiamondsForRerolls")) then
        reroll("ball", offer, deadline, valid)
    end
    if not valid() then
        return true
    end
    if offer.rerollPending and os.clock() < deadline - 1 then
        Match.status = "Waiting for ball reroll"
        return false
    end
    candidates = inventoryPick and candidates or offer.offer or {}
    if #candidates == 0 then
        return false
    end
    -- 2v2: simulating is worth more with the teammate's real ball, so give them time to lock it,
    -- keeping enough of the timer to simulate afterwards.
    local waitUntil = math.min(offer.at + TEAMMATE_PICK_WAIT, deadline - PICK_THINK_RESERVE)
    if Match.teamSize() > 1 and Options.PickStrategy.Value == "Smart" and Match.nextSeed() then
        Match.status = "Picking a ball (waiting for your teammate's pick)"
        waitFor(function()
            if os.clock() >= waitUntil or not valid() then
                return true
            end
            for _, player in ipairs(Match.players()) do
                if player.teammate and player.roleId then
                    return true
                end
            end
            return false
        end, TEAMMATE_PICK_WAIT)
    end
    if not valid() then
        return true
    end
    Match.status = "Picking a ball"
    -- A reply can arrive during the teammate wait too.
    candidates = inventoryPick and candidates or offer.offer or {}
    local revision = offer.revision
    local preferred = selectedInventoryBall()
    local choices = preferred and table.find(candidates, preferred) and { preferred } or allowed(candidates)
    local ball, why = choose(choices, deadline - 1, valid)
    local pickAt = math.min(offer.at + Options.PickDelay.Value, deadline)
    waitFor(function()
        return not valid() or os.clock() >= pickAt
    end, math.max(0, pickAt - os.clock()))
    if not valid() then
        return true
    end
    if not ball or offer.revision ~= revision then
        return false
    end
    if inventoryPick then
        local selectedNow = selectedInventoryBall()
        if selectedNow and selectedNow ~= ball then return false end
        local affordable, text = inventoryPickAvailable(offer)
        if not affordable then
            Env.elevate()
            inventoryCostLabel:SetText(text)
            return false -- re-read the current balance/settings before confirming a paid choice
        end
    end
    if not valid() then return true end
    offer.selectConfirmError = nil
    -- A callback error or a delayed confirmation must never submit another paid pick.
    if inventoryPick and offer.inventorySubmitted then return true end
    local pickRemote = Env.event(inventoryPick and "DuelTableBallSelfSelect" or "DuelTableBallSelect")
    if inventoryPick then
        local selectedNow = selectedInventoryBall()
        if (selectedNow and selectedNow ~= ball) or not inventoryPickAvailable(offer) then return false end
    end
    if not valid() then return true end
    if inventoryPick then offer.inventorySubmitted = true end
    Env.elevate()
    pickRemote:FireServer(model, ball)
    local weekly = Match.isWeeklyFree(ball) and " (weekly free)" or ""
    prediction = { text = "Picked " .. why .. weekly }
    Match.status = "Ball selected: " .. Env.ballName(ball) .. weekly
    if inventoryPick then
        waitFor(function()
            return not valid() or offer.selectConfirmError ~= nil
        end, LOCK_WAIT)
    end
    if inventoryPick and valid() then
        -- An unavailable/denied inventory choice falls back to the ordinary offer.
        local fallback, fallbackWhy = byWinRate(allowed(offer.offer or {}))
        if fallback then
            Env.elevate()
            Env.event("DuelTableBallSelect"):FireServer(model, fallback)
            prediction = { text = "Picked " .. fallbackWhy }
            Match.status = "Inventory choice unavailable; selected " .. Env.ballName(fallback)
        end
    end
    return true
end

-- Aiming -----------------------------------------------------------------------------------------

-- A score as a percentage. Scores carry a small bonus for quick wins (core/sim's tie-break), which
-- pushes a certain win just past 1, and "101% expected" reads as a bug.
local function percent(score)
    return math.clamp(math.floor(score * 100 + 0.5), 0, 100)
end

local function aim()
    if not Sim.ready() then
        Match.status = "Waiting for simulation modules"
        return
    end
    local token, model = Match.aimToken, Match.tableModel
    local function valid()
        return Life.alive and Ui.on("SmartAim") and Match.seated() and Match.phase() == "Aiming"
            and Match.aimToken == token and Match.tableModel == model and not Match.aimLocked
    end
    local players = Match.players()
    local me
    for _, player in ipairs(players) do
        if player.me then
            me = player
        end
        if not player.roleId then
            return -- balls are not all locked yet
        end
    end
    if not (Ui.on("SmartAim") and me) then
        return -- the game locks the current aim when its timer runs out
    end
    Match.status = "Aiming"
    -- 2v2: the teammate's aim is known as they drag it, so wait for it to settle first.
    local thinkTime = math.min(Options.AimThinkTime.Value, PICK_WINDOW - PICK_MARGIN)
    local latest = Match.aimStartedAt + PICK_WINDOW - PICK_MARGIN - thinkTime
    local hasTeammate = false
    for _, player in ipairs(players) do
        hasTeammate = hasTeammate or player.teammate
    end
    while hasTeammate and valid() and os.clock() < latest do
        local live = Match.teammateAim
        if live and os.clock() - live.at >= TEAMMATE_SETTLE then
            break
        end
        Match.status = "Aiming (waiting for your teammate's aim)"
        Life.wait(0.2)
    end
    if not valid() then
        return
    end
    Match.status = "Aiming (solving launch directions)"
    local seed = Match.nextSeed()
    -- Where everyone else will likely aim: a teammate's live aim while they drag it, otherwise
    -- last round's aim (nil in round 1, and nil for anyone the model says re-aims: they are
    -- swept or sampled instead).
    local likely = {}
    for _, player in ipairs(players) do
        if not player.me then
            local _, lastDirection = Match.lastPlay(player)
            -- A direction relayed this round beats last round's guess: a teammate's always, an
            -- opponent's only if the server ever leaks one (then it is their actual aim, not a guess).
            local live = Match.liveAim(player.userId, 10)
            likely[player.userId] = live or (Match.keepsAim(player) ~= false and lastDirection) or nil
        end
    end
    local options = Match.lastReplay and Match.lastReplay.replayOptions or {}
    local team = Match.team()
    local roles = byTeam(players, function(player)
        return player.roleId
    end)
    local function place(ours, scenario)
        return byTeam(players, function(player)
            return player.me and ours or scenario.others[player.userId]
        end)
    end
    local directionCount = math.clamp(math.floor(thinkTime / 10 * AIM_DIRECTIONS / 6) * 6, 12, AIM_DIRECTIONS)
    local deadline = math.min(os.clock() + thinkTime, Match.aimStartedAt + PICK_WINDOW - PICK_MARGIN)
    local arena = Match.arena()
    -- `call` becomes the round's prediction only once the aim is actually sent, so the accuracy
    -- figures never judge a call the hub abandoned at the last moment.
    local direction, expected, detail, call

    local seedReliable = true
    if Ui.on("SeedResilience") and seed then
        local excitement = Match.excitementSelection()
        if excitement and excitement.enabled then
            seedReliable = false
        end
        if seedReliable then
            local misses, checks = 0, 0
            for i = math.max(1, #history - 4), #history do
                local entry = history[i]
                if entry and entry.seedRight ~= nil then
                    checks += 1
                    if not entry.seedRight then misses += 1 end
                end
            end
            if checks >= 2 and misses / checks > 0.4 then
                seedReliable = false
            end
        end
    end

    if seed and seedReliable then
        -- The round is fully determined except for where the others launch, so solve it as a grid
        -- instead of answering one guess. The first opponent column is who the model expects, and
        -- its weight is how often these specific players have actually repeated an aim.
        local modelled = Profile.tableKeepRate(players)
        local sweep = math.clamp(math.floor(thinkTime / 2), 4, OPPONENT_SWEEP)
        local ourHp, theirHp = Match.stakes()
        local lambda = Solver.lambda(Options.AimStyle.Value, ourHp, theirHp)
        local row, columns = Solver.solve({
            team = team,
            seed = seed,
            roles = roles,
            ours = Sim.directions(directionCount),
            opponents = Solver.columns(players, likely, modelled, sweep),
            place = place,
            statLevels = options.statLevels,
            traits = options.selectedSecondaryTraits,
            arena = arena,
            lambda = lambda,
            deadline = deadline,
            valid = valid,
        })
        if not row or not valid() then
            return
        end
        direction, expected = row.direction, row.expected
        local floor = row.worst >= 1 and "a win" or row.worst >= 0.5 and "a draw" or "a loss"
        detail = string.format("floor %s | beats %d/%d aims", floor, row.wins, columns)
        local versus = string.format("%s vs %s", teamBalls(roles, team), teamBalls(roles, otherTeam(team)))
        call = {
            text = string.format("%s: %s (%s, %d%% expected, %s style at lambda %.2f)", versus,
                row.winner == team and "expect a win" or row.winner == "Draw" and "expect a draw" or "likely a loss",
                detail, percent(row.expected), Options.AimStyle.Value, lambda),
            seed = seed,
            assumed = likely,
            predicted = row.winner == team,
            expected = row.expected,
            worst = row.worst,
            wins = row.wins,
            columns = columns,
            lambda = lambda,
            modelled = modelled,
        }
    elseif seed then
        local samples = math.clamp(math.floor(thinkTime / 3), 3, 8)
        local others = {}
        for _, player in ipairs(players) do
            if not player.me then
                others[player.userId] = likely[player.userId] or Sim.randomDirection()
            end
        end
        local scenarios = { { seed = seed, others = others, weight = 0.4 } }
        local altWeight = 0.6 / math.max(1, samples - 1)
        for _ = 2, samples do
            scenarios[#scenarios + 1] = { seed = Sim.randomSeed(), others = others, weight = altWeight }
        end
        local firstWins
        direction, expected, firstWins = Sim.bestDirection({
            team = team,
            roles = roles,
            place = place,
            directions = Sim.directions(directionCount),
            scenarios = scenarios,
            arena = arena,
            deadline = deadline,
            valid = valid,
        })
        if not direction or not valid() then
            return
        end
        detail = string.format("seed unreliable | %d candidates", samples)
        local versus = string.format("%s vs %s", teamBalls(roles, team), teamBalls(roles, otherTeam(team)))
        call = {
            text = string.format("%s: %d%% expected over %d seed candidates (%d/%d directions win the primary)",
                versus, percent(expected), samples, firstWins or 0, directionCount),
            seed = seed,
            assumed = likely,
            expected = expected,
            seedReliable = false,
        }
    else
        -- Round 1: the seed is unknown, so there is no grid. Every scenario is a guessed seed and
        -- the best that can be said is which direction wins over the most of them.
        -- Nobody has a last aim yet, so opponents are random in every scenario; only a teammate
        -- dragging their arrow is known.
        local scenarios = {}
        local samples = math.clamp(math.floor(thinkTime / 10 * ROUND_ONE_SAMPLES), ROUND_ONE_SAMPLES, ROUND_ONE_MAX)
        for _ = 1, samples do
            local others = {}
            for _, player in ipairs(players) do
                if not player.me then
                    others[player.userId] = likely[player.userId] or Sim.randomDirection()
                end
            end
            scenarios[#scenarios + 1] = { seed = Sim.randomSeed(), others = others, weight = 1 }
        end
        local firstWins
        direction, expected, firstWins = Sim.bestDirection({
            team = team,
            roles = roles,
            place = place,
            directions = Sim.directions(directionCount),
            scenarios = scenarios,
            arena = arena,
            deadline = deadline,
            valid = valid,
        })
        if not direction or not valid() then
            return
        end
        detail = string.format("round 1 | %d seeds sampled", samples)
        local versus = string.format("%s vs %s", teamBalls(roles, team), teamBalls(roles, otherTeam(team)))
        call = {
            text = string.format("%s: round 1, best aim wins %d%% of %d sampled seeds (%d/%d directions win the first)",
                versus, percent(expected), samples, firstWins or 0, directionCount),
            expected = expected,
        }
    end

    Env.elevate()
    if Ui.on("AimTrajectory") then
        local ok, err = pcall(Trajectory.show, me, direction, expected, detail)
        Life.errors["duel:trajectory"] = not ok and tostring(err) or nil
        if not ok then
            Trajectory.clear()
        end
    end
    if not valid() then
        Trajectory.clear()
        return
    end
    Env.elevate()
    if Match.teamSize() > 1 then
        -- Shows our arrow on the teammate's screen, as the game does while we drag.
        Env.unreliable("DuelTableAimPreview"):FireServer(Match.tableModel, direction)
    end
    Env.event("DuelTableLaunchDirection"):FireServer(Match.tableModel, direction)
    prediction = call
    Match.status = string.format("Aim selected (%d%% expected, %s)", percent(expected), detail)
    return true
end

-- Resolve cloud star ratings and add bonuses for the current ball's traits.
local function upgrade(offer)
    local model, phase = Match.tableModel, Match.phase()
    local function valid()
        return Life.alive and Ui.on("AutoDuel") and Match.seated() and Match.tableModel == model
            and Match.phase() == phase and Match.upgradeOffer == offer
    end
    local players = Match.players()
    local me, roleId, secondary
    for _, player in ipairs(players) do
        if player.me then
            me = player
            roleId = player.roleId or (Match.ballLocked and Match.ballLocked.roleId) or Match.lastPlay(player)
            local options = Match.lastReplay and Match.lastReplay.replayOptions
            local traits = options and options.selectedSecondaryTraits
            secondary = traits and traits[player.team]
            if Match.teamSize() > 1 and type(secondary) == "table" then
                secondary = secondary[player.index]
            end
            break
        end
    end
    local deadline = offer.at + (offer.duration or 20) - 2
    local best, maxStar, known = Upgrades.best(offer.offer or {}, roleId, secondary)
    if valid() and Ui.on("RerollLowUpgrades") and known and maxStar == 1
        and Match.canRerollUpgrade(Ui.on("UseOwnedDiamondsForRerolls")) then
        reroll("upgrade", offer, deadline, valid)
    end
    if not valid() then
        return true
    end
    if offer.rerollPending and os.clock() < deadline - 1 then
        Match.status = "Waiting for upgrade reroll"
        return false
    end
    local candidates = offer.offer or {}
    local why
    best = nil
    -- The next round's balls are not chosen yet, so the card is judged on the round we just
    -- played: same balls, same aims, next round's seed. That is a proxy, not the certainty the
    -- aim solver gets -- but a card that wins a replay of the last round beats one that merely
    -- reads as if it should.
    if Ui.on("SimulateUpgrades") and me then
        local options = Match.lastReplay and Match.lastReplay.replayOptions or {}
        local lastRoles, lastDirections, complete = {}, {}, true
        for _, player in ipairs(players) do
            local role, direction = Match.lastPlay(player)
            if not (role and direction) then
                complete = false
                break
            end
            lastRoles[player.userId], lastDirections[player.userId] = role, direction
        end
        if complete then
            best, why = Upgrades.bestBySimulation(candidates, {
                seed = Match.nextSeed(),
                team = me.team,
                index = me.index,
                teamMode = Match.teamSize() > 1,
                roles = byTeam(players, function(player)
                    return lastRoles[player.userId]
                end),
                directions = byTeam(players, function(player)
                    return lastDirections[player.userId]
                end),
                statLevels = options.statLevels,
                traits = options.selectedSecondaryTraits,
                arena = Match.arena(),
                roleId = roleId,
                secondary = secondary,
                deadline = deadline,
                valid = valid,
            })
        end
    end
    if not best then
        best = Upgrades.best(candidates, roleId, secondary)
        why = best and (best.id .. ": best star rating and trait match") or nil
    end
    if not best then
        return false
    end
    if not valid() then
        return true
    end
    Match.status = "Selecting upgrade: " .. best.id
    Env.elevate()
    upgradeLabel:SetText("Last card: " .. tostring(why))
    Env.event("DuelTableUpgradeSelect"):FireServer(model, { kind = best.kind, id = best.id })
    return true
end

-- The loop ------------------------------------------------------------------------------------------

local lastQueue = -math.huge
local handledOffer, handledAim, handledUpgrade, seenOffer

-- Aims once per Aiming token. Past the point where a search could still finish before the game
-- locks the current aim, the token is given up on: otherwise a solve that cannot complete was
-- restarted every quarter second until the phase changed, stalling frames for nothing.
local function tryAim()
    if not (Ui.on("SmartAim") and Match.seated() and Match.phase() == "Aiming" and Match.aimToken
        and handledAim ~= Match.aimToken and not Match.aimLocked) then
        return
    end
    local token = Match.aimToken
    if os.clock() >= Match.aimStartedAt + PICK_WINDOW - PICK_MARGIN then
        handledAim = token
        Match.status = "Aim window closed; the game keeps the current aim"
        return
    end
    if aim() then
        handledAim = token
    end
end

local function step()
    if not Ui.on("AutoDuel") then
        Match.status = Ui.on("SmartAim") and "Auto duel off (smart aim still aims your rounds)" or "Off"
        -- Smart aim also helps in matches you play yourself.
        tryAim()
        return
    end
    if not Match.seated() then
        local forCandy = nil
        if Ui.on("StopAtCoinCap") and (Match.capped or Limits.coins().capped) then
            local candy = Limits.candy()
            if not (Ui.on("DuelForCandy") and candy.active and not candy.capped) then
                local both = Ui.on("DuelForCandy") and candy.active
                Match.status = both and "Stopped at the coin and candy caps" or "Stopped at the coin cap"
                Ui.set("AutoDuel", false)
                Ui.notify("Auto duel", (both and "Coin and candy caps" or "Coin cap")
                    .. " reached: duels pay nothing more until the reset.", 8)
                return
            end
            forCandy = string.format(" for candy, %d/%s today", candy.today, tostring(candy.dayMax or "?"))
        end
        local wanted, server = SERVER_FOR_MODE[Options.DuelMode.Value], Env.serverType()
        if wanted and server and server ~= wanted then
            Match.status = string.format("%s is played on %s servers and this is a %s server: press Switch server",
                Options.DuelMode.Value, SERVER_NAME[wanted], SERVER_NAME[server] or server)
            return
        end
        local refusal = Match.queueRefusal
        Match.status = "Queueing (" .. Options.DuelMode.Value .. ")" .. (forCandy or "")
            .. (refusal and refusal.reason == "noAvailableTable" and os.clock() - refusal.at < 30
                and " - no free table on this server yet" or "")
        if os.clock() - lastQueue > QUEUE_INTERVAL then
            lastQueue = os.clock()
            Env.event("DuelQuickPlayRequest"):FireServer()
        end
        return
    end
    local phase = Match.phase()
    Match.status = phase == "Aiming" and (Match.aimLocked or handledAim == Match.aimToken)
        and "Aim selected (waiting for other players)" or "In a match: " .. tostring(phase)
    if phase == "Upgrading" and Match.upgradeOffer and handledUpgrade ~= Match.upgradeOffer then
        local offer = Match.upgradeOffer
        if upgrade(offer) then
            handledUpgrade = offer
        end
        return
    end
    if phase == "Picking" and Match.offer and handledOffer ~= Match.offer and not Match.ballLocked then
        local offer = Match.offer
        -- Cleared once per offer, not on every pass that is still waiting on a reroll or the
        -- teammate: last round's result line used to blink out of the panel four times a second.
        if seenOffer ~= offer then
            seenOffer, prediction = offer, nil
        end
        if pick(offer) then
            handledOffer = offer
        end
    elseif phase == "Aiming" then
        tryAim()
    end
end

Life.loop("duel:auto", 0.25, step)

Life.loop("duel:panel", 0.5, function()
    Match.prediction = prediction
    local lines = { "Status: " .. Match.status }
    if Match.seated() then
        local mine, theirs
        for _, player in ipairs(Match.players()) do
            if player.me then
                mine = Match.hp(player)
            elseif not player.teammate and not theirs then
                theirs = Match.hp(player)
            end
        end
        lines[#lines + 1] = string.format("%s, round %d: you %s hp, them %s hp", tostring(Match.tableId), Match.round(),
            tostring(mine or "?"), tostring(theirs or "?"))
        lines[#lines + 1] = Match.nextSeed() and "Seed: known (exact simulation)" or "Seed: unknown until round 1 is played"
    end
    if prediction then
        local result = prediction.result == true and " - won" or prediction.result == false and " - lost" or ""
        lines[#lines + 1] = prediction.text .. result
    end
    local rounds, matches = session.rounds, session.matches
    lines[#lines + 1] = string.format("Session: matches %d-%d, rounds %d-%d%s, +%d coins", matches.won, matches.lost,
        rounds.won, rounds.lost, rounds.draw > 0 and string.format(" (%d drawn)", rounds.draw) or "", session.coins)
    local coins = Limits.coins()
    local footer = coins.dayMax and string.format("Duel coins today: %d / %d, this week: %d / %d", coins.day, coins.dayMax,
        coins.week, coins.weekMax or 0) or ""
    panel.set(lines, footer)
end)

Life.onCleanup(function()
    table.clear(triedAt)
    table.clear(history)
    prediction, handledOffer, handledAim, handledUpgrade, seenOffer = nil, nil, nil, nil, nil
    Match.prediction = nil
    Trajectory.clear()
end)

return { history = history, session = session }
