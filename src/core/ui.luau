-- Ball VS Ball's window and tabs.

local Ui = use("shared/ui")

return Ui.create({

    footer = "Ball VS Ball",
    tabs = {
        { "Home", "house", "Welcome to DaewidHUB" },
        { "Duel", "swords", "Auto duel, ball picks and aim" },
        { "Intel", "radar", "Opponents, the aim solver and prediction accuracy" },
        { "Rewards", "gift", "Daily quests, Halloween candy, check-in, mail, fusion and crates" },
        { "Settings", "settings", "Menu, themes and configs" },
    },
})

