local Engine = use("vendor/ui")
local Env = use("shared/env")
local Library = { Options = {}, Toggles = {}, Flags = Engine.Flags, unloadCallbacks = {} }
local Group = {}
Group.__index = Group

local function protect(callback, value)
	if not callback then return end
	Env.elevate()
	return callback(value)
end

local function control(group, kind, name, options)
	local info = table.clone(options or {})
	local changed
	info.Flag = name
	info.Description = info.Tooltip or info.Description
	info.Options = table.clone(info.Values or {})
	info.Increment = info.Rounding and 10 ^ -info.Rounding or 1
	if kind == "Dropdown" and not info.Multi and type(info.Default) == "number" then
		info.Default = info.Options[info.Default]
	end
	info.Callback = function(value)
		local result, reason = protect(options and options.Callback, value)
		if result == false then return false, reason end
		protect(changed, value)
		return result
	end
	local entry = group.native["Add" .. kind](group.native, info)
	entry.SetValue = function(_, value) entry.Set(value) end
	entry.OnChanged = function(_, callback) changed = callback end
	entry.SetVisible = function(_, visible) entry._api.frame.Visible = visible == true end
	entry.SetValues = function(_, values)
		assert(kind == "Dropdown" and type(values) == "table", "Expected dropdown values")
		entry.SetOptions(values)
	end
	if kind == "Toggle" then Library.Toggles[name] = entry else Library.Options[name] = entry end
	return entry
end

for _, kind in ipairs({ "Toggle", "Slider", "Dropdown", "Input" }) do
	Group["Add" .. kind] = function(self, name, options) return control(self, kind, name, options) end
end

function Group:AddLabel(text)
	local label = self.native:AddLabel(text)
	function label:SetVisible(visible) self.frame.Visible = visible == true end
	function label:AddKeyPicker(name, options)
		local info = table.clone(options)
		info.Text = info.Text or text
		info.Flag = name
		info.NoList = info.NoUI
		info.Callback = function(key)
			if name == "MenuKeybind" then
				Library.window.native.toggleKey = key
				Library.window.toggleKey = key
			end
			protect(options.Callback, key)
		end
		local entry = self._group.native:AddKeybind(info)
		entry.SetValue = function(_, value) entry.Set(value) end
		Library.Options[name] = entry
		return entry
	end
	label._group = self
	return label
end

function Group:AddButton(options, callback)
	if type(options) == "string" then options = { Text = options, Func = callback } end
	return self.native:AddButton({ Text = options.Text, Description = options.Tooltip,
		Callback = function() protect(options.Func or options.Callback) end })
end

function Group:AddDivider()
	return self.native:AddSection("")
end

local function groupbox(tab, info)
	local L = getgenv().__DAEWID_BALL_LUMEN
	local frame = L.A.surface({ Parent = tab.mount or tab.body, elev = 1, radius = L.T.r.lg,
		Name = "Group_" .. info.Name, Size = UDim2.new(1, 0, 0, 0) })
	frame.AutomaticSize = Enum.AutomaticSize.Y
	L.pad(12, 12, 12, 12, frame)
	L.list(L.T.px("gap"), nil, frame)
	L.C.section(frame, info.Name)
	local body = L.mk("Frame", { Name = "Controls", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = frame })
	L.list(L.T.px("gap"), nil, body)
	local native = setmetatable({ name = tab.name .. "_" .. info.Name, mount = body, native = tab.native }, getmetatable(tab))
	return setmetatable({ native = native }, Group)
end

function Library:OnUnload(callback)
	table.insert(self.unloadCallbacks, callback)
end

function Library:SetIconModule() end

function Library:CreateWindow(info)
	self.window = Engine:CreateWindow({ Title = info.Title, Subtitle = info.Footer,
		ToggleKey = Enum.KeyCode.RightShift, Intro = true, Widgets = false,
		OnDestroy = function()
			for _, callback in ipairs(self.unloadCallbacks) do
				local ok, reason = pcall(callback)
				if not ok then warn("[DaewidHUB] Unload: " .. tostring(reason)) end
			end
		end })
	local window = {}
	function window:AddTab(name, icon, description)
		local tab = Library.window:CreateTab(name, icon, description)
		return { AddGroupbox = function(_, options) return groupbox(tab, options) end }
	end
	self.window.native.subtitleLbl.Text = "BALL VS BALL / PRIVATE EDITION"
	return window
end

function Library:Notify(info)
	if self.window then
		self.window:Notify({ Title = info.Title, Text = info.Description, Duration = info.Time })
	end
end

function Library:SetNotifySide(side)
	assert(side == "Left" or side == "Right", "Invalid notification side")
	getgenv().__DAEWID_BALL_LUMEN.Toast.setSide(side)
end

function Library:SetDPIScale(percent)
	assert(type(percent) == "number" and percent == percent and percent >= 50 and percent <= 200, "Invalid DPI scale")
	local L = getgenv().__DAEWID_BALL_LUMEN
	L.Cfg.set("scale", percent / 100)
	self.window:Refit()
end

function Library:Unload()
	Engine:Destroy()
	table.clear(self.Options)
	table.clear(self.Toggles)
end

return Library
