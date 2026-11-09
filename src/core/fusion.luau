-- October 2026: rarity fusion takes ten Classic balls; form fusion takes six matching copies.
-- Keep tradeability groups separate so automatic fusion cannot bind a tradable copy's result.
local Env = use("core/env")
local Fusion = {}

function Fusion.requiredCount(mode)
    if mode == nil or mode == "Higher rarity" then
        return 10
    elseif mode == "Shiny" or mode == "Rainbow" then
        return 6
    end
end

function Fusion.kind(item)
    if item.serial ~= nil then
        return "Rainbow"
    end
    local kills
    if type(item.metadata) == "table" then
        kills = item.metadata.killCount
    end
    if kills == nil then
        kills = item.killCount
    end
    if kills == nil then
        return "Classic"
    end
    if type(kills) == "number" and kills >= 0 and kills < math.huge and kills % 1 == 0 then
        return "Shiny"
    end
    return nil -- malformed kill metadata must not turn a special copy into a Classic material
end

function Fusion.nextBatch(items, equipment, maxRating, reserved, allowedBall, mode)
    mode = mode or "Higher rarity"
    local required = Fusion.requiredCount(mode)
    if not required then
        return nil
    end
    reserved = reserved or {}
    local materialKind = mode == "Rainbow" and "Shiny" or "Classic"
    local equipped = {}
    for _, value in pairs(type(equipment) == "table" and equipment or {}) do
        local id = type(value) == "table" and (value.id or value.instanceId) or value
        if type(id) == "string" then
            equipped[id] = true
        end
    end
    local groups = {}
    for id, item in pairs(type(items) == "table" and items or {}) do
        if type(id) == "string" and type(item) == "table" and item.itemType == "Ball"
            and type(item.itemId) == "string" and item.ownerUserId == Env.LocalPlayer.UserId
            and Fusion.kind(item) == materialKind and (mode ~= "Higher rarity" or item.canFusion == true)
            and not equipped[id] and not reserved[id]
            and (item.locks == nil or (type(item.locks) == "table" and next(item.locks) == nil)) then
            local ball = Env.loadModule("Config").ball.byCnId[item.itemId]
            if ball and type(ball.rating) == "number" and ball.rating <= maxRating
                and (not allowedBall or allowedBall(item.itemId)) then
                local key = item.itemId .. (item.tradable == true and ":tradable" or ":bound")
                local group = groups[key]
                if not group then
                    group = { ballId = item.itemId, rating = ball.rating, key = key, ids = {} }
                    groups[key] = group
                end
                group.ids[#group.ids + 1] = id
            end
        end
    end
    local candidates = {}
    for _, group in pairs(groups) do
        if #group.ids > required then -- retain one copy of each ball/tradability group
            candidates[#candidates + 1] = group
        end
    end
    table.sort(candidates, function(a, b)
        return a.rating < b.rating or (a.rating == b.rating and a.key < b.key)
    end)
    local group = candidates[1]
    if not group then
        return nil
    end
    table.sort(group.ids)
    return table.move(group.ids, 2, required + 1, 1, {}), group.ballId
end

return Fusion
