end)()
assert(Profiles.validName("my-config 2") and not Profiles.validName("../bad") and not Profiles.validName(""))
local finish = Profiles.build(tab, "DaewidHUB/BallVsBall")
buttons["Create / save configuration"]()
assert(disk["DaewidHUB/BallVsBall/settings/default.json"])
flags.Think.Value, flags.AutoDuel.Value, flags.NeverPick.Value = .9, true, {}
buttons["Load configuration"]()
assert(flags.Think.Value == .4 and flags.AutoDuel.Value == false and flags.NeverPick.Value.A)
assert(applied[#applied] == "AutoDuel")
assert(not table.find(applied, "MenuKeybind"))
buttons["Create / save configuration"]()
assert(disk["DaewidHUB/BallVsBall/settings/default.json.bak"])
buttons["Set selected as autoload"]()
flags.Think.Value = .8
finish()
assert(flags.Think.Value == .4)
entries.cfg_name.Value = "../escape"
buttons["Create / save configuration"]()
assert(not disk["DaewidHUB/BallVsBall/settings/../escape.json"] and #notices == 1)
entries.cfg_name.Value = "default"
buttons["Delete selected configuration"]()
assert(not disk["DaewidHUB/BallVsBall/settings/default.json"] and not disk["DaewidHUB/BallVsBall/settings/autoload.txt"])
print("PASS: config round trip, multi-selects, bind persistence, load order, backups, autoload, path validation and deletion")
