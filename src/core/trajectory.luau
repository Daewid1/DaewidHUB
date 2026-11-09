-- Aim uses the same arena anchor and XY plane as DuelLaunchAimClient (local -Z is up).
local Env = use("core/env")
local Life = use("shared/life")
local Match = use("core/match")
local Trajectory = {}
local root, shownModel, shownToken

function Trajectory.clear()
    Env.elevate()
    if root then
        root:Destroy()
    end
    root, shownModel, shownToken = nil, nil, nil
end

-- `detail` is an optional second line: what the solver guarantees, next to what it expects.
function Trajectory.show(player, direction, expected, detail)
    Trajectory.clear()
    local model = Match.tableModel
    if not Life.alive or not Match.seated() or Match.phase() ~= "Aiming" or not model then
        return false
    end
    local anchor = model:FindFirstChild("棋盘锚点") or model:FindFirstChild("ArenaAnchor")
    if not anchor or not anchor:IsA("BasePart") or direction.Magnitude < 1e-6 then
        return false
    end
    local ok, cfg = Env.call(Env.loadModule("ArenaOverride").resolveConfig, Env.loadModule("BattleConfig"), Match.arena())
    if not ok or not Life.alive or model ~= Match.tableModel or Match.phase() ~= "Aiming" then
        return false
    end
    local slot = cfg.slots[player.team]
    local spawn = slot and ((slot.spawnPositionCorners or {})[player.index] or slot.spawnPosition)
    if typeof(spawn) ~= "Vector2" then
        return false
    end
    Env.elevate()
    root = Instance.new("Folder")
    root.Name = "DaewidHUBAimTrajectory"
    root.Parent = model
    shownModel, shownToken = model, Match.aimToken
    local color = expected > 0.60 and Color3.fromRGB(70, 235, 115)
        or expected >= 0.45 and Color3.fromRGB(255, 215, 65) or Color3.fromRGB(255, 85, 85)
    direction = direction.Unit
    local length = math.min(cfg.arena.size.X, cfg.arena.size.Y) * 0.3
    -- Clip the launch segment to the board's edge, including corner spawns in team modes.
    for _, axis in ipairs({ "X", "Y" }) do
        local component = direction[axis]
        if math.abs(component) > 1e-6 then
            local edge = math.sign(component) * (cfg.arena.size[axis] / 2 - 0.2)
            length = math.min(length, math.max(0.2, (edge - spawn[axis]) / component))
        end
    end
    local tip = spawn + direction * length
    local wing = Vector2.new(-direction.Y, direction.X)
    local head = math.min(1.1, length * 0.3)
    local function point(position)
        local attachment = Instance.new("Attachment")
        attachment.Position = Vector3.new(position.X, position.Y, -0.3)
        attachment.Parent = anchor
        return attachment
    end
    -- Attachments are on a transparent anchor part owned by the visual, so one Destroy clears all.
    local holder = Instance.new("Part")
    holder.Name = "ArenaPlane"
    holder.Size = Vector3.new(0.1, 0.1, 0.1)
    holder.Transparency, holder.Anchored = 1, true
    holder.CanCollide, holder.CanTouch, holder.CanQuery = false, false, false
    holder.CFrame = anchor.CFrame
    holder.Parent = root
    anchor = holder
    local start, finish = point(spawn), point(tip)
    local function beam(a, b, width)
        local line = Instance.new("Beam")
        line.Attachment0, line.Attachment1 = a, b
        line.Width0, line.Width1 = width, width
        line.Color, line.Transparency = ColorSequence.new(color), NumberSequence.new(0)
        line.FaceCamera, line.LightEmission, line.Segments = true, 1, 1
        line.Parent = root
    end
    beam(start, finish, 0.16)
    beam(finish, point(tip - direction * head + wing * head * 0.5), 0.16)
    beam(finish, point(tip - direction * head - wing * head * 0.5), 0.16)
    local label = Instance.new("BillboardGui")
    label.Name, label.Adornee = "Prediction", holder
    label.Size = UDim2.fromOffset(260, detail and 58 or 44)
    label.StudsOffsetWorldSpace = holder.CFrame.LookVector * 3
    label.AlwaysOnTop, label.MaxDistance = true, 150
    label.Parent = root
    local text = Instance.new("TextLabel")
    text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
    text.TextColor3, text.TextStrokeTransparency = color, 0.25
    text.Font, text.TextSize = Enum.Font.GothamBold, 18
    local outcome = expected > 0.60 and "Win" or expected >= 0.45 and "Even" or "Loss"
    text.Text = string.format("Predicted: %s (%d%%)", outcome, math.clamp(math.floor(expected * 100 + 0.5), 0, 100))
        .. (detail and "\n" .. detail or "")
    text.Parent = label
    return true
end

local function refresh()
    if root and (not Life.alive or not Match.seated() or Match.phase() ~= "Aiming"
        or Match.tableModel ~= shownModel or Match.aimToken ~= shownToken or not root.Parent) then
        Trajectory.clear()
    end
end
-- Through Match, so an absent or renamed state remote costs the overlay its prompt refresh
-- rather than erroring out of this module while the hub is still loading.
Match.listen("DuelTableState", refresh)
Life.loop("duel:trajectory", 0.1, refresh)
Life.onCleanup(Trajectory.clear)

return Trajectory

