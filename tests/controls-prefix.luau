local signal = { Connect = function() return { Disconnect = function() end } end }
local function node(properties)
	local object = properties or {}
	object.Parent = object.Parent or {}
	object.Activated, object.InputBegan = signal, signal
	object.SetAttribute = function() end
	object.GetAttribute = function() return nil end
	object.GetChildren = function() return {} end
	object.Destroy = function(self) self.Parent = nil end
	return object
end
local function dimensions(x, y, z, w)
	return { X = { Scale = x, Offset = y }, Y = { Scale = z, Offset = w } }
end
local UDim2 = { new = dimensions, fromOffset = function(x, y) return dimensions(0, x, 0, y) end }
local Vector2 = { new = function(x, y) return { X = x, Y = y } end }
local function enums()
	return setmetatable({}, { __index = function(self, key)
		local value = enums()
		rawset(self, key, value)
		return value
	end })
end
local Enum = enums()
local Color3 = { new = function() return {} end }
local T = { r = { md = 6 }, font = {}, c = {}, size = {}, px = function() return 40 end }
local L = { T = T, Motion = {}, A = {}, UIS = { InputBegan = signal },
	mk = function(_, properties) return node(properties) end, cleanup = function() end,
	hold = function(value) return value end, corner = function() end,
	try = function(_, callback, ...) return pcall(callback, ...) end,
	log = function() end, Toast = { warn = function() end } }
L.A.surface = node
L.A.text = node
L.A.Icon = { chevron = function(parent) return node({ Parent = parent }), node({ Parent = node() }) end }
L.A.selectRow = function() end
L.A.scroll = node
L.A.interactive = function() return {} end
local function getgenv() return { __DAEWID_BALL_LUMEN = L } end
