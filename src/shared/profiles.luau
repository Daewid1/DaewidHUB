local Env = use("shared/env")
local Ui = use("shared/ui")
local Profiles = {}

local function validName(value)
	return type(value) == "string" and #value > 0 and #value <= 64 and value:match("^[%w_%- ]+$") ~= nil
end

local function ensure(path)
	local current = ""
	for part in path:gmatch("[^/]+") do
		current = current == "" and part or current .. "/" .. part
		if not Env.files.isfolder(current) then Env.files.makefolder(current) end
	end
end

function Profiles.build(tab, folder)
	local Library = Ui.Library
	local root = folder .. "/settings"
	local files = Env.files
	ensure(root)
	local group = tab:AddGroupbox({ Name = "Saved configurations" })
	local name = group:AddInput("cfg_name", { Text = "Configuration name", Default = "default", Finished = true })
	local function names()
		local result = {}
		for _, path in ipairs(files.listfiles(root)) do
			local item = path:gsub("\\", "/"):match("([^/]+)%.json$")
			if validName(item) then result[#result + 1] = item end
		end
		table.sort(result)
		return #result > 0 and result or { "(none)" }
	end
	local selected = group:AddDropdown("cfg_pick", { Text = "Saved configurations", Values = names() })
	local status = group:AddLabel("Configs include feature settings and feature shortcuts. Webhook URLs remain local.", true)
	local function chosen()
		local value = name.Value
		if value == "" then value = selected.Value end
		assert(validName(value), "Use 1-64 letters, numbers, spaces, underscores or dashes")
		return value
	end
	local function run(callback)
		return function()
			local ok, reason = pcall(callback)
			if not ok then Ui.notify("Configurations", tostring(reason), 6) end
		end
	end
	local function refresh(value)
		selected:SetValues(names())
		if value then selected:SetValue(value) end
	end
	local function load(value)
		assert(validName(value), "Invalid configuration name")
		local data = Env.HttpService:JSONDecode(files.readfile(root .. "/" .. value .. ".json"))
		assert(type(data) == "table" and data.schema == 1 and type(data.values) == "table", "Invalid configuration")
		local flags, ordered = Library.Flags, {}
		for flag in pairs(data.values) do
			if type(flag) == "string" and flags[flag] and flag ~= "MenuKeybind" and not flag:match("^cfg_") and not flag:match("^theme_") and not flag:match("^ui_") then
				ordered[#ordered + 1] = flag
			end
		end
		table.sort(ordered, function(first, second)
			local firstToggle, secondToggle = flags[first].Type == "Toggle", flags[second].Type == "Toggle"
			if firstToggle ~= secondToggle then return not firstToggle end
			return first < second
		end)
		local failures = {}
		for _, flag in ipairs(ordered) do
			local entry, value = flags[flag], data.values[flag]
			local expected = type(entry.Value)
			local valid = entry.Type == "Keybind" or entry.Type == "Bind" or type(value) == expected
			if valid then
				local ok, reason = pcall(entry.Set, value)
				if not ok then failures[#failures + 1] = flag .. ": " .. tostring(reason) end
			else failures[#failures + 1] = flag .. ": invalid value type" end
		end
		status:SetText("Loaded " .. value .. (#failures > 0 and ("; " .. #failures .. " settings rejected") or ""))
		if #failures > 0 then Ui.notify("Some settings were not applied", table.concat(failures, "\n"), 8) end
	end
	group:AddButton("Create / save configuration", run(function()
		local values = {}
		for flag, entry in pairs(Library.Flags) do
			if flag == "MenuKeybind" or flag:match("^cfg_") or flag:match("^theme_") or flag:match("^ui_") then continue end
			local value = entry.Value
			if typeof(value) == "EnumItem" then value = value.Name end
			if type(value) == "boolean" or type(value) == "number" or type(value) == "string" or type(value) == "table" then values[flag] = value end
		end
		local value = chosen()
		local path = root .. "/" .. value .. ".json"
		local encoded = Env.HttpService:JSONEncode({ schema = 1, values = values })
		if files.isfile(path) then files.writefile(path .. ".bak", files.readfile(path)) end
		files.writefile(path, encoded)
		assert(files.readfile(path) == encoded, "Configuration write could not be verified")
		refresh(value)
		status:SetText("Saved " .. value)
	end))
	group:AddButton("Load configuration", run(function() load(selected.Value) end))
	group:AddButton("Refresh list", run(function() refresh() end))
	group:AddButton("Delete selected configuration", run(function()
		local value = selected.Value
		assert(validName(value), "Select a configuration first")
		files.delfile(root .. "/" .. value .. ".json")
		if files.isfile(root .. "/autoload.txt") and files.readfile(root .. "/autoload.txt") == value then files.delfile(root .. "/autoload.txt") end
		refresh()
		status:SetText("Deleted " .. value)
	end))
	group:AddButton("Set selected as autoload", run(function()
		local value = selected.Value
		assert(validName(value) and files.isfile(root .. "/" .. value .. ".json"), "Select a saved configuration first")
		files.writefile(root .. "/autoload.txt", value)
		status:SetText("Autoload: " .. value)
	end))
	group:AddButton("Clear autoload", run(function()
		if files.isfile(root .. "/autoload.txt") then files.delfile(root .. "/autoload.txt") end
		status:SetText("Autoload disabled")
	end))
	return function()
		if files.isfile(root .. "/autoload.txt") then
			local ok, reason = pcall(load, files.readfile(root .. "/autoload.txt"))
			if not ok then Ui.notify("Autoload failed", tostring(reason), 7) end
		end
	end
end

Profiles.validName = validName
return Profiles
