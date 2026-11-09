-- Settings tab: menu options and local Giorgio-compatible themes and configurations.
-- Each game's features/settings calls Settings.build with its config folder and what a missing
-- executor function changes there. Settings.finish() loads the autoload config; main calls it
-- after every feature is built so a saved config can switch toggles on only once their handlers
-- exist.

local Env = use("shared/env")
local Ui = use("shared/ui")
local Life = use("shared/life")

local Settings = {}

-- options.folder: where this game's configs are saved (under DaewidHUB/).
-- options.effects: { [executor function] = "what goes missing without it" }.
function Settings.build(options)
    local Library, Options = Ui.Library, Ui.Options
    local tab = Ui.Tabs.Settings

    local menu = tab:AddGroupbox({ Side = "Left", Name = "Menu", IconName = "sliders-horizontal" })
    menu:AddDropdown("NotificationSide", {
        Text = "Notification side",
        Values = { "Left", "Right" },
        Default = "Right",
        Callback = function(value)
            Library:SetNotifySide(value)
        end,
    })
    menu:AddDropdown("DPIScale", {
        Text = "DPI scale",
        Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
        Default = "100%",
        Callback = function(value)
            Library:SetDPIScale(tonumber((value:gsub("%%", ""))))
        end,
    })
    menu:AddDivider()
    menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
        Default = "RightShift",
        NoUI = true,
        Text = "Menu keybind",
    })
    menu:AddButton("Unload", function()
        Library:Unload()
    end)
    Library.ToggleKeybind = Options.MenuKeybind

    local interface = tab:AddGroupbox({ Name = "Interface" })
    local L = getgenv().__DAEWID_BALL_LUMEN
    interface:AddButton("Replay introduction", function()
        L.Giorgio.load(function() if L.live() then Ui.Library.window.native:restore() end end, true)
    end)
    interface:AddToggle("ui_reduceMotion", { Text = "Reduce motion", Default = false, Bind = false,
        Callback = function(on)
            L.Cfg.set("reduceMotion", on)
            L.Theme.setMotion(on and "Calm" or "Silk")
            if on then L.Motion.durScale = .01; L.Motion.bounceScale = 0; L.Motion.reprofile() end
        end })
    interface:AddToggle("ui_blur", { Text = "Background blur", Default = false, Bind = false,
        Callback = function(on)
            L.Window.BLUR = on and 16 or 0
            L.A.blurTo(not Ui.Library.window.native.hidden and L.Window.BLUR or 0, "base")
        end })
    interface:AddToggle("ui_keylist", { Text = "Compact keybind HUD", Default = true, Bind = false,
        Callback = function() L.Hub.window:fitViewport() end })
    interface:AddToggle("ui_keylistAll", { Text = "Include inactive shortcuts", Default = false, Bind = false })
    interface:AddToggle("ui_sound", { Text = "Interface sounds", Default = true, Bind = false,
        Callback = function(on) L.Cfg.setFeat("giorgio.sfx", on) end })
    interface:AddSlider("ui_volume", { Text = "Interface volume", Default = .35, Min = 0, Max = 1, Rounding = 2,
        Callback = function(value) L.Cfg.setFeat("giorgio.sfxVolume", value) end })

    -- What this executor lacks and what that changes, so a bug report says it up front.
    local compat = tab:AddGroupbox({ Side = "Left", Name = "Compatibility", IconName = "cpu" })
    local lines = { "Executor: " .. Env.executor }
    for _, name in ipairs(Env.missing) do
        lines[#lines + 1] = string.format("No %s: %s.", name, options.effects[name] or "some features are limited")
    end
    if #Env.missing == 0 then
        lines[#lines + 1] = "Required function names are available. Runtime support depends on the executor."
    end
    compat:AddLabel(table.concat(lines, "\n"), true)
    local runtimeLabel = compat:AddLabel("Runtime: ready.", true)
    Life.loop("settings:runtime", 2, function()
        local messages = {}
        for name, reason in pairs(Env.requestIssues or {}) do
            messages[#messages + 1] = name .. ": " .. reason
        end
        for name, reason in pairs(Life.errors) do
            if name ~= "settings:runtime" then
                messages[#messages + 1] = name .. ": " .. (tostring(reason):match("^[^\n]+") or "unavailable")
            end
        end
        table.sort(messages)
        local extra = math.max(0, #messages - 4)
        while #messages > 4 do table.remove(messages) end
        if extra > 0 then messages[#messages + 1] = string.format("%d more runtime messages.", extra) end
        runtimeLabel:SetText(#messages > 0 and table.concat(messages, "\n") or "Runtime: ready.")
    end)

    if not Env.canSave or not Env.loadstring then
        local storage = tab:AddGroupbox({ Side = "Right", Name = "Saved settings", IconName = "save" })
        storage:AddLabel("Saved configs and custom themes are unavailable on this executor. You can still change the controls for this session.", true)
        function Settings.finish() end
        return Settings
    end

    local Profiles = use("shared/profiles")
    local Themes = use("shared/themes")
    Settings.finish = Profiles.build(tab, "DaewidHUB/" .. options.folder)
    Themes.build(tab, "DaewidHUB/themes")
    return Settings
end

return Settings
