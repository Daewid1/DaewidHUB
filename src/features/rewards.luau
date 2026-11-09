-- Rewards tab: claims what the game hands out for free, and buys crates with coins.
--
-- Claims use the same remotes as the game's own UI, and the server
-- checks each one (progress, time online, day, already claimed), so a claim it refuses costs
-- nothing. What is claimable is read from the player's data as the client sees it:
--   daily quests   dailyQuest.progress/claimed vs Config.dailyQuest.list -> DailyQuestClaim(id)
--   online time    granted automatically by the updated server; display replicated progress only
--   check-in       CheckInService.client.getState() "claimable" days -> CheckInService.client.claim(day)
--   mail           mailbox.mails[id].claimedAt == 0 -> MailService/Claim(id)
-- Crates: GachaRoll(crateId, "coins"), rolled and granted by the server.
-- Halloween: the candy balance and the event's candy shop (below).

local Env = use("core/env")
local Life = use("shared/life")
local Ui = use("core/ui")
local Fusion = use("core/fusion")
local Limits = use("core/limits")

local Options = Ui.Options
local Config = Env.loadModule("Config")

local CLAIM_INTERVAL = 15
local RETRY_AFTER = 120 -- seconds before a refused claim is tried again
local BUY_INTERVAL = 3

local tab = Ui.Tabs.Rewards
local claims = tab:AddGroupbox({ Side = "Left", Name = "Auto claim", IconName = "gift" })
claims:AddToggle("AutoClaim", {
    Text = "Auto claim rewards",
    Default = true,
    Tooltip = "Claims the ticked rewards as soon as the game says they are ready.",
})
Ui.automation("AutoClaim", true)
claims:AddToggle("ClaimQuests", { Text = "Daily quests", Default = true })
claims:AddToggle("ClaimOnline", {
    Text = "Show online reward progress", Default = true,
    Tooltip = "The game now claims online rewards automatically. This only controls their progress display.",
})
claims:AddToggle("ClaimCheckIn", { Text = "Daily check-in", Default = true })
claims:AddToggle("ClaimMail", { Text = "Mail", Default = true })
claims:AddToggle("ClaimLevelRewards", { Text = "Level milestone rewards", Default = true })
claims:AddToggle("ClaimFreeChests", { Text = "Free starter / first-race chests", Default = true })
claims:AddButton({
    Text = "Claim group reward",
    Func = function()
        Life.spawn("rewards:group", function()
            local ok, result = Env.invoke("GroupJoinRewardRequest")
            local text = ok and type(result) == "table" and (result.ok and "Claimed." or tostring(result.reason))
                or "The game did not answer."
            Ui.notify("Group reward", text, 5)
        end)
    end,
    Tooltip = "Only pays if you are in the game's group.",
})
local claimPanel = Ui.panel(claims, #Config.dailyQuest.list + 9)

-- Lock every attempt before sending, including successful claims awaiting data replication.
local attemptedAt = {}
local function mayTry(key)
    local now = os.clock()
    if not Life.alive or now - (attemptedAt[key] or -math.huge) < RETRY_AFTER then
        return false
    end
    attemptedAt[key] = now
    return true
end

local function claimed(ok, result, key)
    if not Life.alive then
        return false
    end
    local success = Life.alive and ok and type(result) == "table" and result.ok == true
    if not success then
        attemptedAt[key] = os.clock()
    end
    return success
end

-- These rewards are granted by the server. Ready releases queued results; it does not accept
-- a level or chest id. In particular FirstRaceFreeChestResult is receive-only.
local rewardLog, seenRewards, seenChests = {}, {}, {}
local levelMilestones, lastExp, levelReadySent = 0, nil, false
local function logReward(key, text, toggle)
    if not Life.alive or seenRewards[key] then
        return
    end
    seenRewards[key] = true
    rewardLog[#rewardLog + 1] = text
    if #rewardLog > 3 then
        table.remove(rewardLog, 1)
    end
    if Ui.on("AutoClaim") and Ui.on(toggle) then
        Env.elevate()
        Ui.notify("Free reward", text, 5)
    end
end

Life.connect(Env.event("LevelRewardResult").OnClientEvent, function(payload)
    if not Life.alive or type(payload) ~= "table" or payload.ok == false then
        return
    end
    for _, entry in ipairs(payload) do
        if type(entry) == "table" and type(entry.level) == "number" then
            local key = "level:" .. entry.level .. ":" .. tostring(entry.rewardId or entry.cnId)
            if not seenRewards[key] then
                levelMilestones += 1
            end
            logReward(key, string.format("Level %d reward claimed", entry.level), "ClaimLevelRewards")
        end
    end
end)

local function chestResult(kind, payload)
    if not Life.alive or type(payload) ~= "table" or payload.ok == false then
        return
    end
    local results = type(payload.results) == "table" and payload.results or payload
    if #results == 0 then
        return
    end
    seenChests[kind] = true
    logReward("chest:" .. kind, string.format("%s chest claimed (%d items)", kind, #results), "ClaimFreeChests")
end
Life.connect(Env.event("NewbieFreeChestResult").OnClientEvent, function(payload)
    chestResult("Starter", payload)
end)
Life.connect(Env.event("FirstRaceFreeChestResult").OnClientEvent, function(payload)
    chestResult("First race", payload)
end)

local function claimLevels(lines, allowed)
    local exp = Env.data("exp")
    local total = type(exp) == "table" and tonumber(exp.total)
    if allowed("ClaimLevelRewards") and (not levelReadySent or (total and total > (lastExp or -1)))
        and mayTry("level:ready") then
        Env.elevate()
        Env.event("LevelRewardReady"):FireServer()
        levelReadySent, lastExp = true, total
    end
    local state = Env.data("levelRewards") or {}
    local granted = {}
    for _, field in ipairs({ "grantedRewards", "grantedRandom" }) do
        for level in pairs(type(state[field]) == "table" and state[field] or {}) do
            granted[tostring(level)] = true
        end
    end
    local count = 0
    for _ in pairs(granted) do
        count += 1
    end
    lines[#lines + 1] = string.format("Level rewards: %d saved milestones, %d received this session", count, levelMilestones)
end

local newbieReadySent = false
local function claimFreeChests(lines, allowed)
    local starter = Env.data("hasClaimedNewbieFreeChestV2")
    local firstRace = Env.data("hasClaimedFirstRaceFreeChest")
    -- One initial handshake also flushes rewards granted before the hub loaded. Retry only
    -- while PlayerData says a starter reward is pending, at the normal refusal cooldown.
    if allowed("ClaimFreeChests") and not seenChests.Starter and starter ~= nil
        and (not newbieReadySent or starter == false) and mayTry("chest:ready") then
        Env.elevate()
        Env.event("NewbieFreeChestReady"):FireServer()
        newbieReadySent = true
    end
    lines[#lines + 1] = "Starter chest: " .. ((starter == true or seenChests.Starter) and "claimed" or "pending")
    lines[#lines + 1] = "First race chest: " .. ((firstRace == true or seenChests["First race"]) and "claimed" or "awaiting first race")
end

local function claimQuests(lines, allowed)
    local data = Env.data("dailyQuest") or {}
    local progress, done = data.progress or {}, data.claimed or {}
    for _, quest in ipairs(Config.dailyQuest.list) do
        local count = progress[quest.cnId] or 0
        local state = done[quest.cnId] and "claimed" or string.format("%d/%d", math.min(count, quest.requireCount), quest.requireCount)
        if not done[quest.cnId] and count >= quest.requireCount and allowed("ClaimQuests") and mayTry("quest:" .. quest.cnId) then
            local ok, result = Env.invoke("DailyQuestClaim", quest.cnId)
            if claimed(ok, result, "quest:" .. quest.cnId) then
                state = "claimed now"
                Ui.notify("Daily quest", string.format("%s: +%s coins", quest.desc, tostring(result.rewardCoins or quest.rewardCoins)), 5)
            end
        end
        lines[#lines + 1] = string.format("%s: %s (%d coins)", quest.desc, state, quest.rewardCoins)
    end
end

local function claimOnline(lines)
    if not Ui.on("ClaimOnline") then
        return
    end
    local data = Env.data("onlineReward") or {}
    local seconds, done = data.onlineSeconds or 0, data.claimed or {}
    local ok, tiers = Env.call(Env.loadModule("OnlineRewardConfig").getTiers)
    if not ok or type(tiers) ~= "table" or #tiers == 0 then
        lines[#lines + 1] = "Online rewards: waiting for reward tiers."
        return
    end
    local nextTier, pending = nil, 0
    for _, tier in ipairs(tiers) do
        local isDone = done[tostring(tier.index)] or done[tier.index]
        if not isDone and seconds >= tier.seconds then
            pending += 1
        end
        if not isDone and seconds < tier.seconds and (not nextTier or tier.seconds < nextTier.seconds) then
            nextTier = tier
        end
    end
    -- Do not poll OnlineRewardNotifications: that drains the game's own notification queue.
    local status = pending > 0 and string.format("%d rewards awaiting the game's auto claim", pending)
        or nextTier and string.format("next reward at %d min", nextTier.minutes) or "every reward claimed"
    lines[#lines + 1] = string.format("Online %d min today: %s", seconds // 60, status)
end

local function claimCheckIn(lines, allowed)
    local service = Env.loadModule("CheckInService").client
    local ok, days = Env.call(service.getState)
    if not ok or type(days) ~= "table" then
        return
    end
    local claimedDays = 0
    for _, day in ipairs(days) do
        if day.status == "claimable" and allowed("ClaimCheckIn") and mayTry("checkin:" .. day.dayIndex) then
            local sent, result = Env.call(service.claim, day.dayIndex)
            if claimed(sent, result, "checkin:" .. day.dayIndex) then
                day.status = "claimed"
                Ui.notify("Check-in", string.format("Claimed day %d", day.dayIndex), 5)
            end
        end
        if day.status == "claimed" then
            claimedDays += 1
        end
    end
    lines[#lines + 1] = string.format("Check-in: %d/%d days claimed", claimedDays, #days)
end

local function claimMail(lines, allowed)
    local mailbox = Env.data("mailbox") or {}
    local waiting = 0
    for id, mail in pairs(type(mailbox.mails) == "table" and mailbox.mails or {}) do
        if type(mail) == "table" and (mail.claimedAt or 0) <= 0 then
            if allowed("ClaimMail") and mayTry("mail:" .. id) then
                local ok, result = Env.invoke("MailService/Claim", id)
                if claimed(ok, result, "mail:" .. id) then
                    Ui.notify("Mail", "Claimed a mail reward", 5)
                else
                    waiting += 1
                end
            else
                waiting += 1
            end
        end
    end
    lines[#lines + 1] = waiting > 0 and string.format("Mail: %d unclaimed", waiting) or "Mail: nothing to claim"
end

Life.loop("rewards:claim", CLAIM_INTERVAL, function()
    local lines = {}
    -- With Auto claim off the panel still shows progress; nothing is claimed.
    local function allowed(toggle)
        return Life.alive and Ui.on("AutoClaim") and Ui.on(toggle)
    end
    for _, step in ipairs({ claimQuests, claimOnline, claimCheckIn, claimMail, claimLevels, claimFreeChests }) do
        step(lines, allowed)
        if not Life.alive then
            return
        end
    end
    for _, entry in ipairs(rewardLog) do
        lines[#lines + 1] = entry
    end
    claimPanel.set(lines, Ui.on("AutoClaim") and "Claiming automatically." or "Auto claim is off.")
end)

-- Halloween -----------------------------------------------------------------------------------------
-- Candy comes from matches (see core/limits). The event shop (Config.eventShop, rows for the
-- running event) sells balls for candy or diamonds: HalloweenShop/Buy(eventId, row index, "candy").
-- Only candy is ever spent here. A candy-bought copy cannot be traded but can be fused.

local CANDY_INTERVAL = 3
local SHOP_REST = 30 -- after a refusal

local halloween = tab:AddGroupbox({ Side = "Left", Name = "Halloween", IconName = "candy" })
local candyLabel = halloween:AddLabel("Loading...", true)

-- The shop for whichever event is configured, read once: rows carry the event id they belong to.
local shopRows, shopLabels, shopByLabel = {}, {}, {}
for index, row in ipairs(type(Config.eventShop) == "table" and Config.eventShop.list or {}) do
    local ball = type(row) == "table" and Config.ball.byCnId[row.ballId]
    local price = type(row) == "table" and tonumber(row.candyPrice)
    if ball and price and price > 0 then
        local name = ball.displayName or row.ballId
        local label = string.format("%s (%d candy)", name, price)
        local entry = { index = index, eventId = row.eventId, ballId = row.ballId, price = price, label = label, name = name }
        shopRows[#shopRows + 1] = entry
        shopLabels[#shopLabels + 1] = label
        shopByLabel[label] = entry
    end
end
halloween:AddDropdown("CandyShopPicks", {
    Text = "Buy with candy",
    Values = #shopLabels > 0 and shopLabels or { "No event shop" },
    Multi = true,
    Default = {},
    Tooltip = "Balls to buy from the Halloween shop. Diamonds are never spent.",
})
halloween:AddSlider("CandyShopCopies", {
    Text = "Copies of each",
    Default = 1,
    Min = 1,
    Max = 6,
    Rounding = 0,
    Tooltip = "Buys until you own this many of each ticked ball, the ball you have fewest of first. Six copies make a Shiny.",
})
halloween:AddToggle("AutoCandyShop", {
    Text = "Auto buy",
    Default = false,
    Tooltip = "Spends candy on the ticked balls as soon as you can afford the next one.",
})
Ui.automation("AutoCandyShop", true)

local function ownedCopies(ballId)
    local count = 0
    for _, item in pairs(Env.data("items") or {}) do
        if type(item) == "table" and item.itemType == "Ball" and item.itemId == ballId
            and (item.ownerUserId == nil or item.ownerUserId == Env.LocalPlayer.UserId) then
            count += 1
        end
    end
    return count
end

-- A bought copy reaches the inventory a moment after the reply. Until it shows up (or 30s pass)
-- it is counted anyway, so a slow replication cannot buy one copy too many.
local credited = {}
local function heldCopies(ballId)
    local actual = ownedCopies(ballId)
    local credit = credited[ballId]
    if credit and (actual >= credit.count or os.clock() >= credit.untilAt) then
        credited[ballId], credit = nil, nil
    end
    return credit and math.max(actual, credit.count) or actual
end

local shopNote, shopRestUntil = "", 0
local function candyShop(candy)
    if not Ui.on("AutoCandyShop") or os.clock() < shopRestUntil then
        return
    end
    local picks, keep = Options.CandyShopPicks.Value or {}, tonumber(Options.CandyShopCopies.Value) or 1
    local chosen, chosenHeld
    for _, entry in ipairs(shopRows) do
        if picks[entry.label] and entry.eventId == candy.eventId then
            local held = heldCopies(entry.ballId)
            -- Strictly fewer, so ties go to the shop's order (cheapest first).
            if held < keep and (not chosen or held < chosenHeld) then
                chosen, chosenHeld = entry, held
            end
        end
    end
    if not chosen then
        local any = false
        for _ in pairs(picks) do any = true break end
        shopNote = any and string.format("Shop: you own %d of every ticked ball.", keep) or "Shop: tick the balls to buy."
        return
    end
    if candy.balance < chosen.price then
        shopNote = string.format("Shop: saving for %s, %d of %d candy.", chosen.name, candy.balance, chosen.price)
        return
    end
    if not mayTry("candyshop:" .. chosen.ballId) then
        return
    end
    local ok, result = Env.invoke("HalloweenShop/Buy", candy.eventId, chosen.index, "candy")
    if not Life.alive then
        return
    end
    local name = chosen.name
    if ok and type(result) == "table" and result.ok == true then
        attemptedAt["candyshop:" .. chosen.ballId] = nil
        credited[chosen.ballId] = { count = chosenHeld + 1, untilAt = os.clock() + 30 }
        shopRestUntil = os.clock() + CANDY_INTERVAL
        shopNote = "Shop: bought " .. name .. "."
        Ui.notify("Halloween shop", "Bought " .. name .. " for " .. chosen.price .. " candy", 5)
    else
        local reason = ok and type(result) == "table" and tostring(result.reason) or tostring(result or "no reply")
        shopRestUntil = os.clock() + SHOP_REST
        shopNote = "Shop: " .. name .. " refused (" .. reason .. ")."
    end
end

local function duration(seconds)
    local days, hours = seconds // 86400, seconds % 86400 // 3600
    return days > 0 and string.format("%dd %dh", days, hours) or string.format("%dh %dm", hours, seconds % 3600 // 60)
end

Life.loop("rewards:halloween", CANDY_INTERVAL, function()
    local candy = Limits.candy()
    if candy.active then
        candyShop(candy)
        candy = Limits.candy()
    end
    if not Life.alive then
        return
    end
    Env.elevate()
    if not candy.active then
        candyLabel:SetText("No Halloween event right now.")
        return
    end
    local lines = {
        string.format("Candy: %d  |  today %d / %s%s", candy.balance, candy.today, tostring(candy.dayMax or "?"),
            candy.capped and " (cap reached)" or ""),
    }
    if candy.endsIn then
        lines[#lines + 1] = "Event ends in " .. duration(math.floor(candy.endsIn))
    end
    for _, entry in ipairs(shopRows) do
        if entry.eventId == candy.eventId then
            lines[#lines + 1] = string.format("%s: own %d", entry.label, ownedCopies(entry.ballId))
        end
    end
    if Ui.on("AutoCandyShop") and shopNote ~= "" then
        lines[#lines + 1] = shopNote
    end
    candyLabel:SetText(table.concat(lines, "\n"))
end)

-- Fusion --------------------------------------------------------------------------------------------
local fusionBox = tab:AddGroupbox({ Side = "Right", Name = "Ball Fusion", IconName = "combine" })
fusionBox:AddToggle("AutoFuseDuplicates", {
    Text = "Auto fuse duplicates", Default = false,
    Tooltip = "Fuses duplicates toward the selected goal. Keeps one eligible copy per ball, form and trade status; equipped or locked copies are skipped.",
})
Ui.automation("AutoFuseDuplicates", true)
fusionBox:AddDropdown("FuseMode", {
    Text = "Fusion goal", Values = { "Higher rarity", "Shiny", "Rainbow" }, Default = "Higher rarity",
    Tooltip = "Higher rarity consumes ten Classic copies. Shiny consumes six Classic copies; Rainbow consumes six Shiny copies. One additional copy is kept.",
})
local rarityLabels, rarityByLabel, ratings = {}, {}, {}
for _, rating in ipairs(Config.rating.list) do
    if type(rating.lvl) == "number" then
        ratings[#ratings + 1] = rating
    end
end
table.sort(ratings, function(a, b) return a.lvl < b.lvl end)
for index = 1, #ratings do
    local rating = ratings[index]
    local label = rating.displayName or rating.name or (index == 1 and "Common" or "Uncommon")
    label = tostring(label) .. " (" .. rating.lvl .. ")"
    rarityLabels[#rarityLabels + 1], rarityByLabel[label] = label, rating.lvl
end
if #rarityLabels == 0 then
    rarityLabels, rarityByLabel = { "Common", "Uncommon" }, { Common = 1, Uncommon = 2 }
end
fusionBox:AddDropdown("FuseMaxRarity", {
    Text = "Maximum material rarity", Values = rarityLabels, Default = rarityLabels[math.min(2, #rarityLabels)],
})
local fusionLabel = fusionBox:AddLabel("Fusion is off.", true)
local reserved, fusedBatches = {}, 0
Life.loop("rewards:fusion", 1.5, function()
    if not Ui.on("AutoFuseDuplicates") then
        fusionLabel:SetText("Fusion is off.")
        return
    end
    local items = Env.data("items")
    if type(items) ~= "table" then
        fusionLabel:SetText("Waiting for inventory.")
        return
    end
    local mode = Options.FuseMode.Value
    local required = Fusion.requiredCount(mode)
    if not required then
        fusionLabel:SetText("Choose a fusion goal.")
        return
    end
    local function attemptKey(id)
        return "fusion:" .. mode .. ":" .. id
    end
    for id, untilAt in pairs(reserved) do
        if items[id] == nil or os.clock() >= untilAt then
            reserved[id] = nil
        end
    end
    local batch, ballId = Fusion.nextBatch(items, Env.data("equipment"),
        rarityByLabel[Options.FuseMaxRarity.Value] or -math.huge, reserved, function(id)
            return os.clock() - (attemptedAt[attemptKey(id)] or -math.huge) >= RETRY_AFTER
        end, mode)
    if not batch then
        fusionLabel:SetText(string.format("%d batches fused. %s needs %d matching copies plus one kept.", fusedBatches, mode, required))
        return
    end
    if not Ui.on("AutoFuseDuplicates") or not mayTry(attemptKey(ballId)) then
        return
    end
    -- Reserve before the yielding invoke so delayed PlayerData cannot resubmit consumed ids.
    for _, id in ipairs(batch) do
        reserved[id] = os.clock() + RETRY_AFTER
    end
    Env.elevate()
    fusionLabel:SetText("Fusing " .. Env.ballName(ballId) .. "...")
    local ok, result
    if mode == "Higher rarity" then
        ok, result = Env.invoke("FusionRequest", batch)
    else
        -- The form-upgrade remote takes one main id and five additional ids, not six materials.
        ok, result = Env.invoke("BallUpgradeRequest", batch[1], table.move(batch, 2, #batch, 1, {}))
    end
    if not Life.alive then
        return
    end
    if ok and type(result) == "table" and result.ok == true then
        for _, id in ipairs(batch) do
            reserved[id] = math.huge -- release only after replication removes the consumed item
        end
        attemptedAt[attemptKey(ballId)] = nil -- another disjoint batch may run in 1.5s
        fusedBatches += 1
        Env.elevate()
        local target = mode == "Higher rarity" and Env.ballName(result.cnId) or (mode .. " " .. Env.ballName(ballId))
        fusionLabel:SetText("Fused " .. Env.ballName(ballId) .. " into " .. target)
    else
        Env.elevate()
        if not ok then
            -- Transport failure does not prove the server rejected the materials.
            for _, id in ipairs(batch) do reserved[id] = math.huge end
        end
        fusionLabel:SetText("Fusion not confirmed: " .. tostring(type(result) == "table" and result.reason or result or "no response"))
    end
end)

-- Crates ---------------------------------------------------------------------------------------------

local crates = tab:AddGroupbox({ Side = "Right", Name = "Crates", IconName = "package" })
local crateByLabel, crateLabels = {}, {}
for _, crate in ipairs(Config.crate.list) do
    if crate.isForSale and type(crate.coinsPrice) == "number" and crate.coinsPrice > 0 then
        local label = string.format("%s x%d (%d coins)", crate.name, crate.drawCount or 1, crate.coinsPrice)
        crateByLabel[label] = crate
        crateLabels[#crateLabels + 1] = label
    end
end
crates:AddDropdown("CrateChoice", {
    Text = "Crate",
    Values = crateLabels,
    Default = crateLabels[1],
})
crates:AddSlider("CrateReserve", {
    Text = "Keep at least",
    Default = 0,
    Min = 0,
    Max = 20000,
    Rounding = 0,
    Suffix = " coins",
    Tooltip = "Auto buy never spends below this.",
})
crates:AddToggle("AutoBuyCrate", {
    Text = "Auto buy",
    Default = false,
    Tooltip = "Buys the crate with coins whenever you have its price plus the amount to keep.",
})
Ui.automation("AutoBuyCrate", true)
local crateLabel = crates:AddLabel("", true)

local function itemName(result)
    if type(result) ~= "table" then
        return "?"
    end
    local id = result.itemId or result.targetId or result.cnId
    local ball = id and Config.ball.byCnId[id]
    return ball and ball.displayName or tostring(id or result.itemType or "?")
end

local function buyCrate()
    local crate = crateByLabel[Options.CrateChoice.Value]
    if not crate then
        return false, "no crate chosen"
    end
    local ok, result = Env.invoke("GachaRoll", crate.cnId, "coins")
    if not ok or type(result) ~= "table" then
        return false, not ok and tostring(result) or "the game did not answer"
    end
    if not result.ok then
        return false, tostring(result.reason or "refused")
    end
    local names = {}
    for _, item in ipairs(type(result.results) == "table" and result.results or { result }) do
        names[#names + 1] = itemName(item)
    end
    return true, table.concat(names, ", ")
end

local function reportBuy(ok, text)
    if not Life.alive then return end
    Env.elevate()
    crateLabel:SetText(ok and "Last crate: " .. text or "Could not buy: " .. text)
end

crates:AddButton({
    Text = "Buy once",
    Func = function()
        Life.spawn("rewards:buy-once", function()
            reportBuy(buyCrate())
        end)
    end,
})

Life.loop("rewards:crates", BUY_INTERVAL, function()
    if not Ui.on("AutoBuyCrate") then
        return
    end
    local crate = crateByLabel[Options.CrateChoice.Value]
    local coins = Env.data("coins") or 0
    if crate and coins >= crate.coinsPrice + Options.CrateReserve.Value and mayTry("crate:" .. crate.cnId) then
        local ok, text = buyCrate()
        if not Life.alive then
            return
        end
        if ok then
            attemptedAt["crate:" .. crate.cnId] = nil
        end
        reportBuy(ok, text)
    end
end)

Life.onCleanup(function()
    table.clear(attemptedAt)
    table.clear(reserved)
    table.clear(rewardLog)
    table.clear(seenRewards)
    table.clear(seenChests)
end)

return {}
