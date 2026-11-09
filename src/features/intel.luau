-- Intel tab: who you are playing, what the solver decided, and whether its predictions hold up.
--
-- Everything here is read-only. It reports on what features/duel publishes on Match (prediction,
-- history, session) and on core/profile's opponent model, so a broken panel can never change how
-- a round is played -- and checking the predictions against what actually happened is the only
-- honest way to know whether the solver is worth its think time.

local Env = use("core/env")
local Life = use("shared/life")
local Ui = use("core/ui")
local Match = use("core/match")
local Profile = use("core/profile")

local tab = Ui.Tabs.Intel

-- Opponents ----------------------------------------------------------------------------------

local opponentsBox = tab:AddGroupbox({ Side = "Left", Name = "Opponents", IconName = "users" })
local opponentsPanel = Ui.panel(opponentsBox, 6)
opponentsBox:AddButton({
    Text = "Forget opponents",
    Func = function()
        Profile.forget()
        Ui.notify("Intel", "Opponent history cleared. Everyone starts at the default aim-repeat guess again.", 5)
    end,
    Tooltip = "Clears every opponent's aim and ball history, here and in the saved file.",
})

local names = {}
local function nameOf(userId)
    if names[userId] == nil then
        local player = Env.Players:GetPlayerByUserId(userId)
        names[userId] = player and player.DisplayName ~= "" and player.DisplayName or false
    end
    return names[userId] or nil
end

Life.loop("intel:opponents", 1, function()
    local lines = {}
    if Match.seated() then
        local players = Match.players()
        for _, player in ipairs(players) do
            if not player.me then
                local tag = player.teammate and " (teammate)" or ""
                if not player.teammate and Match.liveAim(player.userId, 10) then
                    tag = tag .. " [LIVE AIM READ]"
                end
                lines[#lines + 1] = Profile.describe(player, nameOf(player.userId)) .. tag
            end
        end
        lines[#lines + 1] = string.format("Chance the table repeats every aim: %d%%",
            math.floor(Profile.tableKeepRate(players) * 100 + 0.5))
    else
        lines[#lines + 1] = "Not at a table. Opponents show here once you sit down."
    end
    opponentsPanel.set(lines, string.format("%d opponents remembered", Profile.count()))
end)

-- Solver -------------------------------------------------------------------------------------

local solverBox = tab:AddGroupbox({ Side = "Right", Name = "Solver", IconName = "brain" })
local solverPanel = Ui.panel(solverBox, 6)

local function percent(value)
    return value and string.format("%d%%", math.floor(value * 100 + 0.5)) or "?"
end

local function outcomeName(value)
    if value == nil then
        return "?"
    end
    return value >= 1 and "win" or value >= 0.5 and "draw" or "loss"
end

Life.loop("intel:solver", 0.5, function()
    local prediction = Match.prediction
    local lines = {}
    local ours, theirs = Match.stakes()
    if Match.seated() then
        lines[#lines + 1] = string.format("Round %d | seed %s | hp %s vs %s", Match.round(),
            Match.nextSeed() and "known" or "unknown", tostring(ours or "?"), tostring(theirs or "?"))
        local excitement = Match.excitementSelection()
        if excitement and excitement.enabled then
            lines[#lines + 1] = string.format("BestOfN active (%d candidates) — seed prediction unreliable", excitement.candidates)
        end
    end
    if prediction and prediction.columns then
        lines[#lines + 1] = string.format("Expected result: %s", percent(prediction.expected))
        lines[#lines + 1] = string.format("Guaranteed floor: %s, whatever they aim", outcomeName(prediction.worst))
        lines[#lines + 1] = string.format("Beats %d of %d opponent aims", prediction.wins or 0, prediction.columns)
        lines[#lines + 1] = string.format("Risk weight %.2f (0 exploits, 1 plays safe), aim repeat %s",
            prediction.lambda or 0, percent(prediction.modelled))
    elseif prediction then
        lines[#lines + 1] = prediction.text
    else
        lines[#lines + 1] = "No round solved yet."
    end
    solverPanel.set(lines, "From round 2 every round is solved as a grid of your aims against theirs.")
end)

-- Accuracy -----------------------------------------------------------------------------------

local accuracyBox = tab:AddGroupbox({ Side = "Right", Name = "Prediction accuracy", IconName = "target" })
local accuracyPanel = Ui.panel(accuracyBox, 9)

Life.loop("intel:accuracy", 1, function()
    local history = Match.history or {}
    local judged, correct, seeds, seedsRight, kept, opponents = 0, 0, 0, 0, 0, 0
    for _, entry in ipairs(history) do
        if entry.predicted ~= nil and entry.won ~= nil then
            judged += 1
            correct += entry.predicted == entry.won and 1 or 0
        end
        if entry.seedRight ~= nil then
            seeds += 1
            seedsRight += entry.seedRight and 1 or 0
        end
        if entry.opponents then
            kept += entry.opponentsKept or 0
            opponents += entry.opponents
        end
    end
    local lines = {}
    lines[#lines + 1] = judged > 0 and string.format("Win/loss calls right: %d of %d (%d%%)", correct, judged,
        math.floor(correct / judged * 100 + 0.5)) or "Win/loss calls right: none judged yet"
    lines[#lines + 1] = seeds > 0 and string.format("Seed predicted exactly: %d of %d", seedsRight, seeds)
        or "Seed predicted exactly: from round 2"
    lines[#lines + 1] = opponents > 0 and string.format("Opponents repeated their aim: %d of %d", kept, opponents)
        or "Opponents repeated their aim: from round 2"
    -- The newest rounds, newest first.
    for index = #history, math.max(1, #history - 5), -1 do
        local entry = history[index]
        local result = entry.won == true and "won" or entry.won == false and "lost" or "drew"
        local call = entry.predicted == nil and "" or entry.predicted and ", called a win" or ", called a loss"
        lines[#lines + 1] = string.format("R%s %s: %s%s", tostring(entry.round), entry.balls or "?", result, call)
    end
    local session = Match.session
    local footer = session and string.format("Session: matches %d-%d, rounds %d-%d", session.matches.won,
        session.matches.lost, session.rounds.won, session.rounds.lost) or ""
    accuracyPanel.set(lines, footer)
end)

Life.onCleanup(function()
    table.clear(names)
end)

return {}
