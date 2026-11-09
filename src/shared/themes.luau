local Env = use("shared/env")
local Ui = use("shared/ui")
local Profiles = use("shared/profiles")
local Themes = {}

function Themes.build(tab, root)
	local L = getgenv().__DAEWID_BALL_LUMEN
	local files = Env.files
	if not files.isfolder(root) then files.makefolder(root) end
	local group = tab:AddGroupbox({ Name = "Theme studio" })
	local fields = { { "Background", "surface" }, { "Main", "raised" }, { "Accent", "accent" },
		{ "Outline", "line" }, { "Text", "text" } }
	local defaults, inputs = {}, {}
	for _, field in ipairs(fields) do defaults[field[2]] = L.T.c[field[2]] end
	local fonts = {}
	for _, item in ipairs(Enum.Font:GetEnumItems()) do
		if item.Name ~= "Unknown" then fonts[#fonts + 1] = item.Name end
	end
	table.sort(fonts)
	local function color(value)
		assert(type(value) == "string" and value:match("^#?%x%x%x%x%x%x$"), "Use a six-digit hex colour")
		return Color3.fromHex(value:gsub("^#", ""))
	end
	local function repaint(values)
		local nextColors = {}
		for _, field in ipairs(fields) do nextColors[field[2]] = color(values[field[2]]) end
		assert(table.find(fonts, values.font), "Unsupported display font")
		for key, value in pairs(nextColors) do L.T.c[key] = value end
		L.T.font.display = Enum.Font[values.font]
		L.T.reindex()
		if L.repaint then L.repaint() end
		if L.A.repaintGradients then L.A.repaintGradients() end
		for _, object in ipairs(Ui.Library.window.native.gui:GetDescendants()) do
			if object:IsA("TextLabel") and (object.Name == "GiorgioWordmark" or object.TextSize >= 30) then object.Font = L.T.font.display end
		end
	end
	local function safe(callback)
		return function(...)
			local ok, reason = pcall(callback, ...)
			if not ok then Ui.notify("Theme studio", tostring(reason), 6) end
		end
	end
	for _, field in ipairs(fields) do
		inputs[field[2]] = group:AddInput("theme_" .. field[2], { Text = field[1] .. " colour", Default = L.T.c[field[2]]:ToHex(), Finished = true })
	end
	local font = group:AddDropdown("theme_font", { Text = "Display font", Values = fonts, Default = "Garamond" })
	local function values()
		local result = { font = font.Value }
		for key, input in pairs(inputs) do result[key] = input.Value end
		return result
	end
	local function apply(data)
		repaint(data)
		for key, input in pairs(inputs) do input:SetValue(data[key]) end
		font:SetValue(data.font)
	end
	group:AddDropdown("theme_preset", { Text = "Built-in palette", Values = { "Giorgio", "Chrome", "Ember", "Mint", "Orchid", "Bone" }, Default = "Giorgio",
		Callback = safe(function(selected)
			if selected == "Giorgio" then
				local data = { font = "Garamond" }
				for key, value in pairs(defaults) do data[key] = value:ToHex() end
				apply(data)
			else
				L.Theme.set(L.Theme.keyFor(selected))
				for key, input in pairs(inputs) do input:SetValue(L.T.c[key]:ToHex()) end
			end
		end) })
	group:AddButton("Apply colours and font", safe(function() repaint(values()) end))
	group:AddButton("Restore original Giorgio palette", safe(function()
		local data = { font = "Garamond" }
		for key, value in pairs(defaults) do data[key] = value:ToHex() end
		apply(data)
	end))
	local name = group:AddInput("theme_name", { Text = "Custom theme name", Default = "custom", Finished = true })
	local function names()
		local result = {}
		for _, path in ipairs(files.listfiles(root)) do
			local value = path:gsub("\\", "/"):match("([^/]+)%.json$")
			if Profiles.validName(value) then result[#result + 1] = value end
		end
		table.sort(result)
		return #result > 0 and result or { "(none)" }
	end
	local picker = group:AddDropdown("theme_pick", { Text = "Custom themes", Values = names() })
	local function load(value)
		assert(Profiles.validName(value), "Select a custom theme")
		apply(Env.HttpService:JSONDecode(files.readfile(root .. "/" .. value .. ".json")))
	end
	group:AddButton("Save custom theme", safe(function()
		assert(Profiles.validName(name.Value), "Invalid theme name")
		local data = values()
		for _, field in ipairs(fields) do color(data[field[2]]) end
		local path = root .. "/" .. name.Value .. ".json"
		if files.isfile(path) then files.writefile(path .. ".bak", files.readfile(path)) end
		local encoded = Env.HttpService:JSONEncode(data)
		files.writefile(path, encoded)
		assert(files.readfile(path) == encoded, "Theme write could not be verified")
		picker:SetValues(names())
		picker:SetValue(name.Value)
	end))
	group:AddButton("Load selected theme", safe(function() load(picker.Value) end))
	group:AddButton("Delete selected theme", safe(function()
		assert(Profiles.validName(picker.Value), "Select a custom theme")
		local selected = picker.Value
		files.delfile(root .. "/" .. selected .. ".json")
		if files.isfile(root .. "/default.txt") and files.readfile(root .. "/default.txt") == selected then files.delfile(root .. "/default.txt") end
		picker:SetValues(names())
	end))
	group:AddButton("Set selected theme as default", safe(function()
		assert(Profiles.validName(picker.Value) and files.isfile(root .. "/" .. picker.Value .. ".json"), "Select a saved theme")
		files.writefile(root .. "/default.txt", picker.Value)
	end))
	group:AddButton("Clear default theme", safe(function()
		if files.isfile(root .. "/default.txt") then files.delfile(root .. "/default.txt") end
	end))
	if files.isfile(root .. "/default.txt") then safe(load)(files.readfile(root .. "/default.txt")) end
end

return Themes
