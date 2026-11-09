local created, buttons, entries, unloads = {}, {}, {}, 0
local Enum = { KeyCode = { RightShift = "RightShift" }, AutomaticSize = { Y = "Y" } }
local UDim2 = { new = function(...) return { ... } end }
local Engine = { Flags = {} }
local L = { T = { r = { lg = 12 }, px = function() return 8 end }, A = {}, C = {},
	pad = function() end, list = function() end, Cfg = { set = function() end } }
L.A.surface = function(properties) table.insert(created, properties); return properties end
L.mk = function(_, properties) return properties end
L.C.section = function() end
L.Toast = { setSide = function(side) L.side = side end }
local NativeTab = {}
NativeTab.__index = NativeTab
for _, kind in ipairs({ "Toggle", "Slider", "Dropdown", "Input", "Keybind" }) do
	NativeTab["Add" .. kind] = function(_, options)
		local value = options.Default
		if kind == "Dropdown" and value == nil then value = options.Options[1] end
		local entry = { Type = kind, Value = value, _api = { frame = {} }, info = options }
		entry.Set = function(nextValue)
			local previous = entry.Value
			entry.Value = nextValue
			if options.Callback and options.Callback(nextValue) == false then entry.Value = previous end
		end
		entry.SetOptions = function(values) entry.values = values; if not table.find(values, entry.Value) then entry.Set(values[1]) end end
		Engine.Flags[options.Flag] = entry
		entries[options.Flag] = entry
		return entry
	end
end
function NativeTab:AddLabel(text)
	return { frame = {}, SetText = function(self, value) self.text = value end }
end
function NativeTab:AddButton(options) buttons[options.Text] = options.Callback; return {} end
function NativeTab:AddSection() end
function Engine:CreateWindow(options)
	self.options = options
	local window = { native = { subtitleLbl = {} } }
	function window:CreateTab(name) return setmetatable({ name = name, body = {}, native = {} }, NativeTab) end
	function window:Refit() end
	function window:Notify() end
	return window
end
function Engine:Destroy() unloads += 1; self.options.OnDestroy() end
local function getgenv() return { __DAEWID_BALL_LUMEN = L } end
local function use(name)
	if name == "vendor/ui" then return Engine end
	if name == "shared/env" then return { elevate = function() end } end
	error(name)
end
local Library = (function()
