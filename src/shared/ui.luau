-- The window, its tabs, notifications, and small helpers features build their panels from.
-- Each game's core/ui calls Ui.create once with its footer and tabs, then returns this table.
--
-- The library is the Crimson Obsidian fork. Its public methods re-elevate the thread themselves,
-- so UI writes after a game-module call are safe without extra care in feature code.

local Env = use("shared/env")
local Life = use("shared/life")
local Bridge = use("shared/ui-bridge")

local Ui = {}

-- options.footer: the game's name under the title.
-- options.tabs: { { name, icon, description }, ... } in sidebar order.
-- options.only: a set of tab names to create (the rest are skipped), or nil for all of them.
-- options.icons: a bundled icon registry, installed before any window controls are created.
function Ui.create(options)
    local Library = Bridge
    Env.elevate()
    assert(type(Library) == "table" and type(Library.CreateWindow) == "function", "DaewidHUB: UI library did not load")
    if options.icons then
        Library:SetIconModule(options.icons)
    end
    Ui.Library = Library
    Ui.Options = Library.Options
    Ui.Toggles = Library.Toggles

    -- Register before constructing the window, so failed startup can also tear it down.
    Library:OnUnload(function()
        Env.elevate()
        Life.shutdown()
    end)

    Ui.Window = Library:CreateWindow({
        Title = "DaewidHUB",
        Footer = options.footer,
        AutoShow = true,
        Center = true,
        Resizable = true,
        ShowCustomCursor = false,
        NotifySide = "Right",
    })

    -- Created up front so the sidebar order is fixed here, whatever order features load in.
    Ui.Tabs = {}
    for _, entry in ipairs(options.tabs) do
        if not options.only or options.only[entry[1]] then
            Ui.Tabs[entry[1]] = Ui.Window:AddTab(entry[1], entry[2], entry[3])
        end
    end

    return Ui
end

function Ui.notify(title, text, seconds)
    if not Life.alive or not Ui.Library then return end
    Env.elevate()
    Ui.Library:Notify({ Title = title, Description = text, Time = seconds or 5 })
end

-- A fixed stack of labels plus a footer, for lists that change size (tasks, timers, chests).
function Ui.panel(groupbox, rows)
    local labels = {}
    for index = 1, rows do
        labels[index] = groupbox:AddLabel("", true)
        labels[index]:SetVisible(false)
    end
    groupbox:AddDivider()
    local footer = groupbox:AddLabel("", true)
    local panel = {}
    function panel.set(lines, footerText)
        if not Life.alive then return end
        Env.elevate()
        for index = 1, rows do
            local line = lines[index]
            labels[index]:SetVisible(line ~= nil)
            if line ~= nil then
                labels[index]:SetText(line)
            end
        end
        footer:SetText(footerText or "")
    end
    return panel
end

-- Toggle value that is safe to read during unload (the library clears Toggles).
function Ui.on(name)
    local toggle = Ui.Library.Toggles[name]
    return toggle ~= nil and toggle.Value == true
end

function Ui.set(name, value)
    local toggle = Ui.Library.Toggles[name]
    if toggle and toggle.Value ~= value then
        toggle:SetValue(value)
    end
end

-- Toggles that start automation. `stays` marks ones that never pull the character somewhere
-- else (clan spins, auto heal), which travelling can leave running.
local automation = {}

function Ui.automation(name, stays)
    automation[#automation + 1] = { name = name, stays = stays == true }
end

-- Switches automation off: everything, or with moversOnly just what would move the character.
function Ui.stopAll(moversOnly)
    for _, entry in ipairs(automation) do
        if not (moversOnly and entry.stays) then
            Ui.set(entry.name, false)
        end
    end
end

return Ui
