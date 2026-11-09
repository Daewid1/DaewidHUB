-- Home tab: the shared welcome box (shared/home), your stats, and codes.
--
-- Codes come from the game's own config (Config.codes.list, which its redeem screen checks
-- against), so new ones are picked up without a hub update. "grantOnly" codes are handed out by
-- the developers and cannot be typed in. The server allows one redeem every 2 seconds and answers
-- SUCCESS, CLAIMED, EXPIRED or INVALID.

local Env = use("core/env")
local Life = use("shared/life")
local Ui = use("core/ui")
local Home = use("shared/home")
local Match = use("core/match")
local Limits = use("core/limits")

local REDEEM_INTERVAL = 2.5
local RESULTS = {
    SUCCESS = "redeemed now",
    CLAIMED = "already redeemed",
    EXPIRED = "expired",
    INVALID = "not valid",
    INVALID_CODE = "not valid",
}

local tab = Ui.Tabs.Home
local _, statusLabel = Home.build()
local statsBox = tab:AddGroupbox({ Side = "Right", Name = "You", IconName = "user" })
local codesBox = tab:AddGroupbox({ Side = "Right", Name = "Codes", IconName = "ticket" })

local stats = statsBox:AddLabel("Loading...", true)
Life.loop("home:stats", 1, function()
    statusLabel:SetText("Doing: " .. tostring(Match.status or "Idle"))
    local exp = Env.data("exp") or {}
    local ok, level = Env.call(Env.loadModule("ExperienceService").getLevelInfo, exp.total or 0)
    local matches, wins = 0, 0
    for _, mode in pairs(Env.data("matchStats") or {}) do
        matches += mode.matches or 0
        wins += mode.wins or 0
    end
    local coins = Limits.coins()
    stats:SetText(string.format(
        "Level %s\nCoins: %s  |  Diamonds: %s\nMatches: %d, won %d (%d%%)\nWin streak: %s (best %s)\nDuel coins today: %d / %s",
        ok and level and tostring(level.level) or "?",
        tostring(Env.data("coins") or "?"),
        tostring(Env.data("diamonds") or "?"),
        matches, wins, matches > 0 and math.floor(wins / matches * 100 + 0.5) or 0,
        tostring(Env.data("winStreak") or 0), tostring(Env.data("maxWinStreak") or 0),
        coins.day, tostring(coins.dayMax or "no cap")))
end)

local codeList = codesBox:AddLabel("Loading codes...", true)
local redeeming = false

local function redeemCodes()
    local lines = {}
    for _, entry in ipairs(Env.loadModule("Config").codes.list) do
        if not entry.grantOnly then
            if not Life.alive then return end
            local ok, result = Env.invoke("RedeemCodeRedeem", entry.code)
            if not Life.alive then return end
            local text = ok and (RESULTS[result] or tostring(result)) or "the game did not answer"
            lines[#lines + 1] = string.format("%s: %s", entry.code, text)
            Env.elevate()
            codeList:SetText(table.concat(lines, "\n"))
            if result == "SUCCESS" then
                Ui.notify("Codes", "Redeemed " .. entry.code, 5)
            end
            if not Life.wait(REDEEM_INTERVAL) then
                return
            end
        end
    end
    Env.elevate()
    codeList:SetText(#lines > 0 and table.concat(lines, "\n") or "No codes right now.")
end

local function startRedeeming()
    if redeeming or not Life.alive then return end
    redeeming = true
    Life.spawn("home:codes", function()
        Life.call("home:redeem", redeemCodes)
        redeeming = false
    end)
end

codesBox:AddToggle("RedeemOnLoad", {
    Text = "Redeem codes on load",
    Default = true,
    Tooltip = "Tries every code in the game's list once each time the hub loads.",
})
codesBox:AddButton({ Text = "Redeem codes", Func = function()
    startRedeeming()
end })

-- After the autoload, so a saved "off" is respected (main calls Home.afterLoad).
return {
    afterLoad = function()
        if Ui.on("RedeemOnLoad") then
            startRedeeming()
        else
            codeList:SetText("Press Redeem codes to try the game's codes.")
        end
    end,
}
